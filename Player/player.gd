extends CharacterBody3D

const STAIR_STEP_HEIGHT := 0.6
const STAIR_SNAP_LENGTH := 0.65
const STAIR_PROBE_DEPTH := STAIR_STEP_HEIGHT + 0.05
const STAIR_PROBE_DISTANCE := 0.25
const STEP_GROUNDED_HOLD := 0.06
const SLOPE_PROBE_CLEARANCE := 0.1
const STEP_VISUAL_SMOOTHING := 20.0
const STEP_VISUAL_SNAP_DISTANCE := 1.5
const STAND_PROBE_CLEARANCE := 0.02
const STAND_PROBE_RADIUS_INSET := 0.01
const CLIMB_PROBE_HEIGHT := 0.8
const CLIMB_PROBE_REACH := 0.9
const CLIMB_PROBE_WIDTH_SCALE := 1.25
const CLIMB_PROBE_LANES: Array[float] = [0.0, -1.0, 1.0]
const CLIMB_PROBE_HEIGHT_SCALES: Array[float] = [1.0, 0.5, 0.25]
const CLIMB_SURFACE_PROBE := 0.35
const CLIMB_EDGE_MARGIN := 0.05
const CLIMB_REACH_TOLERANCE := 0.01
const CLIMB_STYLE_LOW: StringName = AnimationController.CLIMB_STYLE_LOW
const CLIMB_STYLE_HIGH: StringName = AnimationController.CLIMB_STYLE_HIGH

## How far (in metres) the push probe reaches past this frame's motion. Starting
## the shove a little before the capsule touches keeps a walking body from being
## stopped dead by the thing it is meant to be pushing.
const PUSH_PROBE_MARGIN := 0.08

## Action that drops the body into a ragdoll, and puts it back on its feet when
## pressed again. There is no health yet, so this is the test hook for the death
## pose.
const DEATH_ACTION: StringName = &"death"

## Bones the revive reads the fallen body's position from, in order of
## preference. The imported skeleton names them with the Mixamo prefix.
const HIP_BONE_NAMES: Array[StringName] = [&"mixamorig_Hips", &"Hips"]

const PLAYER_MOVEMENT_STATS = preload("res://Player/player_movement_stats.tres")

## Capsule height (in metres) used while crouched. The capsule is centred on the
## feet (origin at the bottom), so this also drives the shape's Y offset.
@export var crouch_capsule_height: float = 1.1

## Capsule height (in metres) used while rolling. A roll tucks the body up in the
## air, so it needs a little more room than a crouch but nowhere near standing
## height. Rolling out of a crouch keeps the crouch capsule, so this only applies
## to rolls that start standing.
@export var roll_capsule_height: float = 1.4

## Height (in metres above the feet) of the lowest ledge the player can climb
## onto. Anything shorter is handled by the stair step-up instead.
@export var climb_min_height: float = 0.9

## Height (in metres above the feet) of the lowest ledge that can be grabbed
## while airborne. Jumping brings the feet up level with ledges that are too low
## to climb from the ground, and a ledge at chest height is still something to
## haul up onto, so the grounded minimum does not apply in the air.
@export var climb_air_min_height: float = 0.2

## Height (in metres above the feet) of the tallest ledge the regular climb
## covers, roughly head height. Ledges above this need the overhead climb.
@export var climb_max_height: float = 1.6

## Height (in metres above the feet) of the tallest ledge the player can haul
## themselves onto with the overhead climb: as high as their hands reach above
## their head. Anything taller is a wall.
@export var climb_high_max_height: float = 2

## Extra height (in metres) added to the body during the overhead climb. The
## braced hang pose grabs the ledge well above the hips, so the body has to be
## moved relative to the ledge for the hands to sit on it at all; the offset
## fades out over the climb, leaving the player flush on the surface. Negative
## values sink the body.
@export var climb_high_vertical_offset: float = 0.0

## How fast the body follows the climb clip's own height curve. 1.0 rises at the
## pace the clip was drawn at; higher values hold the body back so it rises later
## and more gently through the middle, lower values push it up sooner. Both ends
## are fixed, so only the middle of the rise moves and the player still lands
## exactly on the ledge.
@export_range(0.25, 4.0, 0.05) var climb_rise_speed: float = 1.0

## Seconds the overhead climb holds the body at its starting height before it
## starts following the clip's rise. The braced hang clip opens by pulling the
## body out of the hang, so a body that follows the height curve from the first
## frame shoots up the wall while the hands are still meant to be hanging off the
## ledge. The rest of the rise is remapped onto the time that is left, so the
## player still lands exactly on the ledge when the clip ends.
@export_range(0.0, 1.0, 0.05) var climb_high_rise_delay: float = 0.1

