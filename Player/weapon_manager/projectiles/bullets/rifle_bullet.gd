class_name RigidBodyBullet
extends RigidBody3D

## Burst spawned where the bullet lands. Kept on the bullet so every weapon that
## shares this projectile throws the same debris.
const IMPACT_SCENE: PackedScene = preload("res://Assets/effects/bullet_impact/bullet_impact.tscn")

## How far behind the bullet the contact probe starts. A bullet covers a good
## fraction of a metre per physics step, so the probe has to look back along the
## path it just travelled to find the face it hit.
const CONTACT_PROBE_BACK: float = 0.25

## How far past the bullet the contact probe looks. The capsule sticks out about
## 0.355 m ahead of the body origin, so the origin stops that far short of the
## surface it struck and the probe has to reach past it to find the face.
const CONTACT_PROBE_FORWARD: float = 0.6

@export var damage: float = 1.0
@export var impact_force: float = 5.0

var _impact_started: bool = false


func _on_body_entered(body: Node) -> void:
	if body is RigidBody3D:
		apply_impact_force(body)
	if _impact_started:
		return
	_impact_started = true
	_impact_next_frame()


func apply_impact_force(body: RigidBody3D) -> void:
	# -Z is the bullet's forward axis (set by look_at in the projectile).
	var direction: Vector3 = -global_transform.basis.z.normalized()
	var impact_offset: Vector3 = global_position - body.global_position
	body.apply_impulse(direction * impact_force, impact_offset)


## The contact signal can arrive before the body has settled against the surface
## it hit, so the burst waits one physics frame. That keeps the probe below on the
## face the bullet actually struck instead of the empty space it was crossing.
func _impact_next_frame() -> void:
	await get_tree().physics_frame
	_spawn_impact()
	queue_free()


## Spawns the debris and dust burst on the face the bullet hit. The contact
## signal carries no surface data, so the hit is re-probed with a short ray along
## the bullet's path; when that misses, the bullet's own position and the
## backwards direction stand in so the effect still shows.
func _spawn_impact() -> void:
	var direction: Vector3 = -global_transform.basis.z.normalized()
	var point: Vector3 = global_position
	var normal: Vector3 = -direction
	var hit: Dictionary = _probe_surface(
		global_position - direction * CONTACT_PROBE_BACK,
		global_position + direction * CONTACT_PROBE_FORWARD
	)
	if not hit.is_empty():
		point = hit.get("position", point)
		normal = hit.get("normal", normal)

	var host: Node = get_tree().current_scene
	if host == null:
		host = get_tree().root
	var impact: BulletImpact = IMPACT_SCENE.instantiate()
	host.add_child(impact)
	impact.global_position = point
	impact.spray(normal)


func _probe_surface(from: Vector3, to: Vector3) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collision_mask = collision_mask
	query.hit_from_inside = false
	return get_world_3d().direct_space_state.intersect_ray(query)
