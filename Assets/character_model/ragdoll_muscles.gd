class_name RagdollMuscles
extends RefCounted

## Neutral posture (the equilibrium the body wants to hang in) and the muscle tone that
## pulls the simulated bodies towards it.
##
## This is the difference between a body that "hangs" and one that reads as unconscious. Tone
## pulls the arms forward and slightly in with bent elbows, keeps a little flex in the hips
## and knees, and stops the head lolling straight back, which is the relaxed human (and
## microgravity) posture rather than the starfish of a limp ragdoll.
##
## It is deliberately weak: the torque here is one to two orders of magnitude below what
## gravity exerts on a single limb, so a fall, a shove or a planted foot overrules it
## completely. It only bites when nothing else is happening, which is exactly when a limp
## ragdoll floats into an impossible shape.

## The neutral turn for each joint, as (flexion, swing, twist) SHARES of that joint's own
## range, the same convention as DEATH_POSES.SETTLE_POSES. A share is safe against limit
## changes; a hard-coded angle is not.
const NEUTRAL_POSTURE: Dictionary = {
	# Trunk: a slight forward curl, never a straight plank. These are shares of the joint's own
	# range, so they are rescaled whenever a range changes: 0.22 of 45 degrees is the same ten
	# degree curl as 0.4 of the 25 it used to be, and leaving it at 0.4 doubles the curl.
	&"mixamorig_Spine": Vector3(0.22, 0.5, 0.5),
	&"mixamorig_Spine1": Vector3(0.22, 0.5, 0.5),
	&"mixamorig_Spine2": Vector3(0.22, 0.5, 0.5),
	# Head: flexed a little forward, level rather than flopping back.
	&"mixamorig_Neck": Vector3(0.21, 0.5, 0.5),
	&"mixamorig_Head": Vector3(0.25, 0.5, 0.5),
	# Shoulders: driven forward, which is what carries the arms in front of the body.
	&"mixamorig_LeftShoulder": Vector3(0.78, 0.55, 0.5),
	&"mixamorig_RightShoulder": Vector3(0.78, 0.55, 0.5),
	# Upper arms: well forward, slightly out. The arm range is 50 degrees of flexion, so a
	# 0.88 share is about 44 degrees: arms reach in front of the chest, not straight down.
	&"mixamorig_LeftArm": Vector3(0.88, 0.42, 0.5),
	&"mixamorig_RightArm": Vector3(0.88, 0.42, 0.5),
	# Elbows: the hinge runs 0 (straight) to 120 (folded), so 0.34 is a permanent bend of
	# about 41 degrees. This single value does more for "alive" than any amount of damping.
	&"mixamorig_LeftForeArm": Vector3(0.34, 0.5, 0.5),
	&"mixamorig_RightForeArm": Vector3(0.34, 0.5, 0.5),
	&"mixamorig_LeftHand": Vector3(0.35, 0.5, 0.5),
	&"mixamorig_RightHand": Vector3(0.35, 0.5, 0.5),
	# Hips and knees: only slightly flexed. A big share here reads as sitting up in mid-air.
	&"mixamorig_LeftUpLeg": Vector3(0.22, 0.45, 0.5),
	&"mixamorig_RightUpLeg": Vector3(0.22, 0.45, 0.5),
	&"mixamorig_LeftLeg": Vector3(0.18, 0.5, 0.5),
	&"mixamorig_RightLeg": Vector3(0.18, 0.5, 0.5),
}

## Default neutral turn for a joint with no authored entry: dead centre of its range.
const DEFAULT_NEUTRAL_SHARE: Vector3 = Vector3(0.5, 0.5, 0.5)