## Steepest slope (in degrees above horizontal) that still counts as ground.
## Up to this angle the slope is a floor, so the player walks up it and the
## movement is projected along the surface, which costs speed the steeper it
## gets. Anything steeper cannot be held and the player slides back down it.
@export_range(20.0, 80.0, 0.5) var slope_max_climb_angle: float = 45.0

## Downward acceleration (in m/s^2) gravity gives the player along a slope too
## steep to stand on. Its share grows with the angle, so compared with the
## player's own movement acceleration it decides whether a climb survives: a
## steep enough face always wins and turns the climb into a slide back down.
@export var slope_slide_acceleration: float = 9.8

## Effective mass (kg) the player brings to a shove. It is what turns the player's
## speed into momentum: a sprint at 5.8 m/s carries far more of it than a walk at
## 4.5 m/s, and a roll at 8 m/s more again, so sharing that momentum with the body
## is what makes a sprint or a slide knock it further than a walking shove.
@export_range(20.0, 200.0, 1.0) var push_mass: float = 70.0

## Restitution of the shove. 0 hands over momentum like a perfectly inelastic
## hit, so the body ends up no faster than the speed the two of them share.
## Higher values add a little pop on top, which is what makes an impact read as
## a hit rather than as leaning on something.
@export_range(0.0, 1.0, 0.05) var push_bounciness: float = 0.15

## Ceiling (m/s) on how fast one shove can set a body moving. A light prop hit
## at full roll speed would otherwise be launched across the level, because the
## less the body masses the more of the player's momentum it can take.
@export var max_push_speed: float = 10.0

## How quickly (in 1/s) a contacted rigid body is brought up to the speed the
## shove allows. High values feel rigid and snappy, low values feel like heavy
## shoving, so the same setting reads very differently for a light prop and a
## heavy crate.
@export_range(1.0, 40.0, 0.5) var rigid_body_push_response: float = 12.0

## Set while a state moves the body along a scripted path, such as a climb. The
## step smoothing only exists to soften walking up stairs; against a scripted
## rise it just adds a lag the pose was never drawn for.
var visual_height_scripted: bool = false

var smoothed_visual_height: float = 0.0

var _visual_height_was_scripted: bool = false

var _capsule: CapsuleShape3D
var _standing_capsule_height: float
var _mantle_style: StringName = &""
var _foot_ik: FootIk
var _step_grounded_time: float = 0.0
var _is_dead: bool = false
var _ragdoll: PlayerRagdoll
var _suspended_modifiers: Array[SkeletonModifier3D] = []
## Influence each IK chain had when the body went limp, so it can be handed back.
var _suspended_ik: Dictionary[SkeletonIK3D, float] = {}
## How fast the model is turning, in radians per second. Measured every physics frame
## so the ragdoll can inherit the turn the body died in the middle of.
var _yaw_rate: float = 0.0
var _last_yaw: float = 0.0
var _yaw_tracked: bool = false

@onready var slope_ray_cast: RayCast3D = $SlopeRayCast
@onready var character_model: AnimationController = $CharacterModel
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var state_machine: StateMachine = get_node_or_null("StateMachine") as StateMachine


func _ready() -> void:
	floor_snap_length = STAIR_SNAP_LENGTH
	slope_ray_cast.position.y = STAIR_STEP_HEIGHT + SLOPE_PROBE_CLEARANCE

	# The climb limit and the floor limit are the same thing: a slope is either
	# ground the player can stand and walk up, or a face they slide back down.
	# Other slope checks in this script read floor_max_angle too, so raising it
	# here keeps step-up and ledge detection using the same threshold.
	floor_max_angle = deg_to_rad(slope_max_climb_angle)
	smoothed_visual_height = global_position.y

	# The stamina pool is static, so it outlives the body that spent it. A fresh
	# player starts with a full bar instead of inheriting the last one's.
	Stamina.reset()

	# Duplicate the capsule so the resize is local to this body instead of
	# mutating the shared shape resource from the scene file.
	_capsule = collision_shape.shape.duplicate() as CapsuleShape3D
	collision_shape.shape = _capsule
	_standing_capsule_height = _capsule.height

	character_model.collision_posture_changed.connect(_on_character_collision_posture_changed)
	_foot_ik = character_model.get_node_or_null("FootIk") as FootIk
	_setup_ragdoll()


func _input(event: InputEvent) -> void:
	# Testing hook: the first press drops the body, the next stands it back up.
	if not event.is_action_pressed(DEATH_ACTION):
		return

	if _is_dead:
		_revive()
	else:
		_die()


func _on_character_collision_posture_changed(posture: AnimationController.CollisionPosture) -> void:
	var height: float = _get_posture_capsule_height(posture)
	_capsule.height = height
	collision_shape.position.y = height * 0.5


