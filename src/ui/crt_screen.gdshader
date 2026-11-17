// A CRT tube, drawn over the finished picture. Optional; off unless the player
// asks for it in Settings.
//
// Ported from a Unity URP shader used on another project (RetroCRT/CRT Screen).
// The physics is the same and most of it transferred line for line. What
// changed, and why, is written up in docs/decisions.md D94. The short version:
//
//   * **No phosphor mask, still.** The original anchors its R/G/B triad to
//     output pixels, because a real mask sits on the glass and does not move
//     with the picture. Until the display path was rebuilt that was impossible
//     here - the whole shader ran at 640x360, so a three-pixel triad came out
//     three *game* pixels wide. It is possible now (D96 put this shader at the
//     monitor's resolution, so FRAGCOORD counts monitor pixels) and simply has
//     not been built. Anyone adding one should read section 2 of the original
//     Unity shader rather than invent it.
//   * **No two-source composite and no Y flip.** The original takes the world
//     and the UI as separate textures because that project renders its UI
//     through a second camera, and it has to know which way up the blit handed
//     them over. This game is one canvas; the picture arrives the right way up.
//   * **The distances are in source pixels, out of 640x360.** Not monitor
//     pixels, which is what the original used. Every step is a multiple of
//     `TEXTURE_PIXEL_SIZE`, so a bleed of one is one pixel of the game's own
//     image whatever the monitor is, and nothing needs rescaling when the
//     window changes.
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

// **The picture is `TEXTURE`, not the screen.** This shader is the material on
// the `SubViewportContainer` that shows the game, so the game's own 640x360
// image arrives as the texture being drawn and `UV` runs across the picture
// rather than across the window. Two things follow, and both are the reason
// the display path was rebuilt (decisions.md D96):
//
//   * Everything below measured in pixels can be written in SOURCE pixels, by
//     stepping in `TEXTURE_PIXEL_SIZE`, and stays the same size on every
//     monitor without anybody converting anything.
//   * The warp, the vignette and the corner blackout frame the PICTURE. When
//     this read the whole screen they framed the window, so on a monitor with
//     black bars the tube's edge was somewhere out in the bars.
//
// **The picture arrives as a uniform, set by `CrtOverlay`.** The obvious way
// to write this is to read the built-in `TEXTURE`, since this material is on
// the control that draws the game - but Godot's built-ins exist only inside
// `fragment()` and `vertex()`, and handing `TEXTURE` to a function of your own
// makes the shader compiler complain on every single compile. A plain uniform
// sidesteps the whole question and says where the picture comes from.
uniform sampler2D picture : repeat_disable, filter_linear;

// **Sampled through `sharpened`, below, which is neither nearest nor plain
// linear.** Both of those are wrong for a warped pixel-art picture and this
// shader has now shipped each of them:
//
//   * Plain linear blends every sample with its neighbours by whatever the
//     warp's fractional offset happens to be, so rows of text land on
//     different amounts of blur and some come out visibly softer than others.
//   * Nearest takes whole source pixels, which fixes that and introduces
//     stair-steps along every straight line instead - reported from play, and
//     the reason this third approach exists.
//
// `sharpened` keeps a source pixel flat across its whole area and puts the
// interpolation only in the last screen pixel at its edge. Flat inside, so no
// blur; one screen pixel of ramp at the boundary, so no step. D76 holds: this
// is still square pixels, drawn with their edges antialiased because the tube
// is bending them.

group_uniforms sampling;
// How many screen pixels the edge of a source pixel is smeared over when the
// warp displaces it. **This is the dial between the two faults this shader has
// had**, and neither end of it is good:
//
//   0  - nothing is smeared. Every source pixel is a hard square, and where
//        the curve displaces a row by one pixel you get a visible stair-step
//        in every straight line.
//   1  - the step's corner is softened and the step is still a whole source
//        pixel tall, so it still reads as a step. This was the first attempt.
//   ~2 - the step is spread over most of its own height and stops reading as
//        one, while the inside of each source pixel stays flat.
//   at the enlargement factor and above (3 at 1080p, 4 at 1440p) it is plain
//        bilinear: no steps at all, and text goes soft in patches, which is
//        the fault that started all of this.
uniform float edge_softness : hint_range(0.0, 4.0) = 2.0;

// How many times the picture is enlarged to fill the window: 3 at 1080p, 4 at
// 1440p. `Stage` sets it, through `CrtOverlay`, every time the window changes.
//
// **It is handed in rather than measured, because measuring it did not work.**
// The obvious way is `fwidth` of the sampling coordinate, which is what a
// screen-space derivative is for. Under the Compatibility renderer it comes
// back as zero: the ramp below then collapses to nothing and the filter
// silently degrades to nearest-neighbour, steps and all, with the softness
// control doing nothing whatsoever. That went unnoticed through two rounds of
// looking at it, because "crisp but stepped" is a plausible-looking picture.
// Rendering the same screen at softness 0 and softness 3 and differencing them
// is what caught it - 147 pixels out of 921,600, all of them scanline noise.
//
// **Nothing to adjust by hand.** The game overwrites it whenever the window
// changes, so a value typed into the Inspector is replaced within a frame.
uniform float enlargement : hint_range(1.0, 16.0) = 1.0;
group_uniforms;

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
// Lines down the picture. **360 is one line per row of the game's own image**,
// which is what a tube showing a 360-line signal would draw, and it is only
// reachable because the shader now runs at the monitor's resolution rather
// than the game's.
//
// **The clamp below is about where a fragment is sampled, not about pixels.**
// A line needs more than two rows of output to exist: a fragment is shaded at
// the centre of its row, so at exactly two rows per line the samples land on
// phases 0.25 and 0.75 of the sine, sin squared is equal at both, and every
// row comes out at precisely the mean. The pattern is there in the maths and
// invisible on the screen. That is not a guess - the first build of this
// effect asked for 180 lines over 360 rows and rendered a picture identical,
// row for row, to the one with the effect switched off.
//
// So a 1440-row monitor can carry all 360 of these, a 1080-row monitor can
// carry all 360 exactly, and a 720-row one is clamped to 240. Below that the
// comb coarsens rather than disappearing.
uniform float scanline_count = 360.0;
// Lowered from 0.30 on 2026-11-17 along with the bleed, then left alone when
// the comb got finer: a line is now one source row rather than three, so it
// cuts across a letter far less even at the same strength.
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


