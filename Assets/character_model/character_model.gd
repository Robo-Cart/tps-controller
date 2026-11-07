extends Node3D
class_name AnimationController

## Emitted when the collision posture changes, so the owner of the collision
## shape can resize it. A slide is as low as a crouch, so both share the short
## capsule; a roll has its own, slightly taller one.
signal collision_posture_changed(posture: CollisionPosture)

## Emitted when the character starts or stops crouching, so the camera can follow
## the shorter pose. A slide does not count: the camera keeps its standing height
## through the dive.
signal crouch_changed(is_crouched: bool)

enum CombatStatus { COMBAT, NONCOMBAT }

## Height the collision capsule needs for the pose being played. A crouch and a
## slide both fold the body down as far as it goes; a roll tucks it only part way.
enum CollisionPosture { STANDING, ROLL, SHORT }

const ROLL_ANIMATION_PATH: String = "res://Assets/character_model/new_animations/roll_fit.res"
const ROLL_ANIMATION_NAME: StringName = &"roll_fit"
const ROLL_BLEND_TREE_NODE: StringName = &"roll_animation"
const SLIDE_START_ANIMATION_PATH: String = "res://Assets/character_model/fbx_animations/Armature_slide_start_fit.res"
const SLIDE_LOOP_ANIMATION_PATH: String = "res://Assets/character_model/fbx_animations/Armature_slide_loop_fit.res"
const SLIDE_EXIT_ANIMATION_PATH: String = "res://Assets/character_model/fbx_animations/Armature_slide_exit_fit.res"
const SLIDE_START_ANIMATION_NAME: StringName = &"slide_start"
const SLIDE_LOOP_ANIMATION_NAME: StringName = &"slide_loop"
const SLIDE_EXIT_ANIMATION_NAME: StringName = &"slide_exit"
const SLIDE_START_ONESHOT_NODE: StringName = &"slide_start"
const SLIDE_EXIT_ONESHOT_NODE: StringName = &"slide_exit"
const SLIDE_START_FALLBACK_DURATION: float = 0.833
const CROUCH_IDLE_ANIMATION_PATH: String = "res://Assets/character_model/fbx_animations/Armature_crouch_idle_loop_fit.res"
const CROUCH_WALK_ANIMATION_PATH: String = "res://Assets/character_model/fbx_animations/Armature_crouch_fwd_loop_fit.res"
const CLIMB_ANIMATION_PATH: String = "res://Assets/character_model/fbx_animations/Armature_climbup_1m_fit.res"
const HANG_CLIMB_ANIMATION_PATH: String = "res://Assets/character_model/fbx_animations/Armature_Braced Hang Climbing On_fit.res"
const CROUCH_IDLE_ANIMATION_NAME: StringName = &"crouch_idle"
const CROUCH_WALK_ANIMATION_NAME: StringName = &"crouch_walk"
const CLIMB_ANIMATION_NAME: StringName = &"climb_up"
const HANG_CLIMB_ANIMATION_NAME: StringName = &"hang_climb_up"
const CLIMB_BLEND_TREE_NODE: StringName = &"climb_animation"
const HANG_CLIMB_BLEND_TREE_NODE: StringName = &"hang_climb_animation"
const CLIMB_ONESHOT_NODE: StringName = &"climb"
const HANG_CLIMB_ONESHOT_NODE: StringName = &"hang_climb"
const CLIMB_FALLBACK_DURATION: float = 0.667
const HANG_CLIMB_FALLBACK_DURATION: float = 1.133
## Bone carrying the whole-body translation in the climb clips, and the number of
## samples the authored height curve is baked into.
const CLIMB_HIPS_BONE_NAME: String = "Hips"
const CLIMB_RISE_SAMPLE_COUNT: int = 16
## Smallest authored rise, in bone units, worth baking a curve for.
const CLIMB_MIN_RISE: float = 0.001
## Climb tiers (Player.get_mantle_style()); the overhead tier plays the braced
## hang clip, everything below it the one metre climb.
const CLIMB_STYLE_LOW: StringName = &"low"
const CLIMB_STYLE_HIGH: StringName = &"high"
const CROUCH_STATE_NAMES: Array[StringName] = [&"CrouchIdle", &"CrouchWalk"]
const SLIDE_STATE_NAME: StringName = &"Slide"
const MOVEMENT_TRANSITION_NODES: Array[StringName] = [&"unarmed_movement", &"armed_movement"]
const JUMP_ANIMATION_NAME: StringName = &"merged/Armature_Jumping Up_fit"
const SPRINT_JUMP_ANIMATION_NAME: StringName = &"merged/Armature_Running Jump_fit"
const MOVEMENT_XFADE_TIME: float = 0.2
const CROUCH_XFADE_TIME: float = 0.2
const POSE_LOCK_IK_FADE_TIME: float = 0.12
## Hand IK influences that hold a drawn weapon. The weapon clips are authored for
## these values, so they are what the hands return to whenever the hand IK has to
## be re-armed outside of a weapon clip.
const ARMED_HAND_IK_RIGHT: float = 0.5
const ARMED_HAND_IK_LEFT: float = 1.0

