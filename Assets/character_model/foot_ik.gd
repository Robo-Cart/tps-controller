class_name FootIk
extends Node3D

## Plants the feet on the ground under them and reports whether there is any.
##
## The clips are drawn for flat ground, so on a slope the uphill foot sinks into
## the surface and the downhill foot floats over it, and a foot standing beside a
## step never reaches the step's surface. Probing the ground under each foot and
## shifting the foot by the difference against the ground under the body fixes
## both, and leaves the pose untouched on flat ground where the difference is
## zero.
##
## The hips are where the animation put them, so a foot that moves has to be
## absorbed by the leg that holds it: the knee bends, and the ankle rolls onto the
## surface. The leg is kept inside a band of bends it can actually hold weight in,
## because a knee pulled straight cannot reach any further and instead levers the
## hips off their vertical, and a knee folded to its stop lifts the foot off the
## ground it was meant to find.
##
## The same probes answer whether there is ground under the body at all, which is
## what keeps the player from standing on the corner of a ledge with their feet
## hanging over the drop.

const SIDE_NAMES: Array[String] = ["Left", "Right"]
const FOOT_BONES: Array[StringName] = [&"mixamorig_LeftFoot", &"mixamorig_RightFoot"]
const UP_LEG_BONES: Array[StringName] = [&"mixamorig_LeftUpLeg", &"mixamorig_RightUpLeg"]
const TOE_BONES: Array[StringName] = [&"mixamorig_LeftToeBase", &"mixamorig_RightToeBase"]

## Distance (in metres) above a foot the ground probe starts from, so a foot that
## has sunk into the surface still finds the surface it sank into.
@export var probe_lift: float = 0.4

## Furthest (in metres) a foot is dropped to reach ground below it. Anything
## further down is a drop rather than a slope or a step, so the foot hangs.
@export var max_foot_drop: float = 0.35

## Furthest (in metres) a foot is lifted onto ground above it.
@export var max_foot_raise: float = 0.3

## Fraction of the leg's full length the knee may straighten to. Below one the
## leg keeps a bend in reserve, which is what lets the foot still reach further
## down instead of the hip being pulled to its stop.
@export var leg_reach_limit: float = 0.99

## Fraction of the leg's full length the knee may fold to. A foot lifted onto a
## step shortens the leg, and past this point the fold is deeper than a leg can
## stand on, so the foot stops following the surface up.
@export var leg_fold_limit: float = 0.72

## How much of the surface's slope the ankle rolls onto, from zero (the sole
## stays level, as the clips draw it) to one (the sole lies flat on the surface).
@export var ankle_align: float = 1.0

## Steepest surface (in degrees) the ankle rolls onto. Steeper than this is a
## step face or a wall rather than ground a sole can plant on.
@export var ankle_align_limit: float = 40.0

## Smallest dot product between the surface normal and up that still counts as
## ground to stand on. A vertical face reads as zero.
@export var ankle_flat_normal: float = 0.5

## Height (in metres above the feet) the support probe starts from.
@export var support_lift: float = 0.1

## How far (in metres) below the feet the ground can fall away before the player
## counts as standing on nothing. The stair snap reaches much further down than
## this, so it has to be tighter than the snap length to notice a ledge.
@export var support_distance: float = 0.25

## Distance (in metres) the ground may sit below a foot or toe bone and still
## count as standing on the foot. The bones ride about a hand's width above the
## sole, so this reaches a little under the sole.
@export var support_foot_reach: float = 0.35

## Seconds the support reading has to stay empty before the player counts as
## standing on nothing. One missed frame is not a ledge: a step-up lifts the body
## clear of the ground for a frame or two while it moves onto the step. That is
## the only case it exists for, so it only runs while [member support_grace_hold]
## is set; anywhere else an empty reading is a fall, on the frame it happens.
@export var support_grace_time: float = 0.06

## Speed the feet blend at, in blends per second.
@export var blend_speed: float = 12.0

## Set while a step-up is lifting the body onto a step, which is when an empty
## support reading is expected for a frame or two. Owned by the collision body,
## which is the only thing that knows a step is in progress.
var support_grace_hold: bool = false

var _skeleton: Skeleton3D
var _body: CollisionObject3D
var _foot_indices: Array[int] = []
## Hip and knee of each leg, in the same order as the feet. Both are what the leg
## length is measured over, which is what keeps the knee inside its band of bends.
var _hip_indices: Array[int] = []
var _knee_indices: Array[int] = []
## Bones whose sole decides whether there is ground to stand on: the ankle of each
## foot, which covers the heel, and the toe, which covers the ball.
var _support_indices: Array[int] = []
var _targets: Array[Marker3D] = []
var _offsets: Array[float] = []
var _has_support: bool = true
var _unsupported_time: float = 0.0


