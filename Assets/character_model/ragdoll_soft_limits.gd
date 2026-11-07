class_name RagdollSoftLimits
extends RefCounted

## Soft joint limits: the maths that lets a joint approach its stop instead of hitting it.
##
## A hard `clampf` draws a limb that stops dead at its limit and then slides along a flat
## top, which is the single biggest "mannequin" tell in a ragdoll. Real tissue resists
## earlier and harder: the last part of the range is spongy, the resistance rises faster
## than the angle, and the joint never quite reaches the stop.
##
## [method clip_soft] is the angle a joint is DRAWN at. It is the identity in the middle of
## the range, bends inside a soft zone at each end, and asymptotes at the hard limit, so a
## body that is physically past its stop still reads as a strained joint rather than a
## clipped one. [method stop_step] is the speed the body has taken out of it to bring it
## back, applied as a torque (never a transform write, which the solver spends the next step
## undoing).

## Share of an axis's travel used as the soft zone at each end. 0.3 leaves the middle 40%
## of the range free, then spends 30% compressing into each stop.
const DEFAULT_SOFT_SHARE: float = 0.3

## Per-joint overrides. The trunk is spongier because three short spine joints stack their
## ranges; the hinges keep a tighter zone so a knee still reaches a convincing fold.
const SOFT_SHARE: Dictionary = {
	&"mixamorig_Spine": 0.45,
	&"mixamorig_Spine1": 0.45,
	&"mixamorig_Spine2": 0.45,
	&"mixamorig_Neck": 0.4,
	&"mixamorig_Head": 0.4,
	&"mixamorig_LeftShoulder": 0.35,
	&"mixamorig_RightShoulder": 0.35,
	&"mixamorig_LeftArm": 0.32,
	&"mixamorig_RightArm": 0.32,
	&"mixamorig_LeftForeArm": 0.28,
	&"mixamorig_RightForeArm": 0.28,
	&"mixamorig_LeftHand": 0.25,
	&"mixamorig_RightHand": 0.25,
	&"mixamorig_LeftUpLeg": 0.32,
	&"mixamorig_RightUpLeg": 0.32,
	&"mixamorig_LeftLeg": 0.28,
	&"mixamorig_RightLeg": 0.28,
}

## How sharply resistance rises inside the soft zone. 1 is a linear spring; 2 is the
## muscle-like curve: almost nothing at the edge, decisive at the stop.
const RESISTANCE_EXPONENT: float = 2.0

## Speed a stop's pull takes out of a joint per step, in rad/s per unit of squared overshoot.
## A stop is written as a velocity correction rather than an acceleration for the same reason
## the muscle cap is: an acceleration has to be picked for one mass and is then limp on a
## thigh and violent on a shoulder, which shakes the light bones across their stops forever.
const LIMIT_PULL_STEP: float = 3.0

## Most speed the pull half of a stop may take out in one step, in rad/s.
const MAX_LIMIT_PULL_STEP: float = 10.0

## Most speed a stop may take out in one step in total, in rad/s. The rest is the brake.
const MAX_LIMIT_STEP: float = 20.0


## Give of a pinned axis, in radians. Most joints only have a range on one axis, and the other
## two are held at zero: without a stop there they are free hinges, which is why a knee could
## swing sideways and a foot could spin right round on the shin.
const PIN_SOFT_ZONE: float = 0.035


## The soft zones for a joint, in radians per axis.
static func softness_for(bone_name: StringName, lower: Vector3, upper: Vector3) -> Vector3:
	var share: float = clampf(float(SOFT_SHARE.get(bone_name, DEFAULT_SOFT_SHARE)), 0.0, 0.45)
	return softness(lower, upper, share)


## The soft zones for an arbitrary share. A share at or above 0.5 would make the two zones
## meet in the middle, so it is capped; a pinned axis gets the fixed give below.
static func softness(lower: Vector3, upper: Vector3, share: float) -> Vector3:
	var result: Vector3 = Vector3.ZERO
	var capped: float = clampf(share, 0.0, 0.45)
	for axis: int in 3:
		var span: float = upper[axis] - lower[axis]
		if span <= 0.0:
			result[axis] = PIN_SOFT_ZONE
		else:
			result[axis] = span * capped
	return result


## The angle a joint is drawn at: free in the middle, progressively compressed inside the
## soft zone, asymptotic at the hard stop. Continuous with slope 1 at the zone boundary, so
## there is no kink where the soft zone begins.
static func clip_soft(deviation: Quaternion, spec: Dictionary) -> Quaternion:
	var lower: Vector3 = spec["lower"]
	var upper: Vector3 = spec["upper"]
	var soft: Vector3 = spec.get("soft", Vector3.ZERO)
	var angles: Vector3 = Basis(deviation).get_euler()
	var limited: Vector3 = Vector3(
		clip_angle(angles.x, lower.x, upper.x, soft.x),
		clip_angle(angles.y, lower.y, upper.y, soft.y),
		clip_angle(angles.z, lower.z, upper.z, soft.z)
	)
	if limited.is_equal_approx(angles):
		return deviation

	return Basis.from_euler(limited).get_rotation_quaternion()


