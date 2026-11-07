class_name PlayerRagdoll
extends PhysicalBoneSimulator3D

## Physics rig that drives the character's skeleton once the body goes limp.
##
## Bodies are built at run time from the skeleton's rest pose, so the rig fits whatever model
## the character uses; each is jointed to its nearest physical ancestor with a six degree of
## freedom joint whose translation is locked, so no limb can pull apart.
##
## GodotPhysics holds the pivot but enforces no angular limit, so a joint's range is held by a
## stop torque on the bodies and by a clip on what is DRAWN (JOINT_STIFFNESS, DEATH_POSES).

## Bodies to build, keyed by bone name, with the mass (in kg) each gets: the segment shares
## of an 85 kg adult, so almost half the body is trunk and the limbs are dragged by it.
const BONE_MASS: Dictionary = {
	&"mixamorig_Hips": 14.0,
	&"mixamorig_Spine": 9.0,
	&"mixamorig_Spine1": 8.5,
	&"mixamorig_Spine2": 8.5,
	&"mixamorig_Neck": 1.2,
	&"mixamorig_Head": 5.5,
	&"mixamorig_LeftShoulder": 1.5,
	&"mixamorig_LeftArm": 2.3,
	&"mixamorig_LeftForeArm": 1.3,
	&"mixamorig_LeftHand": 0.5,
	&"mixamorig_RightShoulder": 1.5,
	&"mixamorig_RightArm": 2.3,
	&"mixamorig_RightForeArm": 1.3,
	&"mixamorig_RightHand": 0.5,
	&"mixamorig_LeftUpLeg": 8.2,
	&"mixamorig_LeftLeg": 3.8,
	&"mixamorig_LeftFoot": 0.9,
	&"mixamorig_LeftToeBase": 0.5,
	&"mixamorig_RightUpLeg": 8.2,
	&"mixamorig_RightLeg": 3.8,
	&"mixamorig_RightFoot": 0.9,
	&"mixamorig_RightToeBase": 0.5,
}

## Torso bones are boxed rather than capped: the spine is a stack of short bones, and capsules
## that short leave the chest as loose beads. The boxes are drawn as octagonal prisms.
const BOX_SHAPES: Dictionary = {
	&"mixamorig_Hips": Vector3(0.3, 0.2, 0.22),
	&"mixamorig_Spine": Vector3(0.22, 0.12, 0.16),
	&"mixamorig_Spine1": Vector3(0.24, 0.13, 0.17),
	&"mixamorig_Spine2": Vector3(0.28, 0.16, 0.19),
	&"mixamorig_Neck": Vector3(0.09, 0.1, 0.09),
}

## Box shape that is centred on its bone instead of reaching up to the next one.
const ROOT_BONE: StringName = &"mixamorig_Hips"

## Limb capsules are sized from the bone's own length so they fill the limb without spilling
## into its neighbour; the clamp keeps both torso-height and finger-sized bones sane.
const CAPSULE_RADIUS_SCALE: float = 0.22
const MIN_CAPSULE_RADIUS: float = 0.04
const MAX_CAPSULE_RADIUS: float = 0.09

## Radii given outright, in metres, where scaling from length leaves the shape thinner than
## the mesh it stands in for: an arm sunk into the chest reads as a torso with no arms.
const LIMB_RADII: Dictionary = {
	&"mixamorig_LeftUpLeg": 0.09,
	&"mixamorig_RightUpLeg": 0.09,
	&"mixamorig_LeftLeg": 0.052,
	&"mixamorig_RightLeg": 0.052,
	&"mixamorig_LeftArm": 0.058,
	&"mixamorig_RightArm": 0.058,
	&"mixamorig_LeftForeArm": 0.045,
	&"mixamorig_RightForeArm": 0.045,
}

## Segments shorter than this are treated as a point, where a capsule would be degenerate.
const MIN_SEGMENT_LENGTH: float = 0.02

## Fallback body for a bone with no children to measure against.
const POINT_RADIUS: float = 0.05

## Physics layers the bodies use while simulating: the world is layer 1 and the player is
## layer 2, so they never collide with the capsule the body was standing in.
const BODY_COLLISION_LAYER: int = 1
const BODY_COLLISION_MASK: int = 1

## How far each joint may rotate, in degrees, as (flexion, swing, twist): the fold an elbow or
## knee makes, the travel either side of it, and the turn along the bone. Flexion's backwards
## half is narrowed by EXTENSION_LIMITS. The figures are a living joint's range, not the
## widest a limb can be pushed: a ragdoll lives at its stops, so generous is wrong by look.
const JOINT_LIMITS: Dictionary = {
	# The trunk is the one chain that must NOT live at its stops: a drawn joint cannot fold
	# past its limit, so at 25 the visible chest froze at 35 degrees for a whole fall while
	# the bodies went past 80, which reads as the torso being hauled back upright. A running
	# death folds the waist past 80 at the base joint alone, so this has to be a body's
	# range and not a standing man's.
	&"mixamorig_Spine": Vector3(45.0, 30.0, 20.0),
	&"mixamorig_Spine1": Vector3(45.0, 30.0, 20.0),
	&"mixamorig_Spine2": Vector3(45.0, 30.0, 20.0),
	# The neck and the head stay tighter where the spine was let out: a head that swings as
	# freely as the waist reads as rubber, not as a stopped body.
	&"mixamorig_Neck": Vector3(30.0, 20.0, 20.0),
	&"mixamorig_Head": Vector3(20.0, 15.0, 20.0),
	&"mixamorig_LeftShoulder": Vector3(10.0, 10.0, 8.0),
	&"mixamorig_LeftArm": Vector3(50.0, 25.0, 20.0),
	&"mixamorig_LeftForeArm": Vector3(80.0, 6.0, 15.0),
	&"mixamorig_LeftHand": Vector3(20.0, 12.0, 12.0),
	&"mixamorig_RightShoulder": Vector3(10.0, 10.0, 8.0),
	&"mixamorig_RightArm": Vector3(50.0, 25.0, 20.0),
	&"mixamorig_RightForeArm": Vector3(80.0, 6.0, 15.0),
	&"mixamorig_RightHand": Vector3(20.0, 12.0, 12.0),
	# The hips are what folds a corpse up: a leg that swings 90 at the hip draws the body
	# into a ball. The feet and toes are pinned at 0, so the ankles cannot roll at all.
	&"mixamorig_LeftUpLeg": Vector3(60.0, 20.0, 15.0),
	&"mixamorig_LeftLeg": Vector3(80.0, 4.0, 8.0),
	&"mixamorig_LeftFoot": Vector3(0.0, 0.0, 0.0),
	&"mixamorig_LeftToeBase": Vector3(0.0, 0.0, 0.0),
	&"mixamorig_RightUpLeg": Vector3(60.0, 20.0, 15.0),
	&"mixamorig_RightLeg": Vector3(80.0, 4.0, 8.0),
	&"mixamorig_RightFoot": Vector3(0.0, 0.0, 0.0),
	&"mixamorig_RightToeBase": Vector3(0.0, 0.0, 0.0),
}

