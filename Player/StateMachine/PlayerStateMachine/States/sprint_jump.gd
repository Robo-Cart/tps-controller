extends Motion

signal sprint_ended


func _enter() -> void:
	jump()
	return super._enter()


func _update(delta: float) -> void:
	set_direction()
	calculate_gravity(delta)
	calculate_velocity(
		get_jump_horizontal_speed(sprint_speed),
		direction,
		PLAYER_MOVEMENT_STATS.in_air_acceleration,
		delta
	)
	direction_updated.emit(input_dir)

	Stamina.drain(PLAYER_MOVEMENT_STATS.sprint_stamina_drain * delta)
	if Stamina.is_empty():
		sprint_toggled = false
		sprint_ended.emit()
		finished.emit("Fall")
		return

	if velocity.y <= 0:
		finished.emit("SprintFall")


func jump() -> void:
	start_jump(sprint_speed)


func _state_input(event: InputEvent) -> void:
	if try_air_climb_from_input(event):
		return

	if event.is_action_released("jump"):
		cut_jump_on_release()
	elif event.is_action_pressed("sprint"):
		sprint_toggled = false
		sprint_ended.emit()
		finished.emit("Fall")
