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
var _jump_airborne := false
var _locked_lateral := 0.0
var _can_jump := true
var _start_position: Vector3
var _state := State.NORMAL
var _warp_trail: MeshInstance3D
var _land_player: AudioStreamPlayer3D
var _ship_parts: Array[MeshInstance3D] = []
var _debris: Array[Node3D] = []
var _engine_mat: StandardMaterial3D
var _exhaust: ShipExhaust

const LAND_SOUND_VARIANTS := 5
static var _land_sounds: Array[AudioStreamWAV] = []

func _ready():
	_start_position = global_position
	_build_ship_mesh()
	_land_player = _create_sfx_player()
	add_child(_land_player)
	if _land_sounds.is_empty():
		for i in LAND_SOUND_VARIANTS:
			var freq := lerpf(60.0, 120.0, float(i) / float(LAND_SOUND_VARIANTS - 1))
			_land_sounds.append(_generate_sound(freq, freq * 0.25, 0.15))

func _create_sfx_player() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.max_distance = 100.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	return p

func _generate_sound(start_freq: float, end_freq: float, duration: float) -> AudioStreamWAV:
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
		var sample := sin(phase * TAU) * envelope
		var val := int(clampf(sample, -1.0, 1.0) * 32767)
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	return stream

func _part(mesh: Mesh, pos: Vector3, rot_deg := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	m.rotation_degrees = rot_deg
	m.scale = scl
	add_child(m)
	_ship_parts.append(m)
	return m

func _build_ship_mesh():
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.72, 0.12, 0.12)
	body_mat.metallic = 0.35
	body_mat.roughness = 0.45

	var accent_mat := StandardMaterial3D.new()
	accent_mat.albedo_color = Color(0.85, 0.85, 0.9)
	accent_mat.metallic = 0.5
	accent_mat.roughness = 0.35

	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.16, 0.16, 0.2)
	dark_mat.metallic = 0.6
	dark_mat.roughness = 0.5

	var canopy_mat := StandardMaterial3D.new()
	canopy_mat.albedo_color = Color(0.2, 0.45, 0.6)
	canopy_mat.metallic = 0.8
	canopy_mat.roughness = 0.15
	canopy_mat.emission_enabled = true
	canopy_mat.emission = Color(0.1, 0.3, 0.45)
	canopy_mat.emission_energy_multiplier = 0.6

	_engine_mat = StandardMaterial3D.new()
	_engine_mat.albedo_color = Color(0.05, 0.05, 0.05)
	_engine_mat.emission_enabled = true
	_engine_mat.emission = Color(0, 0, 0)
	_engine_mat.emission_energy_multiplier = 0.0

	_ship_parts.clear()

	# Fuselage: flattened capsule, wide and low
	var hull := CapsuleMesh.new()
	hull.radius = 0.16
	hull.height = 1.05
	hull.material = body_mat
	_part(hull, Vector3(0, 0, 0.02), Vector3(90, 0, 0), Vector3(1.5, 1.0, 0.75))

	# Nose cone
	var nose := CylinderMesh.new()
	nose.top_radius = 0.0
	nose.bottom_radius = 0.13
	nose.height = 0.38
	nose.radial_segments = 12
	nose.material = accent_mat
	_part(nose, Vector3(0, -0.01, -0.62), Vector3(-90, 0, 0), Vector3(1.5, 1.0, 0.7))

	# Cockpit canopy
	var canopy := SphereMesh.new()
	canopy.radius = 0.11
	canopy.height = 0.22
	canopy.material = canopy_mat
	_part(canopy, Vector3(0, 0.12, -0.16), Vector3.ZERO, Vector3(1.1, 0.7, 1.7))

	# Swept wings with tip fins
	var wing := BoxMesh.new()
	wing.size = Vector3(0.5, 0.045, 0.34)
	wing.material = body_mat
	_part(wing, Vector3(-0.42, -0.03, 0.16), Vector3(0, -18, -4))
	_part(wing, Vector3(0.42, -0.03, 0.16), Vector3(0, 18, 4))
	var fin := BoxMesh.new()
	fin.size = Vector3(0.045, 0.15, 0.22)
	fin.material = accent_mat
	_part(fin, Vector3(-0.62, 0.03, 0.24), Vector3(0, -18, 0))
	_part(fin, Vector3(0.62, 0.03, 0.24), Vector3(0, 18, 0))

	# Twin engine pods with glow nozzles
	var pod := CylinderMesh.new()
	pod.top_radius = 0.085
	pod.bottom_radius = 0.07
	pod.height = 0.45
	pod.radial_segments = 10
	pod.material = dark_mat
	_part(pod, Vector3(-0.24, -0.02, 0.36), Vector3(90, 0, 0))
	_part(pod, Vector3(0.24, -0.02, 0.36), Vector3(90, 0, 0))
	var nozzle := CylinderMesh.new()
	nozzle.top_radius = 0.062
	nozzle.bottom_radius = 0.062
	nozzle.height = 0.05
	nozzle.radial_segments = 10
	nozzle.material = _engine_mat
	_part(nozzle, Vector3(-0.24, -0.02, 0.6), Vector3(90, 0, 0))
	_part(nozzle, Vector3(0.24, -0.02, 0.6), Vector3(90, 0, 0))

	# Dorsal fin, apex leaning back
	var dfin := PrismMesh.new()
	dfin.size = Vector3(0.34, 0.2, 0.04)
	dfin.left_to_right = 0.8
	dfin.material = body_mat
	_part(dfin, Vector3(0, 0.17, 0.3), Vector3(0, -90, 0))

	if _exhaust:
		_exhaust.queue_free()
	_exhaust = ShipExhaust.new()
	add_child(_exhaust)