@export var animation_tree: AnimationTree
@export var right_hand: Node3D
@export var armature: Node3D
@export var turn_rate: float = 0.1
@export var hip_ik: SkeletonIK3D
@export var right_hand_ik: SkeletonIK3D
@export var left_hand_ik: SkeletonIK3D
@export var hip_target: Node3D

## Degrees of torso twist applied while a weapon is drawn and the character is
## crouched. The crouch clips are unarmed poses, so a drawn weapon inherits their
## wrist orientation and ends up pointing left of the aim direction; twisting the
## torso brings the whole upper body (and the weapon) back onto the aim. Negative
## values rotate the weapon to the right. Measured against the standing armed
## pose: crouch idle needs about -44, crouch walk about -44.5.
@export var crouch_armed_torso_yaw: float = -40.0

## Seconds into the jump clip playback starts, so the take-off pose is picked up
## without replaying the wind-up. Applied to every blend tree node that plays the
## jump animation.
@export var jump_animation_start_offset: float = 0.5

## Seconds into the sprint jump clip playback starts. The running jump is already
## mid-stride, so it plays from the beginning.
@export var sprint_jump_animation_start_offset: float = 0.0

## Seconds the movement transition takes to blend into the looping slide. A
## one-shot blends over everything below it and, once it is fully blended in, the
## transition is culled and its crossfade freezes where it stood. The slide entry
## clip ends exactly on the loop pose, so it hides that frozen crossfade for its
## whole length and cuts to whatever is left of it: the half blended standing pose
## that reads as the character briefly standing up between the loop and the
## stand-up. Cutting into the loop instead leaves nothing to reveal.
@export var slide_entry_xfade_time: float = 0.0

## Seconds the slide entry clip takes to blend in. Matches the cut above: the
## clip starts on the pose the character slides out of, so it can take over in one
## frame and the loop the transition switched to never shows through underneath.
@export var slide_start_fade_in_time: float = 0.0

## Seconds the stand-up clip takes to blend in over the looping slide. The entry
## clip ends on the loop pose and the stand-up clip starts from it, so the cut
## between them is already seamless; blending in here only lets the run pose the
## movement transition is crossfading to leak through, which lifts the hips part
## way up and drops them again before the stand-up gets going.
@export var slide_exit_fade_in_time: float = 0.0

## Seconds the entry clip takes to blend out when a slide is cancelled early. A
## natural finish cuts the entry clip instead, because by then it is already
## sitting on the loop pose; fading it restarts the clip from its first frame and
## the hips lift for the length of the fade, which reads as a bump at the end of
## the slide.
@export var slide_start_cancel_fade_out_time: float = 0.1

## Seconds the stand-up clip takes to blend back out into whichever state took
## over from the slide, so the character eases into the run/idle pose instead of
## cutting to it on the clip's last frame.
@export var slide_exit_fade_out_time: float = 0.25

var current_mouse_rotation: Vector2 = Vector2.ZERO
var input_dir: Vector2 = Vector2.UP
var current_combat_status: CombatStatus = CombatStatus.NONCOMBAT
var next_weapon_to_load: WeaponModel
var hip_rotation_offset: float = -55

var _is_rolling: bool = false
## World-space heading of the roll or slide that is playing. While a weapon is
## drawn the armature is normally left to the camera and the aim lock, so without
## this the character moves in place relative to the aim instead of where it is
## heading.
var _locked_facing: Vector3 = Vector3.ZERO
var _is_sliding: bool = false
var _is_climbing: bool = false
var _is_crouched: bool = false
## Authored height curve of every in-place clip, keyed by animation name: 0 at
## the first frame and 1 once the clip's own hips have topped out. The in-place
## copies have their hip translation stripped so the climb state can move the
## body itself, so this stores the timing that translation used to carry.
var _rise_curves: Dictionary = {}
## Posture the owner's collision shape is currently sized for. Tracked so the
## posture signal only fires when the combined pose actually changes.
var _collision_posture: CollisionPosture = CollisionPosture.STANDING
## Whether a draw, holster or weapon change clip currently owns the arms. Those
## clips animate the arms themselves, so they drop the hand IK to zero while they
## play, and the clip calls activate_hand_ik() on its last frame to hand the arms
## back. A roll, slide, climb or crouch cuts such a clip short, which is why the
## pose lock takes the re-arm over on release instead of restoring the zero the
## clip left behind.
var _weapon_clip_owns_hands: bool = false
var _torso_modifier: CrouchTorsoModifier
var _foot_ik: FootIk


