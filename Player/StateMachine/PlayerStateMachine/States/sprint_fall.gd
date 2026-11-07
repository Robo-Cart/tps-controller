extends Motion

signal sprint_ended

@export var floor_ray_cast: RayCast3D


func _state_input(event: InputEvent) -> void:
	if try_air_climb_from_input(event):
		return

	if event.is_action_pressed("sprint"):
		sprint_toggled = false
		sprint_ended.emit()
		if is_grounded():
			finished.emit("Run" if direction != Vector3.ZERO else "Idle")
		else:
			finished.emit("Fall")


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

	if is_grounded():
		# Landing hands the sprint back only if the player is still committed to
		# it. Handing it over with the stick eased back would enter Sprint for a
		# single frame before its own stick check dropped straight out again.
		if (
			sprint_toggled
			and Stamina.can_sprint()
			and input_dir.length() >= PLAYER_MOVEMENT_STATS.sprint_min_input
		):
			finished.emit("Sprint")
		elif direction != Vector3.ZERO:
			sprint_toggled = false
			sprint_ended.emit()
			finished.emit("Run")
		else:
			sprint_toggled = false
			sprint_ended.emit()
			finished.emit("Idle")
