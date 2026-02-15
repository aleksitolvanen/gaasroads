extends CharacterBody3D

signal warped
signal exploded

enum State { NORMAL, WARPING, EXPLODING }

@export var min_speed := 0.0
@export var max_speed := 30.0
@export var acceleration := 12.0
@export var lateral_speed := 15.0
@export var jump_velocity := 8.0
@export var gravity := 20.0
@export var bounce_factor := 0.45

var current_speed := 0.0
var frozen := true
var _vertical_velocity := 0.0
var _was_on_floor := true
var _last_floor_y := 0.0
var _bounce_count := 0
var _jump_airborne := false
var _locked_lateral := 0.0
var _can_jump := true
var _start_position: Vector3
var _state := State.NORMAL
var _warp_trail: MeshInstance3D
var _land_player: AudioStreamPlayer3D
var _jump_player: AudioStreamPlayer3D
var _ship_parts: Array[MeshInstance3D] = []
var _debris: Array[Node3D] = []
var _engine_mat: StandardMaterial3D
var _exhaust_core: GPUParticles3D
var _exhaust_outer: GPUParticles3D
var _exhaust_trail: GPUParticles3D

func _ready():
	_start_position = global_position
	_build_ship_mesh()
	_land_player = _create_sfx_player()
	add_child(_land_player)
	_jump_player = _create_sfx_player()
	add_child(_jump_player)

func _create_sfx_player() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.max_distance = 100.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	return p

func _generate_sound(start_freq: float, end_freq: float, duration: float, volume: float = 0.5) -> AudioStreamWAV:
	var sample_rate := 22050
	var samples := int(duration * sample_rate)
	var data := PackedByteArray()
	data.resize(samples * 2)
	var phase := 0.0
	for i in samples:
		var t := float(i) / float(samples)
		var freq := lerpf(start_freq, end_freq, t)
		var envelope := (1.0 - t) * (1.0 - t)
		phase += freq / sample_rate
		var sample := sin(phase * TAU) * envelope * volume
		var val := int(clampf(sample, -1.0, 1.0) * 32767)
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	return stream

