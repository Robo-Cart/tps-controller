extends Area3D
class_name HitBox

signal damage_take(_damage: float)

func _ready() -> void:
	body_entered.connect(on_damage_body_entered)
	
func on_damage_body_entered(body: Node3D) -> void:
	if body is RigidBodyBullet:
		damage_take.emit(body.damage)
