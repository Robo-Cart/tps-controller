extends Control

@onready var current_ammo_label: Label = $HBoxContainer/CurrentAmmoLabel
@onready var reserve_ammo_label: Label = $HBoxContainer/ReserveAmmoLabel


func _on_weapon_manager_ammo_updated(_weapon: Weapon) -> void:
	update_ammo_text(_weapon)

func update_ammo_text(_weapon: Weapon) -> void:
	if _weapon.current_ammo:
		current_ammo_label.text = str(_weapon.current_ammo.ammount)
	else:
		current_ammo_label.text = "0"
	
	var reserve_ammo: int = 0
	
	for i in _weapon.reserve_ammo:
		reserve_ammo += i.ammount
	
	reserve_ammo_label.text = str(reserve_ammo)

func _on_weapon_manager_weapon_manager_started(_status: String, _weapon: Weapon, _model: WeaponModel) -> void:
	update_ammo_text(_weapon)
	show()

func _on_weapon_manager_weapon_manager_finished(_status: String, _weapons_is_empty: bool) -> void:
	hide()