## How far a joint that folds both ways may bend BACKWARDS, in degrees, against the forward
## figure in JOINT_LIMITS: a hip free to swing behind the body lays a leg out with the knee
## bent the wrong way. The spine, neck and head are 0, so the trunk arches nowhere. Feet and
## toes are absent: their bones lie along the facing direction, so the fold probe reads none.
const EXTENSION_LIMITS: Dictionary = {
	&"mixamorig_Spine": 0.0,
	&"mixamorig_Spine1": 0.0,
	&"mixamorig_Spine2": 0.0,
	&"mixamorig_Neck": 0.0,
	&"mixamorig_Head": 0.0,
	&"mixamorig_LeftShoulder": 8.0,
	&"mixamorig_LeftArm": 12.0,
	&"mixamorig_LeftHand": 10.0,
	&"mixamorig_RightShoulder": 8.0,
	&"mixamorig_RightArm": 12.0,
	&"mixamorig_RightHand": 10.0,
	# The hips are the big one: hyperextension is what lays a body out flat with a
	# straight leg driving into the ground, and 8 degrees is all a hip has.
	&"mixamorig_LeftUpLeg": 8.0,
	&"mixamorig_RightUpLeg": 8.0,
}

## Joints that fold one way only, as an elbow and a knee do. The value is the travel in
## degrees from straight to fully folded as (straight, folded), with the side the fold
## goes to as z: 1 towards the front of the body, -1 towards the back. Which way round
## the axis turns the bone is read off the rig, so this stays a description of anatomy.
const HINGE_LIMITS: Dictionary = {
	# The elbow draws the hand forward and up, and stops where the arm is straight.
	&"mixamorig_LeftForeArm": Vector3(0.0, 120.0, 1.0),
	&"mixamorig_RightForeArm": Vector3(0.0, 120.0, 1.0),
	# The knee kicks the heel back, with a few degrees of slack when straight.
	&"mixamorig_LeftLeg": Vector3(-5.0, 140.0, -1.0),
	&"mixamorig_RightLeg": Vector3(-5.0, 140.0, -1.0),
}

## Limits for a bone the table does not name: loose, but still a joint rather than
## a free hinge.
const DEFAULT_JOINT_LIMITS: Vector3 = Vector3(25.0, 15.0, 15.0)

## How much of the pose the bodies put a joint in is DRAWN while the body is still falling, so a
## chain does not read as loose bones; the share is given up once the fall is over (SETTLE_START).
## The trunk is nearly 1: at half it froze the visible chest at 35 degrees while the bodies went
## past 80, and that lag is read as the torso being hauled back upright. Feet and toes are 0 so
## the ankles stay pinned; the one way joints stay loosest, since a stiff knee floats the foot.
const JOINT_STIFFNESS: Dictionary = {
	&"mixamorig_Spine": 0.9,
	&"mixamorig_Spine1": 0.9,
	&"mixamorig_Spine2": 0.9,
	&"mixamorig_Neck": 0.5,
	&"mixamorig_Head": 0.45,
	&"mixamorig_LeftShoulder": 0.45,
	&"mixamorig_LeftArm": 0.6,
	&"mixamorig_LeftForeArm": 0.85,
	&"mixamorig_LeftHand": 0.45,
	&"mixamorig_RightShoulder": 0.45,
	&"mixamorig_RightArm": 0.6,
	&"mixamorig_RightForeArm": 0.85,
	&"mixamorig_RightHand": 0.45,
	&"mixamorig_LeftUpLeg": 0.55,
	&"mixamorig_LeftLeg": 0.85,
	&"mixamorig_LeftFoot": 0.0,
	&"mixamorig_LeftToeBase": 0.0,
	&"mixamorig_RightUpLeg": 0.55,
	&"mixamorig_RightLeg": 0.85,
	&"mixamorig_RightFoot": 0.0,
	&"mixamorig_RightToeBase": 0.0,
}

## Stiffness of a bone the table does not name.
const DEFAULT_JOINT_STIFFNESS: float = 0.36

## The pose data a corpse is aimed at once it has stopped falling, and the clip it is read
## from.
const DEATH_POSES: GDScript = preload("res://Assets/character_model/death_poses.gd")

## How far the drawn pose is pulled towards the settle pose once the body has come to rest, as
## a share: small on purpose, or the limbs float off the floor again. It is the share the
## settled pose is drawn at, so it also says how much of the authored death pose a corpse is
## shown in: past about half, the clip's own bends win over where the limbs actually fell.
const SETTLE_BIAS: float = 0.35

## Axis names in the order the joint exposes them.
const JOINT_AXES: Array[String] = ["x", "y", "z"]

## Angle a hinge is folded by to see which way round its axis turns the bone. Only the
## direction of the movement is used, so any small angle will do.
const FOLD_PROBE_ANGLE: float = 10.0

## The blow the body died of. It dies standing with no momentum of its own, so without one
## the corpse folds where it stood instead of going over. The point is chosen at random on a
## body's shape when nothing says where the shot landed, which puts the shove off that body's
## pivot so the corpse turns as it falls. The figure is the speed the struck body is given.
const HIT_SPEED: float = 4.0

