@tool
class_name NewsChartCanvas
extends GraphEdit
## The News Flow tab's chart: Godot's `GraphEdit` with an arrowhead on every
## connection, so you can see which way a chain runs. A plain `GraphEdit`
## draws a line with nothing to say which end is which.
##
## The head sits on the end that **requires**: an arrow from A to B means
## "B requires A" (docs/news-flow-chart.md, "Words used here").
##
## The line is the same curve `GraphEdit` draws by default; the head is two
## more strokes added to the end of it. `@tool` because it runs inside the
## editor.


## The length and half-width of the head, before zoom.
const HEAD_LENGTH: float = 14.0
const HEAD_HALF_WIDTH: float = 7.0

## How finely the curve is drawn, as `Curve2D.tessellate` takes it.
const CURVE_STAGES: int = 5
const CURVE_TOLERANCE_DEGREES: float = 2.0


## The points of the connection from `from_position` to `to_position`: the
## default curve, then the head at `to_position`, drawn as one line out to
## each barb and back.
func _get_connection_line(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	var points: PackedVector2Array = curve_points(from_position, to_position, connection_lines_curvature)
	var back: Vector2 = Vector2.LEFT * HEAD_LENGTH * zoom
	var side: Vector2 = Vector2.UP * HEAD_HALF_WIDTH * zoom
	points.append(to_position + back + side)
	points.append(to_position)
	points.append(to_position + back - side)
	return points


## The curve `GraphEdit` draws between two ports by default: it leaves and
## arrives horizontally, bent by `curvature`.
static func curve_points(from_position: Vector2, to_position: Vector2, curvature: float) -> PackedVector2Array:
	if curvature <= 0.0:
		return PackedVector2Array([from_position, to_position])
	var handle: float = absf(to_position.x - from_position.x) * curvature
	var curve: Curve2D = Curve2D.new()
	curve.add_point(from_position, Vector2.ZERO, Vector2(handle, 0.0))
	curve.add_point(to_position, Vector2(-handle, 0.0), Vector2.ZERO)
	return curve.tessellate(CURVE_STAGES, CURVE_TOLERANCE_DEGREES)
