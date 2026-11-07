class_name Crouch
extends Motion

signal aim_entered
signal aim_exited

var is_aiming: bool = false


func _enter() -> void:
	super._enter()
	crouched = true

	# Aiming no longer leaves the crouch, so resume the aim pose when the crouch
	# is re-entered while the aim input is still held (for example after a roll).
	if Input.is_action_pressed("aim"):
		_start_aiming()


func _exit() -> void:
	_stop_aiming()
	super._exit()


func _crouch_toggle_requested() -> void:
	# Standing up under a low ceiling would push the full height capsule into it,
	# so the crouch is held until there is room. Every branch below leaves the
	# crouch, so the check belongs here rather than in each one.
	if not can_stand_up():
		return

	if is_aiming:
		# Hand the aim straight to the standing aim state, which emits
		# aim_entered itself, so drop the flag without exiting the camera aim.
		is_aiming = false
		finished.emit("AimWalk" if _has_movement_input() else "AimIdle")
		return

	finished.emit("Run" if _has_movement_input() else "Idle")


func _handle_aim_input(event: InputEvent) -> void:
	if event.is_action_pressed("aim"):
		_start_aiming()
	elif event.is_action_released("aim"):
		_stop_aiming()


func _start_aiming() -> void:
	if is_aiming:
		return

	is_aiming = true
	aim_entered.emit()


func _stop_aiming() -> void:
	if not is_aiming:
		return

	is_aiming = false
	aim_exited.emit()


func _has_movement_input() -> bool:
	return Input.get_vector("left", "right", "up", "down") != Vector2.ZERO


## A crouch on a steep enough face tips into a slide when the player points the
## stick downhill and taps the roll input. Reporting false is just as important
## as reporting true: it is what lets the same tap fall through to the crouch
## toggle and stand the player back up on gentler ground.
func _slide_requested() -> bool:
	if get_slope_angle() < PLAYER_MOVEMENT_STATS.slide_min_slope_angle:
		return false

	if not is_directed_downhill():
		return false

	finished.emit("Slide")
	return true


## Hands the crouch over to a slide when the face is too steep to crouch on,
## and reports whether it did. Unlike the roll tap this needs no input: the stance
## itself is the gesture, and the slope picks the direction, because a crouch
## standing still has no momentum to slide on and the player might be facing
## uphill. The crouch states call this every frame they are held.
func _maybe_start_slide() -> bool:
	if not is_grounded():
		return false

	if get_slope_angle() < PLAYER_MOVEMENT_STATS.slide_min_slope_angle:
		return false

	var downhill := get_downhill_direction()
	if downhill.is_zero_approx():
		return false

	slide_direction_override = downhill
	finished.emit("Slide")
	return true