## Capsule height for a collision posture. The capsule is centred on the feet
## (origin at the bottom), so the Y offset follows from the height.
func _get_posture_capsule_height(posture: AnimationController.CollisionPosture) -> float:
	match posture:
		AnimationController.CollisionPosture.ROLL:
			return roll_capsule_height
		AnimationController.CollisionPosture.SHORT:
			return crouch_capsule_height
		_:
			return _standing_capsule_height


## Whether the player has room to stand up where they are. True when nothing
## overlaps the full height capsule, so a crouch cannot be left under a ceiling.
func can_stand_up() -> bool:
	if _capsule == null:
		return true

	# The capsule only grows upwards (same radius, bottom pinned to the feet), so
	# the standing pose is probed in place rather than swept along a motion.
	return _is_clear_at(global_position)


## World position the player would stand at after climbing onto the ledge in
## front of them, or Vector3.INF when there is nothing climbable in reach.
## Climbable means a walkable surface between the waist and the highest reach,
## deep enough to stand on and clear of anything overhanging it. Also records
## which climb tier the ledge needs, see get_mantle_style().
func find_mantle_target() -> Vector3:
	_mantle_style = &""

	if not _can_climb():
		return Vector3.INF

	var forward := _get_facing_direction()
	var ledge_top := _find_climbable_ledge_top(forward)
	if not ledge_top.is_finite():
		return Vector3.INF

	# Stand clear of the edge, then make sure the body actually fits up there.
	var target := ledge_top + forward * (_capsule.radius + CLIMB_EDGE_MARGIN)
	target.y = ledge_top.y
	if not _is_clear_at(target):
		return Vector3.INF

	_mantle_style = _get_climb_style(ledge_top.y - global_position.y)
	return target


## Tier of the ledge the last find_mantle_target() call found, or an empty
## StringName when there was nothing to climb.
func get_mantle_style() -> StringName:
	return _mantle_style


func _get_climb_style(rise: float) -> StringName:
	return CLIMB_STYLE_LOW if rise <= climb_max_height else CLIMB_STYLE_HIGH


func _can_climb() -> bool:
	if _capsule == null:
		return false

	# Climbing is a standing move: the crouched capsule is shorter than every
	# climbable ledge and the clip is a full body climb. Being airborne is fine;
	# the mantle is also what turns a jump at a wall into a grab.
	return is_equal_approx(_capsule.height, _standing_capsule_height)


## Lowest ledge above the feet that counts as climbable right now. On the
## ground shorter ledges are just steps, but an airborne player is usually
## already part way up the obstacle.
func _get_min_climb_height() -> float:
	return climb_min_height if is_grounded_for_movement() else climb_air_min_height


func _find_climbable_ledge_top(forward: Vector3) -> Vector3:
	if forward.is_zero_approx():
		return Vector3.INF

	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var reach_height: float = maxf(climb_high_max_height, climb_max_height)
	var nearest := Vector3.INF
	var nearest_distance := INF

	# The search is a patch rather than a single ray: lanes across the player's
	# width at a few heights, so an edge has to be roughly ahead of the player
	# instead of exactly on one thin line down the middle of the body.
	for from: Vector3 in _get_climb_probe_origins(forward):
		var to: Vector3 = from + forward * CLIMB_PROBE_REACH
		var wall_hit := space.intersect_ray(_create_ray(from, to))
		if wall_hit.is_empty():
			continue

		var ledge_top := _get_climbable_top_behind(wall_hit, forward, reach_height)
		if not ledge_top.is_finite():
			continue

		# Nearest climbable ledge wins, so a low step in front of a taller wall
		# is skipped rather than hiding the wall standing behind it.
		var distance: float = (ledge_top - global_position).dot(forward)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = ledge_top

	return nearest


## Top of the object whose face the given ray hit, or Vector3.INF when that top
## is not something the player can climb onto from where they are.
func _get_climbable_top_behind(
	wall_hit: Dictionary, forward: Vector3, reach_height: float
) -> Vector3:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var min_height := _get_min_climb_height()
	var wall_point: Vector3 = wall_hit.get("position", Vector3.INF)
	var over_edge := wall_point + forward * CLIMB_EDGE_MARGIN

	# Drop onto the top of that obstacle, starting above the tallest reachable
	# ledge so a wall reads as nothing at all rather than as its own top face.
	var drop_from := Vector3(
		over_edge.x, global_position.y + reach_height + CLIMB_SURFACE_PROBE, over_edge.z
	)
	var drop_to := Vector3(over_edge.x, global_position.y + min_height * 0.5, over_edge.z)
	var ledge_hit := space.intersect_ray(_create_ray(drop_from, drop_to))
	if ledge_hit.is_empty():
		return Vector3.INF

	var ledge_normal: Vector3 = ledge_hit.get("normal", Vector3.DOWN)
	if not _is_walkable_normal(ledge_normal):
		return Vector3.INF

	var ledge_top: Vector3 = ledge_hit.get("position", Vector3.INF)
	var rise := ledge_top.y - global_position.y
	# The tolerance keeps a ledge sitting exactly on the reach limit climbable
	# instead of losing it to float error in the ray hit.
	if rise < min_height or rise > reach_height + CLIMB_REACH_TOLERANCE:
		return Vector3.INF

	return ledge_top