func _physics_process(delta):
	if _state != State.NORMAL or frozen:
		return

	var input_dir := 0.0
	var input_jump := false
	if GameState.autopilot:
		var ap := _compute_autopilot()
		input_dir = ap.dir
		input_jump = ap.jump
		if current_speed < ap.target_speed - 1.0:
			current_speed += acceleration * delta
		elif current_speed > ap.target_speed + 1.0:
			current_speed -= acceleration * delta
	else:
		if Input.is_action_pressed("ui_up") or Input.is_physical_key_pressed(KEY_W):
			current_speed += acceleration * delta
		elif Input.is_action_pressed("ui_down") or Input.is_physical_key_pressed(KEY_S):
			current_speed -= acceleration * delta
		if Input.is_action_pressed("ui_left") or Input.is_physical_key_pressed(KEY_A):
			input_dir = -1.0
		elif Input.is_action_pressed("ui_right") or Input.is_physical_key_pressed(KEY_D):
			input_dir = 1.0
		input_jump = Input.is_action_just_pressed("ui_accept")
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
	if _exhaust:
		_exhaust.update(speed_t)

	var vel := Vector3(0, 0, -current_speed)

	# Lateral input
	var lateral_input := 0.0
	var dir := input_dir

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
				PerfMonitor.mark("land_sfx")
				var t := clampf(impact / 15.0, 0.0, 1.0)
				var vol := clampf(impact / 12.0, 0.3, 0.8)
				_land_player.stream = _land_sounds[roundi(t * (LAND_SOUND_VARIANTS - 1))]
				_land_player.volume_db = linear_to_db(vol)
				_land_player.play()
		else:
			_vertical_velocity = 0
			_jump_airborne = false
			_can_jump = true
	else:
		_vertical_velocity -= gravity * delta
	var near_floor: bool
	if GameState.classical_mode:
		# vy floor expires the window shortly into a fall - without it, y
		# stays below last_floor forever and jump-hammering flies over gaps
		near_floor = is_on_floor() or (global_position.y < _last_floor_y + 0.4 and _vertical_velocity < 0 and _vertical_velocity > -2.5)
	else:
		near_floor = is_on_floor() or (global_position.y < _last_floor_y + 0.55 and _vertical_velocity > -2.5)
	# The banked jump expires with the coyote window - matches the physics
	# solve_level.py proves (strict mode); without this, driving off a ledge
	# banks one air-jump usable at any depth mid-fall
	if not is_on_floor() and not near_floor:
		_can_jump = false
	var can_jump_now := _can_jump or near_floor
	if input_jump and can_jump_now:
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
				if GameState.autopilot:
					var row := int(-global_position.z / 2.0)
					print("[AP CRASH] tunnel wall | pos=(%.1f, %.1f, %.1f) row=%d col=%.1f speed=%.0f impact=%.1f" % [global_position.x, global_position.y, global_position.z, row, global_position.x / 2.0, current_speed, forward_impact])
				start_explosion()
				return
			if absf(normal.x) > 0.2:
				global_position.x += normal.x * 1.0
			continue
		# Regular wall: only forward collision into a Z-facing wall
		if normal.y < 0.5 and normal.z > 0.5 and forward_impact > 5.0:
			if GameState.autopilot:
				var row := int(-global_position.z / 2.0)
				print("[AP CRASH] wall | pos=(%.1f, %.1f, %.1f) row=%d col=%.1f speed=%.0f normal=%s impact=%.1f" % [global_position.x, global_position.y, global_position.z, row, global_position.x / 2.0, current_speed, normal, forward_impact])
			start_explosion()
			return

	if global_position.y < -10:
		if GameState.autopilot:
			var row := int(-global_position.z / 2.0)
			print("[AP CRASH] fell | pos=(%.1f, %.1f, %.1f) row=%d col=%.1f speed=%.0f" % [global_position.x, global_position.y, global_position.z, row, global_position.x / 2.0, current_speed])
		start_explosion()

func start_warp():
	if _state != State.NORMAL:
		return
	_state = State.WARPING
	PerfMonitor.mark("warp")

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

	var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
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
	PerfMonitor.mark("explosion")
	velocity = Vector3.ZERO
	if _exhaust:
		_exhaust.shut_down()

	# Reparent ship parts to scene and fling them
	var scene_root := get_parent()
	for part in _ship_parts:
		var world_pos := part.global_position
		var world_rot := part.global_rotation
		remove_child(part)
		scene_root.add_child(part)
		part.global_position = world_pos
		part.global_rotation = world_rot
		part.reset_physics_interpolation()
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

		var tween := part.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		tween.set_parallel(true)
		tween.tween_property(part, "position", world_pos + rng_vel, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(part, "position:y", world_pos.y - 5, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN).set_delay(0.3)
		tween.tween_property(part, "rotation", world_rot + rng_rot, 1.2)
		tween.tween_property(part, "scale", Vector3.ZERO, 0.4).set_delay(0.8)

	visible = false
	var timer := get_tree().create_timer(1.5)
	timer.timeout.connect(func(): exploded.emit())

func reset_ship():
	PerfMonitor.mark("ship_reset")
	_state = State.NORMAL
	visible = true
	scale = Vector3.ONE
	global_position = _start_position
	reset_physics_interpolation()
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

func _compute_autopilot() -> Dictionary:
	var game = get_parent()
	return Autopilot.compute(game._grid, game._tunnels, game._cols,
		global_position, current_speed, max_speed, lateral_speed,
		is_on_floor(), _can_jump, _vertical_velocity,
		2.0 * jump_velocity / gravity, game._row_base)
