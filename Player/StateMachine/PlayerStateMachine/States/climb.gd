extends Motion

const CLIMB_REFERENCE_HEIGHT: float = 1.0
const CLIMB_HIGH_REFERENCE_HEIGHT: float = 1.7
const CLIMB_SPEED_MIN_SCALE: float = 0.75
const CLIMB_SPEED_MAX_SCALE: float = 1.2
const CLIMB_MIN_DURATION: float = 0.1
## How far up the clip's own rise the body has to be before it starts travelling
## over the ledge, so the capsule is clear of the face it is climbing.
const CLIMB_FORWARD_RISE_THRESHOLD: float = 0.8
## Part of the climb the overhead lift takes to reach its full height. It starts
## at zero so entering the climb does not snap the body upwards.
const CLIMB_OFFSET_RAMP: float = 0.15
## Largest share of the climb the rise delay is allowed to hold the body still
## for, so the remapped rise always has time to land on the ledge.
const CLIMB_MAX_RISE_DELAY_SHARE: float = 0.9

## Blend tree owner that plays the climb clip for as long as the state runs.
@export var animation_controller: AnimationController

var _start_position: Vector3 = Vector3.ZERO
var _target_position: Vector3 = Vector3.ZERO
var _style: StringName = &""
var _rise_curve: PackedFloat32Array = PackedFloat32Array()
var _rise_speed: float = 0.0
var _rise_delay: float = 0.0
var _height_offset: float = 0.0
var _duration: float = 0.0
var _elapsed: float = 0.0
var _is_climbing: bool = false


func _enter() -> void:
	_target_position = mantle_target
	mantle_target = Vector3.INF
	_style = mantle_style
	mantle_style = &""

	if not _target_position.is_finite():
		finished.emit("Idle")
		return

	_start_position = owner.global_position

	# The overhead climb reaches further than the regular one, so it gets its own
	# timing: the clip is authored for a hang it has to pull the body out of, and
	# the body has to clear the ledge before it can move over it.
	var is_overhead: bool = _style == AnimationController.CLIMB_STYLE_HIGH
	var reference_height: float = (
		CLIMB_HIGH_REFERENCE_HEIGHT if is_overhead else CLIMB_REFERENCE_HEIGHT
	)

	var rise: float = _target_position.y - _start_position.y
	var stretch: float = clampf(
		rise / reference_height, CLIMB_SPEED_MIN_SCALE, CLIMB_SPEED_MAX_SCALE
	)
	_duration = maxf(animation_controller.get_climb_duration(_style) * stretch, CLIMB_MIN_DURATION)
	_rise_curve = animation_controller.get_climb_rise_curve(_style)
	_rise_speed = _get_rise_speed()
	_rise_delay = _get_rise_delay(is_overhead)
	_height_offset = _get_height_offset(is_overhead)
	_elapsed = 0.0
	_is_climbing = true

	# The body height is scripted for the whole climb, so the step smoothing would
	# only lag behind it: the pose holds its hands on the ledge, and a model that
	# follows the body late slides them along it.

	# The body is positioned directly instead of being pushed by move_and_slide:
	# the capsule sits against the ledge face for most of the climb, and sliding
	# into it would cancel the horizontal part of the motion.
	velocity = Vector3.ZERO
	velocity_updated.emit(velocity)
	direction_updated.emit(input_dir)
	owner.visual_height_scripted = true
	animation_controller.on_climb_started(_duration, _style)

	super._enter()


func _exit() -> void:
	_is_climbing = false
	owner.visual_height_scripted = false
	animation_controller.on_climb_finished()


