// A CRT tube, drawn over the finished picture. Optional; off unless the player
// asks for it in Settings.
//
// Ported from a Unity URP shader used on another project (RetroCRT/CRT Screen).
// The physics is the same and most of it transferred line for line. What
// changed, and why, is written up in docs/decisions.md D94. The short version:
//
//   * **No phosphor mask.** The original anchors its R/G/B triad to output
//     pixels, because a real mask sits on the glass and does not move with the
//     picture. This game renders at 640x360 and Godot blits that to the window
//     afterwards (project.godot: window/stretch/mode="viewport"), so FRAGCOORD
//     here counts 640x360 pixels, not monitor pixels. A three-pixel triad would
//     come out three *game* pixels wide and then be stretched two or four times
//     larger - coloured stripes across the screen, not a mask. It is left out
//     rather than left in badly.
//   * **No two-source composite and no Y flip.** The original takes the world
//     and the UI as separate textures because that project renders its UI
//     through a second camera, and it has to know which way up the blit handed
//     them over. This game is one canvas; the screen texture arrives the right
//     way up.
//   * **The distances are in game pixels, not monitor pixels.** Every default
//     below that the original expressed in output pixels is divided by roughly
//     the window scale. Thirty output pixels of vignette at 1080p is about ten
//     of these.
//
// **The gamma handling is kept exactly as it was.** Both projects render in a
// gamma colour space, so the values arriving here are sRGB-encoded. The bleed
// and the glow are averages of light, and averaging encoded values gives the
// wrong answer - dark halves come out too bright. So it decodes, works, and
// re-encodes, and the only clamp is the final one, so the effect survives in
// highlights.
//
// **Tuning lives in this file.** The scene that uses it sets no shader
// parameters at all, so these defaults are the only statement of how the
// effect looks and a change here is a change you can see in a diff.
shader_type canvas_item;
render_mode unshaded;

const float PI_ = 3.14159265359;
const float TAU_ = 6.28318530718;

// Taps on each side of the kernels. Compile-time so the loops can unroll, and
// GLES3 - which the Compatibility renderer targets - requires loop bounds it
// can work out in advance.
const int BLEED_TAPS = 4;
const int GLOW_RING = 1;

// The picture as drawn so far. Linear filtering, deliberately: the warp moves
// pixels by fractions of a pixel and the whole job of this shader is to stop
// the image looking like a grid. Nearest sampling here puts stair-steps along
// the curve. Everything else in this game is sampled nearest (D76) and that is
// still right - this is the one surface pretending to be glass.
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

group_uniforms tube_geometry;
// A divisor, so larger is flatter. Zero switches the warp off.
uniform float curvature : hint_range(0.0, 40.0) = 11.0;
// In game pixels, out of 640x360.
uniform float vignette_width : hint_range(0.0, 60.0) = 9.0;
group_uniforms;

group_uniforms colour_bleed;
// Lowered from 0.55 on 2026-11-17. The bleed is the single largest readable
// cost of the effect: measured, it was five of the twelve percentage points of
// horizontal stroke definition the effect was taking away, and this game's
// text has strokes one and two pixels wide. See decisions.md D94.
uniform float bleed_amount : hint_range(0.0, 1.0) = 0.30;
// Exponential falloff in game pixels. The trail runs right, so the taps read
// left.
uniform float bleed_falloff : hint_range(0.25, 6.0) = 1.1;
// One keeps edges sharp and lets only the colour run, which is what composite
// chroma does. Zero lets brightness smear too - beam slew and phosphor
// persistence.
uniform float bleed_luma_keep : hint_range(0.0, 1.0) = 0.65;
group_uniforms;

group_uniforms scanlines;
// Source lines, out of 360 rows.
//
// **Three rows per line is the finest that is visible at all, not two.** The
// original clamps this to half the row count on the reasoning that a line
// needs one dark row and one light row. That is right about the pixels and
// wrong about where they are sampled: a fragment is shaded at the centre of
// its row, so at exactly two rows per line the two samples land on phases
// 0.25 and 0.75, and sin squared is the same at both. The pattern is there in
// the maths and invisible on the screen - every row comes out at exactly the
// mean. Measured, not guessed: at 180 the rendered picture was identical to
// the one with the effect off, row for row.
//
// At three rows per line the samples land on a sixth, a half and five sixths,
// which are not equal, and the comb appears. 120 lines over 360 rows is that.
uniform float scanline_count = 120.0;
// Lowered from 0.30 on 2026-11-17 along with the bleed. The comb costs nothing
// horizontally but cuts across glyphs, and at three rows per line a letter
// eight rows tall takes three of them.
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.22;
uniform float line_noise : hint_range(0.0, 1.0) = 0.12;
uniform float line_noise_speed : hint_range(0.0, 4.0) = 1.0;
group_uniforms;

group_uniforms beam_glow;
uniform float glow_threshold : hint_range(0.0, 1.0) = 0.60;
uniform float glow_strength : hint_range(0.0, 3.0) = 0.45;
// In game pixels.
uniform float glow_radius : hint_range(0.5, 6.0) = 1.5;
group_uniforms;


