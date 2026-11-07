extends Area3D

signal ammo_detected(ammo_pick_up: AmmoPickUp)
signal weapon_detected(weapon_pick_up: WeaponPickUp)

func _on_body_entered(body: Node3D) -> void:
	if body is AmmoPickUp:
		ammo_detected.emit(body)
		
	if body is WeaponPickUp:
		if body.pick_up_ready:
			weapon_detected.emit(body)
