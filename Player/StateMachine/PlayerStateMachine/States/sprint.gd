extends Motion

signal sprint_started
signal sprint_ended


func _enter() -> void:
	sprint_started.emit()
	return super._enter()


func _state_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		if not try_climb():
			finished.emit("SprintJump")
	elif event.is_action_pressed("roll"):
		finished.emit("Roll")
	elif event.is_action_pressed("sprint"):
		sprint_toggled = false
		sprint_ended.emit()
		finished.emit("Run" if direction != Vector3.ZERO else "Idle")


func _crouch_toggle_requested() -> void:
	sprint_toggled = false
	sprint_ended.emit()
	finished.emit("CrouchIdle")


func _slide_requested() -> bool:
	if not is_travelling_fast_enough_to_slide():
		return false

	# The sprint itself is kept so a slide out of a sprint can hand the player
	# back to it with the remaining stamina instead of dropping to a run.
	finished.emit("Slide")
	return true


func _update(delta: float) -> void:
	set_direction()

	# Sprint is a ground state: it drives the horizontal speed directly and never
	# applies gravity, so running off a ledge would leave the player sprinting in
	# mid-air. The carry-over momentum belongs to the air state instead, which
	# hands the sprint back once there is floor underfoot again.
	if not is_grounded():
		finished.emit("SprintFall")
		return

	# The sprint is only held while the player is fully committed to it. Easing
	# the stick back is asking to slow down, so a half-pushed stick ends the
	# sprint instead of walking along at a reduced pace with the whole drain still
	# being paid. Checked before the drain so the frame the player eases off is
	# not charged.
	if input_dir.length() < PLAYER_MOVEMENT_STATS.sprint_min_input:
		sprint_toggled = false
		sprint_ended.emit()
		finished.emit("Run" if direction != Vector3.ZERO else "Idle")
		return

	calculate_velocity(sprint_speed, direction, PLAYER_MOVEMENT_STATS.acceleration, delta)
	direction_updated.emit(input_dir)

	Stamina.drain(PLAYER_MOVEMENT_STATS.sprint_stamina_drain * delta)

	if Stamina.is_empty():
		sprint_toggled = false
		sprint_ended.emit()
		finished.emit("Run")
		return