## How quickly the bodies lose their spin, as a share of what they hold rather than a
## ceiling. Every push the solver makes to hold the rig together is a small kick, and the
## kicks add up until the ragdoll turns where it lies.
const ANGULAR_DAMP: float = 15.0

## The same for travel. Lighter than the spin, because a body thrown across the floor
## should still slide; heavier than nothing, because a body that creeps never stops.
const LINEAR_DAMP: float = 4.0

## What the bodies get for the first moments of the collapse instead: a body that has only
## just died is not limp yet, so the limbs do not whip out to their stops at once.
const IMPACT_ANGULAR_DAMP: float = 30.0
const IMPACT_LINEAR_DAMP: float = 5.0

## How long the impact damping is held, and how long it then takes to let go. Short on
## purpose: held longer it preserves the pose the body died in, where a real one folds at
## the waist and knees within a fifth of a second.
const IMPACT_TENSION_TIME: float = 0.2
const IMPACT_RELEASE_TIME: float = 0.45

## How much of each joint's stiffness the impact tension takes away, as a share of it: this
## is residual muscle tone, not the corpse holding the pose it was animated in.
const IMPACT_TENSION_SHARE: float = 0.25

## The opposite of the tension: the drawn turn is only a share of the bodies' own, so a
## corpse drawn at that share rests slightly off the floor. This lets the share back to 1.
const SETTLE_START: float = 2.5
const SETTLE_TIME: float = 1.0

## How much of the soft-stop correction is kept once the body has come to rest. It is not
## let back at all: the correction is the only thing holding a joint inside its range, since
## GodotPhysics enforces no angular limit, and the stop's brake can only remove a share of the
## outward speed it is scaled by, so a partial weight leaves every joint creeping out.
const REST_LIMIT_SHARE: float = 1.0

var _built: bool = false
## RID of the body the ragdoll must never collide with: the player's own capsule.
var _ignore_body: RID
## Simulated body for each bone, keyed by bone index.
var _bodies: Dictionary = {}
## Joint holding a body to the body above it, keyed by the lower bone's index.
var _joints: Dictionary = {}
## Range each joint is held to, keyed by the lower bone's index: "parent", "rest", "lower"
## and "upper" in radians, the resolved settle turns under "settle", and "stiffness".
var _joint_specs: Dictionary = {}
## Bone indices, ascending, so a parent is written before the children that read it.
var _bone_order: Array[int] = []
## Pose every bone was in when the bodies took over, so it can be given back on revive.
var _handover_poses: Dictionary = {}
## Seconds since the bodies took over, and how much of the impact tension is left, 1 at the
## moment of death falling to 0 once the release is done. Both read it, so it goes limp at once.
var _sim_time: float = 0.0
var _tension: float = 0.0
## How far the drawn pose has been let back to the bodies' own: see SETTLE_START.
var _settle: float = 0.0
## Which of the settle targets this death is drawn towards, and where the blow landed.
var _settle_pose: int = 0
## The turn every bone is left at by the front-death clip, keyed by bone name, and whether
## this body came to rest on its front, which is when that clip is the target.
var _clip_turns: Dictionary = {}
var _face_down: bool = false
var _hit_bone: int = -1
var _hit_point: Vector3 = Vector3.ZERO
## The bodies keyed by bone name, for the impact and posture solvers.
var _bodies_by_name: Dictionary = {}
## Residual muscle tone, 0..1: knocked down by the blow, climbs back over a second.
var _muscle_tone: float = 0.0
## 0 draws the animated pose, 1 draws the simulated one: see ragdoll_blend.gd.
var _simulation_weight: float = 1.0


## Builds the bodies and joints. [param body] is the physics body that must never collide
## with the ragdoll: the player's own capsule sits inside every bone of the rest pose.
func setup(body: CollisionObject3D) -> void:
	if _built:
		return

	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null:
		push_error("PlayerRagdoll must be a child of a Skeleton3D.")
		return

	_built = true
	_clip_turns = DEATH_POSES.load_clip_turns(DEATH_POSES.FRONT_CLIP)
	var bones: Dictionary = {}
	for bone_name: StringName in BONE_MASS:
		var bone: PhysicalBone3D = _create_bone(skeleton, bone_name)
		if bone != null:
			bones[String(bone_name)] = bone

	_bone_order.sort()
	# Unjointed until _create_joints() runs: that is the only thing holding them together.
	_create_joints(skeleton)
	_exclude_joint_pairs(skeleton, bones)
	if body != null:
		_ignore_body = body.get_rid()
		physical_bones_add_collision_exception(_ignore_body)

	# Dormant until the body dies: the rig must never touch the skeleton the clips pose.
	set_active(false)


## Hands the skeleton over to the bodies, starting from the pose it is in right now.
## [param launch_velocity] and [param launch_spin] are the momentum the body died with,
## which is what makes a death at a run carry the body forward and tumble. [param hit_point]
## is where the blow landed, in world space; left out, a point is chosen at random.
func start_simulation(
	launch_velocity: Vector3 = Vector3.ZERO,
	launch_spin: Vector3 = Vector3.ZERO,
	hit_point: Vector3 = Vector3.INF
) -> void:
	if not _built or is_simulating_physics():
		return

	var skeleton: Skeleton3D = get_skeleton()
	# Kept because it is the pose the model has to be given back: the bodies come to rest in
	# a heap, and a skeleton left in that heap stays folded up on the floor after a revive.
	_handover_poses.clear()
	for bone_index: int in range(skeleton.get_bone_count()):
		_handover_poses[bone_index] = skeleton.get_bone_global_pose(bone_index)

	# Active first: the simulator is what walks the bodies back to a kinematic pose at the end.
	set_active(true)
	# The rig was built around the bind pose, which is rarely the pose the body died in, so
	# the bodies are moved onto what is actually on screen before they are let go.
	_sync_bodies_to_pose()
	# Aimed again for the same reason: left at the built pose every joint starts out folded.
	_rebuild_joints(skeleton)
	# The simulation rebuilds the bodies as rigid ones, dropping any collision exception.
	if _ignore_body.is_valid():
		physical_bones_add_collision_exception(_ignore_body)
	physical_bones_start_simulation()
	RagdollImpact.apply_momentum(_bodies, _bone_order, skeleton, launch_velocity, launch_spin)
	# After the launch, which writes the bodies' speed rather than adding to it; and the
	# settle pose is picked per death so two bodies do not come to rest in the same shape.
	_settle_pose = randi() % DEATH_POSES.SETTLE_POSES.size()
	_apply_hit(hit_point)
	# Not limp yet: the impact damping and the pose it died in are held for IMPACT_TENSION_TIME.
	_sim_time = 0.0
	_tension = 1.0
	_settle = 0.0
	# The blow stuns the muscles: tone drops, then climbs back over about a second.
	_muscle_tone = RagdollMuscles.TONE_SHOCK
	_simulation_weight = 1.0
	_apply_damping(IMPACT_ANGULAR_DAMP, IMPACT_LINEAR_DAMP)
	set_physics_process(true)