## Origins of the forward probe: the centre line first so a dead-ahead hit wins
## ties, then one lane either side at the width of the body, each sampled at a
## few heights so a short obstacle is not missed by a ray passing over it.
func _get_climb_probe_origins(forward: Vector3) -> Array[Vector3]:
	var right: Vector3 = up_direction.cross(forward).normalized()
	var half_width: float = _capsule.radius * CLIMB_PROBE_WIDTH_SCALE
	var origins: Array[Vector3] = []

	for lane: float in CLIMB_PROBE_LANES:
		var base: Vector3 = global_position + right * (lane * half_width)
		for height_scale: float in CLIMB_PROBE_HEIGHT_SCALES:
			origins.append(base + up_direction * (CLIMB_PROBE_HEIGHT * height_scale))

	return origins


func _is_clear_at(feet_position: Vector3) -> bool:
	# The probe is inset slightly: the capsule always rests on the floor, and a
	# flush floor contact would otherwise read as a blocked pose.
	var probe_height: float = _standing_capsule_height - STAND_PROBE_CLEARANCE * 2.0
	var probe := CapsuleShape3D.new()
	probe.radius = maxf(_capsule.radius - STAND_PROBE_RADIUS_INSET, 0.01)
	probe.height = probe_height

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.transform = Transform3D(
		global_transform.basis,
		feet_position + up_direction * (STAND_PROBE_CLEARANCE + probe_height * 0.5)
	)

	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	return space.intersect_shape(query, 1).is_empty()


func _create_ray(from: Vector3, to: Vector3) -> PhysicsRayQueryParameters3D:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collision_mask = collision_mask
	return query


## Direction the player is facing on the ground plane: where they are running,
## falling back to the direction they last moved in, then to the model itself.
func _get_facing_direction() -> Vector3:
	var movement := Vector3(velocity.x, 0.0, velocity.z)
	if movement.length() > 0.5:
		return movement.normalized()

	var input_direction := Vector3(character_model.input_dir.x, 0.0, character_model.input_dir.y)
	if input_direction.length() > 0.01:
		return input_direction.normalized()

	var model_forward: Vector3 = character_model.armature.global_transform.basis.z
	model_forward.y = 0.0
	return model_forward.normalized()


func set_velocity_from_motion(vel: Vector3) -> void:
	velocity = vel


## Shoves the rigid bodies the body walks into. The player is a kinematic body, so
## move_and_slide() stops dead against a rigid body instead of pushing it; the
## contacts it leaves behind are what get used here to hand the player's motion
## over to the body as an impulse. Turn this into a force-driven character only
## as a last resort: a RigidBody3D player would lose the step-up, slide and
## slope handling that the whole movement script is built on.
##
## The force comes from the player's momentum (push_mass * speed) rather than
## from their speed alone, so a sprint or a roll into a body carries a third to
## two thirds more momentum than a walk does and sends it further, while a heavy
## body takes the same hit and barely moves.
##
## `motion` is the velocity the body had going into the move, because
## move_and_slide() clips velocity down to whatever the collision allowed and a
## head-on shove would otherwise read as the body standing still.
func _push_rigid_bodies(motion: Vector3, delta: float) -> void:
	if _is_dead or push_mass <= 0.0:
		return

	var movement := Vector3(motion.x, 0.0, motion.z)
	if movement.is_zero_approx():
		return

	var push_direction := movement.normalized()
	var momentum: float = push_mass * movement.length()

	for body in _get_push_targets(movement, delta):
		# Momentum is shared with the body: the faster the player is travelling
		# the more there is to share, and the heavier the body the less of the
		# shared speed it ends up with.
		var target_speed: float = momentum / (push_mass + body.mass)
		target_speed *= 1.0 + push_bounciness
		target_speed = minf(target_speed, max_push_speed)

		var current_speed := body.linear_velocity.dot(push_direction)
		if current_speed >= target_speed:
			continue

		# Ramp the body up to the shove's speed over a few ticks rather than in
		# one hit, so sustained contact reads as pushing and the same code still
		# gives a slide its single, harder knock.
		var impulse := body.mass * (target_speed - current_speed)
		impulse *= minf(rigid_body_push_response * delta, 1.0)
		# Applied centrally. An off-centre impulse tips the body over its leading
		# edge, where it digs into the floor, grinds against the player's capsule
		# and leaves the two of them jammed together.
		body.apply_central_impulse(push_direction * impulse)


