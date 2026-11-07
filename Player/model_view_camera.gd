extends Camera3D

var camera_rotation: Vector2 = Vector2.ZERO
var mouse_sensitivity: float = 0.001
var controller_sensitivity: float = 3.0
var max_y_rotation: float = 1.2
var acceleration: float = 2.0


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	set_process_input(false)
	set_process(false)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var look_input: Vector2 = Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if look_input != Vector2.ZERO:
		camera_look(look_input * controller_sensitivity * delta)

	var input_direction: Vector2 = Input.get_vector("left", "right", "up", "down")
	var direction: Vector3 = (
		(transform.basis * Vector3(input_direction.x, 0, input_direction.y)).normalized()
	)

	position += direction * (delta * acceleration)

	if Input.is_action_pressed("jump"):
		position.y += delta * acceleration
	if Input.is_action_pressed("swap_camera_alignment"):
		position.y -= delta * acceleration


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var mouse_event: Vector2 = event.screen_relative * mouse_sensitivity
		camera_look(mouse_event)


func camera_look(mouse_movement: Vector2) -> void:
	camera_rotation += mouse_movement

	transform.basis = Basis()

	rotate_object_local(Vector3(0, 1, 0), -camera_rotation.x)
	rotate_object_local(Vector3(1, 0, 0), -camera_rotation.y)

	camera_rotation.y = clamp(camera_rotation.y, -max_y_rotation, max_y_rotation)