## Gives the skeleton back to the animation system, in the pose it was taken over in.
func stop_simulation() -> void:
	if not is_simulating_physics():
		return

	set_physics_process(false)
	physical_bones_stop_simulation()
	set_active(false)
	_give_back_poses()


## 0 keeps the animated pose, 1 lets the bodies drive it, and anything between is the
## hand-over. Drive it from a RagdollBlend so the weight is timed rather than scripted.
func set_simulation_weight(weight: float) -> void:
	_simulation_weight = clampf(weight, 0.0, 1.0)


## Applies a secondary blow (a bullet, a shove) to a body that is already simulating. The
## stagger this adds is what an explosion or a hit needs to look like a hit. Ignored when
## the rig is not simulating.
func apply_blow(direction: Vector3, hit_point: Vector3, speed: float) -> void:
	if is_simulating_physics():
		RagdollImpact.apply_blow(_bodies_by_name, get_skeleton(), direction, hit_point, speed)


## Applies a radial blast. Call once per frame while the blast lasts: a one-shot blast is
## eaten by the bodies' angular damp within a few degrees.
func apply_blast(origin: Vector3, radius: float, speed: float) -> void:
	if is_simulating_physics():
		RagdollImpact.apply_blast(_bodies_by_name, origin, radius, speed)


## Puts the pose the bodies took over from back on the skeleton, so no frame is drawn in the
## heap they came to rest in. Covers hands and fingers too: the whole model comes back.
func _give_back_poses() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null or _handover_poses.is_empty():
		return

	for _pass: int in 2:
		for bone_index: int in _handover_poses:
			skeleton.set_bone_global_pose(bone_index, _handover_poses[bone_index] as Transform3D)

	_handover_poses.clear()


func _physics_process(delta: float) -> void:
	if not is_simulating_physics():
		return

	_advance_tension(delta)
	_apply_muscle_drives(delta)
	_write_poses()


## Lets the impact tension go and the drawn pose settle: the heavy damping is smoothed back
## to the baseline over IMPACT_RELEASE_TIME, and the stiffness is let to 1 once it has fallen.
func _advance_tension(delta: float) -> void:
	_sim_time += delta
	# Tone climbs back from the shock value; until it does, the joints are genuinely floppy.
	_muscle_tone = move_toward(
		_muscle_tone, RagdollMuscles.TONE_BASE, RagdollMuscles.TONE_RECOVERY_RATE * delta
	)
	if _tension > 0.0:
		var release_end: float = IMPACT_TENSION_TIME + IMPACT_RELEASE_TIME
		_tension = 1.0 - smoothstep(IMPACT_TENSION_TIME, release_end, _sim_time)
		_apply_damping(
			lerpf(ANGULAR_DAMP, IMPACT_ANGULAR_DAMP, _tension),
			lerpf(LINEAR_DAMP, IMPACT_LINEAR_DAMP, _tension)
		)

	var was_settling: bool = _settle > 0.0
	_settle = smoothstep(SETTLE_START, SETTLE_START + SETTLE_TIME, _sim_time)
	# Which way the body lies is only known once the fall is over, so the target is picked
	# here along with the roll, rather than at the moment of death.
	if _settle > 0.0:
		_face_down = DEATH_POSES.roll_onto_front(get_skeleton(), _bodies)
		if not was_settling:
			_aim_settle_pose()


## Applies muscle tone and the soft-stop correction to the bodies for the next solver step.
## The tone is deliberately weak (see ragdoll_muscles.gd): it holds a posture, it does not
## overrule gravity. The stop keeps REST_LIMIT_SHARE after the body settles: it is all that
## holds a joint inside its range.
func _apply_muscle_drives(delta: float) -> void:
	var tone: float = _muscle_tone * lerpf(1.0, RagdollMuscles.PHYSICAL_TONE_REST_SHARE, _settle)
	var limit_weight: float = lerpf(1.0, REST_LIMIT_SHARE, _settle)
	RagdollMuscles.apply_drives(
		get_skeleton(), _bodies, _joint_specs, _bone_order, delta, tone, limit_weight, _settle
	)


## Aims the body at the pose it is left in: the front pose once it is on its front (DEATH_POSES).
func _aim_settle_pose() -> void:
	if _face_down:
		_settle_pose = DEATH_POSES.clip_index()


## Sets the damping on every body, replacing the project default (see _create_bone).
func _apply_damping(angular: float, linear: float) -> void:
	for bone_index: int in _bone_order:
		var bone: PhysicalBone3D = _bodies[bone_index] as PhysicalBone3D
		if bone == null:
			continue
		bone.angular_damp = angular
		bone.linear_damp = linear