func _update(delta: float) -> void:
	if not _is_climbing:
		return

	_elapsed += delta
	var progress: float = clampf(_elapsed / _duration, 0.0, 1.0)

	# The body follows the clip's own height curve. The climb starts with the hands
	# gripping the ledge, so rising faster than the pose does lifts them off it; the
	# clip's hip translation is the height the artist drew those grabs against.
	var rise_progress: float = _sample_rise(_get_rise_time(progress))
	# The authored curve can outrun the body. The speed bias is a power warp, which
	# leaves both ends where they are: the rise is gentler through the middle while
	# the player still lands exactly on the ledge.
	if not is_equal_approx(_rise_speed, 1.0):
		rise_progress = pow(rise_progress, _rise_speed)
	# Travelling over the ledge waits until the body is most of the way up, or the
	# capsule moves through the face it is still climbing.
	var forward_progress: float = smoothstep(
		0.0,
		1.0,
		clampf(
			(rise_progress - CLIMB_FORWARD_RISE_THRESHOLD) / (1.0 - CLIMB_FORWARD_RISE_THRESHOLD),
			0.0,
			1.0
		)
	)

	var position: Vector3 = _target_position
	position.y = lerpf(_start_position.y, _target_position.y, rise_progress)
	position.y += _sample_height_offset(progress, rise_progress)
	position.x = lerpf(_start_position.x, _target_position.x, forward_progress)
	position.z = lerpf(_start_position.z, _target_position.z, forward_progress)
	owner.global_position = position

	velocity = Vector3.ZERO
	velocity_updated.emit(velocity)
	Stamina.regenerate(delta)

	if progress >= 1.0:
		_finish_climb()


## How fast the body is allowed to follow the authored rise. Read from the player
## so the pace can be tuned without touching the state, and kept above zero so the
## power warp stays monotonic.
func _get_rise_speed() -> float:
	var player: Node = owner
	if player == null:
		return 1.0

	return maxf(player.climb_rise_speed, 0.01)


## Seconds the body holds its starting height before it starts to rise. Only the
## overhead climb needs one: it opens on a hang and the body lifting through that
## beat drags the hands off the ledge they are gripping. Capped to most of the
## climb so the remapped rise still reaches the ledge.
func _get_rise_delay(is_overhead: bool) -> float:
	if not is_overhead:
		return 0.0

	var player: Node = owner
	if player == null:
		return 0.0

	var delay: float = player.climb_high_rise_delay
	return clampf(delay, 0.0, _duration * CLIMB_MAX_RISE_DELAY_SHARE)


## Normalised time the rise curve is sampled at. The delay holds the body where it
## started and the rest of the curve is stretched over the climb that is left, so
## the body still tops out exactly when the clip ends.
func _get_rise_time(progress: float) -> float:
	if _rise_delay <= 0.0 or _duration <= 0.0:
		return progress

	var delay_share: float = clampf(_rise_delay / _duration, 0.0, CLIMB_MAX_RISE_DELAY_SHARE)
	return clampf((progress - delay_share) / (1.0 - delay_share), 0.0, 1.0)


## Height offset the body is moved by for this climb style. Only the overhead
## climb needs one: the regular climb starts with the hands at hip height, while
## the braced hang grabs the ledge well above the hips and would otherwise drag
## the body up to a height its hands were never drawn at.
func _get_height_offset(is_overhead: bool) -> float:
	if not is_overhead:
		return 0.0

	var player: Node = owner
	if player == null:
		return 0.0

	return player.climb_high_vertical_offset


## How much of the overhead lift applies at a normalised time. It comes in over
## the grab and is gone by the time the body reaches the ledge, so the player
## still lands flush on the surface instead of hovering above it.
func _sample_height_offset(progress: float, rise_progress: float) -> float:
	if is_zero_approx(_height_offset):
		return 0.0

	var grab: float = smoothstep(0.0, CLIMB_OFFSET_RAMP, progress)
	return _height_offset * grab * (1.0 - rise_progress)


## Fraction of the climb height the clip's animation has reached at a normalised
## time. Falls back to an even rise when the clip had no height baked in.
func _sample_rise(progress: float) -> float:
	var last: int = _rise_curve.size() - 1
	if last < 0:
		return smoothstep(0.0, 1.0, progress)

	if last == 0:
		return _rise_curve[0]

	var position: float = clampf(progress, 0.0, 1.0) * float(last)
	var index: int = mini(int(position), last - 1)
	return lerpf(_rise_curve[index], _rise_curve[index + 1], position - float(index))


func _finish_climb() -> void:
	_is_climbing = false
	owner.global_position = _target_position
	velocity = Vector3.ZERO
	velocity_updated.emit(velocity)

	set_direction()
	if direction == Vector3.ZERO:
		finished.emit("Idle")
	elif sprint_toggled and Stamina.can_sprint():
		finished.emit("Sprint")
	else:
		finished.emit("Run")
