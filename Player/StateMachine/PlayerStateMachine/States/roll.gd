extends Motion

@export var animation_controller: AnimationController

var roll_direction: Vector3 = Vector3.ZERO
var roll_duration: float = 0.0
var roll_timer: float = 0.0
var started_crouched: bool = false


func _enter() -> void:
	# Roll sets `crouched` back to false through Motion._enter(), so remember the
	# posture we came from before any of that runs.
	started_crouched = crouched

	roll_duration = maxf(PLAYER_MOVEMENT_STATS.roll_duration, 0.05)
	roll_timer = roll_duration
	roll_direction = _get_roll_direction()
	direction_updated.emit(input_dir)

	# The roll is gated before it gets here, so this is the payment. Drain rather
	# than spend so a forced roll still works even if the gate was bypassed.
	Stamina.drain(PLAYER_MOVEMENT_STATS.roll_stamina_cost)

	animation_controller.on_roll_started(roll_duration, roll_direction)

	return super._enter()


func _exit() -> void:
	animation_controller.on_roll_finished()

	return super._exit()


func _update(delta: float) -> void:
	roll_timer -= delta

	var progress: float = 1.0 - clampf(roll_timer / roll_duration, 0.0, 1.0)
	# Decay towards the exit speed rather than towards zero. Bleeding all of the
	# speed out at the end of the roll is what reads as the player stopping dead
	# before run/sprint picks back up.
	var speed_blend: float = 1.0 - pow(progress, 3.0)
	var current_roll_speed: float = lerpf(
		_get_exit_speed(), PLAYER_MOVEMENT_STATS.roll_speed, speed_blend
	)

	velocity.x = roll_direction.x * current_roll_speed
	velocity.z = roll_direction.z * current_roll_speed

	calculate_gravity(delta)
	velocity_updated.emit(velocity)

	if not is_grounded():
		finished.emit("Fall")
		return

	if roll_timer <= 0.0:
		_finish_roll()


func _get_exit_speed() -> float:
	var fraction: float = maxf(PLAYER_MOVEMENT_STATS.roll_exit_speed_fraction, 0.0)
	return PLAYER_MOVEMENT_STATS.run_speed * fraction


func _get_roll_direction() -> Vector3:
	set_direction()

	if direction != Vector3.ZERO:
		return direction

	var forward: Vector3 = -owner.global_transform.basis.z
	forward.y = 0.0
	return forward.normalized()


func _finish_roll() -> void:
	set_direction()

	# Standing up at the end of a roll pushes the full height capsule into
	# whatever the roll just went under, so a roll that ends without headroom
	# stays down and finishes in the crouch instead.
	var must_crouch: bool = started_crouched or not can_stand_up()

	if direction == Vector3.ZERO:
		finished.emit("CrouchIdle" if must_crouch else "Idle")
		return

	# Hand the leftover momentum to the next state so run/sprint starts from the
	# roll's exit speed instead of accelerating from a standstill.
	_apply_exit_velocity()

	if must_crouch:
		finished.emit("CrouchWalk")
	elif sprint_toggled and Stamina.can_sprint():
		finished.emit("Sprint")
	else:
		finished.emit("Run")


func _apply_exit_velocity() -> void:
	var exit_speed: float = _get_exit_speed()
	velocity.x = roll_direction.x * exit_speed
	velocity.z = roll_direction.z * exit_speed
	velocity_updated.emit(velocity)
