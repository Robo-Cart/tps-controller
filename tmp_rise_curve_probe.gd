extends SceneTree

var _frames: int = 0


func _initialize() -> void:
	var scene: PackedScene = load("res://Player/player.tscn")
	var player: Node3D = scene.instantiate()
	root.add_child(player)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false

	var player: Node3D = root.get_child(0)
	var controller: AnimationController = player.get_node("CharacterModel")
	for style: StringName in [&"low", &"high"]:
		var curve: PackedFloat32Array = controller.get_climb_rise_curve(style)
		var line: String = ""
		for index: int in range(curve.size()):
			line += "%.3f " % curve[index]
		print(
			"style=",
			style,
			" duration=%.3f samples=%d" % [controller.get_climb_duration(style), curve.size()]
		)
		print("  rise: ", line)

	quit()
	return true
