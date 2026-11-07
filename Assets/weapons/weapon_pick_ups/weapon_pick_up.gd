extends RigidBody3D
class_name WeaponPickUp

@export var weapon_pick_up: Weapon
@export var ammo_pick_up: Array[Ammo]
@export var pick_up_ready: bool = false

func _ready() -> void:
	await get_tree().create_timer(2).timeout
	pick_up_ready = true
