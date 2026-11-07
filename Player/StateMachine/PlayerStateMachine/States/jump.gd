extends Motion


func _enter() -> void:
	jump()
	return super._enter()


func _state_input(event: InputEvent) -> void:
	if try_air_climb_from_input(event):
		return

	if event.is_action_released("jump"):
		cut_jump_on_release()


func _update(delta: float) -> void:
	set_direction()
	calculate_gravity(delta)
	calculate_velocity(
		get_jump_horizontal_speed(speed),
		direction,
		PLAYER_MOVEMENT_STATS.in_air_acceleration,
		delta
	)
	#direction_updated.emit(input_dir)

	if velocity.y <= 0:
		finished.emit("Fall")


func jump() -> void:
	start_jump(speed)
