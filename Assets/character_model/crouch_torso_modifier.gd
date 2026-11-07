class_name CrouchTorsoModifier
extends SkeletonModifier3D

## Twists the torso around the character's up axis while the crouch animation is
## playing.
##
## The crouch clips are unarmed poses and the hand IK that normally lines a drawn
## weapon up with the aim target is suspended while crouched, so the weapon keeps
## the wrist orientation baked into the clip and sits slightly off centre. This
## modifier rotates everything above the spine as one piece to bring it back.

## Bone the twist is applied to. Everything above it (chest, head, arms) follows.
@export var bone_name: StringName = &"mixamorig_Spine1"

## How quickly the twist blends in and out, in degrees per second of blend.
@export var blend_speed: float = 10.0

var _target_degrees: float = 0.0
var _current_degrees: float = 0.0
var _bone_index: int = -1


func set_target_degrees(degrees: float) -> void:
	_target_degrees = degrees


func _process_modification_with_delta(delta: float) -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null:
		return

	if _bone_index < 0:
		_bone_index = skeleton.find_bone(bone_name)
		if _bone_index < 0:
			return

	_current_degrees = lerpf(
		_current_degrees, _target_degrees, clampf(delta * blend_speed, 0.0, 1.0)
	)

	if is_zero_approx(_current_degrees):
		return

	var yaw: Quaternion = Quaternion(_get_up_axis(skeleton), deg_to_rad(_current_degrees))
	var pose: Quaternion = skeleton.get_bone_pose_rotation(_bone_index)
	skeleton.set_bone_pose_rotation(_bone_index, yaw * pose)


func _get_up_axis(skeleton: Skeleton3D) -> Vector3:
	# The bone pose is stored relative to its parent, so the twist axis has to be
	# converted into the parent's space or the torso would be rotated about an
	# axis running along the spine instead of up through it.
	var parent_index: int = skeleton.get_bone_parent(_bone_index)
	if parent_index < 0:
		return Vector3.UP

	var parent_basis: Basis = skeleton.get_bone_global_pose(parent_index).basis
	if parent_basis.determinant() == 0.0:
		return Vector3.UP

	var axis: Vector3 = parent_basis.inverse() * Vector3.UP
	if is_zero_approx(axis.length()):
		return Vector3.UP

	return axis.normalized()
