extends Node3D

signal camera_rotated(_rotation: Vector2)
signal model_view_changed(view: bool)

enum CameraAlignment { LEFT = -1, RIGHT = 1, CENTRE = 0 }
enum View { MODEL, GAME }

@export var character: CharacterBody3D
@export var edge_spring_arm: SpringArm3D
@export var rear_spring_arm: SpringArm3D
@export var camera: Camera3D
@export var model: Node3D
@export var model_view_camera: Camera3D

@export var camera_alignment_speed: float = 0.2
@export var aim_rear_spring_length: float = 0.5
@export var aim_edge_spring_length: float = 0.5
@export var aim_speed: float = 0.3
@export var aim_fov: float = 55

@export var sprint_fov: float = 90
@export var sprint_tween_speed: float = 0.5

@export var vertical_follow_smoothing: float = 18.0
@export var vertical_follow_snap_distance: float = 1.5

## Height (in metres) the camera is lowered while the character is crouched, so
## the view drops with the shorter pose instead of looking over the character.
@export var crouch_height_offset: float = 0.55
@export var crouch_height_speed: float = 0.15

var camera_rotation: Vector2 = Vector2.ZERO
var mouse_sensitivity: float = 0.001
var controller_sensitivity: float = 3.0
var controller_invert_y: bool = true
var is_aiming: bool = false
## Turned off while a radial menu owns the mouse and the right stick, so looking
## around cannot fight the segment selection.
var look_enabled: bool = true
var max_y_rotation: float = 1.2
var current_camera_alignment: int = CameraAlignment.RIGHT
var current_view: View = View.GAME

var camera_tween: Tween
var crouch_tween: Tween
var smoothed_character_height: float = 0.0
var has_smoothed_character_height: bool = false
var crouch_height: float = 0.0

@onready var default_edge_spring_arm_length: float = edge_spring_arm.spring_length
@onready var default_rear_spring_arm_length: float = rear_spring_arm.spring_length
@onready var default_fov: float = camera.fov
@onready var default_height: float = position.y


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	smoothed_character_height = character.global_position.y
	has_smoothed_character_height = true

	var animation_controller: AnimationController = model as AnimationController
	if animation_controller != null:
		animation_controller.crouch_changed.connect(_on_crouch_changed)


func _input(event: InputEvent) -> void:
	match current_view:
		View.GAME:
			if event.is_action_pressed("ui_cancel"):
				if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
					Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
				else:
					Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

			if (
				look_enabled
				and event is InputEventMouseMotion
				and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
			):
				var mouse_event: Vector2 = event.screen_relative * mouse_sensitivity
				if controller_invert_y:
					mouse_event.y = -mouse_event.y
				camera_look(mouse_event)

			if event.is_action_pressed("swap_camera_alignment"):
				swap_camera_alignment()

	if event.is_action_pressed("model_view"):
		if current_view == View.GAME:
			current_view = View.MODEL
			start_model_view_camera()
			model_view_changed.emit(true)
		else:
			current_view = View.GAME
			stop_model_view_camera()
			model_view_changed.emit(false)


func _process(delta: float) -> void:
	_smooth_vertical_follow(delta)

	if current_view == View.GAME:
		if look_enabled:
			var look_input: Vector2 = Input.get_vector(
				"aim_left", "aim_right", "aim_up", "aim_down"
			)
			if controller_invert_y:
				look_input.y = -look_input.y
			if look_input != Vector2.ZERO:
				camera_look(look_input * controller_sensitivity * delta)

		model_view_camera.global_transform = camera.global_transform
		model_view_camera.global_rotation = camera.global_rotation


func _smooth_vertical_follow(delta: float) -> void:
	var target_height: float = character.global_position.y
	if (
		not has_smoothed_character_height
		or absf(smoothed_character_height - target_height) > vertical_follow_snap_distance
	):
		smoothed_character_height = target_height
		has_smoothed_character_height = true
	else:
		var weight: float = 1.0 - exp(-vertical_follow_smoothing * delta)
		smoothed_character_height = lerpf(smoothed_character_height, target_height, weight)

	position.y = default_height + crouch_height + (smoothed_character_height - target_height)


## Drops the camera to the crouched eye height. The offset is tweened so the view
## sinks with the character instead of cutting to the lower position.
func _on_crouch_changed(is_crouched: bool) -> void:
	if crouch_tween:
		crouch_tween.kill()

	var crouch_target: float = -crouch_height_offset if is_crouched else 0.0
	crouch_tween = get_tree().create_tween()
	crouch_tween.set_trans(Tween.TRANS_EXPO)
	crouch_tween.set_ease(Tween.EASE_OUT)
	crouch_tween.tween_property(self, "crouch_height", crouch_target, crouch_height_speed)


