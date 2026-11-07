extends Motion


func _state_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		if not try_climb():
			finished.emit("Jump")

	if event.is_action_pressed("sprint") and Stamina.can_sprint():
		sprint_toggled = true
		finished.emit("Sprint")

	if event.is_action_pressed("aim"):
		finished.emit("AimWalk")

	if event.is_action_pressed("roll"):
		finished.emit("Roll")


func _crouch_toggle_requested() -> void:
	finished.emit("CrouchIdle")


func _slide_requested() -> bool:
	if not is_travelling_fast_enough_to_slide():
		return false

	finished.emit("Slide")
	return true


func _update(delta: float) -> void:
	set_direction()
	calculate_velocity(speed, direction, PLAYER_MOVEMENT_STATS.acceleration, delta)
	Stamina.regenerate(delta)
	direction_updated.emit(input_dir)

	if direction == Vector3.ZERO:
		finished.emit("Idle")

	if not is_grounded():
		finished.emit("Fall")
