extends Node

## Emote wheel. Holding the emote input opens a radial menu, the look (aim)
## input steers it, and releasing it plays the chosen animation. Moving in any
## direction cancels the emote and hands the body straight back to the movement
## states, which keep running underneath the whole time.
##
## The emote pose is blended over the finished animation graph through an
## AnimationNodeBlend2 that is added to the blend tree at runtime, so no state
## machine work is needed and every clip (loop or one-shot) works the same way.
## The first segment sits at the top of the wheel; the rest follow clockwise.

const EMOTE_ACTION: StringName = &"emote"
const BLEND_TREE_OUTPUT: StringName = &"output"
const EMOTE_BLEND_NODE: StringName = &"emote_blend"
const EMOTE_ANIMATION_NODE: StringName = &"emote_animation"
## Node the blend tree output currently feeds from. Godot exposes no getter for
## existing blend tree connections, so this has to be kept in sync with the
## graph authored in the character model scene.
const GRAPH_FALLBACK_FEED: StringName = &"slide_start"

const TPOSE_ANIMATION: String = "emote_tpose"
const TPOSE_PATH: String = "res://Assets/character_model/new_animations/tpose.res"
const DANCE_ANIMATION: String = "merged/Armature_dance_loop_fit"
## The dead-front resource is a one-key pose (the clip the ragdoll settles into),
## so it holds its last frame instead of playing over time.
const DEAD_ANIMATION: String = "emote_dead_front"
const DEAD_PATH: String = "res://Assets/character_model/merge_animations/dead_front.res"

## Emotes on the wheel, in segment order (the first one is at the top).
## "loop" only decides the fallback; a clip whose own animation is set to loop
## always loops. The wheel shows at most EmoteMenu.MAX_SEGMENTS of these.
const EMOTES: Array[Dictionary] = [
	{"label": "T-Pose", "animation": TPOSE_ANIMATION, "path": TPOSE_PATH, "loop": false},
	{"label": "Dance", "animation": DANCE_ANIMATION, "path": "", "loop": true},
	{"label": "Play Dead", "animation": DEAD_ANIMATION, "path": DEAD_PATH, "loop": false},
]

## Seconds the emote pose takes to blend in over the movement pose, and back out
## when the emote ends.
const BLEND_FADE_TIME: float = 0.16
const IK_FADE_TIME: float = 0.12
## How far the right stick has to lean before it picks a segment.
const LOOK_DEADZONE: float = 0.4
## Mouse travel (in pixels) before the mouse can pick a segment, and the most
## travel that is remembered so a fast flick cannot overshoot the wheel.
const MOUSE_SELECT_DISTANCE: float = 10.0
const MOUSE_TRAVEL_LIMIT: float = 160.0
## Movement input that ends the gesture. The actions carry their own deadzone,
## so this only filters the analogue tail.
const MOVE_CANCEL_DEADZONE: float = 0.2

@export var animation_controller: AnimationController
@export var emote_menu: EmoteMenu
@export var camera: Node3D

var _menu_open: bool = false
var _emoting: bool = false
var _selected: int = -1
var _mouse_travel: Vector2 = Vector2.ZERO
var _emote_animation: AnimationNodeAnimation
var _emote_blend: float = 0.0
var _emote_blend_target: float = 0.0


func _ready() -> void:
	_resolve_targets()
	_ensure_emote_nodes()


## Falls back to the canonical paths in the player scene when the exports were
## not wired, so the emote wheel still works on a bare node.
func _resolve_targets() -> void:
	if animation_controller == null:
		animation_controller = get_node_or_null(^"../CharacterModel") as AnimationController
	if emote_menu == null:
		emote_menu = get_node_or_null(^"../CanvasLayer/EmoteMenu") as EmoteMenu
	if camera == null:
		camera = get_node_or_null(^"../Camera") as Node3D


func _input(event: InputEvent) -> void:
	if event.is_action(EMOTE_ACTION):
		if event.is_action_pressed(EMOTE_ACTION):
			_open_menu()
		elif event.is_action_released(EMOTE_ACTION):
			_commit_menu()
		return

	# With the mouse the aim direction is where the player moves the mouse, so
	# the travel is accumulated while the wheel is up.
	if _menu_open and event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		_mouse_travel = (_mouse_travel + motion.screen_relative).limit_length(MOUSE_TRAVEL_LIMIT)