## How much each joint is pulled towards its neutral turn in the DRAWN pose. This is the
## strongest, cheapest lever on how alive the body reads: it is a shaping of what is drawn,
## so it costs no solver stability. Strong on the limbs that unmistakably flop (shoulders,
## elbows, hips, knees), weaker on the trunk, which is already held by its own mass.
const NEUTRAL_BIAS: Dictionary = {
	&"mixamorig_Spine": 0.08,
	&"mixamorig_Spine1": 0.08,
	&"mixamorig_Spine2": 0.08,
	&"mixamorig_LeftArm": 0.45,
	&"mixamorig_RightArm": 0.45,
	&"mixamorig_LeftForeArm": 0.5,
	&"mixamorig_RightForeArm": 0.5,
	&"mixamorig_LeftShoulder": 0.35,
	&"mixamorig_RightShoulder": 0.35,
	&"mixamorig_LeftUpLeg": 0.32,
	&"mixamorig_RightUpLeg": 0.32,
	&"mixamorig_LeftLeg": 0.38,
	&"mixamorig_RightLeg": 0.38,
	&"mixamorig_Neck": 0.28,
	&"mixamorig_Head": 0.28,
	&"mixamorig_LeftHand": 0.2,
	&"mixamorig_RightHand": 0.2,
}

## Default bias for a joint with no authored entry.
const DEFAULT_NEUTRAL_BIAS: float = 0.25

## Joints that let their posture go while the body is being thrown about. The trunk is the one
## chain where tone was doing damage: a posture spring pulls a joint back to where it wants to
## hang, so a body knocked forward folds at the waist and the spring immediately unbends it,
## the torso is thrown forward by the blow and then hauled back upright while the hips are
## still going over, which reads as a force from nowhere pushing the chest the other way. A
## real trunk does not do that: the abdominal wall holds the resting curl, and a fall that
## folds it further leaves the tissue slack instead of pulling the body back up, so the fold
## the impact made survives and the corpse goes over as one piece. The limbs are not listed:
## their tone is what stops a corpse looking like a puppet, and it is far too weak to swing a
## whole arm back against a fall.
const SLACK_JOINTS: Array[StringName] = [
	&"mixamorig_Spine",
	&"mixamorig_Spine1",
	&"mixamorig_Spine2",
]

## Spin of one of those joints, in rad/s, at which its posture is gone entirely: the share of
## tone left fades linearly to nothing as the spin reaches it. A body being thrown about has
## no posture to hold; it gets one back once it stops being thrown, which is what keeps a
## settled corpse from going slack on the floor and starting to flop.
const SLACK_SPIN: float = 2.0

## How much of the bias survives once the body has settled on the floor. Tone does not
## disappear after death; it fades to this fraction, which is why a corpse still keeps a
## little shape instead of pancaking.
const NEUTRAL_SETTLE_SHARE: float = 0.7

## Muscle tone in the first moments after an impact: a real body goes momentarily slack from
## the shock before tone returns. Never 0: a body that starts at zero hangs from its first
## frame, which is exactly the limp look the tone exists to remove.
const TONE_SHOCK: float = 0.45

## Tone once recovered, as a share of full strength.
const TONE_BASE: float = 0.85

## Seconds for tone to climb from the shock value to the base value. Short, because the
## collapse happens in the first half second: tone that arrives after the fall has arrived
## too late to stop the knees buckling under the body.
const TONE_RECOVERY_TIME: float = 0.35

## Units of tone recovered per second, so the ragdoll can ramp it with one move_toward.
const TONE_RECOVERY_RATE: float = (TONE_BASE - TONE_SHOCK) / TONE_RECOVERY_TIME

## Tone left for the physical (torque) pass once the body has settled. The bodies still have
## to hold their own shape against the floor, so most of the tone is kept: this is what stops
## a settled corpse from being a pile of loose segments.
const PHYSICAL_TONE_REST_SHARE: float = 0.85

## The spring that drives a body towards its neutral world rotation, in rad/s² per rad of
## error. It has to be stiff: at a soft setting the knee sags half a right angle before the
## spring can answer the weight of the shin, and a corpse that sits down on its own heels
## folds into a heap instead of falling over like a body. Tuned against the damping below for
## a damping ratio of about 1: 2*sqrt(400) is 40, so 40 sits on critical.
const MUSCLE_SPRING: float = 400.0

## Damping on the body's angular speed along the error axis, in 1/s.
const MUSCLE_DAMPING: float = 40.0

## Hard ceiling on the angular acceleration tone may ask for, in rad/s². This has to beat
## gravity on the limb it is holding, or tone is a gesture rather than a posture: holding a
## forearm straight out asks for about 450 on a real forearm, so a ceiling under that lets
## every limb hang limp however stiff the spring behind it is.
const MAX_MUSCLE_ACCELERATION: float = 600.0

