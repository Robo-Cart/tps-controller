extends CharacterBody3D

@export var health: float = 5.0


func _on_hit_box_damage_take(_damage: float) -> void:
	health -= _damage
	if health <= 0:
		self.hide()

		await get_tree().create_timer(3).timeout
		health = 5

		self.show()