## Wires the rig up. Called once by the character model, which owns the skeleton
## and the collision body the probes borrow their layer and RID from.
func setup(skeleton: Skeleton3D, armature: Node3D, body: CollisionObject3D) -> void:
	_skeleton = skeleton
	_body = body

	for slot: int in range(SIDE_NAMES.size()):
		var foot_index: int = skeleton.find_bone(FOOT_BONES[slot])
		var hip_index: int = skeleton.find_bone(UP_LEG_BONES[slot])
		if foot_index < 0 or hip_index < 0:
			continue

		_foot_indices.append(foot_index)
		_hip_indices.append(hip_index)
		# The knee is the bone the foot hangs off, so it needs no name of its own
		# and no rig is excluded by calling it something else.
		_knee_indices.append(skeleton.get_bone_parent(foot_index))
		_offsets.append(0.0)
		_support_indices.append(foot_index)

		# The toe is what leaves the ledge first when the body walks off it, so it
		# is part of the footprint too. A rig without toe bones still works: the
		# ankle alone covers the whole foot.
		var toe_index: int = skeleton.find_bone(TOE_BONES[slot])
		if toe_index >= 0:
			_support_indices.append(toe_index)

		var target := Marker3D.new()
		target.name = SIDE_NAMES[slot] + "FootTarget"
		armature.add_child(target)
		target.global_transform = _get_foot_transform(foot_index)
		_targets.append(target)

		# Rooted at the hip and ending on the foot, the chain covers the two bones
		# a leg bends at and leaves the hips where the animation put them. Both ends
		# are named before the chain enters the tree: each setter rebuilds the
		# chain, and a half named one rebuilds as a broken chain.
		var chain := SkeletonIK3D.new()
		chain.name = SIDE_NAMES[slot] + "FootIk"
		chain.root_bone = UP_LEG_BONES[slot]
		chain.tip_bone = FOOT_BONES[slot]
		skeleton.add_child(chain)

		# Only the height and the roll onto the surface are being corrected, so the
		# foot keeps the orientation the clip gave it instead of being turned to
		# face the target marker.
		chain.override_tip_basis = true
		chain.target_node = chain.get_path_to(target)
		# The targets are placed from the pose the animation tree just left, so the
		# solve has to come after this node has run.
		chain.process_priority = 10
		chain.start()
		chain.influence = 1.0


## Whether there is ground under the body, within reach of the feet. False while
## the player hangs over the edge of a ledge or is in the air.
func has_ground_under_feet() -> bool:
	return _has_support


func _process(delta: float) -> void:
	if _body == null or _skeleton == null:
		return

	var up: Vector3 = _body.up_direction
	var weight: float = clampf(delta * blend_speed, 0.0, 1.0)
	var feet: Vector3 = _body.global_position
	var body_ground: float = _probe_ground(feet + up * probe_lift, probe_lift + max_foot_drop)
	_update_support(delta)

	for slot: int in range(_foot_indices.size()):
		var foot: Transform3D = _get_foot_transform(_foot_indices[slot])
		var hit: Dictionary = _probe_hit(foot.origin + up * probe_lift, probe_lift + max_foot_drop)

		# The offset is measured against the ground under the body rather than
		# against the foot's own height, so flat ground reads as zero and only the
		# surface directly under the foot moves it.
		var target_offset: float = 0.0
		if not hit.is_empty() and is_finite(body_ground):
			var position: Vector3 = hit.get("position", Vector3.INF)
			target_offset = clampf(position.y - body_ground, -max_foot_drop, max_foot_raise)
			target_offset = _limit_offset(slot, foot.origin, up, target_offset)

		_offsets[slot] = lerpf(_offsets[slot], target_offset, weight)

		# The ankle rolls onto the surface as well as being moved to it. A sole
		# held level on a slope meets the ground on one edge only, which is what
		# makes the uphill leg read as standing on its toes.
		var basis: Basis = foot.basis
		if not hit.is_empty():
			var normal: Vector3 = hit.get("normal", up)
			basis = _tilt_ankle(basis, normal, up)

		_targets[slot].global_transform = Transform3D(basis, foot.origin + up * _offsets[slot])


## Tracks whether there is ground under the body. An empty reading is a fall on
## the frame it happens, except during the step-up window, where the body is
## expected to be briefly clear of the ground it is stepping onto.
func _update_support(delta: float) -> void:
	if _probe_support():
		_unsupported_time = 0.0
		_has_support = true
		return

	if not support_grace_hold:
		_unsupported_time = support_grace_time
		_has_support = false
		return

	_unsupported_time += delta
	if _unsupported_time >= support_grace_time:
		_has_support = false


