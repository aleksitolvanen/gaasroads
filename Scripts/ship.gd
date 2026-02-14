extends CharacterBody3D

signal warped
signal exploded

enum State { NORMAL, WARPING, EXPLODING }

@export var min_speed := 0.0
@export var max_speed := 25.0
@export var acceleration := 12.0
@export var lateral_speed := 10.0
@export var jump_velocity := 8.0
@export var gravity := 20.0

var current_speed := 0.0
var frozen := true
var _vertical_velocity := 0.0
var _start_position: Vector3
var _state := State.NORMAL
var _warp_trail: MeshInstance3D

func _ready():
	_start_position = global_position
	_build_ship_mesh()

func _build_ship_mesh():
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.7, 0.1, 0.1)

	var accent_mat := StandardMaterial3D.new()
	accent_mat.albedo_color = Color(0.85, 0.85, 0.9)

	var engine_mat := StandardMaterial3D.new()
	engine_mat.albedo_color = Color(0.2, 0.5, 0.9)
	engine_mat.emission_enabled = true
	engine_mat.emission = Color(0.1, 0.3, 0.8)
	engine_mat.emission_energy_multiplier = 1.5

	# Main body - shorter, same width
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.7, 0.25, 1.0)
	body_mesh.material = body_mat
	body.mesh = body_mesh
	add_child(body)

	# Nose cone
	var nose := MeshInstance3D.new()
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.35, 0.15, 0.3)
	nose_mesh.material = accent_mat
	nose.mesh = nose_mesh
	nose.position = Vector3(0, 0.02, -0.55)
	add_child(nose)

	# Small wings
	var wing_mesh := BoxMesh.new()
	wing_mesh.size = Vector3(0.35, 0.04, 0.35)
	wing_mesh.material = body_mat

	var left_wing := MeshInstance3D.new()
	left_wing.mesh = wing_mesh
	left_wing.position = Vector3(-0.4, -0.05, 0.15)
	add_child(left_wing)

	var right_wing := MeshInstance3D.new()
	right_wing.mesh = wing_mesh
	right_wing.position = Vector3(0.4, -0.05, 0.15)
	add_child(right_wing)

	# Engine glow
	var engine := MeshInstance3D.new()
	var engine_mesh := BoxMesh.new()
	engine_mesh.size = Vector3(0.4, 0.15, 0.12)
	engine_mesh.material = engine_mat
	engine.mesh = engine_mesh
	engine.position = Vector3(0, 0, 0.5)
	add_child(engine)

func _physics_process(delta):
	if _state != State.NORMAL or frozen:
		return

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

	# Wall collision: only head-on (forward into wall), not side bumps
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var normal := col.get_normal()
		if normal.y < 0.5 and normal.z > 0.5:
			start_explosion()
			return

	if global_position.y < -10:
		start_explosion()

func start_warp():
	if _state != State.NORMAL:
		return
	_state = State.WARPING

	# Bright engine trail
	var trail_mat := StandardMaterial3D.new()
	trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_mat.albedo_color = Color(0.4, 0.7, 1.0)
	trail_mat.emission_enabled = true
	trail_mat.emission = Color(0.3, 0.6, 1.0)
	trail_mat.emission_energy_multiplier = 4.0

	_warp_trail = MeshInstance3D.new()
	var trail_mesh := BoxMesh.new()
	trail_mesh.size = Vector3(0.3, 0.12, 0.5)
	trail_mesh.material = trail_mat
	_warp_trail.mesh = trail_mesh
	_warp_trail.position = Vector3(0, 0, 1.3)
	add_child(_warp_trail)

	var tween := create_tween()
	# Phase 1: Engine powers up - trail grows bright
	tween.tween_property(_warp_trail, "scale:z", 20.0, 0.8)
	tween.parallel().tween_property(_warp_trail, "position:z", 6.0, 0.8)

	# Phase 2: Ship shoots up into space and disappears off the top of the screen
	tween.tween_property(self, "position:y", position.y + 500, 1.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "position:z", position.z - 100, 1.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)

	# Brief pause then return to menu
	tween.tween_interval(0.3)
	tween.tween_callback(func(): warped.emit())

func start_explosion():
	if _state != State.NORMAL:
		return
	_state = State.EXPLODING
	velocity = Vector3.ZERO

	var tween := create_tween()
	for i in 8:
		tween.tween_property(self, "visible", false, 0.07)
		tween.tween_property(self, "visible", true, 0.07)
	tween.tween_property(self, "visible", false, 0.15)
	tween.tween_callback(func(): exploded.emit())

func reset_ship():
	_state = State.NORMAL
	visible = true
	scale = Vector3.ONE
	global_position = _start_position
	_vertical_velocity = 0
	current_speed = 12.0
	if _warp_trail:
		_warp_trail.queue_free()
		_warp_trail = null