## Rigid bodies the player is currently shoving. Two sources, because neither is
## reliable on its own: the slide contacts are the bodies the capsule really is
## pressed against, and the sweep finds the one it is about to reach. Sweeping
## means the shove starts before the capsule has been stopped dead, which is what
## stops the player and the body from locking together for a few frames.
func _get_push_targets(movement: Vector3, delta: float) -> Array[RigidBody3D]:
	var targets: Array[RigidBody3D] = []
	var seen := {}

	for i in get_slide_collision_count():
		_add_push_target(targets, seen, get_slide_collision(i), movement)

	var sweep := KinematicCollision3D.new()
	var probe := movement * delta + movement.normalized() * PUSH_PROBE_MARGIN
	if test_move(global_transform, probe, sweep):
		_add_push_target(targets, seen, sweep, movement)

	return targets


func _add_push_target(
	targets: Array[RigidBody3D],
	seen: Dictionary,
	collision: KinematicCollision3D,
	movement: Vector3
) -> void:
	var body := collision.get_collider() as RigidBody3D
	if body == null or body.freeze:
		return

	var key := body.get_instance_id()
	if seen.has(key):
		return

	# Only shove against something the player is walking into sideways. The
	# normal of a floor, or of the top of a crate the player is standing on,
	# would otherwise hand a standing body's horizontal motion to whatever it
	# happens to be resting on.
	var normal := collision.get_normal()
	if absf(normal.y) > 0.7 or movement.dot(-normal) <= 0.0:
		return

	seen[key] = true
	targets.append(body)


func _physics_process(delta: float) -> void:
	_step_grounded_time = maxf(_step_grounded_time - delta, 0.0)
	# The foot IK only forgives an empty support reading while a step-up is lifting
	# the body, which is the one moment the feet are expected to be off the ground
	# without the body being in the air.
	if _foot_ik != null:
		_foot_ik.support_grace_hold = _step_grounded_time > 0.0
	_update_floor_snap()
	_absorb_landing()
	# What the slope does to the player's own movement has to be measured before
	# the states run their update, because they read it from Motion.
	_apply_slope_effects()
	_try_step_up(delta)
	_apply_slope_slide(delta)
	# move_and_slide() clips velocity down to what the collision allowed, so the
	# shove below needs the motion from before the move to know how hard the
	# player was walking into the body.
	var intended_motion := Vector3(velocity.x, 0.0, velocity.z)
	# The shove runs before the move. A body that is only pushed once the capsule
	# has already been stopped dead is one the player is jammed against, and both
	# of them can stay locked that way; starting the shove first lets the body
	# move out of the way in the same step.
	_push_rigid_bodies(intended_motion, delta)
	move_and_slide()
	_update_visual_height(delta)
	_track_yaw_rate(delta)


## Rate the model is turning at, so a body that dies mid turn can hand that rotation
## to its ragdoll. Read off the armature rather than the input, because the camera
## turns the body too.
func _track_yaw_rate(delta: float) -> void:
	var forward: Vector3 = character_model.armature.global_transform.basis.z
	var yaw: float = atan2(forward.x, forward.z)
	if _yaw_tracked and delta > 0.0001:
		_yaw_rate = wrapf(yaw - _last_yaw, -PI, PI) / delta
	_last_yaw = yaw
	_yaw_tracked = true


## Floor snapping is what keeps the capsule glued to a ledge lip after the feet
## have already left the surface, which is what leaves a body hanging over the
## drop. The snap is off while the feet have nothing under them, so the body is
## free to fall off the edge instead of being held on the corner.
func _update_floor_snap() -> void:
	floor_snap_length = STAIR_SNAP_LENGTH if has_ground_under_feet() else 0.0


func is_grounded_for_movement() -> bool:
	# The capsule comes to rest on the lip of a ledge with most of the body out
	# over the drop, and the stair snap reaches 0.65 m down, so both is_on_floor()
	# and the floor probe below can report ground while the feet have nothing under
	# them. Standing on nothing is not standing: the grounded states apply no
	# gravity, so taking their word for it is what leaves the player hanging in the
	# air off the edge of a platform.
	if not has_ground_under_feet():
		return false
	# A step-up lifts the body onto the step before the floor below it has been
	# left behind, so the step itself must not read as becoming airborne. The
	# hold is short: it only has to outlast the frames the lift takes.
	if _step_grounded_time > 0.0:
		return true
	if is_on_floor():
		return true
	if velocity.y > 0.0:
		return false
	return _has_walkable_floor_below(global_transform, STAIR_SNAP_LENGTH)


## Whether the feet have ground under them, as found by the foot IK's own probes.
## The probes reach a short way below the feet only, so a body resting on a ledge
## with the drop underneath reads as airborne, which is what gets it falling.
func has_ground_under_feet() -> bool:
	if _foot_ik == null:
		return true
	return _foot_ik.has_ground_under_feet()


