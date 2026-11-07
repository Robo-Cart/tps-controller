class_name Motion
extends State

signal velocity_updated(vel: Vector3)
@warning_ignore("unused_signal")
signal direction_updated(dir: Vector2)
@warning_ignore("unused_signal")
signal animation_change_requested(animation: String)

const PLAYER_MOVEMENT_STATS = preload("res://Player/player_movement_stats.tres")

## How far the movement stick can be pushed before the input counts as an
## intention to move rather than as standing still. Below it a slip takes over.
const SLIP_INPUT_DEADZONE: float = 0.05

## Steepest face assumed to be standable when the owner does not say. Only used
## when a Movement state is run without a Player above it.
const DEFAULT_MAX_SLOPE_ANGLE: float = 45.0

static var input_dir: Vector2 = Vector2.ZERO
static var direction: Vector3 = Vector3.ZERO
static var velocity: Vector3 = Vector3.ZERO
static var sprint_toggled: bool = false
static var jump_horizontal_speed: float = 0.0
static var crouched: bool = false
## Share of its own speed a movement state is allowed to use this frame. The
## owner sets it from the angle of the ground underfoot, so every ground state
## slows on a slope through the same value; it stays at 1 while airborne.
static var slope_speed_scale: float = 1.0
## Horizontal velocity the owner is being slid downhill at because it is standing
## still on a face too steep to hold it. calculate_velocity() aims at this instead
## of at a standstill while there is no movement input, so no state has to know
## that slopes slip. Zero when the ground is gentle or the player is airborne.
static var slope_slip_velocity: Vector3 = Vector3.ZERO
## Heading a slide should travel in, overriding whatever momentum the player
## arrived with. A crouch that tips into a slide on its own is standing still, so
## there is no momentum to slide on: the slope picks the way instead. Read and
## cleared by the slide when it starts.
static var slide_direction_override: Vector3 = Vector3.ZERO
## World position the climb state is moving the body onto. Set by try_climb().
static var mantle_target: Vector3 = Vector3.INF
## Ledge tier the climb state should play, see Player.get_mantle_style().
static var mantle_style: StringName = &""

@export var on_enter_animation: String

var speed: float
var sprint_speed: float
var aim_speed: float
var crouch_speed: float
var jump_velocity: float
var jump_gravity: float
var fall_gravity: float


func _ready() -> void:
	velocity_updated.connect(owner.set_velocity_from_motion)

	speed = PLAYER_MOVEMENT_STATS.run_speed
	sprint_speed = PLAYER_MOVEMENT_STATS.sprint_speed
	aim_speed = PLAYER_MOVEMENT_STATS.aim_speed
	crouch_speed = PLAYER_MOVEMENT_STATS.crouch_speed
	jump_gravity = PLAYER_MOVEMENT_STATS.get_jump_gravity()
	fall_gravity = PLAYER_MOVEMENT_STATS.get_fall_gravity()
	jump_velocity = PLAYER_MOVEMENT_STATS.get_jump_velocity(jump_gravity)


func _enter() -> void:
	crouched = false

	if on_enter_animation:
		animation_change_requested.emit(on_enter_animation)


func set_direction() -> void:
	input_dir = Input.get_vector("left", "right", "up", "down")
	direction = (owner.global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()


func calculate_velocity(
	_speed: float, _direction: Vector3, acceleration: float, delta: float
) -> void:
	# Scaling the target here rather than in each state is what makes a slope cost
	# the same share of the speed whatever ground move is being made, and it leaves
	# the air states alone because the owner keeps the scale at 1 off the ground.
	var target_speed: float = _speed * slope_speed_scale * clampf(input_dir.length(), 0.0, 1.0)
	var target: Vector3 = _direction * target_speed

	# Standing still on a steep face is not stable. With no movement input the body
	# is aimed at the slip the owner measured instead of at a standstill, so no
	# state needs its own slip handling and the slip cannot outrun the braking of
	# the state: it is a speed to travel at, not an impulse added every frame.
	if slope_slip_velocity != Vector3.ZERO and input_dir.length() < SLIP_INPUT_DEADZONE:
		target.x = slope_slip_velocity.x
		target.z = slope_slip_velocity.z

	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)
	velocity_updated.emit(velocity)


func calculate_gravity(delta: float) -> void:
	# The floor reading alone would hold the body up on the lip of a ledge after
	# the feet had already left it, so gravity follows the feet instead.
	if not is_grounded():
		if velocity.y > 0:
			velocity.y -= jump_gravity * delta
		else:
			velocity.y -= fall_gravity * delta


