class_name RagdollImpact
extends RefCounted

## Secondary rotational impulses for a blow or an explosion.
##
## The primary impulse lands on the trunk and gives the body its travel. On its own that is a
## bag of mass sliding away: arms and legs follow the joints with no life of their own. A real
## body's limbs lag the trunk, so this adds counter-rotating impulses at the shoulders and
## hips - arms thrown back while the feet trail forward - plus a yaw twist when the blow landed
## off the spine's axis. That lag is most of the difference between a corpse and a mannequin
## being pushed over.
##
## Every spin here goes through the velocity API rather than a joint, because GodotPhysics
## ignores angular joint limits and a one-shot spin is eaten by the bodies' angular damp
## (ANGULAR_DAMP 15 buys about ten degrees). The blast is therefore applied as a velocity, and
## [method apply_blast] is meant to be called every frame for the length of the explosion.

## Share of body mass used for the limb impulses. Small on purpose: the limb is already being
## dragged by the trunk through its joint, and this only adds the lag on top.
const SHOULDER_MASS_SHARE: float = 0.1
const ARM_MASS_SHARE: float = 0.16
const LEG_MASS_SHARE: float = 0.08

## How far along the limb the impulse is applied, as a share of the segment length. Off the
## pivot is what turns a shove into a swing.
const LEVER_SHARE: float = 0.6

## Ceiling on the speed a secondary impulse may add, in m/s, whatever the blow's strength.
const MAX_SECONDARY_SPEED: float = 6.0

## Yaw twist from a blow that landed off the spine's axis.
const YAW_SHARE: float = 0.3
const MAX_YAW_SPEED: float = 5.0

## Ceiling on the angular speed any single impact may give a body, in rad/s. Without it a
## light hand can be spun into a blur by the lever arm.
const MAX_SECONDARY_SPIN: float = 12.0

## Ceiling on the momentum handed to the bodies when the body dies. A frame spent at a very
## high speed (a teleport, a long fall) would otherwise fire the ragdoll across the level.
const MAX_LAUNCH_SPEED: float = 12.0
const MAX_LAUNCH_SPIN: float = 4.0

## Blast tuning: outward share of body mass, the tangential component that separates a blast
## from a uniform push, and the spin it adds.
const BLAST_MASS_SHARE: float = 0.35
const BLAST_TANGENT: float = 0.35
const BLAST_SPIN_SHARE: float = 0.25
const BLAST_MIN_DISTANCE: float = 0.05


## Hands the momentum the body died with over to the bodies: each gets the speed plus the
## share of the spin its distance from the pivot earns it.
static func apply_momentum(
	bodies: Dictionary,
	bone_order: Array[int],
	skeleton: Skeleton3D,
	launch_velocity: Vector3,
	launch_spin: Vector3
) -> void:
	if skeleton == null:
		return

	var linear: Vector3 = launch_velocity.limit_length(MAX_LAUNCH_SPEED)
	var spin: Vector3 = launch_spin.limit_length(MAX_LAUNCH_SPIN)
	var pivot: Vector3 = skeleton.global_transform.origin
	for bone_index: int in bone_order:
		var bone: PhysicalBone3D = bodies.get(bone_index) as PhysicalBone3D
		if bone == null:
			continue

		var velocity: Vector3 = linear + spin.cross(bone.global_position - pivot)
		var body: RID = bone.get_rid()
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, velocity)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, spin)


## Picks the body a blow lands on, drawn by mass so most hits fall on the trunk, and a point
## along that body rather than at its pivot so the shove turns the corpse as it goes over.
## Returns {"bone_index", "point"}; empty if there is nothing to hit.
static func pick_hit(
	bodies: Dictionary, bone_order: Array[int], skeleton: Skeleton3D
) -> Dictionary:
	var total: float = 0.0
	for bone_index: int in bone_order:
		var bone: PhysicalBone3D = bodies.get(bone_index) as PhysicalBone3D
		if bone != null:
			total += bone.mass
	if total <= 0.0:
		return {}

	var roll: float = randf() * total
	var picked: int = -1
	for bone_index: int in bone_order:
		var bone: PhysicalBone3D = bodies.get(bone_index) as PhysicalBone3D
		if bone == null:
			continue
		roll -= bone.mass
		if roll <= 0.0:
			picked = bone_index
			break
	if picked < 0:
		return {}

	return {"bone_index": picked, "point": _get_hit_point_on(bodies, skeleton, picked)}