func _try_step_up(delta: float) -> void:
	if velocity.y > 0.0 or not is_grounded_for_movement():
		return

	var horizontal_motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	if horizontal_motion.is_zero_approx():
		return

	var step_position := _get_step_position(horizontal_motion)
	if step_position.is_finite():
		global_position = step_position
		_step_grounded_time = STEP_GROUNDED_HOLD
		# The step move already applied this frame's horizontal motion.
		velocity.x = 0.0
		velocity.z = 0.0


func _update_visual_height(delta: float) -> void:
	var target_height := global_position.y
	if (
		visual_height_scripted
		or _visual_height_was_scripted
		or absf(smoothed_visual_height - target_height) > STEP_VISUAL_SNAP_DISTANCE
	):
		smoothed_visual_height = target_height
	else:
		var weight := 1.0 - exp(-STEP_VISUAL_SMOOTHING * delta)
		smoothed_visual_height = lerpf(smoothed_visual_height, target_height, weight)

	_visual_height_was_scripted = visual_height_scripted
	character_model.position.y = smoothed_visual_height - target_height


func _get_step_position(horizontal_motion: Vector3) -> Vector3:
	if (
		not test_move(global_transform, horizontal_motion)
		or _is_blocked_by_steep_slope()
		or test_move(global_transform, up_direction * STAIR_STEP_HEIGHT)
	):
		return Vector3.INF

	# The floor is sampled at least a fixed distance ahead. Sampling only this
	# frame's motion makes climbing speed dependent: at walking speed the down cast
	# lands on the stair's front edge, whose normal is too steep to count as
	# walkable, so slow movement gets stuck while running climbs fine.
	var probe_distance := maxf(horizontal_motion.length(), STAIR_PROBE_DISTANCE)
	var probe_motion := horizontal_motion.normalized() * probe_distance
	var raised_transform := global_transform.translated(up_direction * STAIR_STEP_HEIGHT)
	if test_move(raised_transform, horizontal_motion):
		return Vector3.INF

	var forward_transform := raised_transform.translated(probe_motion)
	var floor_collision := KinematicCollision3D.new()
	if (
		not test_move(forward_transform, -up_direction * STAIR_PROBE_DEPTH, floor_collision)
		or not _is_walkable_normal(floor_collision.get_normal())
	):
		return Vector3.INF

	var drop_distance := floor_collision.get_travel().length()
	var step_rise := STAIR_STEP_HEIGHT - drop_distance
	if step_rise <= 0.01 or step_rise > STAIR_STEP_HEIGHT:
		return Vector3.INF

	# The probe distance only samples the step surface; the body still advances by
	# the motion it actually requested this frame.
	return global_position + up_direction * step_rise + horizontal_motion


## A landing has to drop the fall the body arrived with. Ground states apply no
## gravity and never write the vertical part of Motion.velocity, so without this
## the fall is still sitting there after touchdown; the states re-apply that
## static to the body every frame, which throws away the clip move_and_slide()
## puts on the landing. move_and_slide() then slides the leftover downward
## velocity along whatever face the player is standing on, so on a slope the
## player is shoved downhill at a speed no state can see or brake, and the harder
## they had fallen the harder the shove, which is what made every attempt at a
## climb come out worse than the last.
func _absorb_landing() -> void:
	if not is_on_floor() or velocity.y >= 0.0:
		return

	velocity.y = 0.0
	Motion.velocity.y = 0.0


## The physics half of slope handling. Slopes inside slope_max_climb_angle are
## floors and never reach here; anything steeper is a wall, and the pull of
## gravity along that face is what turns an over-ambitious climb into a slide.
## Nothing is clamped, so the player's own movement keeps fighting the slide and
## the slope angle decides which one wins.
func _apply_slope_slide(delta: float) -> void:
	# A floor already supports the player, and without contact there is no face
	# to be pulled along.
	if is_on_floor() or not is_on_wall():
		return

	var slope_normal := get_wall_normal()
	var downhill := _get_slope_fall_direction(slope_normal)
	if downhill.is_zero_approx():
		return

	# Resolving gravity onto the face leaves sin(angle) of it: nothing on a flat
	# surface, all of it on a vertical wall.
	var along_slope := slope_slide_acceleration * sin(slope_normal.angle_to(up_direction))
	velocity += downhill * (along_slope * delta)


## What a slope does to the player's own movement: it costs speed, and a steep
## enough face refuses to be stood on.
##
## The speed half is a share of the state's own speed, so run, sprint, aim-walk
## and crouch-walk all lose the same amount on the same face and the air states
## are left at full speed. The slip half is the horizontal velocity a standing
## player is pulled down the face at, which calculate_velocity() aims at when
## there is no movement input. Both are published through Motion because the
## states run their own update after this one.
func _apply_slope_effects() -> void:
	if not is_grounded_for_movement():
		Motion.slope_speed_scale = 1.0
		Motion.slope_slip_velocity = Vector3.ZERO
		return

	var floor_normal := _get_ground_normal()
	var angle := rad_to_deg(floor_normal.angle_to(up_direction))
	Motion.slope_speed_scale = _get_slope_speed_scale(angle)
	Motion.slope_slip_velocity = _get_slope_slip_velocity(angle, floor_normal)