## Draws the skeleton from the bodies, which is what bends the skin: each bone at the turn
## its body took, held inside its joint's range (see the note at the top of the file).
func _write_poses() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null:
		return

	# The turn each bone is drawn at. A joint is measured against the bone above it as that
	# bone is drawn, so a limb whose trunk was turned back is measured against the trunk.
	var poses: Dictionary = {}
	var drawn: Dictionary = {}
	for bone_index: int in _bone_order:
		var bone: PhysicalBone3D = _bodies[bone_index] as PhysicalBone3D
		if bone == null:
			continue

		var body_pose: Transform3D = bone.global_transform
		var rotation: Quaternion = body_pose.basis.orthonormalized().get_rotation_quaternion()
		var spec: Dictionary = _joint_specs.get(bone_index, {})
		if not spec.is_empty():
			var parent_rotation: Quaternion = drawn.get(int(spec["parent"]), rotation)
			var rest: Quaternion = spec["rest"]
			# The turn the joint has taken away from the pose the rig was built in.
			var deviation: Quaternion = rest.inverse() * (parent_rotation.inverse() * rotation)
			var limited: Quaternion = RagdollSoftLimits.clip_soft(deviation, spec)
			# The clip runs first, so a stiffened joint is only drawn inside its limits.
			var held: float = float(spec["stiffness"]) * (1.0 - IMPACT_TENSION_SHARE * _tension)
			var stiffness: float = lerpf(held, 1.0, _settle)
			limited = RagdollSoftLimits.stiffen(limited, stiffness)
			# A small, always-on pull towards the relaxed posture: weak enough that gravity and
			# the impact win, strong enough that a limb never floats into a loose shape.
			var neutral: Quaternion = RagdollMuscles.posture_target(spec, _settle)
			var bias: float = float(spec["neutral_bias"]) * _muscle_tone
			bias *= lerpf(1.0, RagdollMuscles.NEUTRAL_SETTLE_SHARE, _settle)
			limited = RagdollSoftLimits.blend(limited, neutral, bias)
			# A body scaled back to the rest pose is a man standing to attention, so once
			# it has settled the turn is pulled towards this death's settle pose.
			var settle: Quaternion = (spec["settle"] as Array)[_settle_pose]
			if _settle > 0.0 and not settle.is_equal_approx(Quaternion.IDENTITY):
				limited = limited.slerp(settle, SETTLE_BIAS * _settle)
			if not deviation.is_equal_approx(limited):
				rotation = parent_rotation * rest * limited

		drawn[bone_index] = rotation
		var simulated: Transform3D = Transform3D(Basis(rotation), body_pose.origin)
		# Active ragdoll: a partial weight keeps the animated pose in the loop while the
		# bodies add weight and inertia. 1 is a plain simulation, which is the death case.
		if _simulation_weight < 1.0:
			var pose: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(bone_index)
			simulated = RagdollBlend.blend_pose(pose, simulated, _simulation_weight)
		poses[bone_index] = simulated

	var world_inverse: Transform3D = skeleton.global_transform.affine_inverse()
	for _pass: int in 2:
		for bone_index: int in _bone_order:
			if not poses.has(bone_index):
				continue

			skeleton.set_bone_global_pose(bone_index, world_inverse * poses[bone_index])


## Applies the blow that killed the body. It lands on a body picked by mass, because a heavy
## body is a bigger target, at a point along that body rather than at its pivot, so the
## shove turns the corpse as it goes over. The joints drag the rest of the body after it; the
## limb lag that makes the reaction read is in ragdoll_impact.gd.
func _apply_hit(hit_point: Vector3) -> void:
	var picked: Dictionary = RagdollImpact.pick_hit(_bodies, _bone_order, get_skeleton())
	_hit_bone = int(picked.get("bone_index", -1))
	if _hit_bone < 0:
		return

	var bone: PhysicalBone3D = _bodies[_hit_bone] as PhysicalBone3D
	_hit_point = hit_point if hit_point.is_finite() else picked["point"]
	# In the back, so the corpse goes over onto its front: see DEATH_POSES.
	var direction: Vector3 = DEATH_POSES.hit_impulse_direction(get_skeleton())
	var impulse: Vector3 = direction * HIT_SPEED * bone.mass
	PhysicsServer3D.body_apply_impulse(bone.get_rid(), impulse, _hit_point - bone.global_position)
	RagdollImpact.apply_blow(_bodies_by_name, get_skeleton(), direction, _hit_point, HIT_SPEED)


## Moves every body onto the bone it follows, so the simulation starts from the drawn pose.
func _sync_bodies_to_pose() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null:
		return

	for bone_index: int in _bone_order:
		var bone: PhysicalBone3D = _bodies[bone_index] as PhysicalBone3D
		if bone == null:
			continue

		var pose: Transform3D = (
			skeleton.global_transform * skeleton.get_bone_global_pose(bone_index)
		)
		bone.global_transform = Transform3D(pose.basis.orthonormalized(), pose.origin)

	# Read off the pose they were just moved onto: the posture tone holds, not the built one.
	RagdollMuscles.anchor_posture(_joint_specs, _bodies, _bone_order)


func _create_bone(skeleton: Skeleton3D, bone_name: StringName) -> PhysicalBone3D:
	var bone_index: int = skeleton.find_bone(String(bone_name))
	if bone_index < 0:
		push_warning("PlayerRagdoll: the skeleton has no bone named %s." % bone_name)
		return null

	var bone: PhysicalBone3D = PhysicalBone3D.new()
	bone.name = bone_name
	# bone_name is not a bound property, so it is set through set(), and before the body
	# enters the tree: that is when the bone id is looked up and it is moved onto the bone.
	bone.set(&"bone_name", String(bone_name))
	bone.mass = float(BONE_MASS[bone_name])
	# Replaced rather than added to, so the figure does not depend on the project default.
	bone.angular_damp_mode = PhysicalBone3D.DAMP_MODE_REPLACE
	bone.angular_damp = ANGULAR_DAMP
	bone.linear_damp_mode = PhysicalBone3D.DAMP_MODE_REPLACE
	bone.linear_damp = LINEAR_DAMP
	# No joint of its own: see _create_joints() for the one it gets instead.
	bone.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
	bone.collision_layer = BODY_COLLISION_LAYER
	bone.collision_mask = BODY_COLLISION_MASK
	add_child(bone)
	bone.add_child(_build_collision_shape(skeleton, bone_index, bone_name))
	_bodies[bone_index] = bone
	_bodies_by_name[bone_name] = bone
	_bone_order.append(bone_index)
	return bone


