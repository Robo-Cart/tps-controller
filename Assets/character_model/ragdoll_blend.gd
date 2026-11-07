class_name RagdollBlend
extends RefCounted

## The active-ragdoll weight: 0 means the animation system owns the skeleton, 1 means the
## simulated bodies do. Everything in between is the hand-over, and the hand-over is what
## makes a stumble read as "catching himself" instead of as a corpse switch being flipped.
##
## The ragdoll's drawn pose is authored from the bodies, so a partial weight blends the
## animation pose towards the simulated one. Keep the animation tree running while the weight
## is below 1: that is what the partial weight is blending FROM. Once it reaches 1 the tree can
## be disabled and the body is fully physical, which is the death case.

## Seconds to go from animated to fully simulated. Short: a stumble is a snap, not a fade.
const BLEND_IN_TIME: float = 0.2

## Seconds to go back to the animation. Longer: recovering must look deliberate.
const BLEND_OUT_TIME: float = 0.5

## Horizontal speed at which a fall becomes a stumble. Below it the body keeps its feet.
const STUMBLE_SPEED: float = 2.0

## Speed at which an airborne body is handed over immediately.
const IMPACT_FALL_SPEED: float = 2.5

## Seconds on the ground before a stumble is handed back to the animation system.
const RECOVER_GROUNDED_TIME: float = 0.35

var weight: float = 0.0
var _target: float = 0.0
var _grounded_time: float = 0.0


## True while any simulation should be fed, even at a partial weight.
func is_simulating() -> bool:
	return weight > 0.0


## Hands the body over to the simulation, e.g. on a trip or a heavy landing.
func request_fall() -> void:
	_target = 1.0
	_grounded_time = 0.0


## Hands the body back to the animation system, e.g. once the skeleton is upright again.
func request_recover() -> void:
	_target = 0.0
	_grounded_time = 0.0


## Advances the weight. [param grounded] and [param speed] let a stumble start and finish
## without the gameplay code having to detect it. Returns the new weight.
func update(delta: float, grounded: bool, speed: float) -> float:
	if delta <= 0.0:
		return weight

	if not grounded and speed >= IMPACT_FALL_SPEED:
		_target = 1.0
		_grounded_time = 0.0
	elif speed >= STUMBLE_SPEED and weight < 1.0 and _target < 1.0:
		# Fast but not falling: lean on the simulation harder, but do not hand it over.
		_target = maxf(_target, 0.5)
	elif grounded and _target > 0.0:
		_grounded_time += delta
		if _grounded_time >= RECOVER_GROUNDED_TIME:
			_target = 0.0
	elif grounded and _target <= 0.0:
		_grounded_time = 0.0

	var duration: float = BLEND_IN_TIME if weight < _target else BLEND_OUT_TIME
	weight = move_toward(weight, _target, delta / maxf(duration, 0.001))
	return weight


## Blends one bone's pose from the animated one towards the simulated one. Both are in the
## same space (the caller converts to world before and back after), so this is a plain
## shortest-arc slerp plus a position lerp.
static func blend_pose(
	animated: Transform3D, simulated: Transform3D, weight: float
) -> Transform3D:
	if weight <= 0.0:
		return animated
	if weight >= 1.0:
		return simulated

	var from: Quaternion = animated.basis.orthonormalized().get_rotation_quaternion()
	var to: Quaternion = simulated.basis.orthonormalized().get_rotation_quaternion()
	var origin: Vector3 = animated.origin.lerp(simulated.origin, weight)
	return Transform3D(Basis(from.slerp(to, weight)), origin)