## Largest change of angular speed one step of tone may make, in rad/s. This is the real
## stability limit and it has to be a limit on SPEED, not on acceleration: the bones that
## chatter are the light ones, where an acceleration ceiling that is sane for a thigh is a
## violent kick for a head, so the same rad/s² figure means wildly different things per bone.
const MAX_MUSCLE_STEP: float = 2.5

## Rate at which the spin one bone has relative to its parent is damped away, in 1/s. This is
## the tissue inside the joint: without it two bones meet at an oiled pivot and a limb swings
## freely through its whole range no matter where the stops are, which is what "no tension in
## the joints" looks like. It only ever removes relative motion, so it cannot add energy.
const JOINT_DAMPING_RATE: float = 12.0

## Floor on that damping, as a share of full strength, so a limp body still has joints that
## resist instead of free hinges.
const JOINT_DAMPING_FLOOR: float = 0.35

## Fallback inertia per kilogram, in m², for a body the physics server reports none for.
## PhysicalBone3D exposes no inertia, and inferring one from the mass is off by a factor of
## ten on a thin limb, so the server's own figure is always preferred: see _inertia_along.
const INERTIA_PER_KG: float = 0.015

## Floor on inertia so a massless box cannot divide the torque to nothing.
const MIN_INERTIA: float = 0.0005




## The neutral turn for a joint, clamped into its own range. Pinned joints (no span on an
## axis) are forced to zero so they never acquire a phantom turn.
static func neutral_deviation(
	bone_name: StringName, lower: Vector3, upper: Vector3, axes: Vector3i
) -> Quaternion:
	var share: Vector3 = NEUTRAL_POSTURE.get(bone_name, DEFAULT_NEUTRAL_SHARE)
	var target: Vector3 = Vector3.ZERO
	target[axes.y] = lerpf(lower[axes.y], upper[axes.y], share.x)
	target[axes.z] = lerpf(lower[axes.z], upper[axes.z], share.y)
	target[axes.x] = lerpf(lower[axes.x], upper[axes.x], share.z)
	for axis: int in 3:
		if is_zero_approx(upper[axis] - lower[axis]):
			target[axis] = 0.0
	return Basis.from_euler(target).get_rotation_quaternion()


## The drawn-pose bias towards [method neutral_deviation] for a joint.
static func bias_for(bone_name: StringName) -> float:
	return float(NEUTRAL_BIAS.get(bone_name, DEFAULT_NEUTRAL_BIAS))


## The share of its tone a joint keeps at [param spin] rad/s of world spin: see SLACK_JOINTS.
static func slack_share(bone_name: StringName, spin: float) -> float:
	if not (bone_name in SLACK_JOINTS):
		return 1.0

	return 1.0 - clampf(spin / SLACK_SPIN, 0.0, 1.0)


## Remembers, per joint, the turn it is at the moment the bodies start simulating: the
## posture its muscles were holding when it died.
##
## Tone drives towards THIS rather than towards the neutral posture, because the neutral
## posture is the turn the rig was BUILT in - a body standing still - and a body that dies at
## a run is leaning, folded and twisted away from it at every joint. Driving towards the built
## posture is a full-body snap back to standing at the exact moment the corpse should start
## falling: measured at up to 160 deg/s of the wrong-way rotation in the first quarter second
## of a running death, which reads as a force from nowhere pushing the torso back upright.
## Held as a deviation from the rest pose, the same shape as the neutral posture, and clipped
## into the joint's range so the target can never fight the soft stop.
static func anchor_posture(
	specs: Dictionary, bodies: Dictionary, bone_order: Array[int]
) -> void:
	for bone_index: int in bone_order:
		var spec: Dictionary = specs.get(bone_index, {})
		var body: PhysicalBone3D = bodies.get(bone_index) as PhysicalBone3D
		if spec.is_empty() or body == null:
			continue

		var parent_body: PhysicalBone3D = bodies.get(spec["parent"]) as PhysicalBone3D
		if parent_body == null:
			continue

		var rest: Quaternion = spec["rest"]
		var parent_rotation: Quaternion = _rotation_of(parent_body)
		var deviation: Quaternion = rest.inverse() * (parent_rotation.inverse() * _rotation_of(body))
		spec["hold"] = RagdollSoftLimits.clip_soft(deviation, spec)


