extends Motion

## Momentum slide: the player drops into a slide, keeps travelling on the speed
## they arrived with and bleeds it off at a share of `slide_friction` instead of
## the much harder braking normal movement uses, so how far they go is a direct
## result of how fast they were moving when they started. It is also where a
## crouch ends up on a face too steep to crouch on, which enters it at its floor
## speed heading downhill whether or not the player was moving.

## How long the slide holds on through a surface reading that dropped out. The
## capsule rides over small bumps in the face that lose the ground for a frame,
## and the flat that reads for those frames was ending shallow slides halfway
## down the slope. Long enough to cover a few frames, short enough that a slide
## really running out on the flat still ends when it should.
const READING_GRACE: float = 0.12

@export var animation_controller: AnimationController

var slide_direction: Vector3 = Vector3.ZERO
var slide_speed: float = 0.0
var slide_time: float = 0.0
var ground_lost_time: float = 0.0
var slope_fed_time: float = 0.0
var entry_duration: float = 0.0
var cancelled: bool = false


func _enter() -> void:
	# Momentum is read before super._enter() runs so the direction is the one the
	# player arrived with, not whatever the idle/run default would be.
	slide_direction = _get_slide_direction()
	slide_speed = _get_horizontal_speed()
	slide_time = 0.0
	ground_lost_time = 0.0
	slope_fed_time = 0.0
	cancelled = false
	entry_duration = animation_controller.get_slide_start_duration()

	super._enter()
	animation_controller.on_slide_started(slide_direction)


func _exit() -> void:
	animation_controller.on_slide_finished(cancelled)
	super._exit()


func _state_input(event: InputEvent) -> void:
	# A second tap of the shared roll input is the roll, so a slide can be
	# cancelled straight into a roll. Jumping out of a slide keeps its momentum
	# because the jump reads the velocity the slide has left.
	if event.is_action_pressed("roll"):
		_start_roll()
		return

	if event.is_action_pressed("jump"):
		cancelled = true
		finished.emit("Jump")


## A tap of the roll input while sliding rolls out of the slide, whatever speed
## the slide has left. With an empty pool the tap is ignored and the slide
## carries on instead of paying for a roll it cannot afford.
func _slide_requested() -> bool:
	if not Stamina.can_roll():
		return false

	_start_roll()
	return true


func _start_roll() -> void:
	if not Stamina.can_roll():
		return

	cancelled = true
	finished.emit("Roll")


func _update(delta: float) -> void:
	slide_time += delta
	_update_speed(delta)

	velocity.x = slide_direction.x * slide_speed
	velocity.z = slide_direction.z * slide_speed

	calculate_gravity(delta)
	velocity_updated.emit(velocity)
	Stamina.regenerate(delta)

	# Only losing the ground for longer than the grace ends the slide. The foot
	# IK's support reading drops out for a frame when the body rides over a bump
	# in the face, and treating that as going airborne cut a shallow slide short
	# and dropped the player back into Run halfway down.
	if is_grounded() or is_on_floor():
		ground_lost_time = 0.0
	else:
		ground_lost_time += delta
		if ground_lost_time >= READING_GRACE:
			finished.emit("Fall")
			return

	# The slope latches for the same reason: on a face steep enough to keep
	# driving the slide, the odd frame that cannot be measured must not be read as
	# the flat ground that lets the slide end.
	if _is_slope_feeding():
		slope_fed_time = READING_GRACE
	else:
		slope_fed_time = maxf(slope_fed_time - delta, 0.0)

	# The entry clip has to play out before the exit pose can stand the character
	# back up, so a slide started at the minimum speed holds its last speed until
	# the animation has dropped into the slide.
	if slide_time < entry_duration:
		return

	# Nothing can be measured while the ground reading is out.
	if ground_lost_time > 0.0:
		return

	# A slope that is still feeding the slide holds it open even once the friction
	# has bled it down to the end speed, so a crouch tipped into a slide downhill
	# descends the whole face instead of flickering out after the entry clip.
	if slide_speed <= PLAYER_MOVEMENT_STATS.slide_end_speed and slope_fed_time <= 0.0:
		_finish_slide()


## Bleeds the slide's speed at whatever friction the face still has, with the
## slope's pull added on, and keeps the result between the end speed and the
## ceiling. Friction is given up as the face steepens while the pull grows with
## `sin(angle)`, so a descent gains speed towards a ceiling the flat never reaches.
func _update_speed(delta: float) -> void:
	var slowest := PLAYER_MOVEMENT_STATS.slide_end_speed
	var fastest := maxf(_get_slide_max_speed(), slowest)
	var change := (_get_slope_gain() - _get_slide_friction()) * delta
	slide_speed = clampf(slide_speed + change, slowest, fastest)


