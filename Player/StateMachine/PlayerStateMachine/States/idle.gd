extends Motion


func _state_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		if not try_climb():
			finished.emit("Jump")

	if event.is_action_pressed("aim"):
		finished.emit("AimIdle")

	if event.is_action_pressed("roll"):
		finished.emit("Roll")


func _crouch_toggle_requested() -> void:
	finished.emit("CrouchIdle")


func _update(delta: float) -> void:
	set_direction()
	calculate_velocity(speed, direction, PLAYER_MOVEMENT_STATS.acceleration, delta)
	Stamina.regenerate(delta)

	if direction != Vector3.ZERO:
		finished.emit("Run")

	if not is_grounded():
		finished.emit("Fall")