func _build_ship_mesh():
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.7, 0.1, 0.1)

	var accent_mat := StandardMaterial3D.new()
	accent_mat.albedo_color = Color(0.85, 0.85, 0.9)

	_engine_mat = StandardMaterial3D.new()
	_engine_mat.albedo_color = Color(0.05, 0.05, 0.05)
	_engine_mat.emission_enabled = true
	_engine_mat.emission = Color(0, 0, 0)
	_engine_mat.emission_energy_multiplier = 0.0

	_ship_parts.clear()

	# Main body - shorter, same width
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.7, 0.25, 1.0)
	body_mesh.material = body_mat
	body.mesh = body_mesh
	add_child(body)
	_ship_parts.append(body)

	# Nose cone
	var nose := MeshInstance3D.new()
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.35, 0.15, 0.3)
	nose_mesh.material = accent_mat
	nose.mesh = nose_mesh
	nose.position = Vector3(0, 0.02, -0.55)
	add_child(nose)
	_ship_parts.append(nose)

	# Small wings
	var wing_mesh := BoxMesh.new()
	wing_mesh.size = Vector3(0.35, 0.04, 0.35)
	wing_mesh.material = body_mat

	var left_wing := MeshInstance3D.new()
	left_wing.mesh = wing_mesh
	left_wing.position = Vector3(-0.4, -0.05, 0.15)
	add_child(left_wing)
	_ship_parts.append(left_wing)

	var right_wing := MeshInstance3D.new()
	right_wing.mesh = wing_mesh
	right_wing.position = Vector3(0.4, -0.05, 0.15)
	add_child(right_wing)
	_ship_parts.append(right_wing)

	# Engine glow
	var engine := MeshInstance3D.new()
	var engine_mesh := BoxMesh.new()
	engine_mesh.size = Vector3(0.4, 0.15, 0.12)
	engine_mesh.material = _engine_mat
	engine.mesh = engine_mesh
	engine.position = Vector3(0, 0, 0.5)
	add_child(engine)
	_ship_parts.append(engine)

	# Exhaust - 2 layers with large overlapping billboard spheres
	# Forms a dense short cone (~0.5 units = half ship length)

	# Core: bright white-blue, tight cone, large overlapping billboards
	_exhaust_core = GPUParticles3D.new()
	_exhaust_core.position = Vector3(0, 0, 0.56)
	_exhaust_core.amount = 40
	_exhaust_core.lifetime = 0.06
	var core_pm := ParticleProcessMaterial.new()
	core_pm.direction = Vector3(0, 0, 1)
	core_pm.spread = 20.0
	core_pm.initial_velocity_min = 2.0
	core_pm.initial_velocity_max = 4.0
	core_pm.gravity = Vector3.ZERO
	core_pm.damping_min = 25.0
	core_pm.damping_max = 40.0
	core_pm.scale_min = 0.8
	core_pm.scale_max = 1.2
	var core_scale_curve := CurveTexture.new()
	var core_curve := Curve.new()
	core_curve.add_point(Vector2(0, 1.0))
	core_curve.add_point(Vector2(0.15, 0.6))
	core_curve.add_point(Vector2(0.4, 0.2))
	core_curve.add_point(Vector2(1.0, 0.0))
	core_scale_curve.curve = core_curve
	core_pm.scale_curve = core_scale_curve
	var core_grad := Gradient.new()
	core_grad.set_color(0, Color(0.9, 0.97, 1.0, 0.9))
	core_grad.add_point(0.3, Color(0.5, 0.8, 1.0, 0.6))
	core_grad.set_color(1, Color(0.2, 0.5, 0.9, 0.0))
	var core_ramp := GradientTexture1D.new()
	core_ramp.gradient = core_grad
	core_pm.color_ramp = core_ramp
	_exhaust_core.process_material = core_pm
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.1
	core_mesh.height = 0.2
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(0.8, 0.95, 1.0)
	core_mat.emission_enabled = true
	core_mat.emission = Color(0.6, 0.85, 1.0)
	core_mat.emission_energy_multiplier = 5.0
	core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	core_mesh.material = core_mat
	_exhaust_core.draw_pass_1 = core_mesh
	add_child(_exhaust_core)

	# Outer: softer blue glow, wider spread for cone edge
	_exhaust_outer = GPUParticles3D.new()
	_exhaust_outer.position = Vector3(0, 0, 0.56)
	_exhaust_outer.amount = 30
	_exhaust_outer.lifetime = 0.08
	var outer_pm := ParticleProcessMaterial.new()
	outer_pm.direction = Vector3(0, 0, 1)
	outer_pm.spread = 35.0
	outer_pm.initial_velocity_min = 1.5
	outer_pm.initial_velocity_max = 3.0
	outer_pm.gravity = Vector3.ZERO
	outer_pm.damping_min = 20.0
	outer_pm.damping_max = 35.0
	outer_pm.scale_min = 1.0
	outer_pm.scale_max = 1.8
	var outer_scale_curve := CurveTexture.new()
	var outer_curve := Curve.new()
	outer_curve.add_point(Vector2(0, 1.0))
	outer_curve.add_point(Vector2(0.1, 0.5))
	outer_curve.add_point(Vector2(0.3, 0.15))
	outer_curve.add_point(Vector2(1.0, 0.0))
	outer_scale_curve.curve = outer_curve
	outer_pm.scale_curve = outer_scale_curve
	var outer_grad := Gradient.new()
	outer_grad.set_color(0, Color(0.25, 0.55, 1.0, 0.5))
	outer_grad.add_point(0.4, Color(0.1, 0.3, 0.8, 0.15))
	outer_grad.set_color(1, Color(0.05, 0.15, 0.5, 0.0))
	var outer_ramp := GradientTexture1D.new()
	outer_ramp.gradient = outer_grad
	outer_pm.color_ramp = outer_ramp
	_exhaust_outer.process_material = outer_pm
	var outer_mesh := SphereMesh.new()
	outer_mesh.radius = 0.12
	outer_mesh.height = 0.24
	var outer_mat := StandardMaterial3D.new()
	outer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outer_mat.albedo_color = Color(0.2, 0.5, 1.0)
	outer_mat.emission_enabled = true
	outer_mat.emission = Color(0.15, 0.4, 0.9)
	outer_mat.emission_energy_multiplier = 2.5
	outer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outer_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	outer_mesh.material = outer_mat
	_exhaust_outer.draw_pass_1 = outer_mesh
	add_child(_exhaust_outer)

	_exhaust_trail = null