## Applies the secondary limb rotation for a blow that shoved the trunk along
## [param direction] at [param speed]. Arms are thrown back along the shove (they lag the
## trunk), the legs are thrown forward under it (they resist), and an off-axis hit adds yaw.
static func apply_blow(
	bodies: Dictionary,
	skeleton: Skeleton3D,
	direction: Vector3,
	hit_point: Vector3,
	speed: float
) -> void:
	if direction.is_zero_approx() or speed <= 0.0:
		return

	var shove: Vector3 = direction.normalized()
	# The limbs lag the trunk: the shoulders are thrown the same way the trunk was shoved.
	_throw(bodies, skeleton, &"mixamorig_LeftShoulder", shove, 1.0, speed, SHOULDER_MASS_SHARE)
	_throw(bodies, skeleton, &"mixamorig_RightShoulder", shove, 1.0, speed, SHOULDER_MASS_SHARE)
	_throw(bodies, skeleton, &"mixamorig_LeftArm", shove, 1.0, speed, ARM_MASS_SHARE)
	_throw(bodies, skeleton, &"mixamorig_RightArm", shove, 1.0, speed, ARM_MASS_SHARE)
	# Legs trail: the hips are driven the other way so the feet stay behind the chest.
	_throw(bodies, skeleton, &"mixamorig_LeftUpLeg", shove, -1.0, speed, LEG_MASS_SHARE)
	_throw(bodies, skeleton, &"mixamorig_RightUpLeg", shove, -1.0, speed, LEG_MASS_SHARE)
	_throw(bodies, skeleton, &"mixamorig_LeftLeg", shove, -1.0, speed, LEG_MASS_SHARE)
	_throw(bodies, skeleton, &"mixamorig_RightLeg", shove, -1.0, speed, LEG_MASS_SHARE)
	_twist(bodies, shove, hit_point, speed)


## Applies a radial blast to every body within [param radius] of [param origin]. Each body gets
## an outward impulse that falls off with distance, a tangential component so the body does not
## expand like a starfish, and a spin. Called once per frame while the blast lasts.
static func apply_blast(
	bodies: Dictionary, origin: Vector3, radius: float, speed: float
) -> void:
	if radius <= 0.0 or speed <= 0.0:
		return

	for key: Variant in bodies:
		var bone: PhysicalBone3D = bodies[key] as PhysicalBone3D
		if bone == null:
			continue
		var offset: Vector3 = bone.global_position - origin
		var distance: float = offset.length()
		if distance > radius or distance < BLAST_MIN_DISTANCE:
			continue
		var falloff: float = 1.0 - distance / radius
		var push: Vector3 = offset / distance
		var tangent: Vector3 = push.cross(Vector3.UP)
		if tangent.is_zero_approx():
			tangent = push.cross(Vector3.RIGHT)
		var impulse: Vector3 = (
			(push + tangent.normalized() * BLAST_TANGENT)
			* speed
			* falloff
			* bone.mass
			* BLAST_MASS_SHARE
		)
		bone.apply_impulse(impulse, Vector3.ZERO)
		add_spin(bone, tangent * speed * falloff * BLAST_SPIN_SHARE)


## Adds [param spin] to a body's angular velocity, leaving what it already had alone and
## capping the result. This is the only way a one-shot rotation survives the angular damp.
static func add_spin(bone: PhysicalBone3D, spin: Vector3) -> void:
	if spin.is_zero_approx():
		return

	var velocity: Vector3 = bone.angular_velocity + spin
	if velocity.length() > MAX_SECONDARY_SPIN:
		velocity = velocity.limit_length(MAX_SECONDARY_SPIN)
	PhysicsServer3D.body_set_state(
		bone.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, velocity
	)