func start_jump(default_horizontal_speed: float) -> void:
	var takeoff_velocity := Vector2(velocity.x, velocity.z)
	var takeoff_speed: float = takeoff_velocity.length()
	if takeoff_speed <= 0.01 and Input.get_vector("left", "right", "up", "down") != Vector2.ZERO:
		takeoff_speed = default_horizontal_speed

	jump_horizontal_speed = takeoff_speed * PLAYER_MOVEMENT_STATS.jump_momentum_multiplier
	if takeoff_velocity.length() > 0.01:
		var velocity_scale: float = jump_horizontal_speed / takeoff_velocity.length()
		velocity.x *= velocity_scale
		velocity.z *= velocity_scale
	velocity.y = jump_velocity


func get_jump_horizontal_speed(default_horizontal_speed: float) -> float:
	if (
		jump_horizontal_speed <= 0.01
		and Input.get_vector("left", "right", "up", "down") != Vector2.ZERO
	):
		return default_horizontal_speed
	return jump_horizontal_speed


func cut_jump_on_release() -> void:
	if velocity.y > 0.0:
		velocity.y *= PLAYER_MOVEMENT_STATS.jump_release_velocity_multiplier


func is_on_floor() -> bool:
	return owner.is_on_floor()


## True when the player is carrying enough momentum for the roll input to be
## worth turning into a slide instead of a crouch.
func is_travelling_fast_enough_to_slide() -> bool:
	var horizontal: Vector2 = Vector2(velocity.x, velocity.z)
	return horizontal.length() >= PLAYER_MOVEMENT_STATS.slide_min_speed


func is_grounded() -> bool:
	if owner.has_method("is_grounded_for_movement"):
		return owner.is_grounded_for_movement()
	return is_on_floor()


## Angle (in degrees above horizontal) of the ground the owner is standing on,
## or 0 while they are airborne.
func get_slope_angle() -> float:
	if owner == null or not owner.has_method("get_ground_slope_angle"):
		return 0.0

	return owner.get_ground_slope_angle()


## Steepest face (in degrees above horizontal) the owner can still stand on. The
## slide blends its friction and its speed ceiling against this, so both follow
## the owner's own slope limit instead of carrying a second copy of the angle.
func get_max_slope_angle() -> float:
	if owner == null:
		return DEFAULT_MAX_SLOPE_ANGLE

	var limit: Variant = owner.get("slope_max_climb_angle")
	if limit == null:
		return DEFAULT_MAX_SLOPE_ANGLE

	return limit


## Unit horizontal direction of the pull down the face the owner is standing on,
## or Vector3.ZERO on level ground.
func get_downhill_direction() -> Vector3:
	if owner == null or not owner.has_method("get_slope_downhill_direction"):
		return Vector3.ZERO

	return owner.get_slope_downhill_direction()


## Whether the movement input points down the face the owner is standing on.
func is_directed_downhill() -> bool:
	var downhill: Vector3 = get_downhill_direction()
	if downhill.is_zero_approx():
		return false

	set_direction()
	if direction == Vector3.ZERO:
		return false

	return direction.dot(downhill) > 0.0


## Whether the owner has room to stand up where it is. States that end a low
## posture use this so the full height capsule is never pushed into a ceiling.
func can_stand_up() -> bool:
	if owner == null or not owner.has_method("can_stand_up"):
		return true

	return owner.can_stand_up()


## Ledge the owner offers to climb onto, or Vector3.INF when there is none.
func find_mantle_target() -> Vector3:
	if not owner.has_method("find_mantle_target"):
		return Vector3.INF

	return owner.find_mantle_target()


## Height tier of the ledge the owner found, or an empty StringName when there
## is nothing to climb.
func find_mantle_style() -> StringName:
	if not owner.has_method("get_mantle_style"):
		return &""

	return owner.get_mantle_style()


## Climbs the ledge in front of the player when there is one, and reports
## whether the climb state was entered. Callers fall through to their normal
## jump when nothing is climbable.
func try_climb() -> bool:
	var target: Vector3 = find_mantle_target()
	if not target.is_finite():
		return false

	mantle_target = target
	mantle_style = find_mantle_style()
	finished.emit("Climb")
	return true


## Grabs the ledge in front of the player while airborne, and reports whether
## the climb state was entered. On the ground the jump action already offers the
## climb, so this only acts when the player is off the floor.
func try_air_climb() -> bool:
	if is_grounded():
		return false

	return try_climb()


## Handles the input half of try_air_climb(): an airborne grab is requested by
## either the dedicated climb action or by pressing jump again once the player
## has left the floor. Reports whether the climb state was entered so the air
## states can stop handling the event.
func try_air_climb_from_input(event: InputEvent) -> bool:
	# Key echo repeats the press while held, so keeping jump held from take-off
	# must not retry the grab every frame.
	if event.is_echo():
		return false

	if not event.is_action_pressed("climb") and not event.is_action_pressed("jump"):
		return false

	return try_air_climb()
