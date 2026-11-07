class_name EmoteMenu
extends Control

## Radial emote wheel. It only draws and highlights; the emote controller owns
## the input and decides when a segment is committed.

## Largest number of emotes the wheel will show. The ring is divided evenly, so
## two emotes get half a circle each and eight get a 45 degree slice.
const MAX_SEGMENTS: int = 8
const OUTER_RADIUS: float = 150.0
const INNER_RADIUS: float = 74.0
const SEGMENT_GAP: float = 0.035
const ARC_SAMPLE_STEP: float = PI / 24.0
const LABEL_FONT_SIZE: int = 16
const TITLE_FONT_SIZE: int = 22
const HINT_FONT_SIZE: int = 13
const BACKDROP_COLOR: Color = Color(0.02, 0.03, 0.05, 0.6)
const HUB_COLOR: Color = Color(0.05, 0.07, 0.1, 0.82)
const SEGMENT_COLOR: Color = Color(0.22, 0.27, 0.35, 0.92)
const SEGMENT_SELECTED_COLOR: Color = Color(0.29, 0.83, 0.62, 0.97)
const LABEL_COLOR: Color = Color(0.9, 0.93, 0.97, 0.95)
const LABEL_SELECTED_COLOR: Color = Color(0.04, 0.08, 0.07, 1.0)
const HINT_COLOR: Color = Color(0.9, 0.93, 0.97, 0.5)

var _labels: PackedStringArray = PackedStringArray()
var _highlight: int = -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Shows the wheel with one segment per label. Anything past MAX_SEGMENTS is
## dropped, so a longer emote list cannot draw segments on top of each other.
func open(labels: PackedStringArray) -> void:
	_labels = labels.slice(0, MAX_SEGMENTS)
	_highlight = -1
	visible = true
	queue_redraw()


func close() -> void:
	visible = false
	_labels = PackedStringArray()
	_highlight = -1


## Marks the segment the look input is pointing at. -1 clears the highlight.
func set_highlight(index: int) -> void:
	var clamped: int = clampi(index, -1, _labels.size() - 1)
	if clamped == _highlight:
		return

	_highlight = clamped
	queue_redraw()


func _draw() -> void:
	if _labels.is_empty():
		return

	var centre: Vector2 = size * 0.5
	draw_circle(centre, OUTER_RADIUS + 12.0, BACKDROP_COLOR)
	draw_circle(centre, INNER_RADIUS - 4.0, HUB_COLOR)

	var step: float = TAU / float(_labels.size())
	for index: int in range(_labels.size()):
		_draw_segment(centre, index, step)
		_draw_segment_label(centre, index, step)

	_draw_hub_text(centre)


func _draw_segment(centre: Vector2, index: int, step: float) -> void:
	# Segment zero is centred on the top of the ring and the rest follow
	# clockwise, which is the same convention the controller maps input with.
	var start: float = -PI * 0.5 + (float(index) - 0.5) * step + SEGMENT_GAP * 0.5
	var end: float = start + step - SEGMENT_GAP
	var samples: int = maxi(2, int(ceil((end - start) / ARC_SAMPLE_STEP)))
	var points: PackedVector2Array = PackedVector2Array()

	for sample: int in range(samples + 1):
		var angle: float = lerpf(start, end, float(sample) / float(samples))
		points.append(centre + Vector2(cos(angle), sin(angle)) * OUTER_RADIUS)
	for sample: int in range(samples, -1, -1):
		var angle: float = lerpf(start, end, float(sample) / float(samples))
		points.append(centre + Vector2(cos(angle), sin(angle)) * INNER_RADIUS)

	var color: Color = SEGMENT_SELECTED_COLOR if index == _highlight else SEGMENT_COLOR
	draw_colored_polygon(points, color)


func _draw_segment_label(centre: Vector2, index: int, step: float) -> void:
	var font: Font = ThemeDB.fallback_font
	var angle: float = -PI * 0.5 + step * float(index)
	var radius: float = (OUTER_RADIUS + INNER_RADIUS) * 0.5
	var anchor: Vector2 = centre + Vector2(cos(angle), sin(angle)) * radius
	var label: String = _labels[index]
	var text_size: Vector2 = font.get_string_size(
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE
	)
	var baseline: Vector2 = anchor - Vector2(text_size.x * 0.5, -text_size.y * 0.35)
	var color: Color = LABEL_SELECTED_COLOR if index == _highlight else LABEL_COLOR

	draw_string(font, baseline, label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, color)


func _draw_hub_text(centre: Vector2) -> void:
	var font: Font = ThemeDB.fallback_font
	var title: String = _labels[_highlight] if _highlight >= 0 else "Emote"
	var title_size: Vector2 = font.get_string_size(
		title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FONT_SIZE
	)
	var title_origin: Vector2 = centre - Vector2(title_size.x * 0.5, -6.0)

	draw_string(
		font, title_origin, title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FONT_SIZE, LABEL_COLOR
	)

	var hint: String = "Release to play" if _highlight >= 0 else "Steer to choose"
	var hint_size: Vector2 = font.get_string_size(
		hint, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_FONT_SIZE
	)
	var hint_origin: Vector2 = centre - Vector2(hint_size.x * 0.5, -30.0)

	draw_string(font, hint_origin, hint, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_FONT_SIZE, HINT_COLOR)