## Joints every body to its nearest physical ancestor. The bones are built without joints of
## their own, so this is the only thing holding the rig together, and every body has to be in
## the tree first: the joint is built from the bodies' frames.
func _create_joints(skeleton: Skeleton3D) -> void:
	for bone_index: int in _bone_order:
		var parent_index: int = _find_physical_parent_index(skeleton, bone_index)
		if parent_index < 0:
			# The pelvis has no body above it, so there is nothing to joint it to.
			continue

		var bone: PhysicalBone3D = _bodies[bone_index] as PhysicalBone3D
		var parent_bone: PhysicalBone3D = _bodies[parent_index] as PhysicalBone3D
		if bone == null or parent_bone == null:
			continue

		var joint: Generic6DOFJoint3D = Generic6DOFJoint3D.new()
		joint.name = "Joint_%s" % bone.name
		add_child(joint)
		# Before the bodies are named: assigning the second one builds the physics joint
		# and it reads whatever frame and limits are in place by then.
		joint.global_transform = (
			skeleton.global_transform * _get_joint_frame(skeleton, parent_index, bone_index)
		)
		_lock_joint_translation(joint)
		_store_joint_limits(skeleton, parent_index, bone_index, bone.name)
		joint.node_a = joint.get_path_to(parent_bone)
		joint.node_b = joint.get_path_to(bone)
		_joints[bone_index] = joint


## Aims every joint at the pose the bodies are in now: the rig is built around one pose and
## simulated from another, and a joint left at the built one starts out already folded.
func _rebuild_joints(skeleton: Skeleton3D) -> void:
	for bone_index: int in _bone_order:
		var joint: Generic6DOFJoint3D = _joints.get(bone_index) as Generic6DOFJoint3D
		if joint == null:
			continue

		var parent_index: int = _find_physical_parent_index(skeleton, bone_index)
		if parent_index < 0:
			continue

		var bone: PhysicalBone3D = _bodies[bone_index] as PhysicalBone3D
		var parent_bone: PhysicalBone3D = _bodies[parent_index] as PhysicalBone3D
		if bone == null or parent_bone == null:
			continue

		joint.global_transform = Transform3D(
			parent_bone.global_transform.basis.orthonormalized(), bone.global_position
		)
		# Naming them is what re-reads the frame, and naming to what they hold is ignored.
		joint.node_a = NodePath()
		joint.node_b = NodePath()
		joint.node_a = joint.get_path_to(parent_bone)
		joint.node_b = joint.get_path_to(bone)


## The frame the joint turns in: at the child's pivot, turned to match the parent.
func _get_joint_frame(skeleton: Skeleton3D, parent_index: int, bone_index: int) -> Transform3D:
	var parent_rest: Transform3D = skeleton.get_bone_global_rest(parent_index)
	var pivot: Vector3 = skeleton.get_bone_global_rest(bone_index).origin
	return Transform3D(parent_rest.basis.orthonormalized(), pivot)


## Locks the joint's three translations and lets its rotation run free: a joint is a pivot,
## and a limb free to slide along one tears away from the body. Rotation is left free
## because GodotPhysics ignores every angular limit it is given, so the range is applied by
## _write_poses() when the rig is drawn instead.
func _lock_joint_translation(joint: Generic6DOFJoint3D) -> void:
	for axis: int in 3:
		var key: String = JOINT_AXES[axis]
		joint.set("linear_limit_%s/enabled" % key, true)
		joint.set("linear_limit_%s/lower_distance" % key, 0.0)
		joint.set("linear_limit_%s/upper_distance" % key, 0.0)
		joint.set("angular_limit_%s/enabled" % key, false)


## Works out the range a joint is held to and keeps it for the clamp, read off the rest pose
## because that is the only pose the bone axes are known in. Radians, because that is what
## the clamp measures in.
func _store_joint_limits(
	skeleton: Skeleton3D, parent_index: int, bone_index: int, bone_name: StringName
) -> void:
	var placement: Dictionary = _get_joint_axis_limits(
		skeleton, parent_index, bone_index, bone_name
	)
	var limits: Array[Vector2] = placement["ranges"]
	var axes: Vector3i = placement["axes"]
	var lower: Vector3 = Vector3.ZERO
	var upper: Vector3 = Vector3.ZERO
	for axis: int in 3:
		lower[axis] = deg_to_rad(limits[axis].x)
		upper[axis] = deg_to_rad(limits[axis].y)

	var parent_rest: Quaternion = _get_rest_turn(skeleton, parent_index)
	var bone_rest: Quaternion = _get_rest_turn(skeleton, bone_index)
	var rest: Quaternion = parent_rest.inverse() * bone_rest
	_joint_specs[bone_index] = {
		"parent": parent_index,
		"rest": rest,
		"lower": lower,
		"upper": upper,
		"soft": RagdollSoftLimits.softness_for(bone_name, lower, upper),
		"neutral": RagdollMuscles.neutral_deviation(bone_name, lower, upper, axes),
		"neutral_bias": RagdollMuscles.bias_for(bone_name),
		"settle": _get_settle_deviations(bone_name, lower, upper, axes, rest),
		"stiffness": clampf(float(JOINT_STIFFNESS.get(bone_name, DEFAULT_JOINT_STIFFNESS)), 0.0, 1.0),
	}


## The turn a bone has in the rest pose.
static func _get_rest_turn(skeleton: Skeleton3D, bone_index: int) -> Quaternion:
	return skeleton.get_bone_global_rest(bone_index).basis.get_rotation_quaternion()