func _ready() -> void:
	hip_ik.start()
	right_hand_ik.start()
	left_hand_ik.start()
	hip_ik.influence = 0
	right_hand_ik.influence = 0
	left_hand_ik.influence = 0

	_register_extra_animations()
	_setup_torso_modifier()
	_setup_foot_ik()
	_apply_jump_start_offset()
	_apply_slide_blends()


func _register_extra_animations() -> void:
	var library: AnimationLibrary = _get_default_animation_library()
	if library == null:
		return

	_register_animation(library, ROLL_ANIMATION_NAME, ROLL_ANIMATION_PATH)
	_register_animation(library, CROUCH_IDLE_ANIMATION_NAME, CROUCH_IDLE_ANIMATION_PATH)
	_register_animation(library, CROUCH_WALK_ANIMATION_NAME, CROUCH_WALK_ANIMATION_PATH)
	_register_animation(library, SLIDE_START_ANIMATION_NAME, SLIDE_START_ANIMATION_PATH)
	_register_animation(library, SLIDE_LOOP_ANIMATION_NAME, SLIDE_LOOP_ANIMATION_PATH)
	_register_animation(library, SLIDE_EXIT_ANIMATION_NAME, SLIDE_EXIT_ANIMATION_PATH)
	_register_in_place_animation(library, CLIMB_ANIMATION_NAME, CLIMB_ANIMATION_PATH)
	_register_in_place_animation(library, HANG_CLIMB_ANIMATION_NAME, HANG_CLIMB_ANIMATION_PATH)


func _register_in_place_animation(
	library: AnimationLibrary, animation_name: StringName, path: String
) -> void:
	if library.has_animation(animation_name):
		return

	var source: Animation = load(path) as Animation
	if source == null:
		return

	# The climb clips lift the hips on their own, which would stack on top of the
	# height the climb state moves the body by and leave the character floating.
	# Dropping the bone's position track leaves an in-place climb; the hip
	# rotation track keeps the body motion so the feet still plant where the clip
	# expects.
	var in_place: Animation = source.duplicate() as Animation
	for index: int in range(in_place.get_track_count() - 1, -1, -1):
		if in_place.track_get_type(index) == Animation.TYPE_POSITION_3D:
			in_place.remove_track(index)
	in_place.loop_mode = Animation.LOOP_NONE

	library.add_animation(animation_name, in_place)
	_rise_curves[animation_name] = _build_rise_curve(source)


## Bakes the height the clip's own hip translation lifts the body by into a
## normalised 0..1 curve. The climb state moves the body and the clip is played
## in place, so without this the body has no way of rising at the pace the
## animation was drawn at and the hands drift off the ledge they grab.
func _build_rise_curve(source: Animation) -> PackedFloat32Array:
	var track: int = -1
	for index: int in range(source.get_track_count()):
		if source.track_get_type(index) != Animation.TYPE_POSITION_3D:
			continue
		if str(source.track_get_path(index)).contains(CLIMB_HIPS_BONE_NAME):
			track = index
			break

	if track < 0:
		return PackedFloat32Array()

	var start_height: float = source.position_track_interpolate(track, 0.0).y
	var peak_height: float = start_height
	for step: int in range(CLIMB_RISE_SAMPLE_COUNT + 1):
		var time: float = source.length * float(step) / float(CLIMB_RISE_SAMPLE_COUNT)
		peak_height = maxf(peak_height, source.position_track_interpolate(track, time).y)

	var rise: float = peak_height - start_height
	if rise <= CLIMB_MIN_RISE:
		return PackedFloat32Array()

	# Both clips settle back down a little once the body is over the ledge, and the
	# body has to end exactly on the mantle target, so the curve never falls.
	var curve: PackedFloat32Array = PackedFloat32Array()
	var previous: float = 0.0
	for step: int in range(CLIMB_RISE_SAMPLE_COUNT + 1):
		var time: float = source.length * float(step) / float(CLIMB_RISE_SAMPLE_COUNT)
		var height: float = source.position_track_interpolate(track, time).y
		previous = maxf(previous, clampf((height - start_height) / rise, 0.0, 1.0))
		curve.append(previous)

	return curve


