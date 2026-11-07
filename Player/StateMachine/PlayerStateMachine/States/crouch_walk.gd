extends Crouch


func _state_input(event: InputEvent) -> void:
	_handle_aim_input(event)

	if event.is_action_pressed("jump"):
		_stop_aiming()
		finished.emit("Jump")

	if event.is_action_pressed("roll"):
		finished.emit("Roll")


func _update(delta: float) -> void:
	if _maybe_start_slide():
		return

	set_direction()
	calculate_velocity(crouch_speed, direction, PLAYER_MOVEMENT_STATS.acceleration, delta)
	Stamina.regenerate(delta)
	direction_updated.emit(input_dir)

	if direction == Vector3.ZERO:
		finished.emit("CrouchIdle")

	if not is_grounded():
		finished.emit("Fall")
