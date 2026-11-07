class_name BulletImpact
extends Node3D

## How long the burst lingers after its longest-lived particle has expired, so
## the last drawn frame is not cut off when the node frees itself.
const CLEAR_MARGIN: float = 0.35

@onready var debris: GPUParticles3D = $Debris
@onready var dust: GPUParticles3D = $Dust


func _ready() -> void:
	var linger: float = maxf(debris.lifetime, dust.lifetime) + CLEAR_MARGIN
	get_tree().create_timer(linger).timeout.connect(queue_free)


## Starts the burst, throwing it back out of the surface it was spawned on.
## `normal` is the surface normal where the bullet landed; a zero vector falls
## back to straight up, which at worst looks like a puff off the ground.
func spray(normal: Vector3) -> void:
	var direction: Vector3 = normal.normalized()
	if direction.length_squared() < 0.5:
		direction = Vector3.UP
	_aim(debris, direction)
	_aim(dust, direction)
	debris.emitting = false
	dust.emitting = true


## Points an emitter's spray along `direction`. The process material is duplicated
## per scene instance (it is marked local to the scene), so this only affects one
## burst and two impacts at different angles can live at the same time.
func _aim(emitter: GPUParticles3D, direction: Vector3) -> void:
	var material: ParticleProcessMaterial = emitter.process_material as ParticleProcessMaterial
	if material == null:
		return
	material.direction = direction
