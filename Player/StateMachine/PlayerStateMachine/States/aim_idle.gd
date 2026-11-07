extends Motion

signal aim_entered
signal aim_exited


func _enter() -> void:
	aim_entered.emit()
	return super._enter()


func _state_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		aim_exited.emit()
		finished.emit("Jump")

	if event.is_action_released("aim"):
		aim_exited.emit()
		finished.emit("Idle")


func _crouch_toggle_requested() -> void:
	finished.emit("CrouchIdle")


func _update(delta: float) -> void:
	set_direction()
	calculate_velocity(aim_speed, direction, PLAYER_MOVEMENT_STATS.acceleration, delta)
	Stamina.regenerate(delta)

	if direction != Vector3.ZERO:
		finished.emit("AimWalk")

	if not is_grounded():
		aim_exited.emit()
		finished.emit("Fall")