## Share of its own speed a movement state keeps on a face of this angle: 1 at
## `slope_slow_angle`, down to `slope_min_speed_fraction` at the steepest face
## that still counts as ground.
func _get_slope_speed_scale(angle: float) -> float:
	var mild_angle := PLAYER_MOVEMENT_STATS.slope_slow_angle
	if angle <= mild_angle:
		return 1.0

	# 0 at the free angle, 1 at the steepest angle that still counts as ground.
	var steepness := clampf(
		inverse_lerp(mild_angle, maxf(slope_max_climb_angle, mild_angle + 0.5), angle), 0.0, 1.0
	)
	var slowest := clampf(PLAYER_MOVEMENT_STATS.slope_min_speed_fraction, 0.0, 1.0)
	return lerpf(1.0, slowest, steepness)


## Horizontal velocity a standing player is slid down a face of this angle at:
## nothing below `slip_angle`, and `slip_speed` on the steepest face that can
## still be stood on, so a gentle slope is never a hazard.
func _get_slope_slip_velocity(angle: float, floor_normal: Vector3) -> Vector3:
	var slip_angle := PLAYER_MOVEMENT_STATS.slip_angle
	if angle <= slip_angle:
		return Vector3.ZERO

	var downhill := _get_slope_fall_direction(floor_normal)
	downhill.y = 0.0
	if downhill.is_zero_approx():
		return Vector3.ZERO

	# Nothing at the free angle, all of it at the steepest standable face.
	var grip := clampf(
		inverse_lerp(slip_angle, maxf(slope_max_climb_angle, slip_angle + 0.5), angle), 0.0, 1.0
	)
	return downhill.normalized() * (PLAYER_MOVEMENT_STATS.slip_speed * grip)


## Angle (in degrees above horizontal) of the ground under the feet, or 0 while
## the player is airborne.
func get_ground_slope_angle() -> float:
	if not is_grounded_for_movement():
		return 0.0

	return rad_to_deg(_get_ground_normal().angle_to(up_direction))


## Unit horizontal direction of the pull down the face under the feet, or
## Vector3.ZERO on level ground.
func get_slope_downhill_direction() -> Vector3:
	var downhill := _get_slope_fall_direction(_get_ground_normal())
	downhill.y = 0.0
	if downhill.is_zero_approx():
		return Vector3.ZERO

	return downhill.normalized()


## Surface normal of the ground under the feet. get_floor_normal() only has a
## value once move_and_slide() has reported a floor contact, and a body the stair
## snap is holding just off the surface is still standing on it as far as the
## movement states are concerned, so the slope checks read the surface with a
## probe of their own rather than going blind on a hovering frame.
func _get_ground_normal() -> Vector3:
	if is_on_floor():
		return get_floor_normal()

	var hit := _probe_ground(global_transform, STAIR_SNAP_LENGTH)
	if hit.is_empty():
		return up_direction
	return hit.get("normal", up_direction)


## Unit direction gravity pulls the player along a surface with the given normal.
func _get_slope_fall_direction(surface_normal: Vector3) -> Vector3:
	var gravity_direction := -up_direction
	var downhill := gravity_direction - surface_normal * gravity_direction.dot(surface_normal)
	if downhill.is_zero_approx():
		return Vector3.ZERO
	return downhill.normalized()


func _is_blocked_by_steep_slope() -> bool:
	return not _get_steep_slope_normal().is_zero_approx()


func _get_steep_slope_normal() -> Vector3:
	slope_ray_cast.force_raycast_update()
	if not slope_ray_cast.is_colliding():
		return Vector3.ZERO

	var normal := slope_ray_cast.get_collision_normal()
	if _is_walkable_normal(normal):
		return Vector3.ZERO
	return normal


func _has_walkable_floor_below(from_transform: Transform3D, distance: float) -> bool:
	var hit := _probe_ground(from_transform, distance)
	if hit.is_empty():
		return false
	var hit_normal: Vector3 = hit.get("normal", Vector3.DOWN)
	return _is_walkable_normal(hit_normal)


## Casts straight down from the feet into the ground they are standing on, far
## enough to find the surface a body hovering under the stair snap floats over.
func _probe_ground(from_transform: Transform3D, distance: float) -> Dictionary:
	var from := from_transform.origin + up_direction * 0.05
	var to := from - up_direction * distance
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collision_mask = collision_mask
	return get_world_3d().direct_space_state.intersect_ray(query)


