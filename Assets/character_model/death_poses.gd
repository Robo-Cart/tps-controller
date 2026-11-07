extends RefCounted

## Where a corpse is drawn once it has come to rest. Two kinds of target live here: a share
## of each joint's own range, which is hand authored, and the turn captured from an authored
## death clip, which is a real pose. It lives in its own file because this is data, and
## because the ragdoll is at its line limit.

## The clip a body that fell face down is aimed at, read at its last key: that is where the
## clip leaves the body, which is what a corpse looks like.
const FRONT_CLIP: String = "res://Assets/character_model/merge_animations/dead_front.res"

## How squarely the trunk has to face the floor before a body counts as lying on its front,
## as the dot of its front with up. Slacker than this and a body on its side is counted, and
## pulled over onto its face.
const FACE_DOWN_DOT: float = 0.35

const HIPS_BONE: StringName = &"mixamorig_Hips"

## The rest pose axes the front is built from: the chest gives up and the two hip joints give
## the character's right, so their cross is the front however the rig was authored. The toes
## cannot be used for this, because they point at the floor as much as they point forward.
const UP_BONE: StringName = &"mixamorig_Spine2"
const LEFT_LEG_BONE: StringName = &"mixamorig_LeftUpLeg"
const RIGHT_LEG_BONE: StringName = &"mixamorig_RightUpLeg"

## How far the killing blow is scattered either side of the model's own front, in radians, so
## that two deaths do not come to rest in the same shape.
const HIT_SPREAD: float = 0.5

## How fast a corpse is rolled onto its front, in radians a second. Faint, because the body is
## driven rather than thrown, so the roll reads as a body slumping the last way over.
const ROLL_RATE: float = 3.0

## Where a joint is drawn as the body comes to rest, as (flexion, swing, twist) shares of its
## own range: 0 is the lower stop, 1 the upper, and 0.5 the middle, which is the rest pose on
## a joint that folds both ways. Scaling a joint back to the rest pose draws a man standing
## to attention, so the turn is pulled towards one of these. A knee runs folded at 0 to
## straight at 1, so trailing legs are shares close to 1.
const SETTLE_POSES: Array[Dictionary] = [
	{
		&"mixamorig_Spine2": Vector3(0.45, 0.5, 0.5),
		&"mixamorig_Neck": Vector3(0.45, 0.42, 0.5),
		&"mixamorig_Head": Vector3(0.5, 0.35, 0.78),
		&"mixamorig_LeftArm": Vector3(0.2, 0.38, 0.5),
		&"mixamorig_RightArm": Vector3(0.2, 0.62, 0.5),
		&"mixamorig_LeftForeArm": Vector3(0.22, 0.5, 0.5),
		&"mixamorig_RightForeArm": Vector3(0.28, 0.5, 0.5),
		&"mixamorig_LeftUpLeg": Vector3(0.16, 0.5, 0.5),
		&"mixamorig_RightUpLeg": Vector3(0.1, 0.5, 0.5),
		&"mixamorig_LeftLeg": Vector3(0.86, 0.5, 0.5),
		&"mixamorig_RightLeg": Vector3(0.93, 0.5, 0.5),
	},
	{
		&"mixamorig_Spine1": Vector3(0.34, 0.5, 0.5),
		&"mixamorig_Spine2": Vector3(0.4, 0.55, 0.5),
		&"mixamorig_Neck": Vector3(0.3, 0.6, 0.5),
		&"mixamorig_Head": Vector3(0.42, 0.6, 0.22),
		&"mixamorig_LeftArm": Vector3(0.32, 0.6, 0.5),
		&"mixamorig_RightArm": Vector3(0.32, 0.4, 0.5),
		&"mixamorig_LeftForeArm": Vector3(0.3, 0.5, 0.5),
		&"mixamorig_RightForeArm": Vector3(0.24, 0.5, 0.5),
		&"mixamorig_LeftUpLeg": Vector3(0.45, 0.5, 0.5),
		&"mixamorig_RightUpLeg": Vector3(0.4, 0.5, 0.5),
		&"mixamorig_LeftLeg": Vector3(0.72, 0.5, 0.5),
		&"mixamorig_RightLeg": Vector3(0.8, 0.5, 0.5),
	},
]


## The index the clip's turn is stored at: one past the share poses, because the clip target
## is appended to every joint rather than authored into that table.
static func clip_index() -> int:
	return SETTLE_POSES.size()


## The turn every bone holds on the clip's last key, keyed by bone name, or empty when the
## clip cannot be read so the caller falls back to the share poses.
static func load_clip_turns(path: String) -> Dictionary:
	var animation: Animation = load(path) as Animation
	if animation == null:
		push_warning("Death poses: nothing to load at %s." % path)
		return {}

	var turns: Dictionary = {}
	for track: int in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue

		var keys: int = animation.track_get_key_count(track)
		if keys <= 0:
			continue

		# Every clip is merged onto the one skeleton, so the subname is the bone.
		var bone: StringName = animation.track_get_path(track).get_concatenated_subnames()
		turns[bone] = animation.track_get_key_value(track, keys - 1)

	return turns