## The turn each settle target asks this joint to be drawn at, as a deviation from the rest
## pose, resolved now because the joint's range and axes are only known here. The last
## target is the front-death clip, which is a real pose rather than a share of a range.
func _get_settle_deviations(
	bone_name: StringName, lower: Vector3, upper: Vector3, axes: Vector3i, rest: Quaternion
) -> Array[Quaternion]:
	var targets: Array[Quaternion] = []
	for pose: Dictionary in DEATH_POSES.SETTLE_POSES:
		var share: Vector3 = pose.get(bone_name, Vector3.ZERO)
		if share.is_zero_approx():
			targets.append(Quaternion.IDENTITY)
			continue

		targets.append(DEATH_POSES.resolve_share(share, lower, upper, axes))

	targets.append(_get_clip_deviation(bone_name, lower, upper, rest))
	return targets


## The turn the front-death clip leaves this joint at, held inside its range so the aim can
## never draw a joint further than the clamp allows. A pinned joint is left out: the ankles
## have neither range nor stiffness, and that is what keeps the feet on the shins.
func _get_clip_deviation(
	bone_name: StringName, lower: Vector3, upper: Vector3, rest: Quaternion
) -> Quaternion:
	var turn: Variant = _clip_turns.get(bone_name)
	if turn == null or (lower.is_zero_approx() and upper.is_zero_approx()):
		return Quaternion.IDENTITY

	var deviation: Quaternion = rest.inverse() * (turn as Quaternion)
	return RagdollSoftLimits.clip_hard(deviation, lower, upper)


## The travel each of the joint's axes is allowed, in degrees, as (lower, upper), and which
## axis each role landed on: the axis the bone runs along is the twist, and of the two that
## are left the one closest to the character's left-right axis is the hinge.
func _get_joint_axis_limits(
	skeleton: Skeleton3D, parent_index: int, bone_index: int, bone_name: StringName
) -> Dictionary:
	var limits: Vector3 = JOINT_LIMITS.get(bone_name, DEFAULT_JOINT_LIMITS)
	var parent_rest: Transform3D = skeleton.get_bone_global_rest(parent_index)
	var bone_origin: Vector3 = skeleton.get_bone_global_rest(bone_index).origin
	var along: Vector3 = (parent_rest.affine_inverse() * bone_origin).normalized()
	var twist_axis: int = _dominant_axis(along)

	var right: Vector3 = parent_rest.basis.orthonormalized().inverse() * Vector3.RIGHT
	var others: Array[int] = []
	for axis: int in 3:
		if axis != twist_axis:
			others.append(axis)

	var flexion_axis: int = others[0]
	var swing_axis: int = others[1]
	if absf(right[others[1]]) > absf(right[others[0]]):
		flexion_axis = others[1]
		swing_axis = others[0]

	var result: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	result[twist_axis] = Vector2(-limits.z, limits.z)
	result[swing_axis] = Vector2(-limits.y, limits.y)
	result[flexion_axis] = _get_flexion_range(
		skeleton, parent_index, bone_index, flexion_axis, bone_name, limits
	)
	return {"ranges": result, "axes": Vector3i(twist_axis, flexion_axis, swing_axis)}


## How far the joint folds, in (lower, upper) degrees. A ball joint folds both ways; an elbow
## or a knee only one way, so it gets the range its HINGE_LIMITS entry asks for.
func _get_flexion_range(
	skeleton: Skeleton3D,
	parent_index: int,
	bone_index: int,
	axis: int,
	bone_name: StringName,
	limits: Vector3
) -> Vector2:
	if not HINGE_LIMITS.has(bone_name):
		return _get_ball_flexion_range(skeleton, parent_index, bone_index, axis, bone_name, limits)

	var hinge: Vector3 = HINGE_LIMITS[bone_name]
	var fold_sign: float = _get_fold_sign(skeleton, parent_index, bone_index, axis, hinge.z)
	if is_zero_approx(fold_sign):
		# The rig says nothing about which way the body faces, so the fold goes both ways.
		return Vector2(-hinge.y, hinge.y)
	if fold_sign > 0.0:
		return Vector2(hinge.x, hinge.y)

	return Vector2(-hinge.y, -hinge.x)


## How far a joint that folds both ways may bend forwards and backwards. Forwards is the
## JOINT_LIMITS figure, backwards the smaller EXTENSION_LIMITS one.
func _get_ball_flexion_range(
	skeleton: Skeleton3D,
	parent_index: int,
	bone_index: int,
	axis: int,
	bone_name: StringName,
	limits: Vector3
) -> Vector2:
	var forward: float = limits.x
	var backward: float = float(EXTENSION_LIMITS.get(bone_name, limits.x))
	var fold_sign: float = _get_fold_sign(skeleton, parent_index, bone_index, axis, 1.0)
	if is_zero_approx(fold_sign):
		# Neither half can be placed on the right side of the pose, so both get the wider.
		var widest: float = maxf(forward, backward)
		return Vector2(-widest, widest)
	if fold_sign > 0.0:
		return Vector2(-backward, forward)

	return Vector2(-forward, backward)


## Which way round the flexion axis folds the bone over: 1 when turning it the positive way
## sends the bone towards [param side] (1 is the front of the body, -1 the back), -1 when it
## is the other way, and 0 when the rig gives nothing to measure against.
func _get_fold_sign(
	skeleton: Skeleton3D, parent_index: int, bone_index: int, axis: int, side: float
) -> float:
	var forward: Vector3 = _get_forward_direction(skeleton)
	if forward.is_zero_approx():
		return 0.0

	var parent_rest: Transform3D = skeleton.get_bone_global_rest(parent_index)
	var bone_direction: Vector3 = (
		(skeleton.get_bone_global_rest(bone_index).origin - parent_rest.origin).normalized()
	)
	var axis_direction: Vector3 = parent_rest.basis.orthonormalized()[axis]
	var folded: Vector3 = (
		bone_direction.rotated(axis_direction, deg_to_rad(FOLD_PROBE_ANGLE)) - bone_direction
	)
	return 1.0 if folded.dot(forward) * side > 0.0 else -1.0