func _is_walkable_normal(normal: Vector3) -> bool:
	return normal.dot(up_direction) >= cos(floor_max_angle)


## Builds the ragdoll rig on the model's skeleton. The bodies are generated from the
## skeleton's rest pose, so nothing has to be authored in the scene.
func _setup_ragdoll() -> void:
	var skeleton: Skeleton3D = _find_skeleton(character_model)
	if skeleton == null:
		return

	_ragdoll = PlayerRagdoll.new()
	_ragdoll.name = "Ragdoll"
	skeleton.add_child(_ragdoll)
	_ragdoll.setup(self)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D

	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found

	return null


## Drops the body: the capsule stops moving and colliding, everything that writes
## bone poses lets go of the skeleton, and the physics bodies take it over from the
## pose it collapsed in.
func _die() -> void:
	if _ragdoll == null:
		return

	_is_dead = true
	# Captured before the capsule is stopped: this is the momentum the bodies take
	# over, so a body that dies at a run keeps going instead of stopping dead.
	var launch_velocity: Vector3 = velocity
	var launch_spin: Vector3 = Vector3.UP * _yaw_rate
	velocity = Vector3.ZERO
	set_physics_process(false)
	collision_shape.disabled = true
	# The state machine drives the animation tree, so both are parked. Disabling
	# the machine's processing rather than its physics alone keeps the camera's
	# model view from switching it back on behind the death.
	if state_machine != null:
		state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	character_model.animation_tree.active = false
	_suspend_pose_modifiers()
	_ragdoll.start_simulation(launch_velocity, launch_spin)


## Stands the body back up where it fell: the ragdoll is stopped first, so the
## skeleton still holds the pose the bodies left it in.
func _revive() -> void:
	if _ragdoll == null:
		return

	var hips_position: Vector3 = _get_hips_position()
	_ragdoll.stop_simulation()
	_restore_pose_modifiers()
	character_model.animation_tree.active = true
	if state_machine != null:
		state_machine.process_mode = Node.PROCESS_MODE_INHERIT

	# Whatever posture the body died in, it comes back on its feet.
	character_model.set_crouched(false)
	_capsule.height = _standing_capsule_height
	collision_shape.position.y = _capsule.height * 0.5
	collision_shape.disabled = false
	global_position = hips_position
	smoothed_visual_height = global_position.y
	visual_height_scripted = false
	velocity = Vector3.ZERO
	_yaw_rate = 0.0
	_is_dead = false
	set_physics_process(true)


## IK chains and the crouch modifier all write bone poses every frame, which would
## fight the bodies for the skeleton. They are switched off for as long as the body
## is limp, and this remembers which ones to switch back on. The foot chains are
## SkeletonIK3D rather than SkeletonModifier3D, so they are muted by influence
## instead of disabled, and the node that aims them stops probing the ground.
func _suspend_pose_modifiers() -> void:
	if _ragdoll == null:
		return

	var skeleton: Node = _ragdoll.get_parent()
	if skeleton == null:
		return

	if _foot_ik != null:
		_foot_ik.set_process(false)

	for child: Node in skeleton.get_children():
		if child == _ragdoll:
			continue

		var modifier: SkeletonModifier3D = child as SkeletonModifier3D
		if modifier != null:
			modifier.active = false
			_suspended_modifiers.append(modifier)

		# SkeletonIK3D is a modifier as well, but its influence is the documented
		# weight of the pose it hands over, so it is muted on top of being disabled.
		var ik: SkeletonIK3D = child as SkeletonIK3D
		if ik != null:
			_suspended_ik[ik] = ik.influence
			ik.influence = 0.0


func _restore_pose_modifiers() -> void:
	for modifier: SkeletonModifier3D in _suspended_modifiers:
		# A modifier can be freed while the body is limp, when the weapon it hangs
		# an IK chain off is dropped or swapped.
		if is_instance_valid(modifier):
			modifier.active = true

	_suspended_modifiers.clear()

	for ik: SkeletonIK3D in _suspended_ik:
		if is_instance_valid(ik):
			ik.influence = _suspended_ik[ik]

	_suspended_ik.clear()

	if _foot_ik != null:
		_foot_ik.set_process(true)


## World position of the pelvis, which is where the body stands up from. The
## ragdoll copies the bodies onto the skeleton, so while the body is limp this
## reads the pose the ragdoll came to rest in.
func _get_hips_position() -> Vector3:
	var skeleton: Skeleton3D = null
	if _ragdoll != null:
		skeleton = _ragdoll.get_parent() as Skeleton3D
	if skeleton == null:
		return global_position

	for bone_name: StringName in HIP_BONE_NAMES:
		var bone_index: int = skeleton.find_bone(String(bone_name))
		if bone_index >= 0:
			return skeleton.global_transform * skeleton.get_bone_global_pose(bone_index).origin

	return global_position
