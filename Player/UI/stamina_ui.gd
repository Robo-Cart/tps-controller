extends Control

## Colour of a full pool and of an empty one. The fill travels between the two as
## the pool drains, so the bar warns before a sprint cuts out or a roll is
## refused instead of only reporting the empty state.
const FILL_FULL: Color = Color(0.35, 0.85, 0.75, 1.0)
const FILL_EMPTY: Color = Color(0.88, 0.4, 0.28, 1.0)

## Same low-poly palette as the pause menu, so the bar reads as part of the HUD
## rather than as an overlay stuck on top of it.
const BACKGROUND_COLOR: Color = Color(0.075, 0.105, 0.11, 0.72)
const BORDER_COLOR: Color = Color(0.26, 0.56, 0.52, 0.9)
const BORDER_WIDTH: int = 1
const CORNER_RADIUS: int = 3

## Gap (in pixels) between the frame and the fill, so the border always shows.
const FILL_INSET: float = 2.0

## How fast the bar follows the pool, in 1/s. Sprinting is already smooth, so
## this is really about the one-off costs: a roll should read as a drop, not as
## the bar jumping.
const FOLLOW_SPEED: float = 18.0

## Opacity the bar settles at while the pool is full, so a rested player is not
## staring at a full bar the whole time. It brightens as soon as anything is
## spent.
const IDLE_OPACITY: float = 0.4
const ACTIVE_OPACITY: float = 1.0
const OPACITY_SPEED: float = 6.0

## Below this the pool counts as full for the purpose of fading the bar out.
## get_fraction() lands exactly on 1.0 at full, but the smoothing approaches it.
const FULL_THRESHOLD: float = 0.999

var _shown_fraction: float = 1.0
var _opacity: float = IDLE_OPACITY

var _background: Panel
var _fill: ColorRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_shown_fraction = Stamina.get_fraction()
	_update_bar()


func _process(delta: float) -> void:
	var target := Stamina.get_fraction()
	_shown_fraction = lerpf(_shown_fraction, target, 1.0 - exp(-FOLLOW_SPEED * delta))

	var wanted_opacity := IDLE_OPACITY if target >= FULL_THRESHOLD else ACTIVE_OPACITY
	_opacity = move_toward(_opacity, wanted_opacity, OPACITY_SPEED * delta)

	_update_bar()


func _build() -> void:
	_background = Panel.new()
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = BACKGROUND_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(BORDER_WIDTH)
	style.set_corner_radius_all(CORNER_RADIUS)
	_background.add_theme_stylebox_override("panel", style)
	add_child(_background)

	_fill = ColorRect.new()
	_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fill.offset_left = FILL_INSET
	_fill.offset_top = FILL_INSET
	_fill.offset_right = -FILL_INSET
	_fill.offset_bottom = -FILL_INSET
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.color = FILL_FULL
	add_child(_fill)


## Drives the fill from offsets rather than from size, so the bar lays itself out
## with the same anchors as its frame and stays correct at any resolution.
func _update_bar() -> void:
	var track_width := maxf(size.x - FILL_INSET * 2.0, 0.0)
	_fill.offset_right = -(FILL_INSET + track_width * (1.0 - _shown_fraction))
	_fill.color = FILL_EMPTY.lerp(FILL_FULL, clampf(_shown_fraction, 0.0, 1.0))
	modulate.a = _opacity