func _process(delta: float) -> void:
	_advance_blend(delta)

	if not _menu_open and not _emoting:
		return

	# Any movement input ends the emote immediately. The movement states were
	# never disabled, so the body simply carries on from here.
	if _get_move_strength() > MOVE_CANCEL_DEADZONE:
		_cancel_gesture()
		return

	if _menu_open:
		_update_selection()


func _open_menu() -> void:
	if _menu_open:
		return

	_ensure_emote_nodes()
	_stop_emote()
	_menu_open = true
	_selected = -1
	_mouse_travel = Vector2.ZERO
	_set_camera_look(false)

	if emote_menu != null:
		emote_menu.open(_get_labels())


func _commit_menu() -> void:
	if not _menu_open:
		return

	var chosen: int = _selected
	_close_menu()

	if chosen < 0 or chosen >= _get_emote_count():
		return

	_play_emote(EMOTES[chosen])


func _close_menu() -> void:
	_menu_open = false
	_selected = -1
	_mouse_travel = Vector2.ZERO
	_set_camera_look(true)

	if emote_menu != null:
		emote_menu.close()


func _cancel_gesture() -> void:
	if _menu_open:
		_close_menu()

	_stop_emote()


func _update_selection() -> void:
	var look: Vector2 = Input.get_vector(&"aim_left", &"aim_right", &"aim_up", &"aim_down")
	var direction: Vector2 = Vector2.ZERO

	if look.length() >= LOOK_DEADZONE:
		direction = look
		# A stick choice overrides the mouse, so the next mouse move starts from
		# the centre instead of fighting the stick.
		_mouse_travel = Vector2.ZERO
	elif _mouse_travel.length() >= MOUSE_SELECT_DISTANCE:
		direction = _mouse_travel.normalized()

	if direction == Vector2.ZERO:
		return

	var index: int = _get_segment_index(direction)
	if index == _selected:
		return

	_selected = index
	if emote_menu != null:
		emote_menu.set_highlight(index)


## Segment under a direction, where zero points straight up and the angle grows
## clockwise. Matches the way the wheel draws its segments.
func _get_segment_index(direction: Vector2) -> int:
	var count: int = _get_emote_count()
	if count <= 0:
		return -1

	var angle: float = atan2(direction.x, -direction.y)
	if angle < 0.0:
		angle += TAU

	var step: float = TAU / float(count)
	return int(round(angle / step)) % count


func _play_emote(entry: Dictionary) -> void:
	_ensure_emote_nodes()
	if _emote_animation == null:
		return

	var animation_name := StringName(str(entry.get("animation", "")))
	var path := str(entry.get("path", ""))
	if not path.is_empty():
		_register_animation(animation_name, path)

	_emote_animation.animation = animation_name
	_emote_animation.loop_mode = _get_loop_mode(animation_name, bool(entry.get("loop", false)))
	_emote_blend_target = 1.0
	_emoting = true
	_suspend_ik()


func _stop_emote() -> void:
	if not _emoting:
		return

	_emoting = false
	_emote_blend_target = 0.0
	_restore_ik()


func _advance_blend(delta: float) -> void:
	if _emote_animation == null:
		return

	if is_equal_approx(_emote_blend, _emote_blend_target):
		return

	var rate: float = 1.0 / BLEND_FADE_TIME if BLEND_FADE_TIME > 0.0 else 1.0
	_emote_blend = move_toward(_emote_blend, _emote_blend_target, rate * delta)
	_write_blend(_emote_blend)


func _write_blend(value: float) -> void:
	if animation_controller == null or animation_controller.animation_tree == null:
		return

	animation_controller.animation_tree.set(&"parameters/%s/blend_amount" % EMOTE_BLEND_NODE, value)