## The hard clamp, kept for targets that must never poke outside the anatomical range (the
## authored settle clip is resolved through it).
static func clip_hard(deviation: Quaternion, lower: Vector3, upper: Vector3) -> Quaternion:
	var angles: Vector3 = Basis(deviation).get_euler()
	var limited: Vector3 = Vector3(
		clampf(angles.x, lower.x, upper.x),
		clampf(angles.y, lower.y, upper.y),
		clampf(angles.z, lower.z, upper.z)
	)
	if limited.is_equal_approx(angles):
		return deviation

	return Basis.from_euler(limited).get_rotation_quaternion()


## One axis of [method clip_soft]. With a zone width of zero this degrades to a hard clamp.
static func clip_angle(angle: float, lower: float, upper: float, soft: float) -> float:
	if upper <= lower or soft <= 0.0:
		return clampf(angle, lower, upper)

	var high_edge: float = upper - soft
	if angle > high_edge:
		var over: float = angle - high_edge
		return high_edge + soft * over / (soft + over)

	var low_edge: float = lower + soft
	if angle < low_edge:
		var over: float = low_edge - angle
		return low_edge - soft * over / (soft + over)

	return angle


## Scales a turn down about the rest pose. Stiffness can only bring a joint short of its
## stop, never past it, because it is always applied after the limit clip.
static func stiffen(deviation: Quaternion, stiffness: float) -> Quaternion:
	if stiffness >= 1.0:
		return deviation

	var softened: Vector3 = Basis(deviation).get_euler() * stiffness
	if softened.is_zero_approx():
		return Quaternion.IDENTITY

	return Basis.from_euler(softened).get_rotation_quaternion()


## Blends a joint's turn towards a target turn, shortest way round on each axis. Used for
## the always-on pull towards the neutral posture: both ends are inside the range, so the
## result is too, and the pull can never defeat a limit.
static func blend(deviation: Quaternion, target: Quaternion, weight: float) -> Quaternion:
	if weight <= 0.0 or deviation.is_equal_approx(target):
		return deviation
	if weight >= 1.0:
		return target

	var from: Vector3 = Basis(deviation).get_euler()
	var to: Vector3 = Basis(target).get_euler()
	for axis: int in 3:
		# A 350-degree Euler turn is the same pose as -10; wrapping avoids spinning the
		# long way round whenever the decomposition flips.
		to[axis] = from[axis] + wrapf(to[axis] - from[axis], -PI, PI)
	return Basis.from_euler(from.lerp(to, weight)).get_rotation_quaternion()


## How far an angle is into a soft zone, as a signed value: 0 in the free middle, +1 when
## pressed exactly against the upper stop, -1 against the lower, and beyond ±1 when the
## physical body has gone past what the drawn pose will show.
static func signed_overshoot(angle: float, lower: float, upper: float, soft: float) -> float:
	if upper <= lower:
		# Pinned: there is no travel at all, so the stop sits at zero and any turn away from
		# it is into the soft zone. This is the axis of every joint that only hinges.
		if soft <= 0.0:
			return 0.0
		var pinned_over: float = absf(angle - lower) - soft
		if pinned_over <= 0.0:
			return 0.0
		return signf(angle - lower) * pinned_over / soft
	if soft <= 0.0:
		if angle > upper:
			return angle - upper
		if angle < lower:
			return angle - lower
		return 0.0

	var high_edge: float = upper - soft
	if angle > high_edge:
		return (angle - high_edge) / soft

	var low_edge: float = lower + soft
	if angle < low_edge:
		return (angle - low_edge) / soft

	return 0.0


## The full stop correction, as a speed to take out of the joint this step, in rad/s. Two
## parts: the squared pull of the soft zone, and a brake that removes whatever outward speed
## the joint still has. The brake is bounded by the speed it is cancelling, so it stops the
## joint instead of bouncing it, and a joint already on its way back gets no brake at all.
static func stop_step(overshoot: float, outward_speed: float) -> float:
	var pull: float = minf(LIMIT_PULL_STEP * pow(overshoot, RESISTANCE_EXPONENT), MAX_LIMIT_PULL_STEP)
	var brake: float = clampf(outward_speed, 0.0, MAX_LIMIT_STEP - pull)
	return pull + brake