func start_model_view_camera() -> void:
	model_view_camera.camera_rotation = Vector2.ZERO
	camera.current = false
	model_view_camera.current = true
	model_view_camera.set_process(true)
	model_view_camera.set_process_input(true)


func stop_model_view_camera() -> void:
	camera.current = true
	model_view_camera.current = false
	model_view_camera.set_process(false)
	model_view_camera.set_process_input(false)


func camera_look(mouse_movement: Vector2) -> void:
	camera_rotation += mouse_movement

	transform.basis = Basis()
	character.transform.basis = Basis()

	character.rotate_object_local(Vector3(0, 1, 0), -camera_rotation.x)
	rotate_object_local(Vector3(1, 0, 0), -camera_rotation.y)

	camera_rotation.y = clamp(camera_rotation.y, -max_y_rotation, max_y_rotation)
	camera_rotated.emit(camera_rotation)


func swap_camera_alignment() -> void:
	match current_camera_alignment:
		CameraAlignment.RIGHT:
			set_current_camera_alignment(CameraAlignment.LEFT)
		CameraAlignment.LEFT:
			set_current_camera_alignment(CameraAlignment.RIGHT)
		CameraAlignment.CENTRE:
			return

	var edge_spring_length: float = (
		aim_edge_spring_length if is_aiming else default_edge_spring_arm_length
	)
	var new_pos: float = edge_spring_length * current_camera_alignment
	set_rear_spring_arm_position(new_pos, camera_alignment_speed)


func set_current_camera_alignment(alignment: CameraAlignment) -> void:
	current_camera_alignment = alignment


func set_rear_spring_arm_position(pos: float, speed: float) -> void:
	if camera_tween:
		camera_tween.kill()

	camera_tween = get_tree().create_tween()
	camera_tween.set_trans(Tween.TRANS_EXPO)
	camera_tween.set_ease(Tween.EASE_OUT)

	camera_tween.tween_property(edge_spring_arm, "spring_length", pos, speed)


func enter_aim() -> void:
	is_aiming = true
	if camera_tween:
		camera_tween.kill()

	camera_tween = get_tree().create_tween()
	camera_tween.set_parallel()

	camera_tween.set_trans(Tween.TRANS_EXPO)
	camera_tween.set_ease(Tween.EASE_OUT)

	camera_tween.tween_property(camera, "fov", aim_fov, aim_speed)
	camera_tween.tween_property(
		edge_spring_arm,
		"spring_length",
		aim_edge_spring_length * current_camera_alignment,
		aim_speed
	)
	camera_tween.tween_property(rear_spring_arm, "spring_length", aim_rear_spring_length, aim_speed)


func exit_aim() -> void:
	is_aiming = false
	if camera_tween:
		camera_tween.kill()

	camera_tween = get_tree().create_tween()
	camera_tween.set_parallel()

	camera_tween.set_trans(Tween.TRANS_EXPO)
	camera_tween.set_ease(Tween.EASE_OUT)

	camera_tween.tween_property(camera, "fov", default_fov, aim_speed)
	camera_tween.tween_property(
		edge_spring_arm,
		"spring_length",
		default_edge_spring_arm_length * current_camera_alignment,
		aim_speed
	)
	camera_tween.tween_property(
		rear_spring_arm, "spring_length", default_rear_spring_arm_length, aim_speed
	)


func enter_sprint() -> void:
	if camera_tween:
		camera_tween.kill()

	camera_tween = get_tree().create_tween()

	camera_tween.set_parallel()
	camera_tween.set_trans(Tween.TRANS_EXPO)
	camera_tween.set_ease(Tween.EASE_OUT)

	camera_tween.tween_property(camera, "fov", sprint_fov, sprint_tween_speed)
	camera_tween.tween_property(
		edge_spring_arm,
		"spring_length",
		default_edge_spring_arm_length * current_camera_alignment,
		aim_speed
	)
	camera_tween.tween_property(
		rear_spring_arm, "spring_length", default_rear_spring_arm_length, aim_speed
	)


func exit_sprint() -> void:
	if camera_tween:
		camera_tween.kill()

	camera_tween = get_tree().create_tween()
	camera_tween.set_parallel()

	camera_tween.set_trans(Tween.TRANS_EXPO)
	camera_tween.set_ease(Tween.EASE_OUT)

	camera_tween.tween_property(camera, "fov", default_fov, sprint_tween_speed)
	camera_tween.tween_property(
		edge_spring_arm,
		"spring_length",
		default_edge_spring_arm_length * current_camera_alignment,
		aim_speed
	)
	camera_tween.tween_property(
		rear_spring_arm, "spring_length", default_rear_spring_arm_length, aim_speed
	)


func _on_sprint_sprint_started() -> void:
	enter_sprint()


func _on_sprint_ended() -> void:
	exit_sprint()


func _on_aim_entered() -> void:
	enter_aim()


func _on_aim_exited() -> void:
	exit_aim()
