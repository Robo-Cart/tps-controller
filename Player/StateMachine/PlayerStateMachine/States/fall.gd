extends Motion

@export var floor_ray_cast: RayCast3D


func _state_input(event: InputEvent) -> void:
	try_air_climb_from_input(event)


func _update(delta: float) -> void:
	set_direction()
	calculate_gravity(delta)
	calculate_velocity(
		get_jump_horizontal_speed(speed),
		direction,
		PLAYER_MOVEMENT_STATS.in_air_acceleration,
		delta
	)

	if floor_ray_cast.is_colliding():
		if direction != Vector3.ZERO:
			animation_change_requested.emit("Run")
		else:
			animation_change_requested.emit("Idle")

	# Landing is a grounded landing, not merely a floor contact: the body can
	# touch the lip of a ledge with its feet over the drop, and taking that for a
	# landing is what flickered the player between Run and Fall on the edge.
	if is_grounded():
		if direction != Vector3.ZERO:
			finished.emit("Run")
		else:
			finished.emit("Idle")