## Horizontal direction the character faces, read off the feet. Zero when there is no toe.
func _get_forward_direction(skeleton: Skeleton3D) -> Vector3:
	var forward: Vector3 = _get_bone_forward(
		skeleton, &"mixamorig_LeftFoot", &"mixamorig_LeftToeBase"
	)
	if forward.is_zero_approx():
		forward = _get_bone_forward(skeleton, &"mixamorig_RightFoot", &"mixamorig_RightToeBase")

	return forward


## Horizontal direction from one bone to another in the rest pose, zero if either is missing.
func _get_bone_forward(skeleton: Skeleton3D, from_name: StringName, to_name: StringName) -> Vector3:
	var from_index: int = skeleton.find_bone(String(from_name))
	var to_index: int = skeleton.find_bone(String(to_name))
	if from_index < 0 or to_index < 0:
		return Vector3.ZERO

	var direction: Vector3 = (
		skeleton.get_bone_global_rest(to_index).origin
		- skeleton.get_bone_global_rest(from_index).origin
	)
	direction.y = 0.0
	return direction.normalized()


## Index of the axis carrying most of [param direction], how a bone's length axis is found.
static func _dominant_axis(direction: Vector3) -> int:
	var absolute: Vector3 = direction.abs()
	if absolute.x >= absolute.y and absolute.x >= absolute.z:
		return 0
	return 1 if absolute.y >= absolute.z else 2


func _build_collision_shape(
	skeleton: Skeleton3D, bone_index: int, bone_name: StringName
) -> CollisionShape3D:
	var shape_node: CollisionShape3D = CollisionShape3D.new()
	# Named so a shot can be matched back to the bone it struck once bullets are wired in.
	shape_node.name = &"HitArea"
	if BOX_SHAPES.has(bone_name):
		var size: Vector3 = BOX_SHAPES[bone_name]
		shape_node.shape = _create_prism(size)
		# The hips are the root of the torso, so their shape is centred on the bone;
		# every other one starts at its own bone and reaches towards the next.
		var offset: float = 0.0 if bone_name == ROOT_BONE else size.y * 0.5
		shape_node.position = Vector3(0.0, offset, 0.0)
		return shape_node

	var rest: Transform3D = skeleton.get_bone_global_rest(bone_index)
	var child_index: int = _get_segment_child(skeleton, bone_index)
	if child_index < 0:
		shape_node.shape = _create_sphere(POINT_RADIUS)
		return shape_node

	# Where the next bone sits in this bone's own space: the capsule follows the limb.
	var segment: Vector3 = rest.affine_inverse() * skeleton.get_bone_global_rest(child_index).origin
	var length: float = segment.length()
	if length < MIN_SEGMENT_LENGTH:
		shape_node.shape = _create_sphere(POINT_RADIUS)
		return shape_node

	var radius: float = clampf(
		float(LIMB_RADII.get(bone_name, length * CAPSULE_RADIUS_SCALE)),
		MIN_CAPSULE_RADIUS,
		MAX_CAPSULE_RADIUS
	)
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = maxf(length, radius * 2.0)
	shape_node.shape = capsule
	shape_node.transform = Transform3D(_get_up_basis(segment), segment * 0.5)
	return shape_node


func _get_segment_child(skeleton: Skeleton3D, bone_index: int) -> int:
	var children: PackedInt32Array = skeleton.get_bone_children(bone_index)
	return children[0] if not children.is_empty() else -1


## Basis whose Y axis runs along [param direction], which is how a capsule is aligned.
static func _get_up_basis(direction: Vector3) -> Basis:
	var up: Vector3 = direction.normalized()
	var reference: Vector3 = Vector3.RIGHT if absf(up.dot(Vector3.UP)) > 0.99 else Vector3.UP
	var right: Vector3 = reference.cross(up).normalized()
	return Basis(right, up, right.cross(up))


## An octagonal prism rather than a box, so a chest settles onto a facet not a flat face.
func _create_prism(size: Vector3) -> ConvexPolygonShape3D:
	var half: Vector3 = size * 0.5
	var points: PackedVector3Array = PackedVector3Array()
	for corner: int in 8:
		var angle: float = TAU * float(corner) / 8.0
		var offset: Vector3 = Vector3(cos(angle) * half.x, 0.0, sin(angle) * half.z)
		points.append(offset + Vector3(0.0, -half.y, 0.0))
		points.append(offset + Vector3(0.0, half.y, 0.0))

	var prism: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
	prism.points = points
	return prism


func _create_sphere(radius: float) -> SphereShape3D:
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = radius
	return sphere


## Jointed bodies still collide in Godot, and a parent and child overlap around the pivot
## they share, so those pairs are excluded or the rig stretches instead of falling.
func _exclude_joint_pairs(skeleton: Skeleton3D, bones: Dictionary) -> void:
	for bone_name: String in bones:
		var parent_bone: PhysicalBone3D = _find_physical_parent(
			skeleton, bones, skeleton.find_bone(bone_name)
		)
		if parent_bone == null:
			continue

		var bone: PhysicalBone3D = bones[bone_name]
		PhysicsServer3D.body_add_collision_exception(bone.get_rid(), parent_bone.get_rid())
		PhysicsServer3D.body_add_collision_exception(parent_bone.get_rid(), bone.get_rid())


## Nearest ancestor bone that has a body of its own.
func _find_physical_parent(
	skeleton: Skeleton3D, bones: Dictionary, bone_index: int
) -> PhysicalBone3D:
	var parent_index: int = skeleton.get_bone_parent(bone_index)
	while parent_index >= 0:
		var parent_name: String = skeleton.get_bone_name(parent_index)
		if bones.has(parent_name):
			return bones[parent_name]
		parent_index = skeleton.get_bone_parent(parent_index)

	return null


## Index of the nearest ancestor bone that has a body of its own, or -1 at the root.
func _find_physical_parent_index(skeleton: Skeleton3D, bone_index: int) -> int:
	var parent_index: int = skeleton.get_bone_parent(bone_index)
	while parent_index >= 0:
		var parent_name: StringName = StringName(skeleton.get_bone_name(parent_index))
		if BONE_MASS.has(parent_name):
			return parent_index
		parent_index = skeleton.get_bone_parent(parent_index)

	return -1