## The turn a share pose asks a joint to be drawn at, along the joint's own axes: a share is
## (flexion, swing, twist), the order the limits are written in.
static func resolve_share(
	share: Vector3, lower: Vector3, upper: Vector3, axes: Vector3i
) -> Quaternion:
	var target: Vector3 = Vector3.ZERO
	target[axes.y] = lerpf(lower[axes.y], upper[axes.y], share.x)
	target[axes.z] = lerpf(lower[axes.z], upper[axes.z], share.y)
	target[axes.x] = lerpf(lower[axes.x], upper[axes.x], share.z)
	return Basis.from_euler(target).get_rotation_quaternion()


## The way the trunk faces in the world, as the hips body carries it: the rest pose front
## turned by the frame the whole body turns in. Zero when the rig cannot be measured.
static func body_front(skeleton: Skeleton3D, hips: PhysicalBone3D) -> Vector3:
	if skeleton == null or hips == null:
		return Vector3.ZERO

	var front: Vector3 = _model_front(skeleton)
	if front.is_zero_approx():
		return Vector3.ZERO

	var hips_rest: Transform3D = skeleton.get_bone_global_rest(
		skeleton.find_bone(String(HIPS_BONE))
	)
	return hips.global_transform.basis * (hips_rest.basis.orthonormalized().inverse() * front)


## Turns a body that has come down on anything but its front over onto it, once the fall is
## over, and answers whether the corpse is lying on its front. Rolling is the only way to get
## there: with no tone left the knees fold, the body sits down on its own heels and falls back,
## so left alone it never reaches the face down pose the front clip is authored for.
static func roll_onto_front(skeleton: Skeleton3D, bodies: Dictionary) -> bool:
	var hips: PhysicalBone3D = bodies.get(skeleton.find_bone(String(HIPS_BONE))) as PhysicalBone3D
	var front: Vector3 = body_front(skeleton, hips)
	if front.is_zero_approx():
		return false

	if front.y < -FACE_DOWN_DOT:
		return true

	# About the axis the front and the floor between them give: this takes the front down.
	var spin: Vector3 = front.cross(Vector3.DOWN).normalized() * ROLL_RATE
	for body: PhysicalBone3D in bodies.values():
		if body != null:
			PhysicsServer3D.body_set_state(
				body.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, spin
			)

	return true


## The way the blow that killed the body pushes it.
static func hit_impulse_direction(skeleton: Skeleton3D) -> Vector3:
	var front: Vector3 = _world_front(skeleton)
	if front.is_zero_approx():
		return Vector3.ZERO

	var azimuth: float = randf_range(-HIT_SPREAD, HIT_SPREAD)
	return front.rotated(Vector3.UP, azimuth)


## The way the model faces in the world, flattened onto the floor so a death does not tip the
## body into it.
static func _world_front(skeleton: Skeleton3D) -> Vector3:
	var front: Vector3 = _model_front(skeleton)
	if front.is_zero_approx():
		return Vector3.ZERO

	var world_front: Vector3 = skeleton.global_transform.basis * front
	world_front.y = 0.0
	return world_front.normalized()


## The way the model faces in its own rest pose. It is built out of the rig itself, so no rig
## convention is assumed: up runs from the hips to the chest, right from the left hip joint to
## the right one, and their cross is the way the body faces.
static func _model_front(skeleton: Skeleton3D) -> Vector3:
	var up: Vector3 = _rest_direction(skeleton, HIPS_BONE, UP_BONE)
	var right: Vector3 = _rest_direction(skeleton, LEFT_LEG_BONE, RIGHT_LEG_BONE)
	if up.is_zero_approx() or right.is_zero_approx():
		return Vector3.ZERO

	# Square the two against each other, so a leaning spine cannot tip the front off level.
	right = (right - up * right.dot(up)).normalized()
	return up.cross(right)


## The rest pose's direction from one bone's joint to another's, or zero when either is
## missing from the skeleton.
static func _rest_direction(
	skeleton: Skeleton3D, from_bone: StringName, to_bone: StringName
) -> Vector3:
	var from_index: int = skeleton.find_bone(String(from_bone))
	var to_index: int = skeleton.find_bone(String(to_bone))
	if from_index < 0 or to_index < 0:
		return Vector3.ZERO

	return (
		(
			skeleton.get_bone_global_rest(to_index).origin
			- skeleton.get_bone_global_rest(from_index).origin
		)
		. normalized()
	)