## Whether a sole has ground within reach of it. The answer has to come from the
## feet rather than from the body: the capsule rests on its centre axis, so a
## probe under the body keeps the player standing on the lip of a ledge with both
## feet already out over the drop.
func _probe_support() -> bool:
	var up: Vector3 = _body.up_direction
	var reach: float = support_lift + support_foot_reach

	for bone_index: int in _support_indices:
		var from: Vector3 = _get_foot_transform(bone_index).origin + up * support_lift
		if is_finite(_probe_ground(from, reach)):
			return true

	# A posture that tucks the feet out of the way, such as a roll, leaves no sole
	# anywhere near the ground the body is still lying on, so the centre axis
	# counts as well. It is a single probe, so it adds no footprint of its own to
	# overhang the drop.
	var body_from: Vector3 = _body.global_position + up * support_lift
	return is_finite(_probe_ground(body_from, support_lift + support_distance))


## World transform the animation tree left the foot in. The IK chains write their
## result as a pose override, so this stays the pose being corrected instead of
## the pose that was corrected last frame.
func _get_foot_transform(foot_index: int) -> Transform3D:
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(foot_index)


## World position of a bone in the pose the animation tree left it in.
func _get_bone_position(bone_index: int) -> Vector3:
	return (_skeleton.global_transform * _skeleton.get_bone_global_pose(bone_index)).origin


## Clamps a foot offset to the range the knee can hold, measured from the hip the
## animation put the leg under. The hips are fixed, so the only thing that can
## take up a foot moving is the bend in the knee, and both of its stops ruin the
## stance: a leg pulled straight stops reaching and instead drags the hips down
## with it, and a leg folded onto its stop holds the foot above the ground it was
## reaching for.
func _limit_offset(slot: int, foot_origin: Vector3, up: Vector3, offset: float) -> float:
	if _knee_indices[slot] < 0:
		return offset

	var hip: Vector3 = _get_bone_position(_hip_indices[slot])
	var knee: Vector3 = _get_bone_position(_knee_indices[slot])
	var reach: float = hip.distance_to(knee) + knee.distance_to(foot_origin)
	if reach <= 0.0001:
		return offset

	# How far the ankle is from the hip, as a function of the offset, is a circle
	# around the hip, so the offset that gives the leg a given length is a root of
	# a quadratic. The root nearer the pose is the edge of the allowed range.
	var to_hip: Vector3 = hip - foot_origin
	var along: float = to_hip.dot(up)
	var square: float = to_hip.length_squared()

	var lowest: float = -max_foot_drop
	var straight: float = _span_offset(along, square, reach * leg_reach_limit)
	if is_finite(straight):
		lowest = maxf(lowest, minf(straight, 0.0))

	var highest: float = max_foot_raise
	var folded: float = _span_offset(along, square, reach * leg_fold_limit)
	if is_finite(folded):
		highest = minf(highest, maxf(folded, 0.0))

	return clampf(offset, lowest, highest)


## Offset along [param up] at which the ankle sits exactly [param span] metres from
## the hip, or INF when the leg cannot hold that length straight up or down.
func _span_offset(along: float, square: float, span: float) -> float:
	var discriminant: float = along * along - square + span * span
	if discriminant <= 0.0:
		return INF
	return along - sqrt(discriminant)


## Turns the ankle onto the surface it stands on. A surface too steep to be stood
## on, such as the face of a step, is left alone so the sole keeps the tilt the
## clip gave it.
func _tilt_ankle(foot_basis: Basis, normal: Vector3, up: Vector3) -> Basis:
	if ankle_align <= 0.0 or normal.length_squared() < 0.0001:
		return foot_basis

	var surface: Vector3 = normal.normalized()
	if surface.dot(up) < ankle_flat_normal:
		return foot_basis

	var angle: float = up.angle_to(surface) * ankle_align
	if angle < 0.001:
		return foot_basis

	var axis: Vector3 = up.cross(surface)
	if axis.length_squared() < 0.000001:
		return foot_basis

	var roll: Basis = Basis(
		Quaternion(axis.normalized(), minf(angle, deg_to_rad(ankle_align_limit)))
	)
	return roll * foot_basis


## Height (world Y) of the ground under the given point, or INF when the probe
## finds nothing within its reach.
func _probe_ground(from: Vector3, distance: float) -> float:
	var hit: Dictionary = _probe_hit(from, distance)
	if hit.is_empty():
		return INF

	var position: Vector3 = hit.get("position", Vector3.INF)
	return position.y


## The surface the probe found, or an empty dictionary when it found nothing
## within its reach.
func _probe_hit(from: Vector3, distance: float) -> Dictionary:
	var up: Vector3 = _body.up_direction
	var query := PhysicsRayQueryParameters3D.create(from, from - up * distance)
	query.exclude = [_body.get_rid()]
	query.collision_mask = _body.collision_mask

	return _body.get_world_3d().direct_space_state.intersect_ray(query)
