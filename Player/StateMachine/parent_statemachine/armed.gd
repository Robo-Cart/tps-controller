extends CombatTransitionState

@export var _weapon_manager: WeaponManager

func _state_input(event: InputEvent) -> void:
	if event.is_action_pressed("holster_weapon"):
		finished.emit("Unarmed")
		
	if event.is_action_pressed("drop"):
		var weapons: float = _weapon_manager.drop_weapon()
		
		if weapons == 0:
			finished.emit("Unarmed")

func _on_camera_model_view_changed(view: bool) -> void:
	state_machine._set_active(!view)
