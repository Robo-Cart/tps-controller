extends SceneTree


func _init() -> void:
	var paths: Array[String] = [
		"res://Assets/character_model/fbx_animations/Armature_crouch_idle_loop_fit.res",
		"res://Assets/character_model/fbx_animations/Armature_crouch_fwd_loop_fit.res",
		"res://Assets/character_model/fbx_animations/Armature_Crouching Idle_fit.res",
		"res://Assets/character_model/fbx_animations/Armature_crouch_fwd_loop_fit.res",
	]
	for path: String in paths:
		var anim: Animation = load(path) as Animation
		if anim == null:
			print("FAILED ", path)
			continue
		print(
			"ANIM ",
			path.get_file(),
			" len=",
			anim.length,
			" loop=",
			anim.loop_mode,
			" tracks=",
			anim.get_track_count()
		)
		for i: int in anim.get_track_count():
			var track_path: NodePath = anim.track_get_path(i)
			if (
				String(track_path).contains("Hips")
				and anim.track_get_type(i) == Animation.TYPE_POSITION_3D
			):
				var keys: int = anim.track_get_key_count(i)
				print("  HIPS keys=", keys)
				print(
					"  HIPS t0=",
					anim.track_get_key_time(i, 0),
					" v=",
					anim.track_get_key_value(i, 0)
				)
				print(
					"  HIPS t1=",
					anim.track_get_key_time(i, 1),
					" v=",
					anim.track_get_key_value(i, 1)
				)
				print(
					"  HIPS last=",
					anim.track_get_key_time(i, keys - 1),
					" v=",
					anim.track_get_key_value(i, keys - 1)
				)
				break
	quit()