## The turn a joint's tone holds: the posture it died in, relaxing towards the neutral
## posture as the body settles. [param relax] is 0..1.
static func posture_target(spec: Dictionary, relax: float) -> Quaternion:
	var hold: Quaternion = spec.get("hold", spec["neutral"]) as Quaternion
	var neutral: Quaternion = spec["neutral"]
	if relax <= 0.0 or hold.is_equal_approx(neutral):
		return hold

	return hold.slerp(neutral, relax)


## Drives every simulated body towards the posture it died in and pushes it out of its soft
## stops. Called once per physics step BEFORE the pose is read, so the torque takes effect on
## the next solver step. [param tone] and [param limit_weight] are both 0..1, and [param relax]
## carries the target from the anchored posture towards the neutral one.
static func apply_drives(
	skeleton: Skeleton3D,
	bodies: Dictionary,
	specs: Dictionary,
	bone_order: Array[int],
	delta: float,
	tone: float,
	limit_weight: float,
	relax: float
) -> void:
	if skeleton == null or delta <= 0.0 or (tone <= 0.0 and limit_weight <= 0.0):
		return

	# Targets are accumulated parent-first so a limb's neutral world rotation includes its
	# parent's own tone correction: tone is a posture, not a set of independent twists.
	var targets: Dictionary = {}
	for bone_index: int in bone_order:
		var body: PhysicalBone3D = bodies.get(bone_index) as PhysicalBone3D
		if body == null:
			continue
		var spec: Dictionary = specs.get(bone_index, {})
		if spec.is_empty():
			targets[bone_index] = _rotation_of(body)
			continue
		var parent_index: int = spec["parent"]
		var parent_body: PhysicalBone3D = bodies.get(parent_index) as PhysicalBone3D
		if parent_body == null:
			targets[bone_index] = _rotation_of(body)
			continue
		var parent_target: Quaternion = targets.get(parent_index, _rotation_of(parent_body))
		var target: Quaternion = parent_target * spec["rest"] * posture_target(spec, relax)
		targets[bone_index] = target
		if tone > 0.0:
			var share: float = tone * slack_share(body.name, _angular_velocity(body).length())
			if share > 0.0:
				apply_tone(body, parent_body, target, delta, share)
		apply_joint_damping(body, parent_body, delta, maxf(tone, JOINT_DAMPING_FLOOR))
		if limit_weight > 0.0:
			apply_limit(body, parent_body, spec, limit_weight)


## Spring-damper towards a target world rotation, applied as a torque impulse. The correction
## acts about the error axis only, so it cannot fight the body's angular momentum around
## other axes.
##
## The damping is measured against the PARENT's spin, not against the world, because the
## target is anchored to the parent (see apply_drives): the error only changes when the joint
## itself turns. Damping the absolute spin instead brakes every bone that is falling as part
## of a whole body, so the trunk loses the rotation the fall gave it, stops, and rocks back
## while the hips carry on over — a reverse force out of nowhere.
static func apply_tone(
	body: PhysicalBone3D,
	parent_body: PhysicalBone3D,
	target: Quaternion,
	delta: float,
	tone: float
) -> void:
	var error: Quaternion = target * _rotation_of(body).inverse()
	var angle: float = error.get_angle()
	var axis: Vector3 = error.get_axis().normalized()
	if angle > PI:
		# Quaternion.get_angle() runs out to a full turn because the sign of w is arbitrary.
		# Driving the long way round asks for five times the acceleration on a one radian
		# error, which is enough to slam the body past its target every step.
		angle = TAU - angle
		axis = -axis
	if angle < 0.0005:
		return

	var along_speed: float = (_angular_velocity(body) - _angular_velocity(parent_body)).dot(axis)
	var acceleration: float = MUSCLE_SPRING * angle - MUSCLE_DAMPING * along_speed
	acceleration = clampf(acceleration, -MAX_MUSCLE_ACCELERATION, MAX_MUSCLE_ACCELERATION)
	# Then the step limit, which is what actually keeps a light bone from being kicked back
	# and forth across its target every frame.
	var ceiling: float = MAX_MUSCLE_STEP / delta
	apply_angular_acceleration(body, axis, clampf(acceleration * tone, -ceiling, ceiling), delta)