vec3 to_linear(vec3 c) {
	return pow(max(c, vec3(0.0)), vec3(2.2));
}


vec3 to_gamma(vec3 c) {
	return pow(max(c, vec3(0.0)), vec3(1.0 / 2.2));
}


float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}


vec3 sample_linear(vec2 uv) {
	return to_linear(texture(screen_tex, uv).rgb);
}


float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}


// Both axes bend, and each is driven by the other's distance from the middle.
// That cross-coupling is what makes it a barrel rather than a stretch along one
// axis.
vec2 barrel_warp(vec2 uv, float amount) {
	if (amount <= 0.0) {
		return uv;
	}
	vec2 c = uv * 2.0 - 1.0;
	vec2 k = c.yx / amount;
	c += c * (k * k);
	return c * 0.5 + 0.5;
}


// A one-sided exponential kernel reading to the LEFT, so the smear trails
// right, the way the beam travels. Normalised, so average brightness is
// unchanged.
vec3 horizontal_bleed(vec2 uv, float texel_x) {
	vec3 centre = sample_linear(uv);
	if (bleed_amount <= 0.0) {
		return centre;
	}

	float tau = max(bleed_falloff, 0.01);
	vec3 acc = centre;
	float weight_sum = 1.0;

	for (int i = 1; i <= BLEED_TAPS; i++) {
		float w = exp(-float(i) / tau);
		acc += sample_linear(uv - vec2(float(i) * texel_x, 0.0)) * w;
		weight_sum += w;
	}

	vec3 bled = acc / weight_sum;

	// Push the blurred result back towards the brightness it started with. At
	// one, only the colour runs and edges stay sharp.
	vec3 chroma_only = bled * (luma(centre) / max(luma(bled), 1e-4));
	bled = mix(bled, chroma_only, clamp(bleed_luma_keep, 0.0, 1.0));

	return mix(centre, bled, bleed_amount);
}


// Bright areas only, so dark areas stay dark. This is the beam swelling as the
// drive voltage rises, which is why it keys off a threshold instead of blurring
// the whole picture.
vec3 beam_glow(vec2 uv, vec2 texel) {
	if (glow_strength <= 0.0) {
		return vec3(0.0);
	}

	vec3 acc = vec3(0.0);
	float weight_sum = 0.0;

	for (int y = -GLOW_RING; y <= GLOW_RING; y++) {
		for (int x = -GLOW_RING; x <= GLOW_RING; x++) {
			vec2 offset = vec2(float(x), float(y)) * glow_radius * texel;
			float w = exp(-float(x * x + y * y) * 0.5);
			acc += max(sample_linear(uv + offset) - glow_threshold, 0.0) * w;
			weight_sum += w;
		}
	}

	return (acc / weight_sum) * glow_strength;
}


// Clamped to what the picture can actually resolve; see `scanline_count` for
// why the divisor is three and not the two the original used.
float resolved_scanline_count(float rows) {
	return min(scanline_count, rows / 3.0);
}


// Tied to the line count rather than to the number of rows on screen, so the
// pattern keeps its apparent size instead of thinning out as the window grows.
float scanline_weight(float uv_y, float rows, float noise) {
	float strength = scanline_strength * mix(1.0 - line_noise, 1.0, noise);
	float s = sin(fract(uv_y * resolved_scanline_count(rows)) * PI_);
	s = s * s;
	// sin squared averages a half, so dividing by the mean leaves overall
	// brightness alone rather than darkening the whole picture.
	return mix(1.0 - strength, 1.0, s) / max(1.0 - 0.5 * strength, 1e-4);
}


void fragment() {
	vec2 size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 texel = SCREEN_PIXEL_SIZE;

	vec2 uv = barrel_warp(SCREEN_UV, curvature);

	// The warp pushes the corners off the edge of the picture. Black those out
	// rather than leaving it to whatever the sampler's clamping does, which
	// smears the edge row outwards.
	vec2 inside = step(vec2(0.0), uv) * step(uv, vec2(1.0));
	float on_tube = inside.x * inside.y;

	vec3 col = horizontal_bleed(uv, texel.x);
	col += beam_glow(uv, texel);

	// The same count the pattern uses, or the noise flickers across lines that
	// are not there.
	float line_index = floor(uv.y * resolved_scanline_count(size.y));
	float noise = hash21(vec2(line_index, floor(TIME * line_noise_speed * 24.0)));
	col *= scanline_weight(uv.y, size.y, noise);

	vec2 edge = abs(uv * 2.0 - 1.0);
	vec2 w = max(vignette_width * texel, vec2(1e-5));
	vec2 v = clamp(smoothstep(vec2(0.0), w, 1.0 - edge), vec2(0.0), vec2(1.0));
	col *= v.x * v.y * on_tube;

	COLOR = vec4(clamp(to_gamma(col), vec3(0.0), vec3(1.0)), 1.0);
}