## Friction (in m/s^2) the ground takes off the slide this frame. It comes from
## the surface pressing back on the body, so the less of the face there is to
## press back the less of it the slide keeps: level ground holds the full
## `slide_friction`, and a face as steep as the player can stand on gives no more
## than `slide_slope_friction`. That is what lets a descent build speed out of its
## own pull instead of merely losing less of it.
func _get_slide_friction() -> float:
	return lerpf(
		PLAYER_MOVEMENT_STATS.slide_friction,
		PLAYER_MOVEMENT_STATS.slide_slope_friction,
		_get_slope_blend()
	)


## Speed (in m/s) the slide is allowed to reach on this face: `slide_max_speed` on
## the flat, up to `slide_slope_max_speed` on a face as steep as the player can
## stand on. It is a ceiling rather than a target, so a slide still on level
## ground never gets near the higher one.
func _get_slide_max_speed() -> float:
	var slope_speed: float = maxf(
		PLAYER_MOVEMENT_STATS.slide_slope_max_speed, PLAYER_MOVEMENT_STATS.slide_max_speed
	)
	return lerpf(PLAYER_MOVEMENT_STATS.slide_max_speed, slope_speed, _get_slope_blend())


## 0 on level ground up to 1 on the steepest face the player can stand on,
## measured against the owner's own slope limit. The slide blends both its
## friction and its ceiling with it, so the two move together.
func _get_slope_blend() -> float:
	var steepest := maxf(get_max_slope_angle(), 0.5)
	return clampf(inverse_lerp(0.0, steepest, get_slope_angle()), 0.0, 1.0)


## Acceleration (in m/s^2) the slope adds to the slide, or 0 when it is running
## on the flat or pointed up the face. It is `slide_slope_acceleration * sin(angle)`,
## so a face shoves harder the steeper it gets; `_update_speed()` subtracts the
## slide's friction from it and clamps the result at the face's ceiling, which is
## what stops a long descent from running away.
func _get_slope_gain() -> float:
	var angle := get_slope_angle()
	if angle <= 0.0:
		return 0.0

	var downhill := get_downhill_direction()
	if downhill.is_zero_approx():
		return 0.0

	var travel := Vector3(slide_direction.x, 0.0, slide_direction.z)
	if travel.dot(downhill) <= 0.0:
		return 0.0

	return PLAYER_MOVEMENT_STATS.slide_slope_acceleration * sin(deg_to_rad(angle))


## Whether the face is steep enough, and the slide pointed far enough downhill,
## for the slope to keep driving the slide along.
func _is_slope_feeding() -> bool:
	if get_slope_angle() < PLAYER_MOVEMENT_STATS.slide_min_slope_angle:
		return false

	var downhill := get_downhill_direction()
	if downhill.is_zero_approx():
		return false

	var travel := Vector3(slide_direction.x, 0.0, slide_direction.z)
	return travel.dot(downhill) > 0.0


func _finish_slide() -> void:
	# Hand what is left of the momentum to the next state so it does not start
	# from a standstill.
	velocity.x = slide_direction.x * slide_speed
	velocity.z = slide_direction.z * slide_speed
	velocity_updated.emit(velocity)

	set_direction()

	# The slide ran on the short capsule, and standing up grows the shape
	# upwards. Under a ceiling the slide fitted under there is no room for that,
	# so the player stays crouched instead of standing up into it. The stand-up
	# clip is skipped as well, since the player is not standing.
	if not can_stand_up():
		cancelled = true
		finished.emit("CrouchWalk" if direction != Vector3.ZERO else "CrouchIdle")
		return

	if direction == Vector3.ZERO:
		finished.emit("Idle")
		return

	if sprint_toggled and Stamina.can_sprint():
		finished.emit("Sprint")
	else:
		finished.emit("Run")


## The slide travels wherever the momentum was pointing when it started, falling
## back to the input direction and then to the way the player is facing. A crouch
## that tipped into a slide on its own has none of those worth using, so it hands
## the downhill direction over instead.
func _get_slide_direction() -> Vector3:
	if not slide_direction_override.is_zero_approx():
		var forced := slide_direction_override
		slide_direction_override = Vector3.ZERO
		return forced

	var momentum := Vector3(velocity.x, 0.0, velocity.z)
	if momentum.length() > 0.01:
		return momentum.normalized()

	set_direction()
	if direction != Vector3.ZERO:
		return direction

	var forward: Vector3 = -owner.global_transform.basis.z
	forward.y = 0.0
	return forward.normalized()


func _get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()
