extends Projectile
class_name RigidBodyProjectile

@export var projectile_velocity: int = 100
@export var expirey_time: int = 10
@export var rigid_body_bullet: PackedScene


func _set_weapon_projectile(weapon: Weapon, _model: WeaponModel) -> void:
	var camera_collision: Vector3 = _camera_ray_cast()
	launch_rigid_projectile(camera_collision, _model, rigid_body_bullet, weapon.impact_force)
	get_tree().create_timer(expirey_time).timeout.connect(on_expirey_timeout)


func launch_rigid_projectile(
	point: Vector3, _model: WeaponModel, bullet: PackedScene, impact_force: float = 0.0
) -> void:
	var _projectile: RigidBodyBullet = bullet.instantiate()

	_projectile.top_level = true
	_projectile.position = _model.bullet_point.global_position

	add_child(_projectile)
	_projectile.look_at(point)
	_projectile.impact_force = impact_force

	var direction: Vector3 = (point - _model.bullet_point.global_position).normalized()
	_projectile.set_linear_velocity(direction * projectile_velocity)


func on_expirey_timeout() -> void:
	queue_free()