static func _throw(
	bodies: Dictionary,
	skeleton: Skeleton3D,
	bone_name: StringName,
	direction: Vector3,
	sign: float,
	speed: float,
	mass_share: float
) -> void:
	var bone: PhysicalBone3D = bodies.get(bone_name) as PhysicalBone3D
	if bone == null:
		return

	var lever: Vector3 = _limb_lever(skeleton, bone)
	var impulse: Vector3 = (
		direction * sign * minf(speed, MAX_SECONDARY_SPEED) * bone.mass * mass_share
	)
	bone.apply_impulse(impulse, lever * LEVER_SHARE)
	_limit_spin(bone)


## The trunk twists about its own up axis when the blow landed to one side of it, so a hit on
## the shoulder turns the body instead of only shoving it.
static func _twist(
	bodies: Dictionary, direction: Vector3, hit_point: Vector3, speed: float
) -> void:
	var torso: PhysicalBone3D = bodies.get(&"mixamorig_Spine2") as PhysicalBone3D
	var hips: PhysicalBone3D = bodies.get(&"mixamorig_Hips") as PhysicalBone3D
	if torso == null or hips == null:
		return

	var lateral: Vector3 = hit_point - torso.global_position
	lateral.y = 0.0
	var side: Vector3 = direction.cross(Vector3.UP)
	if lateral.is_zero_approx() or side.is_zero_approx():
		return

	var spin: float = (
		signf(lateral.dot(side)) * minf(speed * YAW_SHARE, MAX_YAW_SPEED) * -1.0
	)
	add_spin(hips, Vector3.UP * spin)
	# A little counter-twist in the chest keeps the shoulders and the pelvis from turning as
	# one rigid block.
	add_spin(torso, Vector3.UP * -spin * 0.35)


## A point along the segment a body's shape is built on, so a blow lands off its pivot.
static func _get_hit_point_on(
	bodies: Dictionary, skeleton: Skeleton3D, bone_index: int
) -> Vector3:
	var bone: PhysicalBone3D = bodies.get(bone_index) as PhysicalBone3D
	if bone == null:
		return Vector3.ZERO

	var head: Vector3 = bone.global_position
	var child_index: int = _segment_child(skeleton, bone_index)
	var child: PhysicalBone3D = bodies.get(child_index) as PhysicalBone3D
	if child == null:
		return head

	return head.lerp(child.global_position, randf_range(0.25, 0.75))


## How far down the bone the impulse should land. Taken from the child bone's world position so
## the swing follows the limb's real direction rather than the capsule's axis.
static func _limb_lever(skeleton: Skeleton3D, bone: PhysicalBone3D) -> Vector3:
	var index: int = bone.get_bone_id()
	if skeleton != null and index >= 0:
		for child_index: int in skeleton.get_bone_children(index):
			var child_position: Vector3 = (
				skeleton.global_transform * skeleton.get_bone_global_pose(child_index).origin
			)
			var offset: Vector3 = child_position - bone.global_position
			if offset.length() > 0.02:
				return offset
	return bone.global_transform.basis.y * 0.15


static func _segment_child(skeleton: Skeleton3D, bone_index: int) -> int:
	if skeleton == null:
		return -1
	var children: PackedInt32Array = skeleton.get_bone_children(bone_index)
	return children[0] if not children.is_empty() else -1


static func _limit_spin(bone: PhysicalBone3D) -> void:
	var velocity: Vector3 = bone.angular_velocity
	if velocity.length() > MAX_SECONDARY_SPIN:
		PhysicsServer3D.body_set_state(
			bone.get_rid(),
			PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY,
			velocity.limit_length(MAX_SECONDARY_SPIN)
		)



