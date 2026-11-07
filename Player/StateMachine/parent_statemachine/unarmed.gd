extends CombatTransitionState


func _state_input(event: InputEvent) -> void:
	if event.is_action_pressed("holster_weapon"):
		finished.emit("Armed")

func _on_camera_model_view_changed(view: bool) -> void:
	state_machine._set_active(!view)
