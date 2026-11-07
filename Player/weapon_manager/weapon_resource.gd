extends Resource
class_name Weapon

@export var name: String
@export var weapon_model: PackedScene
@export var auto_fire: bool = false

# Impulse (kg*m/s) applied to dynamic bodies hit by this weapon's bullets.
@export var impact_force: float = 5.0

@export var hand_position: Vector3
@export var hand_rotation: Vector3

@export var weapon_idle_animation: Animation
@export var weapon_shoot_animation: Animation
@export var weapon_reload_animation: Animation
@export var weapon_change_animation: Animation
@export_range(0.1, 3.0, 0.1) var weapon_change_speed_scale: float = 1.5

@export var current_ammo: Ammo
@export var reserve_ammo: Array[Ammo]
@export var max_ammo_clips: int = 2
@export var override_max_ammo: bool = false
@export var weapon_to_drop: PackedScene
