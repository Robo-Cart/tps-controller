extends StateMachine

const ROLL_ACTION: StringName = &"roll"
const DEFAULT_DOUBLE_TAP_WINDOW: float = 0.35
const DEFAULT_DOUBLE_TAP_MAX_HOLD: float = 0.25

@export var player_movement_stats: MovementStats
@export var animation_controller: AnimationController

var _roll_held: bool = false
var _roll_pressed_at: float = -INF
var _roll_released_at: float = -INF
var _roll_tap_pending: bool = false
var _swallow_next_release: bool = false
var _posture_before_gesture: bool = false


func _ready() -> void:
	for child in get_children():
		child.direction_updated.connect(animation_controller.on_character_input_direction_changed)
		child.animation_change_requested.connect(animation_controller.on_state_machine_state_change)

	_create_state_map()
	_set_active(false)


func _set_active(value: bool) -> void:
	if not value:
		_cancel_pending_tap()

	super._set_active(value)


func _input(event: InputEvent) -> void:
	# The roll input is swallowed here so a press never reaches the states as a
	# roll; a press toggles the crouch immediately, and a second press inside the
	# double tap window is forwarded as a roll instead.
	if event.is_action(ROLL_ACTION):
		_handle_roll_input(event)
		return

	super._input(event)


func _on_camera_model_view_changed(view: bool) -> void:
	_set_active(!view)


func _handle_roll_input(event: InputEvent) -> void:
	if event.is_action_released(ROLL_ACTION):
		_handle_roll_released()
		return

	# Key echo repeats the press while held; joypad buttons do not.
	if not event.is_action_pressed(ROLL_ACTION) or _roll_held:
		return

	_handle_roll_pressed()


func _handle_roll_pressed() -> void:
	_roll_held = true
	_roll_pressed_at = _now()

	var is_double_tap: bool = (
		_roll_tap_pending and _now() - _roll_released_at <= _get_double_tap_window()
	)

	if is_double_tap:
		_roll_tap_pending = false
		# A roll costs stamina. When the pool is too low the gesture is dropped
		# rather than forwarded, so the roll state never has to refuse a roll it
		# has already started playing.
		if not Stamina.can_roll():
			return
		# The release that ends this gesture is part of the roll, not a new
		# crouch tap, so swallow it when it arrives.
		_swallow_next_release = true
		# The first press already committed the crouch, so the roll has to act as
		# if it started from the posture held before the gesture began. Otherwise
		# a roll out of standing would exit back into the crouch.
		Motion.crouched = _posture_before_gesture
		_send_action_event(ROLL_ACTION)
		return

	# A single tap toggles the crouch on the press itself. Waiting out the double
	# tap window first, to be sure it was not the first half of a roll, is what
	# made crouching feel laggy.
	_posture_before_gesture = Motion.crouched
	_roll_tap_pending = true

	# Moving fast turns the same tap into a slide. The tap stays pending, so a
	# second press inside the window still rolls out of the slide.
	if _try_start_slide():
		return

	if current_state != null:
		current_state._crouch_toggle_requested()


func _handle_roll_released() -> void:
	_roll_held = false

	if _swallow_next_release:
		_swallow_next_release = false
		return

	# Only short presses count as a tap, so holding the button cannot be the
	# first half of a double tap.
	var held_duration: float = _now() - _roll_pressed_at
	if held_duration < 0.0 or held_duration > _get_double_tap_max_hold():
		_roll_tap_pending = false
		return

	_roll_released_at = _now()


func _get_double_tap_window() -> float:
	if player_movement_stats == null:
		return DEFAULT_DOUBLE_TAP_WINDOW
	return player_movement_stats.roll_double_tap_window


## Starts a slide when the current state is willing to take the tap, and reports
## whether it did. The speed the slide needs is checked by the state itself, so a
## slide already in progress can take the tap at any speed and roll out of it.
## The crouch states get asked too: pointing down a steep enough face turns the
## tap into a slide instead of standing the player back up, and they say no when
## the ground is too gentle for that.
func _try_start_slide() -> bool:
	if current_state == null:
		return false

	return current_state._slide_requested()


func _get_double_tap_max_hold() -> float:
	if player_movement_stats == null:
		return DEFAULT_DOUBLE_TAP_MAX_HOLD
	return player_movement_stats.roll_double_tap_max_hold


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _cancel_pending_tap() -> void:
	_roll_tap_pending = false


func _send_action_event(action: StringName) -> void:
	if current_state == null:
		return

	var action_event := InputEventAction.new()
	action_event.action = action
	action_event.pressed = true
	current_state._state_input(action_event)