func _apply_jump_start_offset() -> void:
	# The jump clips are shared by the armed and unarmed movement transitions, so
	# every node playing one has to be offset or the two machines would disagree.
	_apply_animation_start_offset(JUMP_ANIMATION_NAME, jump_animation_start_offset)
	_apply_animation_start_offset(SPRINT_JUMP_ANIMATION_NAME, sprint_jump_animation_start_offset)


func _apply_animation_start_offset(animation_name: StringName, offset: float) -> void:
	if animation_tree == null:
		return

	var blend_tree: AnimationNodeBlendTree = animation_tree.tree_root as AnimationNodeBlendTree
	if blend_tree == null:
		return

	for node_name: String in blend_tree.get_node_list():
		var animation_node: AnimationNodeAnimation = (
			blend_tree.get_node(StringName(node_name)) as AnimationNodeAnimation
		)
		if animation_node == null:
			continue
		if animation_node.animation != animation_name:
			continue

		animation_node.start_offset = offset


## Writes the slide blend times onto the two slide one-shots. Keeping both ends of
## the loop -> exit -> locomotion blend here means they can be tuned together, and
## the scene keeps whatever the blend tree was left with.
func _apply_slide_blends() -> void:
	var slide_start: AnimationNodeOneShot = _get_oneshot(SLIDE_START_ONESHOT_NODE)
	if slide_start != null:
		slide_start.fadein_time = slide_start_fade_in_time
		slide_start.fadeout_time = 0.0

	var slide_exit: AnimationNodeOneShot = _get_oneshot(SLIDE_EXIT_ONESHOT_NODE)
	if slide_exit != null:
		slide_exit.fadein_time = slide_exit_fade_in_time
		slide_exit.fadeout_time = slide_exit_fade_out_time


## Looks a one-shot up on the blend tree so the slide calls can reach its fade
## times without every caller repeating the tree walk.
func _get_oneshot(node_name: StringName) -> AnimationNodeOneShot:
	if animation_tree == null:
		return null

	var blend_tree: AnimationNodeBlendTree = animation_tree.tree_root as AnimationNodeBlendTree
	if blend_tree == null or not blend_tree.has_node(node_name):
		return null

	return blend_tree.get_node(node_name) as AnimationNodeOneShot


func _get_default_animation_library() -> AnimationLibrary:
	var animation_player: AnimationPlayer = (
		animation_tree.get_node(animation_tree.anim_player) as AnimationPlayer
	)
	if animation_player == null:
		return null

	var library: AnimationLibrary = animation_player.get_animation_library(&"")
	if library != null:
		return library

	library = AnimationLibrary.new()
	animation_player.add_animation_library(&"", library)
	return library


func _register_animation(
	library: AnimationLibrary, animation_name: StringName, path: String
) -> void:
	if library.has_animation(animation_name):
		return

	var animation: Animation = load(path) as Animation
	if animation == null:
		return

	library.add_animation(animation_name, animation)