// A sample that keeps source pixels square without stair-stepping them.
//
// `density` is how many source pixels one screen pixel covers. Inside a pixel the
// result is that pixel's colour exactly; across its edge it ramps over about
// one screen pixel. With `density` very small - a picture enlarged many times
// - the ramp is a fraction of a source pixel and the picture is crisp; as the
// enlargement shrinks towards 1 the ramp widens and the picture degrades into
// ordinary bilinear rather than into aliasing.
vec2 sharpened(vec2 uv, vec2 source_size, vec2 density) {
	vec2 in_pixels = uv * source_size;

	// **The seam, not the centre.** `floor(x + 0.5)` is the nearest boundary
	// *between* two source pixels; `floor(x) + 0.5` would be the middle of one.
	// Getting that wrong inverts the whole filter - it then ramps across the
	// middle of every pixel and snaps at the edges, so nothing is ever flat and
	// the picture looks like pixel art scaled by a fraction. That is exactly
	// what it did when first written, and exactly what it was reported as.
	vec2 seam = floor(in_pixels + 0.5);

	// How far this sample is from that seam, measured in ramps, then clamped to
	// half a source pixel. Within the ramp the result slides from one source
	// pixel to the next; beyond it the clamp lands on a source pixel's own
	// centre, where bilinear returns that pixel's colour exactly.
	vec2 ramp = max(density * edge_softness, vec2(1e-5));
	vec2 from_seam = clamp((in_pixels - seam) / ramp, vec2(-0.5), vec2(0.5));
	return (seam + from_seam) / source_size;
}


vec3 sample_linear(vec2 uv, vec2 source_size, vec2 density) {
	return to_linear(texture(picture, sharpened(uv, source_size, density)).rgb);
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
vec3 horizontal_bleed(vec2 uv, float texel_x, vec2 source_size, vec2 density) {
	vec3 centre = sample_linear(uv, source_size, density);
	if (bleed_amount <= 0.0) {
		return centre;
	}

	float tau = max(bleed_falloff, 0.01);
	vec3 acc = centre;
	float weight_sum = 1.0;

	for (int i = 1; i <= BLEED_TAPS; i++) {
		float w = exp(-float(i) / tau);
		acc += sample_linear(
			uv - vec2(float(i) * texel_x, 0.0), source_size, density
		) * w;
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
vec3 beam_glow(vec2 uv, vec2 texel, vec2 source_size, vec2 density) {
	if (glow_strength <= 0.0) {
		return vec3(0.0);
	}

	vec3 acc = vec3(0.0);
	float weight_sum = 0.0;

	for (int y = -GLOW_RING; y <= GLOW_RING; y++) {
		for (int x = -GLOW_RING; x <= GLOW_RING; x++) {
			vec2 offset = vec2(float(x), float(y)) * glow_radius * texel;
			float w = exp(-float(x * x + y * y) * 0.5);
			acc += max(
				sample_linear(uv + offset, source_size, density) - glow_threshold,
				0.0
			) * w;
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
	// One source pixel, in the picture's own coordinates. Every distance in
	// this shader is a multiple of it, so the effect is the same size on a
	// 720p window and a 4K one. Taken from the picture itself rather than from
	// `TEXTURE_PIXEL_SIZE`, so nothing here depends on what the control this
	// material sits on happens to be drawing.
	vec2 source_size = vec2(textureSize(picture, 0));
	vec2 texel = 1.0 / source_size;

	// The rows the monitor actually has, which is the only thing the scanline
	// clamp needs and the one place window pixels are still the right unit.
	vec2 size = 1.0 / SCREEN_PIXEL_SIZE;

	vec2 uv = barrel_warp(UV, curvature);

	// How many source pixels one screen pixel covers. A whole-number
	// enlargement makes this the same in both axes and the same everywhere,
	// so the warp's own local stretching is ignored - it is a fraction of a
	// per cent across the picture and not worth a derivative that does not
	// work (see `enlargement`).
	vec2 density = vec2(1.0 / max(enlargement, 1.0));

	// The warp pushes the corners off the edge of the picture. Black those out
	// rather than leaving it to whatever the sampler's clamping does, which
	// smears the edge row outwards.
	vec2 inside = step(vec2(0.0), uv) * step(uv, vec2(1.0));
	float on_tube = inside.x * inside.y;

	vec3 col = horizontal_bleed(uv, texel.x, source_size, density);
	col += beam_glow(uv, texel, source_size, density);

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
