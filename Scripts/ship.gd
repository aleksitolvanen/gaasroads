extends CharacterBody3D

@export var min_speed := 0.0
@export var max_speed := 25.0
@export var acceleration := 12.0
@export var lateral_speed := 10.0
@export var jump_velocity := 8.0
@export var gravity := 20.0

var current_speed := 12.0
var _vertical_velocity := 0.0
var _start_position: Vector3

func _ready():
	_start_position = global_position

func _physics_process(delta):
	if Input.is_action_pressed("ui_up"):
		current_speed += acceleration * delta
	elif Input.is_action_pressed("ui_down"):
		current_speed -= acceleration * delta
	current_speed = clamp(current_speed, min_speed, max_speed)

	var vel := Vector3(0, 0, -current_speed)

	if Input.is_action_pressed("ui_left"):
		vel.x = -lateral_speed
	elif Input.is_action_pressed("ui_right"):
		vel.x = lateral_speed

	if is_on_floor():
		_vertical_velocity = 0
		if Input.is_action_just_pressed("ui_accept"):
			_vertical_velocity = jump_velocity
	else:
		_vertical_velocity -= gravity * delta

	vel.y = _vertical_velocity
	velocity = vel
	move_and_slide()

	if global_position.y < -10:
		global_position = _start_position
		_vertical_velocity = 0