func on_roll_started(duration: float, facing: Vector3 = Vector3.ZERO) -> void:
	var blend_tree: AnimationNodeBlendTree = animation_tree.tree_root as AnimationNodeBlendTree
	if blend_tree == null or not blend_tree.has_node(ROLL_BLEND_TREE_NODE):
		return

	var roll_animation_node: AnimationNodeAnimation = (
		blend_tree.get_node(ROLL_BLEND_TREE_NODE) as AnimationNodeAnimation
	)
	if roll_animation_node == null:
		return

	roll_animation_node.use_custom_timeline = true
	roll_animation_node.stretch_time_scale = true
	roll_animation_node.timeline_length = maxf(duration, 0.1)

	_is_rolling = true
	_locked_facing = facing
	_update_ik_state()
	_sync_collision_posture()
	_apply_locked_facing()

	animation_tree["parameters/roll/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE


func on_roll_finished() -> void:
	if not _is_rolling:
		return

	_is_rolling = false
	_locked_facing = Vector3.ZERO
	_sync_collision_posture()

	_restore_aim_facing()
	_update_ik_state()


## Starts a slide: the entry clip plays over the looping slide the movement
## transition is already blending into, and the armature is locked to the slide
## heading so the character travels the way the momentum was pointing.
func on_slide_started(facing: Vector3 = Vector3.ZERO) -> void:
	_is_sliding = true
	_locked_facing = facing
	_update_ik_state()
	_sync_collision_posture()
	_apply_locked_facing()

	animation_tree["parameters/%s/request" % SLIDE_START_ONESHOT_NODE] = (
		AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
	)


## Ends the slide. `cancelled` is set when another state took over, in which case
## the stand-up clip is dropped so it does not mask the pose that is taking over.
func on_slide_finished(cancelled: bool = false) -> void:
	if not _is_sliding:
		return

	_is_sliding = false
	_locked_facing = Vector3.ZERO
	_sync_collision_posture()

	# The entry clip is cut short when the momentum runs out early, so fade it out
	# before the exit pose stands the character back up. A natural finish cuts it
	# instead: the clip has already reached the loop pose, and a fade there would
	# restart the clip and lift the hips just before the stand-up takes over.
	var slide_start: AnimationNodeOneShot = _get_oneshot(SLIDE_START_ONESHOT_NODE)
	if slide_start != null:
		slide_start.fadeout_time = 0.0 if not cancelled else slide_start_cancel_fade_out_time

	animation_tree["parameters/%s/request" % SLIDE_START_ONESHOT_NODE] = (
		AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT
	)

	if not cancelled:
		animation_tree["parameters/%s/request" % SLIDE_EXIT_ONESHOT_NODE] = (
			AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
		)

	_restore_aim_facing()
	_update_ik_state()


## Length of the slide entry clip, used by the slide state to keep the entry
## animation playing until the character has dropped into the slide pose.
func get_slide_start_duration() -> float:
	var library: AnimationLibrary = _get_default_animation_library()
	if library == null or not library.has_animation(SLIDE_START_ANIMATION_NAME):
		return SLIDE_START_FALLBACK_DURATION

	return library.get_animation(SLIDE_START_ANIMATION_NAME).length


## Hands the armature back to the aim lock once a roll or slide ends. rotate_model()
## writes the LOCAL yaw from the camera, which only lands on the aim while the
## parent chain carries no yaw of its own; in combat it does as soon as the camera
## has moved since the weapon was drawn, so aim in world space instead.
func _restore_aim_facing() -> void:
	if current_combat_status == CombatStatus.COMBAT:
		_set_armature_facing(PI - current_mouse_rotation.x)


## Points the armature (and with it the skeleton, the hip target and the weapon
## attachment) down the locked heading. The armature is only free to turn while the
## hip IK is suspended, which is what a roll or slide does.
func _apply_locked_facing() -> void:
	if not _is_rolling and not _is_sliding:
		return

	var facing: Vector3 = Vector3(_locked_facing.x, 0.0, _locked_facing.z)
	if facing.length_squared() < 0.000001:
		return

	_set_armature_facing(atan2(facing.x, facing.z))


## Turns the armature to face `world_yaw`. The armature's parent chain carries yaw
## of its own - the player body follows the camera while the model keeps the free
## look offset it held when combat started - so the local yaw is the world yaw
## minus whatever the parents contribute.
func _set_armature_facing(world_yaw: float) -> void:
	armature.transform.basis = Basis()
	armature.rotate_object_local(Vector3(0, 1, 0), world_yaw - _get_armature_parent_yaw())


func _get_armature_parent_yaw() -> float:
	var parent: Node3D = armature.get_parent() as Node3D
	if parent == null:
		return 0.0

	var forward: Vector3 = parent.global_transform.basis.z
	return atan2(forward.x, forward.z)


## Length of the climb clip in seconds, used by the climb state to time its
## movement so the body arrives with the animation. The overhead tier uses the
## braced hang clip instead of the one metre climb.
func get_climb_duration(style: StringName = &"low") -> float:
	var animation_name: StringName = _get_climb_animation_name(style)
	var fallback: float = CLIMB_FALLBACK_DURATION
	if animation_name == HANG_CLIMB_ANIMATION_NAME:
		fallback = HANG_CLIMB_FALLBACK_DURATION

	var library: AnimationLibrary = _get_default_animation_library()
	if library == null or not library.has_animation(animation_name):
		return fallback

	return library.get_animation(animation_name).length


## Height curve of a climb clip, sampled 0..1 across the clip: 0 is the pose the
## climb starts from, 1 is the clip's own top. The climb state moves the body on
## this curve so it rises at the pace the animation was drawn at.
func get_climb_rise_curve(style: StringName = &"low") -> PackedFloat32Array:
	var animation_name: StringName = _get_climb_animation_name(style)
	if not _rise_curves.has(animation_name):
		return PackedFloat32Array()

	var curve: PackedFloat32Array = _rise_curves[animation_name]
	return curve


func on_climb_started(duration: float, style: StringName = &"low") -> void:
	var blend_tree: AnimationNodeBlendTree = animation_tree.tree_root as AnimationNodeBlendTree
	if blend_tree == null:
		return

	var animation_name: StringName = _get_climb_animation_name(style)
	var is_overhead: bool = animation_name == HANG_CLIMB_ANIMATION_NAME
	var blend_tree_node: StringName = (
		HANG_CLIMB_BLEND_TREE_NODE if is_overhead else CLIMB_BLEND_TREE_NODE
	)
	if not blend_tree.has_node(blend_tree_node):
		return

	var climb_animation_node: AnimationNodeAnimation = (
		blend_tree.get_node(blend_tree_node) as AnimationNodeAnimation
	)
	if climb_animation_node == null:
		return

	climb_animation_node.use_custom_timeline = true
	climb_animation_node.stretch_time_scale = true
	climb_animation_node.timeline_length = maxf(duration, 0.1)

	_is_climbing = true
	_update_ik_state()

	var oneshot_node: StringName = HANG_CLIMB_ONESHOT_NODE if is_overhead else CLIMB_ONESHOT_NODE
	animation_tree["parameters/%s/request" % oneshot_node] = (
		AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
	)


func _get_climb_animation_name(style: StringName) -> StringName:
	return HANG_CLIMB_ANIMATION_NAME if style == CLIMB_STYLE_HIGH else CLIMB_ANIMATION_NAME


func on_climb_finished() -> void:
	if not _is_climbing:
		return

	_is_climbing = false
	_update_ik_state()


func set_crouched(value: bool) -> void:
	if _is_crouched == value:
		return

	_is_crouched = value
	_update_ik_state()
	_sync_collision_posture()
	crouch_changed.emit(_is_crouched)


## Keeps the owner's collision shape in step with the pose being played. A slide
## fits through the same gaps a crouch does, so either one needs the short
## capsule, while a roll tucks the body to its own height. The signal only fires
## when the combined posture changes.
func _sync_collision_posture() -> void:
	var posture: CollisionPosture = _get_collision_posture()
	if posture == _collision_posture:
		return

	_collision_posture = posture
	collision_posture_changed.emit(_collision_posture)


## Posture the current pose calls for. A crouch or a slide wins over a roll, so
## rolling out of a crouch keeps the short capsule instead of growing it back
## into the ceiling the crouch was fitting under.
func _get_collision_posture() -> CollisionPosture:
	if _is_crouched or _is_sliding:
		return CollisionPosture.SHORT
	if _is_rolling:
		return CollisionPosture.ROLL
	return CollisionPosture.STANDING


func _update_ik_state() -> void:
	_update_crouch_torso_yaw()

	if _is_rolling or _is_sliding or _is_climbing or _is_crouched:
		# The lock cuts short any weapon clip that was still laying claim to the
		# arms, and that clip will never reach the frame that re-arms them.
		_weapon_clip_owns_hands = false
		_set_pose_lock_ik()
		return

	match current_combat_status:
		CombatStatus.COMBAT:
			set_ik_influence(hip_ik, 1.0, POSE_LOCK_IK_FADE_TIME)
			set_ik_influence(
				left_hand_ik, _hand_ik_after_lock(ARMED_HAND_IK_LEFT), POSE_LOCK_IK_FADE_TIME
			)
			set_ik_influence(
				right_hand_ik, _hand_ik_after_lock(ARMED_HAND_IK_RIGHT), POSE_LOCK_IK_FADE_TIME
			)
		CombatStatus.NONCOMBAT:
			_set_pose_lock_ik()


## Hand influence to restore once the pose lock releases: the armed value, unless
## a weapon clip is still playing and will call activate_hand_ik() itself.
func _hand_ik_after_lock(armed_influence: float) -> float:
	return 0.0 if _weapon_clip_owns_hands else armed_influence


func _set_pose_lock_ik() -> void:
	# The hip IK chain is rooted at the spine, so leaving it running while the
	# character rolls or crouches pins the torso (and everything above it) to the
	# hip target and the upper body stops animating. The hand IK chains follow
	# the weapon targets, so they are suspended for the same reason.
	set_ik_influence(hip_ik, 0.0, POSE_LOCK_IK_FADE_TIME)
	set_ik_influence(left_hand_ik, 0.0, POSE_LOCK_IK_FADE_TIME)
	set_ik_influence(right_hand_ik, 0.0, POSE_LOCK_IK_FADE_TIME)


func _setup_torso_modifier() -> void:
	var skeleton: Skeleton3D = hip_ik.get_parent() as Skeleton3D
	if skeleton == null:
		return

	_torso_modifier = CrouchTorsoModifier.new()
	skeleton.add_child(_torso_modifier)


func _setup_foot_ik() -> void:
	# The feet are planted against the world, so the probe needs the body the model
	# is standing on: without one the model is a preview with no ground to test.
	var skeleton: Skeleton3D = hip_ik.get_parent() as Skeleton3D
	var body := get_parent() as CollisionObject3D
	if skeleton == null or armature == null or body == null:
		return

	_foot_ik = FootIk.new()
	_foot_ik.name = "FootIk"
	add_child(_foot_ik)
	_foot_ik.setup(skeleton, armature, body)


func _update_crouch_torso_yaw() -> void:
	if _torso_modifier == null:
		return

	# Only a drawn weapon needs the correction; crouch clips are unarmed poses and
	# nothing is attached to the hands when unarmed.
	var armed_crouch: bool = (
		current_combat_status == CombatStatus.COMBAT
		and _is_crouched
		and not _is_rolling
		and not _is_sliding
	)
	_torso_modifier.set_target_degrees(crouch_armed_torso_yaw if armed_crouch else 0.0)


func on_state_machine_state_change(state: String) -> void:
	var state_name: StringName = StringName(state)
	var is_crouch_state: bool = state_name in CROUCH_STATE_NAMES
	# A roll started from a crouch keeps the crouched posture (and the short
	# collision shape) until the roll ends, otherwise standing up mid-roll would
	# push the full height capsule into a ceiling the crouch was fitting under.
	if not (_is_rolling and _is_crouched):
		set_crouched(is_crouch_state)

	# Blending into the crouch pose at the normal locomotion speed looks like the
	# character slowly sinks into it, so crouch states crossfade much faster.
	if state_name == SLIDE_STATE_NAME:
		_set_movement_xfade(slide_entry_xfade_time)
	else:
		_set_movement_xfade(CROUCH_XFADE_TIME if is_crouch_state else MOVEMENT_XFADE_TIME)

	match current_combat_status:
		CombatStatus.NONCOMBAT:
			animation_tree["parameters/unarmed_movement/transition_request"] = state
		CombatStatus.COMBAT:
			animation_tree["parameters/armed_movement/transition_request"] = state


func _set_movement_xfade(xfade_time: float) -> void:
	var blend_tree: AnimationNodeBlendTree = animation_tree.tree_root as AnimationNodeBlendTree
	if blend_tree == null:
		return

	for node_name: StringName in MOVEMENT_TRANSITION_NODES:
		if not blend_tree.has_node(node_name):
			continue

		var transition: AnimationNodeTransition = (
			blend_tree.get_node(node_name) as AnimationNodeTransition
		)
		if transition != null:
			transition.xfade_time = xfade_time


func on_combat_status_changed(status: String) -> void:
	# Drawing and holstering both play the change weapon clip, which owns the arms
	# until it re-arms the hand IK on its last frame.
	_weapon_clip_owns_hands = true

	match status:
		"non_combat":
			input_dir = Vector2.UP
			current_combat_status = CombatStatus.NONCOMBAT
			_on_camera_camera_rotated(current_mouse_rotation)
			rotate_model(input_dir, current_mouse_rotation)
		"combat":
			current_combat_status = CombatStatus.COMBAT
			rotate_model(Vector2.UP, current_mouse_rotation)

	_update_ik_state()

	animation_tree["parameters/combat_transition/transition_request"] = status


func set_ik_influence(ik: SkeletonIK3D, _influence: float, _time: float) -> void:
	var tween: Tween = get_tree().create_tween()
	tween.tween_property(ik, "influence", _influence, _time)


func on_character_input_direction_changed(dir: Vector2) -> void:
	input_dir = input_dir.lerp(dir, turn_rate)
	var input_strength: float = clampf(dir.length(), 0.0, 1.0)
	var animation_speed: float = 1.0
	if input_strength > 0.05:
		animation_speed = lerpf(0.5, 1.0, input_strength)
	animation_tree["parameters/armed_movement_speed/scale"] = animation_speed
	animation_tree["parameters/unarmed_movement_speed/scale"] = animation_speed
	match current_combat_status:
		CombatStatus.NONCOMBAT:
			rotate_model(input_dir, current_mouse_rotation)
		CombatStatus.COMBAT:
			animation_tree["parameters/walk_blend/blend_position"] = input_dir
			animation_tree["parameters/run_blend/blend_position"] = input_dir


func _on_camera_camera_rotated(_rotation: Vector2) -> void:
	current_mouse_rotation = _rotation
	rotate_hip()
	match current_combat_status:
		CombatStatus.NONCOMBAT:
			transform.basis = Basis()
			rotate_object_local(Vector3(0, 1, 0), current_mouse_rotation.x)

	# The camera moves the body under the model, which changes how much yaw the
	# armature has to carry to stay on the locked roll/slide heading.
	_apply_locked_facing()


func rotate_hip() -> void:
	hip_target.transform.basis = Basis()
	hip_target.rotate_object_local(Vector3(1, 0, 0), current_mouse_rotation.y)
	hip_target.rotate_object_local(Vector3(0, 1, 0), deg_to_rad(hip_rotation_offset))


func rotate_model(angle: Vector2 = Vector2.ZERO, _rotation: Vector2 = Vector2.ZERO) -> void:
	var new_angle: float = atan2(angle.x, angle.y) - _rotation.x
	armature.transform.basis = Basis()
	armature.rotate_object_local(Vector3(0, 1, 0), new_angle)


func _on_weapon_manager_weapon_changed(_weapon: Weapon, _model: WeaponModel) -> void:
	set_ik_influence(left_hand_ik, 0, .1)
	set_ik_influence(right_hand_ik, 0, .1)
	load_new_weapon(_weapon, _model)


func load_new_weapon(_weapon: Weapon, model: WeaponModel) -> void:
	_weapon_clip_owns_hands = true
	right_hand.position = _weapon.hand_position
	right_hand.rotation = _weapon.hand_rotation

	animation_tree.tree_root.get_node("weapon_idle_animation").set_animation(
		_weapon.weapon_idle_animation.resource_name
	)
	animation_tree.tree_root.get_node("weapon_shoot_animation").set_animation(
		_weapon.weapon_shoot_animation.resource_name
	)
	animation_tree.tree_root.get_node("weapon_reload_animation").set_animation(
		_weapon.weapon_reload_animation.resource_name
	)
	var change_animation_node: AnimationNodeAnimation = animation_tree.tree_root.get_node(
		"weapon_change_animation"
	)
	change_animation_node.set_animation(_weapon.weapon_change_animation.resource_name)
	change_animation_node.use_custom_timeline = true
	change_animation_node.stretch_time_scale = true
	change_animation_node.timeline_length = (
		_weapon.weapon_change_animation.length / _weapon.weapon_change_speed_scale
	)

	animation_tree["parameters/change_weapon/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
	next_weapon_to_load = model


func attach_weapon_to_hand() -> void:
	if next_weapon_to_load:
		right_hand.add_child(next_weapon_to_load)
		next_weapon_to_load = null


func remove_weapon_attachment() -> void:
	if right_hand.get_child_count() > 0:
		var current_weapon_attachment: Node3D = right_hand.get_child(0)
		current_weapon_attachment.queue_free()


func activate_hand_ik() -> void:
	# The clip has reached its hand-back frame, so it no longer owns the arms even
	# when the lock swallows the influence change itself.
	_weapon_clip_owns_hands = false

	if _is_rolling or _is_sliding or _is_crouched:
		return

	if current_combat_status == CombatStatus.COMBAT:
		set_ik_influence(right_hand_ik, ARMED_HAND_IK_RIGHT, .1)
		set_ik_influence(left_hand_ik, ARMED_HAND_IK_LEFT, .1)


func _on_weapon_manager_weapon_manager_finished(status: String, weapons_is_empty: bool) -> void:
	if animation_tree["parameters/combat_transition/current_state"] == status:
		return

	on_combat_status_changed(status)

	next_weapon_to_load = null

	if not weapons_is_empty:
		if animation_tree["parameters/change_weapon/active"]:
			remove_weapon_attachment()
			animation_tree["parameters/change_weapon/request"] = (
				AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT
			)
		else:
			animation_tree["parameters/change_weapon/request"] = (
				AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
			)


func _on_weapon_manager_weapon_manager_started(
	status: String, _weapon: Weapon, _model: WeaponModel
) -> void:
	on_combat_status_changed(status)
	load_new_weapon(_weapon, _model)


func _on_weapon_manager_weapon_fired() -> void:
	animation_tree["parameters/shoot/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE


func _on_weapon_manager_weapon_realoded() -> void:
	set_ik_influence(right_hand_ik, 0, .1)
	set_ik_influence(left_hand_ik, 0, .1)
	animation_tree["parameters/reload/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