## Viscous resistance inside one joint: this step removes a share of the spin the child has
## relative to its parent. Muscles, tendons and skin all do this and it is the whole
## difference between a limb hinged on a pin and a limb with tissue around it. It acts on the
## RELATIVE speed, so it never fights the body moving as a whole; it only ever removes
## energy, so it cannot destabilise the solver.
static func apply_joint_damping(
	body: PhysicalBone3D, parent_body: PhysicalBone3D, delta: float, weight: float
) -> void:
	var relative: Vector3 = _angular_velocity(body) - _angular_velocity(parent_body)
	var speed: float = relative.length()
	if speed < 0.02 or delta <= 0.0:
		return

	var axis: Vector3 = relative / speed
	# Framerate independent: the share of the relative spin left after one step.
	var removed: float = speed * (1.0 - exp(-JOINT_DAMPING_RATE * weight * delta))
	var torque: Vector3 = -axis * _inertia_along(body, axis) * removed
	PhysicsServer3D.body_apply_torque_impulse(body.get_rid(), torque)


## Soft-stop correction for one joint. The joint's turn is measured in its own rest frame,
## where the stored range lives, and corrected about the same frame's axes: measuring in the
## parent's frame instead puts a hip's fold on an axis that is 180 degrees from the one it
## actually turns about, so the stop drives it further out.
static func apply_limit(
	body: PhysicalBone3D,
	parent_body: PhysicalBone3D,
	spec: Dictionary,
	limit_weight: float
) -> void:
	var soft: Vector3 = spec["soft"]
	if soft.is_zero_approx():
		return

	var lower: Vector3 = spec["lower"]
	var upper: Vector3 = spec["upper"]
	var rest: Quaternion = spec["rest"]
	var parent_basis: Basis = parent_body.global_transform.basis.orthonormalized()
	var parent_rotation: Quaternion = parent_basis.get_rotation_quaternion()
	var joint_basis: Basis = Basis(parent_rotation * rest)
	var deviation: Quaternion = rest.inverse() * (parent_rotation.inverse() * _rotation_of(body))

	# A joint folds about one axis, so the fold is read as one turn and split over the joint's
	# axes by how much of that turn lies along each. Reading it as Euler angles instead puts a
	# knee folded backwards into whichever axis the decomposition happens to pick, which is how
	# a real fold ends up being corrected about the wrong axis and simply kept folding.
	var fold: float = deviation.get_angle()
	var fold_axis: Vector3 = deviation.get_axis().normalized()
	if fold > PI:
		fold = TAU - fold
		fold_axis = -fold_axis
	if fold < 0.0005:
		return

	# Half a turn is its own mirror image, so the axis of the fold is not defined there and the
	# stop would be driving about whichever axis the maths picked off a rounding error, which
	# is how a foot left alone can spin right round on the shin. Past that point there is no
	# shorter way back, so the joint is held to its parent's motion instead.
	if fold > PI - 0.05:
		_damp_to_parent(body, parent_body, limit_weight)
		return

	# The violated axis with the largest overshoot sets the strength of the correction. Every
	# violated axis asks for the same thing: undo the turn the joint is making, so the pull is
	# one force along the turn rather than three that partially cancel each other out.
	var overshoot: float = 0.0
	for axis: int in 3:
		var along: float = RagdollSoftLimits.signed_overshoot(
			fold * fold_axis[axis], lower[axis], upper[axis], soft[axis]
		)
		overshoot = maxf(overshoot, absf(along))
	# A fold spread evenly over three axes can sit inside every one of them and still be
	# further out than the joint can reach, which is how a shoulder ends up turned well past
	# its range with no axis reporting a violation. The whole turn is checked against the
	# furthest corner of the range for that reason.
	var reach: float = maxf(
		Vector3(maxf(upper.x, 0.0), maxf(upper.y, 0.0), maxf(upper.z, 0.0)).length(),
		Vector3(maxf(-lower.x, 0.0), maxf(-lower.y, 0.0), maxf(-lower.z, 0.0)).length()
	)
	overshoot = maxf(overshoot, (fold - reach) / maxf(soft[soft.max_axis_index()], 0.0001))
	if is_zero_approx(overshoot):
		return

	var world_axis: Vector3 = (joint_basis * fold_axis).normalized()
	# Positive while the joint is still turning further out of its range, which is the only
	# time the brake applies: a joint already coming back is left to the pull alone.
	var relative: Vector3 = _angular_velocity(body) - _angular_velocity(parent_body)
	var outward_speed: float = relative.dot(world_axis)
	var step: float = RagdollSoftLimits.stop_step(overshoot, outward_speed)
	apply_angular_step(body, world_axis, -step * limit_weight)