## Adds the emote branch to the top of the animation blend tree the first time
## it is needed: output <- emote_blend <- (whole existing graph, emote clip).
func _ensure_emote_nodes() -> void:
	if animation_controller == null:
		return

	var tree: AnimationTree = animation_controller.animation_tree
	if tree == null:
		return

	var blend_tree := tree.tree_root as AnimationNodeBlendTree
	if blend_tree == null:
		return

	if blend_tree.has_node(EMOTE_BLEND_NODE):
		_emote_animation = blend_tree.get_node(EMOTE_ANIMATION_NODE) as AnimationNodeAnimation
		return

	var feed: StringName = _get_graph_feed(blend_tree)
	if feed.is_empty():
		push_warning("EmoteController: cannot find the blend tree output feed, emotes disabled.")
		return

	var animation_node := AnimationNodeAnimation.new()
	blend_tree.add_node(EMOTE_ANIMATION_NODE, animation_node, Vector2(-240.0, 560.0))
	var blend_node := AnimationNodeBlend2.new()
	blend_tree.add_node(EMOTE_BLEND_NODE, blend_node, Vector2(0.0, 560.0))

	# The tree output has to point at the new branch before its inputs can be
	# wired: the blend tree refuses to connect anything into the node that is
	# currently feeding the output.
	blend_tree.connect_node(BLEND_TREE_OUTPUT, 0, EMOTE_BLEND_NODE)
	blend_tree.connect_node(EMOTE_BLEND_NODE, 0, feed)
	blend_tree.connect_node(EMOTE_BLEND_NODE, 1, EMOTE_ANIMATION_NODE)

	_emote_animation = animation_node
	_emote_blend = 0.0
	_emote_blend_target = 0.0
	_write_blend(0.0)


## Node currently feeding the blend tree output, so the new branch can sit on
## top of it instead of replacing the whole graph. Godot 4 builds expose no
## getter for existing connections, so the known feed is used and the insertion
## is skipped when it is missing.
func _get_graph_feed(blend_tree: AnimationNodeBlendTree) -> StringName:
	if blend_tree.has_node(GRAPH_FALLBACK_FEED):
		return GRAPH_FALLBACK_FEED

	return &""


## Loop mode for a clip: an animation that is authored to loop keeps looping,
## everything else holds its last frame. The catalog entry is only the fallback
## for a clip that is missing from the library.
func _get_loop_mode(animation_name: StringName, fallback_loop: bool) -> Animation.LoopMode:
	var library: AnimationLibrary = _get_library()
	if library != null and library.has_animation(animation_name):
		var animation: Animation = library.get_animation(animation_name)
		if animation.loop_mode != Animation.LOOP_NONE:
			return Animation.LOOP_LINEAR
		return Animation.LOOP_NONE

	return Animation.LOOP_LINEAR if fallback_loop else Animation.LOOP_NONE


func _get_library() -> AnimationLibrary:
	if animation_controller == null or animation_controller.animation_tree == null:
		return null

	var tree: AnimationTree = animation_controller.animation_tree
	var player := tree.get_node_or_null(tree.anim_player) as AnimationPlayer
	if player == null:
		return null

	var library: AnimationLibrary = player.get_animation_library(&"")
	if library != null:
		return library

	library = AnimationLibrary.new()
	player.add_animation_library(&"", library)
	return library


func _register_animation(animation_name: StringName, path: String) -> void:
	var library: AnimationLibrary = _get_library()
	if library == null or library.has_animation(animation_name):
		return

	var animation: Animation = load(path) as Animation
	if animation != null:
		library.add_animation(animation_name, animation)


## Emote poses are authored without the weapon and hip aim correction, so the
## IK chains are faded out while one plays and handed back afterwards.
func _suspend_ik() -> void:
	if animation_controller == null:
		return

	if animation_controller.hip_ik != null:
		animation_controller.set_ik_influence(animation_controller.hip_ik, 0.0, IK_FADE_TIME)
	if animation_controller.right_hand_ik != null:
		animation_controller.set_ik_influence(animation_controller.right_hand_ik, 0.0, IK_FADE_TIME)
	if animation_controller.left_hand_ik != null:
		animation_controller.set_ik_influence(animation_controller.left_hand_ik, 0.0, IK_FADE_TIME)


func _restore_ik() -> void:
	if animation_controller == null:
		return

	# The controller already knows what the current posture and combat status
	# call for, so let it put the chains back rather than guessing here.
	animation_controller.call(&"_update_ik_state")


func _set_camera_look(enabled: bool) -> void:
	if camera == null:
		return

	camera.set(&"look_enabled", enabled)


func _get_move_strength() -> float:
	return Input.get_vector(&"left", &"right", &"up", &"down").length()


func _get_emote_count() -> int:
	return mini(EMOTES.size(), EmoteMenu.MAX_SEGMENTS)


func _get_labels() -> PackedStringArray:
	var labels: PackedStringArray = PackedStringArray()
	for index: int in range(_get_emote_count()):
		labels.append(str(EMOTES[index].get("label", "Emote")))
	return labels