func _physics_process(delta):
	if _state != State.NORMAL or frozen:
		return

	if Input.is_action_pressed("ui_up") or Input.is_physical_key_pressed(KEY_W):
		current_speed += acceleration * delta
	elif Input.is_action_pressed("ui_down") or Input.is_physical_key_pressed(KEY_S):
		current_speed -= acceleration * delta
	current_speed = clamp(current_speed, min_speed, max_speed)

	# Engine glow and exhaust scale with speed
	var speed_t := current_speed / max_speed
	if _engine_mat:
		_engine_mat.albedo_color = Color(
			lerpf(0.05, 0.9, speed_t),
			lerpf(0.05, 0.15, speed_t),
			lerpf(0.05, 0.05, speed_t)
		)
		_engine_mat.emission_energy_multiplier = lerpf(0.0, 5.0, speed_t)
		_engine_mat.emission = Color(
			lerpf(0.0, 0.8, speed_t),
			lerpf(0.0, 0.1, speed_t),
			lerpf(0.0, 0.05, speed_t)
		)
	var has_thrust := speed_t > 0.05
	if _exhaust_core:
		_exhaust_core.emitting = has_thrust
		var pm: ParticleProcessMaterial = _exhaust_core.process_material
		pm.initial_velocity_min = lerpf(1.0, 4.0, speed_t)
		pm.initial_velocity_max = lerpf(2.0, 6.0, speed_t)
		_exhaust_core.amount = int(lerpf(15, 45, speed_t))
		_exhaust_core.lifetime = lerpf(0.03, 0.07, speed_t)
	if _exhaust_outer:
		_exhaust_outer.emitting = has_thrust
		var pm2: ParticleProcessMaterial = _exhaust_outer.process_material
		pm2.initial_velocity_min = lerpf(0.8, 3.0, speed_t)
		pm2.initial_velocity_max = lerpf(1.5, 4.5, speed_t)
		pm2.spread = lerpf(25.0, 40.0, speed_t)
		_exhaust_outer.amount = int(lerpf(12, 35, speed_t))
		_exhaust_outer.lifetime = lerpf(0.04, 0.09, speed_t)

	var vel := Vector3(0, 0, -current_speed)

	# Lateral input
	var lateral_input := 0.0
	var dir := 0.0
	if Input.is_action_pressed("ui_left") or Input.is_physical_key_pressed(KEY_A):
		dir = -1.0
	elif Input.is_action_pressed("ui_right") or Input.is_physical_key_pressed(KEY_D):
		dir = 1.0

	if GameState.classical_mode:
		var effective_lateral := dir * lateral_speed * (0.25 + 0.35 * speed_t)
		if _jump_airborne:
			vel.x = _locked_lateral
		else:
			vel.x = effective_lateral
		lateral_input = effective_lateral
	else:
		lateral_input = dir * lateral_speed
		vel.x = lateral_input

	if is_on_floor():
		_last_floor_y = global_position.y
		if not _was_on_floor and _vertical_velocity < -1.0:
			var impact := absf(_vertical_velocity)
			_vertical_velocity = impact * bounce_factor
			_jump_airborne = false
			_can_jump = true
			# Bongo-like landing thud — only for significant impacts
			if impact > 2.0 and GameState.sfx_enabled:
				var freq := lerpf(60, 120, clampf(impact / 15.0, 0.0, 1.0))
				var vol := clampf(impact / 12.0, 0.3, 0.8)
				_land_player.stream = _generate_sound(freq, freq * 0.25, 0.15, vol)
				_land_player.play()
		else:
			_vertical_velocity = 0
			_bounce_count = 0
			_jump_airborne = false
			_can_jump = true
	else:
		_vertical_velocity -= gravity * delta
	var can_jump_now: bool
	if GameState.classical_mode:
		var near_floor := is_on_floor() or (global_position.y < _last_floor_y + 0.4 and _vertical_velocity < 0)
		can_jump_now = _can_jump or near_floor
	else:
		can_jump_now = is_on_floor() or (global_position.y < _last_floor_y + 0.55 and _vertical_velocity > -2.5)
	if Input.is_action_just_pressed("ui_accept") and can_jump_now:
		_vertical_velocity = jump_velocity
		_can_jump = false
		if GameState.classical_mode:
			_jump_airborne = true
			_locked_lateral = lateral_input
	_was_on_floor = is_on_floor()

	vel.y = _vertical_velocity
	velocity = vel
	var pre_slide_vel := vel
	move_and_slide()

	# Wall collision — only head-on (forward into wall) destroys ship
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var normal := col.get_normal()
		var collider := col.get_collider()
		var forward_impact := absf(pre_slide_vel.z * normal.z)
		# Tunnel walls: nudge sideways on side contact, explode only on forward hit
		if collider and collider.has_meta("tunnel_wall"):
			if forward_impact > 8.0 and absf(normal.z) > 0.3:
				start_explosion()
				return
			if absf(normal.x) > 0.2:
				global_position.x += normal.x * 1.0
			continue
		# Regular wall: only forward collision into a Z-facing wall
		if normal.y < 0.5 and normal.z > 0.5 and forward_impact > 5.0:
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
	if _exhaust_core:
		_exhaust_core.emitting = false
	if _exhaust_outer:
		_exhaust_outer.emitting = false
	if _exhaust_trail:
		_exhaust_trail.emitting = false

	# Reparent ship parts to scene and fling them
	var scene_root := get_parent()
	for part in _ship_parts:
		var world_pos := part.global_position
		var world_rot := part.global_rotation
		remove_child(part)
		scene_root.add_child(part)
		part.global_position = world_pos
		part.global_rotation = world_rot
		_debris.append(part)

		var rng_vel := Vector3(
			randf_range(-4, 4),
			randf_range(2, 8),
			randf_range(-3, 3)
		)
		var rng_rot := Vector3(
			randf_range(-10, 10),
			randf_range(-10, 10),
			randf_range(-10, 10)
		)

		var tween := part.create_tween()
		tween.set_parallel(true)
		tween.tween_property(part, "position", world_pos + rng_vel, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(part, "position:y", world_pos.y - 5, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN).set_delay(0.3)
		tween.tween_property(part, "rotation", world_rot + rng_rot, 1.2)
		tween.tween_property(part, "scale", Vector3.ZERO, 0.4).set_delay(0.8)

	visible = false
	var timer := get_tree().create_timer(1.5)
	timer.timeout.connect(func(): exploded.emit())

func reset_ship():
	_state = State.NORMAL
	visible = true
	scale = Vector3.ONE
	global_position = _start_position
	_vertical_velocity = 0
	_was_on_floor = true
	_jump_airborne = false
	_locked_lateral = 0.0
	_can_jump = true
	current_speed = 12.0
	if _warp_trail:
		_warp_trail.queue_free()
		_warp_trail = null
	# Clean up debris and rebuild ship
	for d in _debris:
		if is_instance_valid(d):
			d.queue_free()
	_debris.clear()
	_ship_parts.clear()
	_build_ship_mesh()