## Takes the joint's own spin out of it, leaving it moving with its parent. Used where the
## joint has folded so far round that there is no defined way back.
static func _damp_to_parent(
	body: PhysicalBone3D, parent_body: PhysicalBone3D, weight: float
) -> void:
	var relative: Vector3 = _angular_velocity(body) - _angular_velocity(parent_body)
	var speed: float = relative.length()
	if speed < 0.01:
		return

	var step: float = minf(speed, RagdollSoftLimits.MAX_LIMIT_STEP) * weight
	apply_angular_step(body, relative, -step)


## Removes [param step] rad/s of angular speed about [param world_axis] in one step, as a
## torque impulse. Working in speed rather than acceleration is what makes one constant mean
## the same thing on every bone: the impulse is scaled by the body's real inertia, so the
## bone loses exactly that much speed and no more, whatever it weighs.
static func apply_angular_step(body: PhysicalBone3D, world_axis: Vector3, step: float) -> void:
	if is_zero_approx(step) or world_axis.is_zero_approx():
		return

	var unit: Vector3 = world_axis.normalized()
	PhysicsServer3D.body_apply_torque_impulse(body.get_rid(), unit * _inertia_along(body, unit) * step)


## Applies an angular acceleration as a one-step torque impulse. The impulse is allowed to
## accumulate with the body's existing angular velocity, which is what lets repeated frames
## of small tone actually add up instead of overwriting each other.
static func apply_angular_acceleration(
	body: PhysicalBone3D, world_axis: Vector3, acceleration: float, delta: float
) -> void:
	if is_zero_approx(acceleration) or world_axis.is_zero_approx():
		return

	var unit: Vector3 = world_axis.normalized()
	var torque: Vector3 = unit * _inertia_along(body, unit) * acceleration * delta
	PhysicsServer3D.body_apply_torque_impulse(body.get_rid(), torque)


## The body's real inertia about [param world_axis], in kg·m², from the physics server. The
## server's figure is a diagonal in the body's own frame, so the value along a world axis is
## the reciprocal of the sum of that axis's squared share on each of them.
static func _inertia_along(body: PhysicalBone3D, world_axis: Vector3) -> float:
	var fallback: float = maxf(body.mass * INERTIA_PER_KG, MIN_INERTIA)
	var diagonal: Vector3 = PhysicsServer3D.body_get_param(
		body.get_rid(), PhysicsServer3D.BODY_PARAM_INERTIA
	) as Vector3
	if not diagonal.is_finite() or diagonal.is_zero_approx():
		return fallback

	var local: Vector3 = body.global_transform.basis.orthonormalized().inverse() * world_axis
	var sum: float = 0.0
	for axis: int in 3:
		sum += local[axis] * local[axis] / maxf(diagonal[axis], MIN_INERTIA)
	if sum <= 0.0:
		return fallback
	return 1.0 / sum


## The body's spin from the physics server. PhysicalBone3D.angular_velocity is only refreshed
## on a body state change and does not agree with the solver during the step the corrections
## are made in, so every correction reads the same authoritative number here.
static func _angular_velocity(body: PhysicalBone3D) -> Vector3:
	var state: Variant = PhysicsServer3D.body_get_state(
		body.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY
	)
	if state is Vector3 and (state as Vector3).is_finite():
		return state

	return body.angular_velocity


static func _rotation_of(body: PhysicalBone3D) -> Quaternion:
	return body.global_transform.basis.orthonormalized().get_rotation_quaternion()












