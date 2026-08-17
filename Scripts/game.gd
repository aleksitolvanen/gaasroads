extends Node3D

var level_path: String

const TILE_SIZE := 2.0
const TILE_HEIGHT := 0.5

const _FALLBACK_LEVEL := [
	"1.1.1.1.1.1.1.1.1.1.", "1.1.1.1.1.1.1.1.1.1.",
	"1.1.1.1.1.1.1.1.1.1.", "1.1.1.1.1.1.1.1.1.1.",
	"1.1.1.1.1.1.1.1.1.1.", "1.1.1.1.1.1.1.1.1.1.",
	"1.1.1.........1.1.1.", "1.1.1.........1.1.1.",
	"1.1.1.1.1.1.1.1.1.1.", "1.1.1.1.1.1.1.1.1.1.",
	"1.................1.", "1.................1.",
	"1.1.1.1.1.1.1.1.1.1.", "1.1.1.1.1.1.1.1.1.1.",
	"1.1.1.1.1.1.1.1.1.1.", "1.1.1.1.1.1.1.1.1.1.",
	"1T1T1T1T1T1T1T1T1T1T", "1T1T1T1T1T1T1T1T1T1T",
	"1.1.1.1.1.1.1.1.1.1.", "1.1.1.1.1.1.1.1.1.1.",
	"2.2.2.2.2.2.2.2.2.2.", "2.2.2.2.2.2.2.2.2.2.",
	"1.1.1.1.1.1.1.1.1.1.", "1.1.1.1.1.1.1.1.1.1.",
	"1.1.1.1.1.1.1.1.1.1.", "1.1.1.1.1.1.1.1.1.1.",
]

var _camera: Camera3D
var _ship: CharacterBody3D
var _bg_quad: MeshInstance3D
var _speed_gauge: ProgressBar
var _speed_label: Label
var _hud_canvas: CanvasLayer
var _level_end_z := -1000.0
var _env_end_z := -1000.0
# Wormhole theme: every tunnel transit flashes and re-tints the world
const WORM_PALETTE := [
	Color(0.7, 0.4, 1.0), Color(0.3, 0.9, 1.0), Color(1.0, 0.75, 0.35),
	Color(0.4, 1.0, 0.6), Color(1.0, 0.4, 0.7),
]
var _in_portal := false
var _portal_hops := 0
var _wormhole_fill: DirectionalLight3D
var _finishing := false
var _laser_timer := 0.0
var _laser_rng := RandomNumberGenerator.new()
var _mothership_active := false
var _fighters: Array[Node3D] = []
var _green_laser_mat: StandardMaterial3D
var _red_laser_mat: StandardMaterial3D
var _laser_mesh: BoxMesh
var _timer_label: Label
var _share_panel: Control
var _share_text: LineEdit
var _timer_running := false
var _share_open := false
var _level_content := ""
var _grid: Array[Array] = []
var _tunnels: Array[Array] = []
# Endless mode trims passed rows off _grid/_tunnels; _row_base is the
# absolute row index of _grid[0]
var _row_base := 0
var _cols := 10
var _build_queue: Array = []
var _build_next := 0
var _level_ready := false
var _build_start_msec := 0
var _ready_label: Label
var _height_materials: Dictionary = {}
var _tunnel_wall_mat: StandardMaterial3D
var _spawned_track: Array = []
var _cleanup_tick := 0
var _chunk_state := {}
var _warmup: Node3D
var _smooth_frames := 0

const READY_DELAY_MSEC := 600
const READY_TIMEOUT_MSEC := 6000

func _ready():
	level_path = GameState.selected_level
	_ship = $Ship
	_ship.current_speed = 12.0
	_ship.warped.connect(_on_ship_warped)
	_ship.exploded.connect(_on_ship_exploded)

	var grp := clampi(GameState.selected_group, 0, LevelGenerator.GROUP_GRAVITY.size() - 1)
	_ship.gravity = LevelGenerator.GROUP_GRAVITY[grp]
	_ship.jump_velocity = LevelGenerator.GROUP_JUMP_VELOCITY[grp]
	_camera = $Camera3D
	# Run after the ship's physics tick so the camera follows its fresh position
	process_physics_priority = 1
	GameState.elapsed_time = 0.0
	_timer_running = false
	_create_hud()
	_init_track_materials()
	_create_shader_warmup()
	# Load first: the backgrounds size themselves from _level_end_z
	_load_level()
	_create_space_environment()
	Music.play_for_group(GameState.selected_group)

func _process(delta):
	if _share_open:
		return
	# Frame-time settle detector: on WebGL the first round of a session spends
	# its first seconds draining the shader-compile queue, stalling frames.
	# GET READY stays up until frames are smooth again.
	if delta < 0.025:
		_smooth_frames += 1
	else:
		_smooth_frames = 0
	_process_build_queue()
	if Input.is_action_just_pressed("ui_cancel") or Input.is_physical_key_pressed(KEY_Q):
		get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")
		return

	var ship_pos := _ship.global_position

	if _mothership_active and not _finishing:
		_laser_timer -= delta
		if _laser_timer <= 0:
			_laser_timer = _laser_rng.randf_range(0.08, 0.25)
			_spawn_laser(ship_pos)

	if not GameState.is_endless and not _finishing and ship_pos.z < _level_end_z - 5.0:
		_finishing = true
		_ship.start_warp()
		_create_warp_streaks()

	_speed_gauge.value = _ship.current_speed
	_speed_label.text = "%d" % _ship.current_speed

	# Timer
	if not _timer_running and _level_ready and _ship.current_speed > 0 and not _finishing:
		_timer_running = true
	if _timer_running and not _finishing:
		GameState.elapsed_time += delta
	if _timer_label:
		if GameState.is_endless:
			var dist := int(absf(ship_pos.z))
			_timer_label.text = "%dm" % dist
		else:
			_timer_label.text = GameState.format_time(GameState.elapsed_time) if GameState.elapsed_time > 0.0 else "0:00.00"

	# Endless mode: generate ahead (one segment per frame), free track far behind
	if GameState.is_endless and _level_ready:
		if not _chunk_state.is_empty():
			var t0 := Time.get_ticks_usec()
			var new_rows := LevelGenerator.chunk_next(_chunk_state)
			if new_rows.size() > 0:
				_enqueue_rows(PackedStringArray(new_rows))
			if _chunk_state.done:
				_chunk_state = {}
			PerfMonitor.mark("chunk_seg %d rows %dus" % [new_rows.size(), Time.get_ticks_usec() - t0])
		elif ship_pos.z - _level_end_z < 600:
			var params: Dictionary = GameState.endless_params.duplicate()
			params["seed"] = randi()
			params["length"] = 200
			# endless ramps up with distance survived
			params["diff_boost"] = clampf(float(_row_base + _grid.size()) / 2500.0, 0.0, 0.3)
			_chunk_state = LevelGenerator.chunk_begin(params)
		_cleanup_tick += 1
		if _cleanup_tick >= 30:
			_cleanup_tick = 0
			_free_passed_track(ship_pos.z)

	# Wormhole: crossing a bore is a portal transit - flash on both mouths,
	# and each exit re-tints the world so you come out "somewhere else"
	if GameState.selected_group == 7 and _level_ready and not _finishing:
		var prow := int(-ship_pos.z / TILE_SIZE) - _row_base
		var pcol := clampi(roundi(ship_pos.x / TILE_SIZE), 0, _cols - 1)
		var inside: bool = prow >= 0 and prow < _tunnels.size() and _tunnels[prow][pcol]
		if inside != _in_portal:
			_in_portal = inside
			if inside:
				_portal_swap(prow, pcol)
			_portal_transit(inside)

func _physics_process(_delta):
	if _share_open:
		return
	var ship_pos := _ship.global_position

	if _mothership_active and not _finishing:
		_update_fighters(ship_pos)

	if not _finishing:
		_camera.global_position = Vector3(ship_pos.x, ship_pos.y + 2.5, ship_pos.z + 4.2)
		_camera.look_at(ship_pos + Vector3(0, -1.5, -6), Vector3.UP)
	else:
		# Camera stays put, looks at the ship as it flies up and away
		_camera.look_at(ship_pos, Vector3.UP)

	if _bg_quad:
		_bg_quad.global_position = Vector3(ship_pos.x, ship_pos.y - 20, ship_pos.z - 120)

func _create_hud():
	var canvas := CanvasLayer.new()
	_hud_canvas = canvas
	add_child(canvas)

	if GameState.cockpit_texture:
		var cockpit_rect := TextureRect.new()
		cockpit_rect.texture = GameState.cockpit_texture
		cockpit_rect.anchor_left = 0
		cockpit_rect.anchor_top = 0
		cockpit_rect.anchor_right = 1
		cockpit_rect.anchor_bottom = 1
		cockpit_rect.offset_left = 0
		cockpit_rect.offset_top = 0
		cockpit_rect.offset_right = 0
		cockpit_rect.offset_bottom = 0
		cockpit_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cockpit_rect.stretch_mode = TextureRect.STRETCH_SCALE
		cockpit_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		canvas.add_child(cockpit_rect)

	var gauge_container := Control.new()
	gauge_container.anchor_left = 0.5
	gauge_container.anchor_right = 0.5
	gauge_container.anchor_top = 1
	gauge_container.anchor_bottom = 1
	gauge_container.offset_left = -80
	gauge_container.offset_right = 80
	gauge_container.offset_top = -55
	gauge_container.offset_bottom = -15
	canvas.add_child(gauge_container)

	var speed_title := Label.new()
	speed_title.text = "SPEED"
	speed_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speed_title.anchor_right = 1
	speed_title.offset_bottom = 18
	speed_title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	speed_title.add_theme_font_size_override("font_size", 12)
	gauge_container.add_child(speed_title)

	_speed_gauge = ProgressBar.new()
	_speed_gauge.min_value = 0
	_speed_gauge.max_value = 30
	_speed_gauge.value = 12
	_speed_gauge.show_percentage = false
	_speed_gauge.anchor_left = 0
	_speed_gauge.anchor_right = 1
	_speed_gauge.offset_top = 18
	_speed_gauge.offset_bottom = 32
	var gauge_bg := StyleBoxFlat.new()
	gauge_bg.bg_color = Color(0.05, 0.05, 0.15)
	gauge_bg.corner_radius_bottom_left = 2
	gauge_bg.corner_radius_bottom_right = 2
	gauge_bg.corner_radius_top_left = 2
	gauge_bg.corner_radius_top_right = 2
	_speed_gauge.add_theme_stylebox_override("background", gauge_bg)
	var gauge_fill := StyleBoxFlat.new()
	gauge_fill.bg_color = Color(0.2, 0.6, 1.0)
	gauge_fill.corner_radius_bottom_left = 2
	gauge_fill.corner_radius_bottom_right = 2
	gauge_fill.corner_radius_top_left = 2
	gauge_fill.corner_radius_top_right = 2
	_speed_gauge.add_theme_stylebox_override("fill", gauge_fill)
	gauge_container.add_child(_speed_gauge)

	_speed_label = Label.new()
	_speed_label.text = "12"
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_label.anchor_right = 1
	_speed_label.offset_top = 32
	_speed_label.offset_bottom = 50
	_speed_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	_speed_label.add_theme_font_size_override("font_size", 14)
	gauge_container.add_child(_speed_label)

	# Share hint
	var share_hint := Label.new()
	share_hint.text = "C: share track | P: autopilot"
	share_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	share_hint.anchor_left = 0
	share_hint.anchor_top = 0
	share_hint.offset_left = 10
	share_hint.offset_top = 10
	share_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55, 0.5))
	share_hint.add_theme_font_size_override("font_size", 11)
	canvas.add_child(share_hint)

	# Timer display
	_timer_label = Label.new()
	_timer_label.text = "0:00.00"
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.anchor_left = 0.5
	_timer_label.anchor_right = 0.5
	_timer_label.offset_left = -60
	_timer_label.offset_right = 60
	_timer_label.offset_top = -72
	_timer_label.offset_bottom = -55
	_timer_label.anchor_top = 1
	_timer_label.anchor_bottom = 1
	_timer_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85, 0.8))
	_timer_label.add_theme_font_size_override("font_size", 14)
	canvas.add_child(_timer_label)

	# Shown while the track is being built
	_ready_label = Label.new()
	_ready_label.text = "GET READY"
	_ready_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ready_label.anchor_left = 0
	_ready_label.anchor_right = 1
	_ready_label.anchor_top = 0.35
	_ready_label.anchor_bottom = 0.35
	_ready_label.offset_bottom = 44
	_ready_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	_ready_label.add_theme_font_size_override("font_size", 32)
	_ready_label.visible = false
	canvas.add_child(_ready_label)

func _create_space_environment():
	# Endless tracks keep extending, so give them a deep decoration horizon
	_env_end_z = minf(_level_end_z, -2500.0) if GameState.is_endless else _level_end_z
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	match GameState.selected_group:
		2:  # Solar - very dark ambient, sun does the work
			env.ambient_light_color = Color(0.08, 0.06, 0.04)
			env.ambient_light_energy = 0.35
		1:  # Nebula
			env.ambient_light_color = Color(0.12, 0.08, 0.15)
			env.ambient_light_energy = 0.45
		3:  # Dark Matter
			env.ambient_light_color = Color(0.06, 0.1, 0.08)
			env.ambient_light_energy = 0.28
		4:  # The Grid
			env.ambient_light_color = Color(0.05, 0.10, 0.13)
			env.ambient_light_energy = 0.35
		5:  # The Graveyard
			env.ambient_light_color = Color(0.1, 0.08, 0.07)
			env.ambient_light_energy = 0.4
		6:  # The Bloom
			env.ambient_light_color = Color(0.07, 0.12, 0.1)
			env.ambient_light_energy = 0.4
		7:  # Wormhole
			env.ambient_light_color = Color(0.09, 0.07, 0.14)
			env.ambient_light_energy = 0.4
		_:  # Cosmic Highway
			env.ambient_light_color = Color(0.08, 0.08, 0.12)
			env.ambient_light_energy = 0.45

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	var light_target := Vector3(5, 2, -50)
	match GameState.selected_group:
		1:  # Nebula - light from accretion ring at (4, 15, -350)
			sun.basis = Basis.looking_at((light_target - Vector3(4, 15, -350)).normalized())
			sun.light_color = Color(1.0, 0.6, 0.3)
			sun.light_energy = 1.4
		2:  # Solar - bright harsh sunlight from (-80, 55, -300)
			sun.basis = Basis.looking_at((light_target - Vector3(-120, 80, -600)).normalized())
			sun.light_color = Color(1.0, 0.85, 0.4)
			sun.light_energy = 2.0
		3:  # Dark Matter - eerie green from mothership at (30, 18, -350)
			sun.basis = Basis.looking_at((light_target - Vector3(30, 18, -350)).normalized())
			sun.light_color = Color(0.4, 0.8, 0.5)
			sun.light_energy = 1.0
		4:  # The Grid - cold datalight from the portal side
			sun.basis = Basis.looking_at((light_target - Vector3(-40, 55, -240)).normalized())
			sun.light_color = Color(0.6, 0.9, 1.0)
			sun.light_energy = 1.4
		5:  # The Graveyard - pale dead-star light low on the horizon
			sun.basis = Basis.looking_at((light_target - Vector3(120, 30, -500)).normalized())
			sun.light_color = Color(0.85, 0.78, 0.68)
			sun.light_energy = 1.1
		6:  # The Bloom - warm rose glow from the mother bloom
			sun.basis = Basis.looking_at((light_target - Vector3(-20, 35, -260)).normalized())
			sun.light_color = Color(1.0, 0.72, 0.62)
			sun.light_energy = 1.3
		7:  # Wormhole - violet light falling out of the vortex ahead
			sun.basis = Basis.looking_at((light_target - Vector3(9, 40, -420)).normalized())
			sun.light_color = Color(0.7, 0.55, 1.0)
			sun.light_energy = 1.3
		_:  # Cosmic Highway - cool starlight from upper-left
			sun.basis = Basis.looking_at((light_target - Vector3(-30, 40, -200)).normalized())
			sun.light_color = Color(0.8, 0.85, 1.0)
			sun.light_energy = 1.0
	# every theme's sun sits ahead of the player, so cast shadows land on
	# the approach to a step; partial opacity keeps them readable
	sun.shadow_opacity = 0.75
	add_child(sun)

	# Shadowless fill from behind the cockpit, aimed down the track: lights
	# the front faces of steps and walls that the sun leaves black. One
	# extra directional light with no shadow map is near-free on WebGL.
	var fill := DirectionalLight3D.new()
	fill.shadow_enabled = false
	fill.basis = Basis.looking_at(Vector3(0.12, -0.3, -1.0).normalized())
	match GameState.selected_group:
		1:  # Nebula - cool violet against the orange ring light
			fill.light_color = Color(0.75, 0.6, 0.9)
			fill.light_energy = 0.36
		2:  # Solar - warm neutral, keeps the harsh sun look
			fill.light_color = Color(1.0, 0.85, 0.7)
			fill.light_energy = 0.38
		3:  # Dark Matter - pale green, kept dimmest so the theme stays murky
			fill.light_color = Color(0.55, 0.85, 0.7)
			fill.light_energy = 0.28
		4:  # The Grid - magenta counterlight against the cyan
			fill.light_color = Color(0.55, 0.25, 0.6)
			fill.light_energy = 0.3
		5:  # The Graveyard - dim rust
			fill.light_color = Color(0.42, 0.26, 0.18)
			fill.light_energy = 0.3
		6:  # The Bloom - soft moss green
			fill.light_color = Color(0.4, 0.7, 0.6)
			fill.light_energy = 0.3
		7:  # Wormhole - starts violet; every portal transit re-tints it
			fill.light_color = WORM_PALETTE[0]
			fill.light_energy = 0.34
		_:  # Cosmic Highway
			fill.light_color = Color(0.8, 0.85, 1.0)
			fill.light_energy = 0.38
	add_child(fill)
	if GameState.selected_group == 7:
		_wormhole_fill = fill

	match GameState.selected_group:
		1:
			_create_nebula_background()
		2:
			_create_solar_background()
		3:
			_create_dark_matter_background()
		4:
			_create_grid_background()
		5:
			_create_wreck_background()
		6:
			_create_bloom_background()
		7:
			_create_wormhole_background()
		_:
			_create_image_background()

func _create_image_background():
	if GameState.background_texture:
		_bg_quad = MeshInstance3D.new()
		var quad_mesh := QuadMesh.new()
		quad_mesh.size = Vector2(500, 300)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = GameState.background_texture
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		quad_mesh.material = mat
		_bg_quad.mesh = quad_mesh
		add_child(_bg_quad)

func _create_nebula_background():
	# Stars via MultiMesh
	var star_mesh := QuadMesh.new()
	star_mesh.size = Vector2(0.3, 0.3)
	var star_mat := StandardMaterial3D.new()
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.albedo_color = Color.WHITE
	star_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	star_mesh.material = star_mat

	var star_z_min := minf(-400, _env_end_z - 100)
	var star_count := maxi(1200, int(absf(star_z_min) * 2))

	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.mesh = star_mesh
	multi_mesh.instance_count = star_count

	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in star_count:
		var pos := Vector3(
			rng.randf_range(-150, 150),
			rng.randf_range(-40, 100),
			rng.randf_range(star_z_min, 50)
		)
		var s := rng.randf_range(0.1, 0.6)
		var t := Transform3D.IDENTITY.scaled(Vector3(s, s, s))
		t.origin = pos
		multi_mesh.set_instance_transform(i, t)

	var star_instance := MultiMeshInstance3D.new()
	star_instance.multimesh = multi_mesh
	add_child(star_instance)

	# Main accretion ring - see-through center
	var disk_mesh := TorusMesh.new()
	disk_mesh.inner_radius = 25.0
	disk_mesh.outer_radius = 45.0
	var disk_mat := StandardMaterial3D.new()
	disk_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disk_mat.albedo_color = Color(1.0, 0.5, 0.1)
	disk_mat.emission_enabled = true
	disk_mat.emission = Color(1.0, 0.4, 0.05)
	disk_mat.emission_energy_multiplier = 2.0
	disk_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	disk_mesh.material = disk_mat

	var disk_instance := MeshInstance3D.new()
	disk_instance.mesh = disk_mesh
	disk_instance.position = Vector3(4, 15, -350)
	disk_instance.rotation_degrees = Vector3(75, 0, 15)
	add_child(disk_instance)

	# Rings along the track to fly through
	var track_length := absf(_env_end_z)
	var ring_spacing := 250.0
	var ring_count := int(track_length / ring_spacing)

	# Particle mesh for dust around rings
	var dust_mesh := QuadMesh.new()
	dust_mesh.size = Vector2(0.4, 0.4)
	var dust_mat := StandardMaterial3D.new()
	dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_mat.albedo_color = Color(1.0, 0.7, 0.3, 0.6)
	dust_mat.emission_enabled = true
	dust_mat.emission = Color(1.0, 0.6, 0.2)
	dust_mat.emission_energy_multiplier = 2.0
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dust_mesh.material = dust_mat

	for i in ring_count:
		# Vary color per ring: orange / gold / pink / cyan
		var hue := rng.randf_range(0.02, 0.15)
		var sat := rng.randf_range(0.6, 1.0)
		var ring_color := Color.from_hsv(hue, sat, 1.0)
		var ring_emission := Color.from_hsv(hue, sat, 0.8)

		var ring_mat := StandardMaterial3D.new()
		ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring_mat.albedo_color = ring_color
		ring_mat.emission_enabled = true
		ring_mat.emission = ring_emission
		ring_mat.emission_energy_multiplier = 2.5
		ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

		var inner := rng.randf_range(18.0, 30.0)
		var outer := inner + rng.randf_range(3.0, 6.0)
		var ring_root := Node3D.new()
		ring_root.position = Vector3(
			9.0 + rng.randf_range(-5.0, 5.0),
			rng.randf_range(2.0, 7.0),
			-(i + 1) * ring_spacing + rng.randf_range(-30, 30)
		)
		ring_root.rotation_degrees = Vector3(90 + rng.randf_range(-15, 15), rng.randf_range(-20, 20), rng.randf_range(-10, 10))
		# Oblong stretch
		var stretch := rng.randf_range(0.6, 1.0)
		ring_root.scale = Vector3(1.0, stretch, 1.0) if rng.randf() < 0.5 else Vector3(stretch, 1.0, 1.0)
		add_child(ring_root)

		# Main ring
		var ring := MeshInstance3D.new()
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = inner
		ring_mesh.outer_radius = outer
		ring_mesh.material = ring_mat
		ring.mesh = ring_mesh
		ring_root.add_child(ring)

		# Inner glow ring - thinner, brighter, slightly offset
		var glow_ring := MeshInstance3D.new()
		var glow_mesh := TorusMesh.new()
		glow_mesh.inner_radius = inner - 1.0
		glow_mesh.outer_radius = inner + 0.5
		var glow_mat := StandardMaterial3D.new()
		glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow_mat.albedo_color = Color(ring_color, 0.4)
		glow_mat.emission_enabled = true
		glow_mat.emission = ring_emission
		glow_mat.emission_energy_multiplier = 4.0
		glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		glow_mesh.material = glow_mat
		glow_ring.mesh = glow_mesh
		glow_ring.rotation_degrees = Vector3(rng.randf_range(-5, 5), rng.randf_range(-5, 5), 0)
		ring_root.add_child(glow_ring)

		# Haze sphere around ring center
		var haze := MeshInstance3D.new()
		var haze_mesh := SphereMesh.new()
		var haze_r := outer * 1.2
		haze_mesh.radius = haze_r
		haze_mesh.height = haze_r * 2
		var haze_mat := StandardMaterial3D.new()
		haze_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		haze_mat.albedo_color = Color(ring_color, 0.04)
		haze_mat.emission_enabled = true
		haze_mat.emission = ring_emission
		haze_mat.emission_energy_multiplier = 0.8
		haze_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# Front faces culled: one glow layer from outside, one from inside,
		# instead of double full-screen overdraw when flying through
		haze_mat.cull_mode = BaseMaterial3D.CULL_FRONT
		haze_mesh.material = haze_mat
		haze.mesh = haze_mesh
		ring_root.add_child(haze)

		# OmniLight at ring center
		var ring_light := OmniLight3D.new()
		ring_light.light_color = ring_color
		ring_light.light_energy = 0.6
		ring_light.omni_range = outer * 1.2
		ring_light.omni_attenuation = 2.0
		ring_light.shadow_enabled = false
		ring_root.add_child(ring_light)

		# Dust particles scattered around the ring - one MultiMesh per ring,
		# same pattern as the star field (per-node quads cost a draw each)
		var dust_count := rng.randi_range(12, 25)
		var dm := QuadMesh.new()
		dm.size = Vector2(1, 1)
		dm.material = dust_mat
		var dust_mm := MultiMesh.new()
		dust_mm.transform_format = MultiMesh.TRANSFORM_3D
		dust_mm.mesh = dm
		dust_mm.instance_count = dust_count
		for j in dust_count:
			var angle := rng.randf() * TAU
			var r := rng.randf_range(inner * 0.7, outer * 1.1)
			var ds := rng.randf_range(0.3, 0.8)
			var t := Transform3D.IDENTITY.scaled(Vector3(ds, ds, ds))
			t.origin = Vector3(cos(angle) * r, sin(angle) * r, rng.randf_range(-2, 2))
			dust_mm.set_instance_transform(j, t)
		var dust := MultiMeshInstance3D.new()
		dust.multimesh = dust_mm
		ring_root.add_child(dust)

func _create_solar_background():
	# Scattered dim stars
	var star_mesh := QuadMesh.new()
	star_mesh.size = Vector2(0.2, 0.2)
	var star_mat := StandardMaterial3D.new()
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.albedo_color = Color(0.6, 0.5, 0.3)
	star_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	star_mesh.material = star_mat

	var solar_z_min := minf(-400, _env_end_z - 100)
	var solar_star_count := maxi(400, int(absf(solar_z_min) * 0.8))

	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.mesh = star_mesh
	multi_mesh.instance_count = solar_star_count

	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in solar_star_count:
		var pos := Vector3(
			rng.randf_range(-150, 150),
			rng.randf_range(-30, 100),
			rng.randf_range(solar_z_min, 50)
		)
		var s := rng.randf_range(0.1, 0.4)
		var t := Transform3D.IDENTITY.scaled(Vector3(s, s, s))
		t.origin = pos
		multi_mesh.set_instance_transform(i, t)

	var star_instance := MultiMeshInstance3D.new()
	star_instance.multimesh = multi_mesh
	add_child(star_instance)

	# Huge bright star - close and threatening
	var sun_mesh := SphereMesh.new()
	sun_mesh.radius = 90.0
	sun_mesh.height = 180.0
	var sun_mat := StandardMaterial3D.new()
	sun_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sun_mat.albedo_color = Color(1.0, 0.85, 0.4)
	sun_mat.emission_enabled = true
	sun_mat.emission = Color(1.0, 0.7, 0.2)
	sun_mat.emission_energy_multiplier = 3.0
	sun_mesh.material = sun_mat

	var sun_obj := MeshInstance3D.new()
	sun_obj.mesh = sun_mesh
	sun_obj.position = Vector3(-120, 80, -600)
	add_child(sun_obj)

	var sun_light := OmniLight3D.new()
	sun_light.position = Vector3(-120, 80, -600)
	sun_light.light_color = Color(1.0, 0.8, 0.4)
	sun_light.light_energy = 0.8
	sun_light.omni_range = 150.0
	sun_light.omni_attenuation = 1.5
	sun_light.shadow_enabled = false
	add_child(sun_light)

	# Inner corona ring - tight glow
	var corona_mesh := TorusMesh.new()
	corona_mesh.inner_radius = 88.0
	corona_mesh.outer_radius = 120.0
	var corona_mat := StandardMaterial3D.new()
	corona_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	corona_mat.albedo_color = Color(1.0, 0.6, 0.1, 0.6)
	corona_mat.emission_enabled = true
	corona_mat.emission = Color(1.0, 0.5, 0.05)
	corona_mat.emission_energy_multiplier = 2.5
	corona_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	corona_mesh.material = corona_mat

	var corona := MeshInstance3D.new()
	corona.mesh = corona_mesh
	corona.position = Vector3(-120, 80, -600)
	corona.rotation_degrees = Vector3(rng.randf_range(-20, 20), rng.randf_range(-10, 10), 0)
	add_child(corona)

	# Outer haze - big soft glow
	var haze_mesh := SphereMesh.new()
	haze_mesh.radius = 140.0
	haze_mesh.height = 280.0
	var haze_mat := StandardMaterial3D.new()
	haze_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	haze_mat.albedo_color = Color(1.0, 0.5, 0.1, 0.12)
	haze_mat.emission_enabled = true
	haze_mat.emission = Color(1.0, 0.4, 0.05)
	haze_mat.emission_energy_multiplier = 1.5
	haze_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	haze_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	haze_mesh.material = haze_mat

	var haze := MeshInstance3D.new()
	haze.mesh = haze_mesh
	haze.position = Vector3(-120, 80, -600)
	add_child(haze)

func _create_dark_matter_background():
	_mothership_active = true
	_laser_rng.seed = 88
	_laser_timer = 1.0

	# Pre-create laser materials
	_green_laser_mat = StandardMaterial3D.new()
	_green_laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_green_laser_mat.albedo_color = Color(0.2, 1.0, 0.4)
	_green_laser_mat.emission_enabled = true
	_green_laser_mat.emission = Color(0.1, 0.9, 0.3)
	_green_laser_mat.emission_energy_multiplier = 4.0

	_red_laser_mat = StandardMaterial3D.new()
	_red_laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_red_laser_mat.albedo_color = Color(1.0, 0.2, 0.1)
	_red_laser_mat.emission_enabled = true
	_red_laser_mat.emission = Color(0.9, 0.1, 0.05)
	_red_laser_mat.emission_energy_multiplier = 4.0

	_laser_mesh = BoxMesh.new()
	_laser_mesh.size = Vector3(0.15, 0.15, 15.0)

	var rng := RandomNumberGenerator.new()
	rng.seed = 66

	# Sparse tinted stars - faint purple/green hues
	var star_mesh := QuadMesh.new()
	star_mesh.size = Vector2(0.2, 0.2)
	var star_mat := StandardMaterial3D.new()
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.albedo_color = Color(0.5, 0.4, 0.6)
	star_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	star_mesh.material = star_mat

	var dark_z_min := minf(-500, _env_end_z - 100)
	var dark_star_count := maxi(500, int(absf(dark_z_min)))

	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.mesh = star_mesh
	multi_mesh.instance_count = dark_star_count

	for i in dark_star_count:
		var pos := Vector3(
			rng.randf_range(-200, 200),
			rng.randf_range(-50, 120),
			rng.randf_range(dark_z_min, 50)
		)
		var s := rng.randf_range(0.05, 0.4)
		var t := Transform3D.IDENTITY.scaled(Vector3(s, s, s))
		t.origin = pos
		multi_mesh.set_instance_transform(i, t)

	var star_instance := MultiMeshInstance3D.new()
	star_instance.multimesh = multi_mesh
	add_child(star_instance)

	# --- Giant alien mothership ---
	var hull_mat := StandardMaterial3D.new()
	hull_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hull_mat.albedo_color = Color(0.18, 0.16, 0.22)
	hull_mat.emission_enabled = true
	hull_mat.emission = Color(0.07, 0.05, 0.1)
	hull_mat.emission_energy_multiplier = 1.0

	var glow_mat := StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.albedo_color = Color(0.3, 0.8, 0.5)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(0.2, 0.9, 0.4)
	glow_mat.emission_energy_multiplier = 3.0

	var red_glow_mat := StandardMaterial3D.new()
	red_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red_glow_mat.albedo_color = Color(0.8, 0.15, 0.1)
	red_glow_mat.emission_enabled = true
	red_glow_mat.emission = Color(0.9, 0.1, 0.05)
	red_glow_mat.emission_energy_multiplier = 2.5

	# Spawn mothership groups along the track
	var track_length := absf(_env_end_z)
	var fleet_spacing := 400.0
	var fleet_count := maxi(1, int(track_length / fleet_spacing))

	for fi in fleet_count:
		var fleet_z := -200.0 - fi * fleet_spacing
		var fleet_x := rng.randf_range(-50, 50)
		var fleet_y := rng.randf_range(15, 30)

		var ship_root := Node3D.new()
		ship_root.position = Vector3(fleet_x, fleet_y, fleet_z)
		ship_root.rotation_degrees = Vector3(rng.randf_range(-5, 8), rng.randf_range(-35, -15), rng.randf_range(-10, 10))
		add_child(ship_root)

		var mothership_light := OmniLight3D.new()
		mothership_light.position = Vector3(fleet_x, fleet_y, fleet_z)
		mothership_light.light_color = Color(0.3, 0.9, 0.5)
		mothership_light.light_energy = 0.6
		mothership_light.omni_range = 100.0
		mothership_light.omni_attenuation = 2.0
		mothership_light.shadow_enabled = false
		add_child(mothership_light)

		_build_mothership(ship_root, hull_mat, glow_mat, red_glow_mat, rng)

	# Distant nebula wisps for depth
	var wisp_mat := StandardMaterial3D.new()
	wisp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wisp_mat.albedo_color = Color(0.12, 0.06, 0.18, 0.07)
	wisp_mat.emission_enabled = true
	wisp_mat.emission = Color(0.08, 0.03, 0.12)
	wisp_mat.emission_energy_multiplier = 0.8
	wisp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wisp_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	for i in 4:
		var wisp := MeshInstance3D.new()
		var wisp_mesh := QuadMesh.new()
		wisp_mesh.size = Vector2(rng.randf_range(80, 150), rng.randf_range(40, 80))
		wisp_mesh.material = wisp_mat
		wisp.mesh = wisp_mesh
		wisp.position = Vector3(
			rng.randf_range(-120, 120),
			rng.randf_range(10, 90),
			rng.randf_range(-480, -250)
		)
		wisp.rotation_degrees = Vector3(
			rng.randf_range(-20, 20),
			rng.randf_range(-30, 30),
			rng.randf_range(-15, 15)
		)
		add_child(wisp)

	# --- Fighter escort ships ---
	# Some near the mothership (static), some that follow the player (dynamic)
	var fighter_mat := StandardMaterial3D.new()
	fighter_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fighter_mat.albedo_color = Color(0.08, 0.07, 0.1)
	fighter_mat.emission_enabled = true
	fighter_mat.emission = Color(0.03, 0.02, 0.05)
	fighter_mat.emission_energy_multiplier = 0.5

	var fighter_glow := StandardMaterial3D.new()
	fighter_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fighter_glow.albedo_color = Color(0.3, 0.8, 0.5)
	fighter_glow.emission_enabled = true
	fighter_glow.emission = Color(0.2, 0.7, 0.3)
	fighter_glow.emission_energy_multiplier = 3.0

	# A small fighter: body + two prongs + engine glow, baked once and
	# shared by all 8 instances
	var fbody_mesh := BoxMesh.new()
	fbody_mesh.size = Vector3(1.5, 0.6, 3.0)
	var prong_m := BoxMesh.new()
	prong_m.size = Vector3(0.4, 0.3, 2.0)
	var feng_mesh := BoxMesh.new()
	feng_mesh.size = Vector3(0.8, 0.3, 0.3)
	var fighter_mesh := _bake_mesh([
		[fighter_mat, [
			[fbody_mesh, _at(Vector3.ZERO)],
			[prong_m, _at(Vector3(-1.2, 0, -0.8))],
			[prong_m, _at(Vector3(1.2, 0, -0.8))],
		]],
		[fighter_glow, [[feng_mesh, _at(Vector3(0, 0, 1.6))]]],
	])

	for i in 8:
		var fighter := MeshInstance3D.new()
		fighter.mesh = fighter_mesh
		add_child(fighter)
		_fighters.append(fighter)

		# Initial positions: first 4 near first fleet, last 4 will track player
		if i < 4:
			fighter.global_position = Vector3(
				rng.randf_range(-20, 40),
				rng.randf_range(25, 40),
				-200 + rng.randf_range(-30, 30)
			)
			fighter.rotation_degrees = Vector3(
				rng.randf_range(-10, 10), rng.randf_range(-30, 30), rng.randf_range(-5, 5)
			)

# Bakes [mesh, transform] part lists into one ArrayMesh, one surface per
# material group - the GL Compatibility renderer has no batching, so static
# background props must merge their pieces to keep draw calls down.
func _bake_mesh(groups: Array) -> ArrayMesh:
	var mesh: ArrayMesh = null
	for g in groups:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for p in g[1]:
			st.append_from(p[0], 0, p[1])
		st.set_material(g[0])
		mesh = st.commit(mesh)
	return mesh

func _at(pos: Vector3, rot_deg := Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)), pos)

func _build_mothership(ship_root: Node3D, hull_mat: StandardMaterial3D, glow_mat: StandardMaterial3D, red_glow_mat: StandardMaterial3D, rng: RandomNumberGenerator):
	var hull_mesh := CylinderMesh.new()
	hull_mesh.top_radius = 25.0
	hull_mesh.bottom_radius = 28.0
	hull_mesh.height = 6.0

	var bridge_mesh := CylinderMesh.new()
	bridge_mesh.top_radius = 6.0
	bridge_mesh.bottom_radius = 10.0
	bridge_mesh.height = 10.0

	var dome_mesh := SphereMesh.new()
	dome_mesh.radius = 6.5
	dome_mesh.height = 7.0

	var prong_mesh := BoxMesh.new()
	prong_mesh.size = Vector3(3.0, 2.0, 35.0)

	var engine_mesh := BoxMesh.new()
	engine_mesh.size = Vector3(18.0, 5.0, 12.0)

	var hull_parts := [
		[hull_mesh, _at(Vector3.ZERO)],
		[bridge_mesh, _at(Vector3(0, 8, 0))],
		[dome_mesh, _at(Vector3(0, 13, 0))],
		[prong_mesh, _at(Vector3(-8, -1, -25))],
		[prong_mesh, _at(Vector3(8, -1, -25))],
		[engine_mesh, _at(Vector3(0, -1, 22))],
	]

	var strip_mesh := BoxMesh.new()
	strip_mesh.size = Vector3(20.0, 0.3, 1.0)

	var tip_mesh := BoxMesh.new()
	tip_mesh.size = Vector3(2.0, 1.5, 2.0)

	var window_mesh := BoxMesh.new()
	window_mesh.size = Vector3(8.0, 1.5, 0.3)

	var glow_parts := [
		[tip_mesh, _at(Vector3(-8, -1, -43))],
		[tip_mesh, _at(Vector3(8, -1, -43))],
		[window_mesh, _at(Vector3(0, 12, -6.5))],
	]
	for z_off in [-10.0, -3.0, 4.0, 11.0]:
		glow_parts.append([strip_mesh, _at(Vector3(0, -3.2, z_off))])

	var engine_glow_mesh := CylinderMesh.new()
	engine_glow_mesh.top_radius = 2.0
	engine_glow_mesh.bottom_radius = 2.5
	engine_glow_mesh.height = 1.5

	var red_parts := []
	for x_off in [-5.0, 0.0, 5.0]:
		red_parts.append([engine_glow_mesh, _at(Vector3(x_off, -1, 28.5), Vector3(90, 0, 0))])

	var body := MeshInstance3D.new()
	body.mesh = _bake_mesh([[hull_mat, hull_parts], [glow_mat, glow_parts], [red_glow_mat, red_parts]])
	ship_root.add_child(body)

	var aura_mat := StandardMaterial3D.new()
	aura_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	aura_mat.albedo_color = Color(0.1, 0.25, 0.15, 0.04)
	aura_mat.emission_enabled = true
	aura_mat.emission = Color(0.05, 0.15, 0.1)
	aura_mat.emission_energy_multiplier = 1.0
	aura_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	aura_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	var aura_mesh := SphereMesh.new()
	aura_mesh.radius = 55.0
	aura_mesh.height = 110.0
	aura_mesh.material = aura_mat
	var aura := MeshInstance3D.new()
	aura.mesh = aura_mesh
	aura.position = Vector3(0, 5, 0)
	ship_root.add_child(aura)

	# Escort ships
	var escort_hull_mat := StandardMaterial3D.new()
	escort_hull_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	escort_hull_mat.albedo_color = Color(0.2, 0.18, 0.25)
	escort_hull_mat.emission_enabled = true
	escort_hull_mat.emission = Color(0.08, 0.06, 0.12)
	escort_hull_mat.emission_energy_multiplier = 1.0

	var white_light_mat := StandardMaterial3D.new()
	white_light_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white_light_mat.albedo_color = Color(0.9, 0.95, 1.0)
	white_light_mat.emission_enabled = true
	white_light_mat.emission = Color(0.8, 0.9, 1.0)
	white_light_mat.emission_energy_multiplier = 5.0

	var orange_light_mat := StandardMaterial3D.new()
	orange_light_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	orange_light_mat.albedo_color = Color(1.0, 0.6, 0.1)
	orange_light_mat.emission_enabled = true
	orange_light_mat.emission = Color(1.0, 0.5, 0.05)
	orange_light_mat.emission_energy_multiplier = 4.0

	var ehull_mesh := CylinderMesh.new()
	ehull_mesh.top_radius = 5.0
	ehull_mesh.bottom_radius = 7.0
	ehull_mesh.height = 2.0

	var ebridge_mesh := CylinderMesh.new()
	ebridge_mesh.top_radius = 1.5
	ebridge_mesh.bottom_radius = 2.2
	ebridge_mesh.height = 1.8

	var spike_mesh := BoxMesh.new()
	spike_mesh.size = Vector3(0.7, 0.5, 8.0)

	var light_mesh := BoxMesh.new()
	light_mesh.size = Vector3(0.6, 0.6, 0.6)

	var lo_mesh := BoxMesh.new()
	lo_mesh.size = Vector3(0.7, 0.4, 0.7)

	var eeng_mesh := BoxMesh.new()
	eeng_mesh.size = Vector3(2.5, 0.8, 0.8)

	# All escorts share one baked mesh; only their root transform differs
	var escort_mesh := _bake_mesh([
		[escort_hull_mat, [
			[ehull_mesh, _at(Vector3.ZERO)],
			[ebridge_mesh, _at(Vector3(0, 1.8, 0))],
			[spike_mesh, _at(Vector3(0, -0.3, -8.0))],
		]],
		[white_light_mat, [
			[light_mesh, _at(Vector3(-6.5, 0, 0))],
			[light_mesh, _at(Vector3(6.5, 0, 0))],
		]],
		[orange_light_mat, [
			[lo_mesh, _at(Vector3(0, -1.2, 3.0))],
			[lo_mesh, _at(Vector3(0, -1.2, -3.0))],
		]],
		[glow_mat, [[eeng_mesh, _at(Vector3(0, -0.2, 7.5))]]],
	])

	var escort_offsets := [
		Vector3(-35, 5, 10), Vector3(40, -3, -5), Vector3(-15, 12, -20),
		Vector3(50, 8, 15), Vector3(-45, -2, -10), Vector3(20, -6, 25),
	]

	for i in escort_offsets.size():
		var escort := MeshInstance3D.new()
		escort.mesh = escort_mesh
		escort.position = escort_offsets[i]
		escort.rotation_degrees = Vector3(rng.randf_range(-8, 8), rng.randf_range(-40, 40), rng.randf_range(-8, 8))
		ship_root.add_child(escort)

		# Slow drift animation
		var drift := escort.create_tween().set_loops()
		var drift_offset := Vector3(rng.randf_range(-8, 8), rng.randf_range(-4, 4), rng.randf_range(-6, 6))
		var drift_time := rng.randf_range(8.0, 15.0)
		drift.tween_property(escort, "position", escort_offsets[i] + drift_offset, drift_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		drift.tween_property(escort, "position", escort_offsets[i], drift_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _update_fighters(ship_pos: Vector3):
	# Fighters 4-7 orbit far from the player - visible but distant
	for i in range(4, _fighters.size()):
		var f := _fighters[i]
		var idx := i - 4
		var angle := Time.get_ticks_msec() * 0.0003 + idx * TAU / 4.0
		var radius := 50.0 + idx * 10.0
		var height := 20.0 + idx * 8.0
		f.global_position = Vector3(
			ship_pos.x + cos(angle) * radius,
			ship_pos.y + height,
			ship_pos.z - 50.0 + sin(angle) * 25.0
		)
		f.look_at(ship_pos)

func _spawn_laser(ship_pos: Vector3):
	# Pick a random fighter as origin
	if _fighters.is_empty():
		return

	var source_idx := _laser_rng.randi_range(0, _fighters.size() - 1)
	var source_pos := _fighters[source_idx].global_position

	var roll := _laser_rng.randf()
	var origin: Vector3
	var target: Vector3

	if roll < 0.45:
		# Fighter shoots at another fighter (crossfire in the background)
		var target_idx := _laser_rng.randi_range(0, _fighters.size() - 1)
		if target_idx == source_idx:
			target_idx = (target_idx + 1) % _fighters.size()
		origin = source_pos
		target = _fighters[target_idx].global_position
	elif roll < 0.8:
		# Background bolts - fly across the sky far above/around the player
		origin = source_pos
		target = Vector3(
			ship_pos.x + _laser_rng.randf_range(-40, 40),
			ship_pos.y + _laser_rng.randf_range(10, 30),
			ship_pos.z + _laser_rng.randf_range(-30, 10)
		)
	else:
		# Occasional shot that passes near the platforms (but still offset)
		origin = source_pos
		target = Vector3(
			ship_pos.x + _laser_rng.randf_range(-15, 15),
			ship_pos.y + _laser_rng.randf_range(2, 8),
			ship_pos.z + _laser_rng.randf_range(-15, 5)
		)

	var dir := (target - origin).normalized()
	var mat := _green_laser_mat if _laser_rng.randf() > 0.3 else _red_laser_mat

	PerfMonitor.mark("laser")
	var laser := MeshInstance3D.new()
	laser.mesh = _laser_mesh
	laser.material_override = mat
	add_child(laser)
	laser.global_position = origin
	laser.look_at(origin + dir)
	laser.reset_physics_interpolation()

	var speed := _laser_rng.randf_range(40.0, 70.0)
	var dist := origin.distance_to(target) + 80.0
	var travel_time := dist / speed
	var end_pos := origin + dir * dist
	var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(laser, "global_position", end_pos, travel_time).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(laser.queue_free)

func _load_level():
	var content: String

	if GameState.generated_content != "":
		content = GameState.generated_content
	else:
		var file := FileAccess.open(level_path, FileAccess.READ)
		if file:
			content = file.get_as_text()
			file.close()

	if content == "":
		printerr("Failed to open level file: %s - using built-in level" % level_path)
		content = "\n".join(_FALLBACK_LEVEL)
		var warn := Label.new()
		warn.text = "FALLBACK LEVEL - file not found: %s" % level_path
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warn.anchor_left = 0
		warn.anchor_right = 1
		warn.anchor_bottom = 1
		warn.offset_top = -30
		warn.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
		warn.add_theme_font_size_override("font_size", 14)
		_hud_canvas.add_child(warn)

	_start_track(content)

func _start_track(content: String):
	# Clears any existing track, then queues the new one for time-sliced building
	for child in $Level.get_children():
		child.queue_free()
	_grid = []
	_tunnels = []
	_row_base = 0
	_build_queue.clear()
	_build_next = 0
	_spawned_track.clear()
	_chunk_state = {}
	_in_portal = false
	_portal_hops = 0
	_level_content = content
	_level_ready = false
	_build_start_msec = Time.get_ticks_msec()
	_ship.frozen = true
	if _ready_label:
		_ready_label.visible = true
	if _warmup:
		_warmup.visible = true

	# Prepend a flat runway before the level content
	var runway_row := "..".repeat(2) + "1.".repeat(6) + "..".repeat(2)
	var lines := PackedStringArray()
	for _i in 24:
		lines.append(runway_row)
	lines += content.split("\n")
	# Remove trailing empty lines
	while lines.size() > 0 and lines[-1].strip_edges() == "":
		lines.remove_at(lines.size() - 1)

	# Tile format is 2 chars: [height_char][modifier_char]
	var cols := 0
	for line in lines:
		var c := line.length() / 2
		if c > cols:
			cols = c
	_cols = cols

	_enqueue_rows(lines)

func _enqueue_rows(lines: PackedStringArray):
	var row_offset := _row_base + _grid.size()
	var rows := lines.size()

	var grid: Array[Array] = []
	var tunnels: Array[Array] = []
	for r in rows:
		var floor_row: Array[int] = []
		floor_row.resize(_cols)
		floor_row.fill(0)
		var tunnel_row: Array[bool] = []
		tunnel_row.resize(_cols)
		tunnel_row.fill(false)

		var line := lines[r]
		for ci in range(0, line.length(), 2):
			var tile_idx := ci / 2
			if tile_idx >= _cols:
				break
			var h_char := line[ci]
			var m_char := line[ci + 1] if ci + 1 < line.length() else "."
			if h_char >= "1" and h_char <= "9":
				floor_row[tile_idx] = h_char.unicode_at(0) - "0".unicode_at(0)
			# '.' or ' ' as height char = gap (height stays 0)
			if m_char == "T" or m_char == "t":
				tunnel_row[tile_idx] = true
		grid.append(floor_row)
		tunnels.append(tunnel_row)
		_grid.append(floor_row)
		_tunnels.append(tunnel_row)

	_level_end_z = -(_row_base + _grid.size() - 1) * TILE_SIZE

	# Greedy-merge floor tiles within this block into build jobs
	var used: Array[Array] = []
	for r in rows:
		var row: Array[bool] = []
		row.resize(_cols)
		row.fill(false)
		used.append(row)

	for r in rows:
		for c in _cols:
			var height: int = grid[r][c]
			if height == 0 or used[r][c]:
				continue

			var w := 0
			while c + w < _cols and grid[r][c + w] == height and not used[r][c + w]:
				w += 1

			var d := 1
			while r + d < rows:
				var ok := true
				for cc in range(c, c + w):
					if grid[r + d][cc] != height or used[r + d][cc]:
						ok = false
						break
				if not ok:
					break
				d += 1

			for rr in range(r, r + d):
				for cc in range(c, c + w):
					used[rr][cc] = true

			_build_queue.append([0, c, row_offset + r, w, d, height])

	# Tunnel arches — merge consecutive tunnel rows at same column/height into jobs
	var t_used: Array[Array] = []
	for r in rows:
		var row: Array[bool] = []
		row.resize(_cols)
		row.fill(false)
		t_used.append(row)

	for r in rows:
		for c in _cols:
			if not tunnels[r][c] or t_used[r][c] or grid[r][c] == 0:
				continue
			var floor_h: int = grid[r][c]
			var depth := 0
			while r + depth < rows and tunnels[r + depth][c] and grid[r + depth][c] == floor_h and not t_used[r + depth][c]:
				depth += 1
			for rr in range(r, r + depth):
				t_used[rr][c] = true
			_build_queue.append([1, c, row_offset + r, depth, floor_h])

func _process_build_queue():
	if _build_next >= _build_queue.size():
		if not _level_ready and not _grid.is_empty():
			var waited := Time.get_ticks_msec() - _build_start_msec
			if waited >= READY_DELAY_MSEC and (_smooth_frames >= 8 or waited > READY_TIMEOUT_MSEC):
				_level_ready = true
				_ship.frozen = false
				if _ready_label:
					_ready_label.visible = false
				if _warmup:
					_warmup.visible = false
				print("[PERF] level ready after %dms" % waited)
		return
	var level_node := $Level
	# Bigger budget behind the GET READY screen, small one during play
	var budget_usec := 8000 if not _level_ready else 3000
	var deadline := Time.get_ticks_usec() + budget_usec
	var built := 0
	while _build_next < _build_queue.size() and Time.get_ticks_usec() < deadline:
		var job: Array = _build_queue[_build_next]
		_build_next += 1
		built += 1
		if job[0] == 0:
			_build_tile_job(level_node, job)
		else:
			_build_arch_job(level_node, job)
	if _level_ready and built > 0:
		PerfMonitor.mark("built %d jobs" % built)
	if _build_next >= _build_queue.size():
		_build_queue.clear()
		_build_next = 0

func _build_tile_job(level_node: Node3D, job: Array):
	var c: int = job[1]
	var r: int = job[2]
	var w: int = job[3]
	var d: int = job[4]
	var height: int = job[5]
	var actual_height := height * TILE_HEIGHT
	var tile := _create_merged_tile(w, d, actual_height, _height_materials[height])
	tile.position = Vector3(
		c * TILE_SIZE + (w - 1) * TILE_SIZE / 2.0,
		actual_height / 2.0,
		-r * TILE_SIZE - (d - 1) * TILE_SIZE / 2.0
	)
	level_node.add_child(tile)
	if GameState.is_endless:
		_spawned_track.append([tile, -(r + d) * TILE_SIZE])

func _build_arch_job(level_node: Node3D, job: Array):
	var c: int = job[1]
	var r: int = job[2]
	var depth: int = job[3]
	var floor_h: int = job[4]

	var base_y := floor_h * TILE_HEIGHT
	var arch_height := 1.2
	var half_w := TILE_SIZE / 2.0
	var wall_thickness := 0.06
	var center_x := c * TILE_SIZE
	var center_z := -r * TILE_SIZE - (depth - 1) * TILE_SIZE / 2.0
	var tunnel_depth := depth * TILE_SIZE
	var arch_segments := 24
	var min_y := 0.1

	# Build smooth half-cylinder with SurfaceTool
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z_front := tunnel_depth / 2.0
	var z_back := -tunnel_depth / 2.0

	for seg in arch_segments:
		var a0 := PI * float(seg) / float(arch_segments)
		var a1 := PI * float(seg + 1) / float(arch_segments)
		var x0 := -cos(a0) * half_w
		var y0 := sin(a0) * arch_height
		var x1 := -cos(a1) * half_w
		var y1 := sin(a1) * arch_height
		if y0 < min_y and y1 < min_y:
			continue

		# Normal at each point (pointing outward)
		var n0 := Vector3(-cos(a0), sin(a0), 0).normalized()
		var n1 := Vector3(-cos(a1), sin(a1), 0).normalized()

		# Outer surface
		var o0f := Vector3(x0, y0, z_front)
		var o1f := Vector3(x1, y1, z_front)
		var o0b := Vector3(x0, y0, z_back)
		var o1b := Vector3(x1, y1, z_back)
		# Inner surface (offset inward)
		var i0f := o0f - n0 * wall_thickness
		var i1f := o1f - n1 * wall_thickness
		var i0b := o0b - n0 * wall_thickness
		var i1b := o1b - n1 * wall_thickness

		# Outer face (normals out)
		st.set_normal(n0); st.add_vertex(o0f)
		st.set_normal(n1); st.add_vertex(o1f)
		st.set_normal(n0); st.add_vertex(o0b)
		st.set_normal(n1); st.add_vertex(o1f)
		st.set_normal(n1); st.add_vertex(o1b)
		st.set_normal(n0); st.add_vertex(o0b)

		# Inner face (normals in)
		st.set_normal(-n0); st.add_vertex(i0b)
		st.set_normal(-n1); st.add_vertex(i1f)
		st.set_normal(-n0); st.add_vertex(i0f)
		st.set_normal(-n0); st.add_vertex(i0b)
		st.set_normal(-n1); st.add_vertex(i1b)
		st.set_normal(-n1); st.add_vertex(i1f)

	# Front and back cap rings
	for seg in arch_segments:
		var a0 := PI * float(seg) / float(arch_segments)
		var a1 := PI * float(seg + 1) / float(arch_segments)
		var x0 := -cos(a0) * half_w
		var y0 := sin(a0) * arch_height
		var x1 := -cos(a1) * half_w
		var y1 := sin(a1) * arch_height
		if y0 < min_y and y1 < min_y:
			continue
		var n0 := Vector3(-cos(a0), sin(a0), 0).normalized()
		var n1 := Vector3(-cos(a1), sin(a1), 0).normalized()
		var o0 := Vector3(x0, y0, 0)
		var o1 := Vector3(x1, y1, 0)
		var i0 := o0 - n0 * wall_thickness
		var i1 := o1 - n1 * wall_thickness
		# Front cap
		var fz := Vector3(0, 0, z_front)
		var fn := Vector3(0, 0, 1)
		st.set_normal(fn); st.add_vertex(o0 + fz)
		st.set_normal(fn); st.add_vertex(i1 + fz)
		st.set_normal(fn); st.add_vertex(i0 + fz)
		st.set_normal(fn); st.add_vertex(o0 + fz)
		st.set_normal(fn); st.add_vertex(o1 + fz)
		st.set_normal(fn); st.add_vertex(i1 + fz)
		# Back cap
		var bz := Vector3(0, 0, z_back)
		var bn := Vector3(0, 0, -1)
		st.set_normal(bn); st.add_vertex(i0 + bz)
		st.set_normal(bn); st.add_vertex(i1 + bz)
		st.set_normal(bn); st.add_vertex(o0 + bz)
		st.set_normal(bn); st.add_vertex(o1 + bz)
		st.set_normal(bn); st.add_vertex(o0 + bz)
		st.set_normal(bn); st.add_vertex(i1 + bz)

	var arch_mesh := st.commit()
	arch_mesh.surface_set_material(0, _tunnel_wall_mat)

	var arch_body := StaticBody3D.new()
	arch_body.set_meta("tunnel_wall", true)
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = arch_mesh
	arch_body.add_child(mesh_inst)

	# Trimesh collision from the generated mesh
	var trimesh_shape := arch_mesh.create_trimesh_shape()
	var col_shape := CollisionShape3D.new()
	col_shape.shape = trimesh_shape
	arch_body.add_child(col_shape)

	# Wormhole: event-horizon rings framing both portal mouths
	if GameState.selected_group == 7:
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 1.05
		ring_mesh.outer_radius = 1.3
		ring_mesh.rings = 24
		ring_mesh.ring_segments = 6
		var pring_mat := StandardMaterial3D.new()
		pring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pring_mat.albedo_color = Color(0.55, 0.35, 1.0)
		pring_mat.emission_enabled = true
		pring_mat.emission = Color(0.5, 0.3, 1.0)
		pring_mat.emission_energy_multiplier = 2.5
		ring_mesh.material = pring_mat
		for endz in [tunnel_depth * 0.5, -tunnel_depth * 0.5]:
			var pring := MeshInstance3D.new()
			pring.mesh = ring_mesh
			pring.rotation_degrees = Vector3(90, 0, 0)
			pring.position = Vector3(0, 0.55, endz)
			arch_body.add_child(pring)

	arch_body.position = Vector3(center_x, base_y, center_z)
	level_node.add_child(arch_body)

	# Invisible solid roof on top to prevent clipping through
	var roof_body := StaticBody3D.new()
	roof_body.set_meta("tunnel_wall", true)
	var roof_col := CollisionShape3D.new()
	var roof_box := BoxShape3D.new()
	roof_box.size = Vector3(TILE_SIZE, 0.3, tunnel_depth)
	roof_col.shape = roof_box
	roof_body.add_child(roof_col)
	roof_body.position = Vector3(center_x, base_y + arch_height + 0.15, center_z)
	level_node.add_child(roof_body)

	if GameState.is_endless:
		var end_z := -(r + depth) * TILE_SIZE
		_spawned_track.append([arch_body, end_z])
		_spawned_track.append([roof_body, end_z])

# Panel texture shared by all track materials: dark border frame, bevel
# ring, faint noise. World-triplanar mapping repeats it once per 2u tile,
# so merged tile runs still read as individual tiles - the SkyRoads grid.
func _make_tile_texture() -> ImageTexture:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in size:
		for x in size:
			var edge := mini(mini(x, size - 1 - x), mini(y, size - 1 - y))
			var v := 1.0
			if edge == 0:
				v = 0.55
			elif edge == 1:
				v = 0.7
			elif edge <= 3:
				v = 0.88
			v -= rng.randf() * 0.05
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

# Frost-bordered cell for the ice theme: bright rimed edges and faint
# internal crack lines - triplanar-tiled per 2u like the panel texture, so
# merged tile runs still read as individual ice blocks
func _make_ice_texture() -> ImageTexture:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	for y in size:
		for x in size:
			var edge := mini(mini(x, size - 1 - x), mini(y, size - 1 - y))
			var v := 0.7 + rng.randf() * 0.06
			if edge == 0:
				v = 1.0
			elif edge == 1:
				v = 0.93
			elif edge <= 3:
				v = 0.82
			img.set_pixel(x, y, Color(v, v, v * 1.02))
	for _i in 6:
		var x := rng.randi_range(8, size - 9)
		var y := rng.randi_range(8, size - 9)
		for _j in rng.randi_range(8, 20):
			img.set_pixel(clampi(x, 5, size - 6), clampi(y, 5, size - 6), Color(0.9, 0.94, 1.0))
			x += rng.randi_range(-2, 2)
			y += rng.randi_range(-1, 2)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _apply_tile_texture(mat: StandardMaterial3D, tex: ImageTexture):
	mat.albedo_texture = tex
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	# period 2u (one tile), offset half a period so borders land on tile
	# edges (odd world coords), not tile centers
	mat.uv1_scale = Vector3(0.5, 0.5, 0.5)
	mat.uv1_offset = Vector3(0.5, 0.5, 0.5)

func _init_track_materials():
	var group_colors := [
		Color(0.4, 0.65, 1.0),
		Color(0.7, 0.4, 0.9),
		Color(1.0, 0.6, 0.25),
		Color(0.3, 0.68, 0.45),
		Color(0.15, 0.85, 1.0),
		Color(0.71, 0.5, 0.34),
		Color(1.0, 0.78, 0.45),
		Color(0.55, 0.45, 1.0),
	]
	var base_color: Color = group_colors[clampi(GameState.selected_group, 0, group_colors.size() - 1)]
	var tile_tex := _make_tile_texture()

	# Dark Matter stays murky: weakest self-glow of all themes
	var glow := 0.28 if GameState.selected_group == 3 else 0.4
	var ice_tex: ImageTexture
	var ice_normal: NoiseTexture2D
	if GameState.selected_group == 1:
		ice_tex = _make_ice_texture()
		var noise := FastNoiseLite.new()
		noise.seed = 11
		noise.frequency = 0.12
		ice_normal = NoiseTexture2D.new()
		ice_normal.width = 128
		ice_normal.height = 128
		ice_normal.noise = noise
		ice_normal.as_normal_map = true
		ice_normal.bump_strength = 6.0
	for h in range(1, 10):
		var mat := StandardMaterial3D.new()
		var brightness := 1.2 + (h - 1) * 0.1
		if GameState.selected_group == 1:
			# Nebula: solid translucent ice blocks. Backfaces render so a
			# tile reads as a filled cube, rim approximates the fresnel
			# frost of real ice, and the noise normal map gives the
			# surface its uneven glints; frost borders mark each 2u cell
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.albedo_color = Color(0.76, 0.72, 1.0) * (0.9 + (h - 1) * 0.04)
			mat.albedo_color.a = 0.62
			mat.metallic = 0.0
			mat.metallic_specular = 0.8
			mat.roughness = 0.05
			mat.rim_enabled = true
			mat.rim = 0.5
			mat.rim_tint = 0.3
			mat.normal_enabled = true
			mat.normal_texture = ice_normal
			mat.normal_scale = 0.6
			mat.emission_enabled = true
			mat.emission = Color(0.45, 0.32, 0.78) * 0.3
			mat.emission_energy_multiplier = glow
			_apply_tile_texture(mat, ice_tex)
		elif GameState.selected_group == 4:
			mat = _make_grid_tile(h, glow, tile_tex)
		elif GameState.selected_group == 5:
			mat = _make_wreck_tile(h, glow, tile_tex)
		elif GameState.selected_group == 6:
			mat = _make_bloom_tile(h, glow, tile_tex)
		elif GameState.selected_group == 7:
			mat = _make_wormhole_tile(h, glow, tile_tex)
		else:
			mat.albedo_color = base_color * brightness
			mat.albedo_color.a = 1.0
			mat.emission_enabled = true
			mat.emission = base_color * 0.3
			mat.emission_energy_multiplier = glow
			_apply_tile_texture(mat, tile_tex)
		_height_materials[h] = mat

	_tunnel_wall_mat = StandardMaterial3D.new()
	_tunnel_wall_mat.albedo_color = base_color.darkened(0.4)
	_tunnel_wall_mat.emission_enabled = true
	_tunnel_wall_mat.emission = base_color * 0.1
	_tunnel_wall_mat.emission_energy_multiplier = 0.3
	_tunnel_wall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_apply_tile_texture(_tunnel_wall_mat, tile_tex)
	if GameState.selected_group == 7:
		# Wormhole bores are the portals: the throat glows from inside
		_tunnel_wall_mat.albedo_color = Color(0.12, 0.08, 0.22)
		_tunnel_wall_mat.emission = Color(0.5, 0.3, 1.0)
		_tunnel_wall_mat.emission_energy_multiplier = 1.1

func _free_passed_track(ship_z: float):
	var keep: Array = []
	var freed := 0
	for entry in _spawned_track:
		if entry[1] > ship_z + 20.0:
			entry[0].queue_free()
			freed += 1
		else:
			keep.append(entry)
	_spawned_track = keep
	if freed > 0:
		PerfMonitor.mark("freed %d" % freed)
	# Drop the parsed rows behind the ship too - nothing reads them again
	# (the autopilot only looks forward), and an endless run otherwise grows
	# _grid/_tunnels without bound
	var passed := int(-ship_z / TILE_SIZE) - 30 - _row_base
	if passed > 0:
		_grid = _grid.slice(passed)
		_tunnels = _tunnels.slice(passed)
		_row_base += passed

func _create_shader_warmup():
	# Draws every shader variant behind the GET READY gate so nothing compiles
	# mid-round (see shader_warmup.gd).
	_warmup = ShaderWarmup.build_rig()
	_camera.add_child(_warmup)

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_C and not _finishing and not _share_open:
			_open_share_dialog()

# The tree is paused while the dialog is open and the Game node is pausable,
# so its own _unhandled_input never sees the close keys - they must live on
# an always-processing node inside the dialog.
class ShareDialogKeys extends Node:
	signal close_requested
	func _unhandled_input(event):
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_C or event.keycode == KEY_ESCAPE:
				close_requested.emit()
				get_viewport().set_input_as_handled()

func _share_payload() -> String:
	# Generated tracks share as a compact reproducible code; authored or
	# imported content falls back to the raw row text.
	if not GameState.is_endless and not GameState.gen_params.is_empty():
		return GameState.encode_share_code(GameState.gen_params)
	return _level_content

func _open_share_dialog():
	_share_open = true
	get_tree().paused = true

	var panel := ColorRect.new()
	panel.color = Color(0, 0, 0, 0.85)
	panel.anchor_right = 1
	panel.anchor_bottom = 1
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_share_panel = panel
	_hud_canvas.add_child(panel)

	var keys := ShareDialogKeys.new()
	keys.process_mode = Node.PROCESS_MODE_ALWAYS
	keys.close_requested.connect(_close_share_dialog)
	panel.add_child(keys)

	var title := Label.new()
	title.text = "SHARE TRACK"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.1
	title.anchor_right = 0.9
	title.offset_top = 20
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	title.add_theme_font_size_override("font_size", 20)
	panel.add_child(title)

	var hint := Label.new()
	hint.text = "Select all and copy the level data below. Press Esc or C to close."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.anchor_left = 0.1
	hint.anchor_right = 0.9
	hint.offset_top = 50
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	hint.add_theme_font_size_override("font_size", 12)
	panel.add_child(hint)

	_share_text = LineEdit.new()
	_share_text.text = _share_payload()
	_share_text.anchor_left = 0.05
	_share_text.anchor_right = 0.95
	_share_text.offset_top = 80
	_share_text.offset_bottom = 105
	_share_text.add_theme_font_size_override("font_size", 11)
	_share_text.process_mode = Node.PROCESS_MODE_ALWAYS
	_share_text.focus_mode = Control.FOCUS_NONE
	panel.add_child(_share_text)
	_share_text.select_all.call_deferred()

	# Copy button
	var copy_btn := Button.new()
	copy_btn.text = "Copy to Clipboard"
	copy_btn.anchor_left = 0.35
	copy_btn.anchor_right = 0.65
	copy_btn.offset_top = 115
	copy_btn.offset_bottom = 143
	copy_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	copy_btn.pressed.connect(_on_copy_pressed.bind(copy_btn))
	panel.add_child(copy_btn)

	# Continue button
	var continue_btn := Button.new()
	continue_btn.text = "Continue"
	continue_btn.anchor_left = 0.35
	continue_btn.anchor_right = 0.65
	continue_btn.offset_top = 153
	continue_btn.offset_bottom = 181
	continue_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	continue_btn.pressed.connect(_close_share_dialog)
	panel.add_child(continue_btn)

	# Set up focus navigation between buttons
	copy_btn.focus_neighbor_bottom = continue_btn.get_path()
	copy_btn.focus_neighbor_top = continue_btn.get_path()
	continue_btn.focus_neighbor_bottom = copy_btn.get_path()
	continue_btn.focus_neighbor_top = copy_btn.get_path()
	copy_btn.grab_focus.call_deferred()

func _on_copy_pressed(btn: Button):
	DisplayServer.clipboard_set(_share_payload())
	btn.text = "Copied!"

func _close_share_dialog():
	_share_open = false
	get_tree().paused = false
	if _share_panel:
		_share_panel.queue_free()
		_share_panel = null
		_share_text = null


func _create_warp_streaks():
	PerfMonitor.mark("warp_streaks")
	var streak_mat := StandardMaterial3D.new()
	streak_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak_mat.albedo_color = Color(0.8, 0.9, 1.0)
	streak_mat.emission_enabled = true
	streak_mat.emission = Color(0.6, 0.8, 1.0)
	streak_mat.emission_energy_multiplier = 3.0

	var cam_pos := _camera.global_position
	var cam_fwd := -_camera.global_basis.z
	var cam_right := _camera.global_basis.x
	var cam_up := _camera.global_basis.y

	var streak_mesh := BoxMesh.new()
	streak_mesh.size = Vector3(0.05, 0.05, 1.0)
	streak_mesh.material = streak_mat

	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 100:
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(1.5, 15.0)
		var depth := rng.randf_range(8.0, 50.0)

		var pos := cam_pos + cam_fwd * depth + cam_right * cos(angle) * radius + cam_up * sin(angle) * radius

		var streak := MeshInstance3D.new()
		streak.mesh = streak_mesh
		add_child(streak)
		streak.global_position = pos
		streak.look_at(cam_pos)
		streak.reset_physics_interpolation()

		var duration := rng.randf_range(0.6, 1.6)
		var stretch := rng.randf_range(30.0, 80.0)
		var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		tween.tween_property(streak, "scale:z", stretch, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _on_ship_warped():
	if not GameState.is_endless and not GameState.autopilot and GameState.run_records:
		GameState.mark_completed(GameState.menu_group, GameState.menu_track)
	get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")

func _on_ship_exploded():
	if GameState.is_endless and not GameState.autopilot:
		var dist := absf(_ship.global_position.z)
		GameState.save_endless_best(dist)
	GameState.elapsed_time = 0.0
	_timer_running = false
	if GameState.is_endless:
		# Passed track has been freed, so start a fresh run on a new track
		_reset_endless_track()
	_ship.reset_ship()

func _reset_endless_track():
	var params: Dictionary = GameState.endless_params.duplicate()
	params["seed"] = randi()
	params["length"] = 300
	_start_track(LevelGenerator.generate(params))

func _create_merged_tile(tiles_wide: int, tiles_deep: int, height: float, material: StandardMaterial3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	var size_x := tiles_wide * TILE_SIZE
	var size_z := tiles_deep * TILE_SIZE

	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(size_x, height, size_z)
	box_mesh.material = material
	mesh_instance.mesh = box_mesh
	body.add_child(mesh_instance)

	var col := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(size_x, height, size_z)
	col.shape = box_shape
	body.add_child(col)

	return body

# ---------------- The Grid (theme 4) ----------------

static var _grid_circuit_tex: ImageTexture

func _get_grid_circuit_texture() -> ImageTexture:
	if _grid_circuit_tex != null:
		return _grid_circuit_tex
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xCAFE
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color(0.16, 0.16, 0.16))
	var edge := Color(0.9, 0.9, 0.9)
	var edge_dim := Color(0.42, 0.42, 0.42)
	for i in 64:
		img.set_pixel(i, 0, edge)
		img.set_pixel(0, i, edge)
		img.set_pixel(i, 63, edge)
		img.set_pixel(63, i, edge)
		img.set_pixel(i, 1, edge_dim)
		img.set_pixel(1, i, edge_dim)
		img.set_pixel(i, 62, edge_dim)
		img.set_pixel(62, i, edge_dim)
	var trace := Color(0.72, 0.72, 0.72)
	var pad := Color(1.0, 1.0, 1.0)
	for _n in 9:
		var cx := rng.randi_range(10, 53)
		var cy := rng.randi_range(10, 53)
		var horiz := rng.randf() < 0.5
		var d1 := -1 if rng.randf() < 0.5 else 1
		var d2 := -1 if rng.randf() < 0.5 else 1
		for px in range(cx - 1, cx + 2):
			for py in range(cy - 1, cy + 2):
				img.set_pixel(clampi(px, 3, 60), clampi(py, 3, 60), pad)
		for _s in rng.randi_range(8, 18):
			if horiz:
				cx = clampi(cx + d1, 4, 59)
			else:
				cy = clampi(cy + d1, 4, 59)
			img.set_pixel(cx, cy, trace)
		for _s in rng.randi_range(6, 14):
			if horiz:
				cy = clampi(cy + d2, 4, 59)
			else:
				cx = clampi(cx + d2, 4, 59)
			img.set_pixel(cx, cy, trace)
		for px in range(cx - 1, cx + 2):
			for py in range(cy - 1, cy + 2):
				img.set_pixel(clampi(px, 3, 60), clampi(py, 3, 60), pad)
	img.generate_mipmaps()
	_grid_circuit_tex = ImageTexture.create_from_image(img)
	return _grid_circuit_tex

@warning_ignore("unused_parameter")
func _make_grid_tile(h: int, glow: float, tile_tex: ImageTexture) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var t := clampf((h - 1) / 8.0, 0.0, 1.0)
	var trace_col := Color(0.12, 0.85, 1.0).lerp(Color(0.75, 0.3, 1.0), t * 0.5)
	mat.albedo_color = Color(0.05, 0.09, 0.13).lerp(Color(0.09, 0.06, 0.14), t)
	mat.metallic = 0.65
	mat.roughness = 0.32
	mat.emission_enabled = true
	mat.emission = trace_col
	mat.emission_energy_multiplier = glow * (0.85 + 0.55 * t)
	var tex := _get_grid_circuit_texture()
	_apply_tile_texture(mat, tex)
	mat.emission_texture = tex
	return mat

func _create_grid_background():
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xDA7A
	var z_min := minf(-400.0, _env_end_z - 100.0)
	var z_span := absf(z_min)

	# Wireframe floor plane far below
	var grid_img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	grid_img.fill(Color(0.008, 0.012, 0.025))
	var line_col := Color(0.05, 0.7, 0.85)
	var line_dim := Color(0.02, 0.28, 0.36)
	for i in 64:
		grid_img.set_pixel(i, 0, line_col)
		grid_img.set_pixel(0, i, line_col)
		grid_img.set_pixel(i, 1, line_dim)
		grid_img.set_pixel(1, i, line_dim)
	grid_img.generate_mipmaps()
	var grid_tex := ImageTexture.create_from_image(grid_img)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_mat.albedo_texture = grid_tex
	floor_mat.uv1_scale = Vector3(64.0, 64.0, 1.0)
	floor_mat.emission_enabled = true
	floor_mat.emission = Color(0.15, 0.75, 0.95)
	floor_mat.emission_energy_multiplier = 0.8
	floor_mat.emission_texture = grid_tex
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(1400.0, z_span + 600.0)
	floor_mesh.material = floor_mat
	var floor_inst := MeshInstance3D.new()
	floor_inst.mesh = floor_mesh
	floor_inst.transform = _at(Vector3(9.0, -25.0, z_min * 0.5))
	add_child(floor_inst)

	# Server monoliths with neon corner strips (one baked mesh, 2 surfaces)
	var body_mat := StandardMaterial3D.new()
	body_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	body_mat.albedo_color = Color(0.025, 0.04, 0.07)
	var strip_mat := StandardMaterial3D.new()
	strip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	strip_mat.albedo_color = Color(0.25, 0.95, 1.0)
	strip_mat.emission_enabled = true
	strip_mat.emission = Color(0.2, 0.9, 1.0)
	strip_mat.emission_energy_multiplier = 2.0
	var unit_box := BoxMesh.new()
	var body_parts: Array = []
	var strip_parts: Array = []
	for i in 16:
		var side := -1.0 if i % 2 == 0 else 1.0
		var tx := 9.0 + side * rng.randf_range(45.0, 150.0)
		var tz := rng.randf_range(z_min - 120.0, -50.0)
		var th := rng.randf_range(30.0, 95.0)
		var tw := rng.randf_range(6.0, 16.0)
		var pos := Vector3(tx, -25.0 + th * 0.5, tz)
		var rot := Basis(Vector3.UP, rng.randf_range(-0.35, 0.35))
		body_parts.append([unit_box, Transform3D(rot * Basis.from_scale(Vector3(tw, th, tw)), pos)])
		var c := tw * 0.5
		strip_parts.append([unit_box, Transform3D(rot * Basis.from_scale(Vector3(0.5, th * 0.98, 0.5)), pos + rot * Vector3(c, 0.0, c))])
		strip_parts.append([unit_box, Transform3D(rot * Basis.from_scale(Vector3(0.5, th * 0.98, 0.5)), pos + rot * Vector3(-c, 0.0, -c))])
		strip_parts.append([unit_box, Transform3D(rot * Basis.from_scale(Vector3(tw * 0.7, 0.5, tw * 0.7)), pos + Vector3(0.0, th * 0.5 + 0.3, 0.0))])
	var towers := MeshInstance3D.new()
	towers.mesh = _bake_mesh([[body_mat, body_parts], [strip_mat, strip_parts]])
	add_child(towers)

	# Portal gate ring at the far end (one baked mesh, 2 surfaces)
	var ring_cyan := StandardMaterial3D.new()
	ring_cyan.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_cyan.albedo_color = Color(0.3, 0.95, 1.0)
	ring_cyan.emission_enabled = true
	ring_cyan.emission = Color(0.25, 0.9, 1.0)
	ring_cyan.emission_energy_multiplier = 3.0
	var ring_mag := StandardMaterial3D.new()
	ring_mag.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mag.albedo_color = Color(1.0, 0.35, 0.9)
	ring_mag.emission_enabled = true
	ring_mag.emission = Color(1.0, 0.3, 0.85)
	ring_mag.emission_energy_multiplier = 3.0
	var torus_a := TorusMesh.new()
	torus_a.inner_radius = 34.0
	torus_a.outer_radius = 38.0
	var torus_b := TorusMesh.new()
	torus_b.inner_radius = 26.0
	torus_b.outer_radius = 28.5
	var portal := MeshInstance3D.new()
	portal.mesh = _bake_mesh([[ring_cyan, [[torus_a, Transform3D()]]], [ring_mag, [[torus_b, Transform3D()]]]])
	portal.transform = _at(Vector3(9.0, 24.0, z_min - 200.0), Vector3(90.0, 0.0, 0.0))
	add_child(portal)
	var portal_light := OmniLight3D.new()
	portal_light.light_color = Color(0.4, 0.85, 1.0)
	portal_light.light_energy = 1.8
	portal_light.omni_range = 200.0
	portal_light.shadow_enabled = false
	portal_light.transform = _at(Vector3(9.0, 20.0, z_min - 160.0))
	add_child(portal_light)
	var pulse := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(portal, "scale", Vector3.ONE * 1.06, 3.5)
	pulse.tween_property(portal, "scale", Vector3.ONE, 3.5)

	# Drifting data packets (one MultiMesh)
	var packet_mesh := BoxMesh.new()
	packet_mesh.size = Vector3(0.7, 0.7, 0.7)
	var packet_mat := StandardMaterial3D.new()
	packet_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	packet_mat.vertex_color_use_as_albedo = true
	packet_mesh.material = packet_mat
	var packet_mm := MultiMesh.new()
	packet_mm.transform_format = MultiMesh.TRANSFORM_3D
	packet_mm.use_colors = true
	packet_mm.mesh = packet_mesh
	packet_mm.instance_count = 160
	for i in 160:
		var px: float
		var py: float
		if rng.randf() < 0.22:
			px = rng.randf_range(-25.0, 45.0)
			py = rng.randf_range(32.0, 85.0)
		else:
			px = 9.0 + (-1.0 if rng.randf() < 0.5 else 1.0) * rng.randf_range(32.0, 140.0)
			py = rng.randf_range(-18.0, 70.0)
		var pz := rng.randf_range(z_min - 120.0, 5.0)
		var s := rng.randf_range(0.5, 1.8)
		var pb := Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Basis.from_scale(Vector3.ONE * s)
		packet_mm.set_instance_transform(i, Transform3D(pb, Vector3(px, py, pz)))
		var roll := rng.randf()
		var col := Color(0.35, 0.95, 1.0)
		if roll < 0.2:
			col = Color(1.0, 0.35, 0.9)
		elif roll < 0.32:
			col = Color(0.95, 0.98, 1.0)
		packet_mm.set_instance_color(i, col)
	var packets := MultiMeshInstance3D.new()
	packets.multimesh = packet_mm
	add_child(packets)
	var drift := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	drift.tween_property(packets, "position:y", 3.0, 6.0)
	drift.tween_property(packets, "position:y", 0.0, 6.0)

	# Vertical light pillars rising from the floor grid (one MultiMesh)
	var pillar_mesh := CylinderMesh.new()
	pillar_mesh.top_radius = 0.5
	pillar_mesh.bottom_radius = 0.5
	pillar_mesh.height = 1.0
	pillar_mesh.radial_segments = 6
	pillar_mesh.rings = 1
	pillar_mesh.cap_top = false
	pillar_mesh.cap_bottom = false
	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pillar_mat.albedo_color = Color(0.5, 0.9, 1.0)
	pillar_mat.emission_enabled = true
	pillar_mat.emission = Color(0.4, 0.85, 1.0)
	pillar_mat.emission_energy_multiplier = 1.6
	pillar_mesh.material = pillar_mat
	var pillar_mm := MultiMesh.new()
	pillar_mm.transform_format = MultiMesh.TRANSFORM_3D
	pillar_mm.mesh = pillar_mesh
	pillar_mm.instance_count = 22
	for i in 22:
		var side := -1.0 if i % 2 == 0 else 1.0
		var lx := 9.0 + side * rng.randf_range(32.0, 130.0)
		var lz := rng.randf_range(z_min - 80.0, -30.0)
		var lh := rng.randf_range(18.0, 55.0)
		pillar_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(1.0, lh, 1.0)), Vector3(lx, -25.0 + lh * 0.5, lz)))
	var pillars := MultiMeshInstance3D.new()
	pillars.multimesh = pillar_mm
	add_child(pillars)

	# Light-cycle trail beams along the floor (one baked surface)
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.albedo_color = Color(1.0, 0.3, 0.85)
	beam_mat.emission_enabled = true
	beam_mat.emission = Color(1.0, 0.25, 0.8)
	beam_mat.emission_energy_multiplier = 2.2
	var beam_parts: Array = []
	for off in [-112.0, -58.0, 62.0, 118.0]:
		beam_parts.append([unit_box, Transform3D(Basis.from_scale(Vector3(1.4, 0.3, z_span + 500.0)), Vector3(9.0 + off, -24.5, z_min * 0.5))])
	var beams := MeshInstance3D.new()
	beams.mesh = _bake_mesh([[beam_mat, beam_parts]])
	add_child(beams)

# ---------------- The Graveyard (theme 5) ----------------

static var _wreck_plate_tex: ImageTexture

func _wreck_plate_texture() -> ImageTexture:
	if _wreck_plate_tex != null:
		return _wreck_plate_tex
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xDEAD5A17
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var v := 0.58 + rng.randf_range(-0.05, 0.05)
			if y == 21 or y == 42:
				v -= 0.16
			if (y < 21 and x == 40) or (y >= 21 and y < 42 and x == 14) or (y >= 42 and x == 50):
				v -= 0.14
			var edge := mini(mini(x, 63 - x), mini(y, 63 - y))
			var c := Color(v, v * 0.94, v * 0.87)
			if edge < 2:
				var w := 0.92 - 0.1 * edge + rng.randf_range(-0.04, 0.04)
				c = Color(w, w * 0.97, w * 0.9)
			elif edge == 2:
				c = c.darkened(0.4)
			img.set_pixel(x, y, c)
	for ry in [6, 21, 42, 57]:
		for rx in [6, 57]:
			img.set_pixel(rx, ry, Color(0.9, 0.87, 0.8))
			img.set_pixel(rx + 1, ry + 1, Color(0.18, 0.16, 0.14))
	for s in 6:
		var sx := rng.randi_range(6, 50)
		var sy := rng.randi_range(6, 50)
		var dy := -1 if rng.randf() < 0.5 else 1
		for k in rng.randi_range(7, 15):
			var px := sx + k
			var py := sy + k * dy
			if px > 2 and px < 61 and py > 2 and py < 61:
				img.set_pixel(px, py, img.get_pixel(px, py).lightened(0.35))
	for e in 4:
		img.set_pixel(rng.randi_range(8, 55), rng.randi_range(8, 55), Color(0.75, 0.4, 0.18))
	img.generate_mipmaps()
	_wreck_plate_tex = ImageTexture.create_from_image(img)
	return _wreck_plate_tex

@warning_ignore("unused_parameter")
func _make_wreck_tile(h: int, glow: float, tile_tex: ImageTexture) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var t := clampf((h - 1) / 8.0, 0.0, 1.0)
	mat.albedo_color = Color(0.4, 0.31, 0.25).lerp(Color(0.55, 0.51, 0.46), t)
	mat.metallic = 0.6
	mat.metallic_specular = 0.45
	mat.roughness = 0.82 - 0.14 * t
	_apply_tile_texture(mat, _wreck_plate_texture())
	mat.emission_enabled = true
	mat.emission = Color(0.62, 0.24, 0.08).lerp(Color(0.5, 0.34, 0.18), t)
	mat.emission_energy_multiplier = glow * (0.55 + 0.05 * h)
	return mat

func _create_wreck_background():
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x6E4C0FF1
	var z_min := minf(-400.0, _env_end_z - 100.0)
	var box := func(sx: float, sy: float, sz: float) -> BoxMesh:
		var m := BoxMesh.new()
		m.size = Vector3(sx, sy, sz)
		return m
	var cyl := func(r: float, h: float) -> CylinderMesh:
		var m := CylinderMesh.new()
		m.top_radius = r
		m.bottom_radius = r
		m.height = h
		m.radial_segments = 10
		m.rings = 1
		return m

	var hull_mat := StandardMaterial3D.new()
	hull_mat.albedo_color = Color(0.19, 0.17, 0.16)
	hull_mat.metallic = 0.45
	hull_mat.roughness = 0.85
	var bone_mat := StandardMaterial3D.new()
	bone_mat.albedo_color = Color(0.58, 0.54, 0.48)
	bone_mat.metallic = 0.15
	bone_mat.roughness = 0.9
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.04, 0.04, 0.05)
	glass_mat.metallic = 0.9
	glass_mat.roughness = 0.25
	var ember_mat := StandardMaterial3D.new()
	ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_mat.albedo_color = Color(0.85, 0.32, 0.09)
	ember_mat.emission_enabled = true
	ember_mat.emission = Color(0.85, 0.32, 0.09)
	ember_mat.emission_energy_multiplier = 1.4

	# dead star low on the horizon, ash ring around it
	var star_pos := Vector3(140.0, 25.0, z_min - 220.0)
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 55.0
	core_mesh.height = 110.0
	core_mesh.radial_segments = 24
	core_mesh.rings = 12
	core.mesh = core_mesh
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(0.82, 0.75, 0.65)
	core.material_override = core_mat
	core.transform = _at(star_pos)
	add_child(core)
	var halo := MeshInstance3D.new()
	var halo_mesh := SphereMesh.new()
	halo_mesh.radius = 85.0
	halo_mesh.height = 170.0
	halo_mesh.radial_segments = 24
	halo_mesh.rings = 12
	halo.mesh = halo_mesh
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	halo_mat.albedo_color = Color(0.8, 0.5, 0.3, 0.1)
	halo.material_override = halo_mat
	halo.transform = _at(star_pos)
	add_child(halo)
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 75.0
	ring_mesh.outer_radius = 115.0
	ring_mesh.rings = 40
	ring_mesh.ring_segments = 6
	ring.mesh = ring_mesh
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(0.3, 0.25, 0.21)
	ring.material_override = ring_mat
	ring.transform = _at(star_pos, Vector3(78, 0, 12)).scaled_local(Vector3(1, 0.12, 1))
	add_child(ring)

	# dim ash starfield, occasional ember star
	var star_mm := MultiMesh.new()
	star_mm.transform_format = MultiMesh.TRANSFORM_3D
	star_mm.use_colors = true
	var star_quad := QuadMesh.new()
	star_quad.size = Vector2(1.4, 1.4)
	var star_mat := StandardMaterial3D.new()
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.vertex_color_use_as_albedo = true
	star_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	star_mat.billboard_keep_scale = true
	star_quad.material = star_mat
	star_mm.mesh = star_quad
	star_mm.instance_count = 220
	var star_center := Vector3(9.0, 0.0, z_min * 0.5)
	for i in 220:
		var dir := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.15, 1.0), rng.randf_range(-1.0, 1.0))
		if dir.length() < 0.05:
			dir = Vector3(0.3, 0.5, -0.8)
		var p := star_center + dir.normalized() * rng.randf_range(500.0, 900.0)
		var sb := Basis.from_scale(Vector3.ONE * rng.randf_range(0.6, 1.8))
		star_mm.set_instance_transform(i, Transform3D(sb, p))
		var c := Color(0.7, 0.68, 0.64) * rng.randf_range(0.35, 0.95)
		if i % 9 == 0:
			c = Color(0.75, 0.45, 0.25) * rng.randf_range(0.5, 0.9)
		star_mm.set_instance_color(i, c)
	var star_mi := MultiMeshInstance3D.new()
	star_mi.multimesh = star_mm
	add_child(star_mi)

	# far silhouette slabs - dead hulls against the sky
	var slab_mm := MultiMesh.new()
	slab_mm.transform_format = MultiMesh.TRANSFORM_3D
	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3(46.0, 13.0, 4.0)
	var slab_mat := StandardMaterial3D.new()
	slab_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	slab_mat.albedo_color = Color(0.045, 0.04, 0.038)
	slab_mesh.material = slab_mat
	slab_mm.mesh = slab_mesh
	slab_mm.instance_count = 12
	for i in 12:
		var s_side := 1.0 if i % 2 == 0 else -1.0
		var sp := Vector3(9.0 + s_side * rng.randf_range(160.0, 320.0), rng.randf_range(-50.0, 120.0), rng.randf_range(z_min - 150.0, -80.0))
		var bb := Basis.from_euler(Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(0.0, TAU), rng.randf_range(-0.6, 0.6)))
		bb = bb.scaled(Vector3.ONE * rng.randf_range(0.8, 2.4))
		slab_mm.set_instance_transform(i, Transform3D(bb, sp))
	var slab_mi := MultiMeshInstance3D.new()
	slab_mi.multimesh = slab_mm
	add_child(slab_mi)

	# drifting debris chips
	var debris_mat := StandardMaterial3D.new()
	debris_mat.albedo_color = Color(0.32, 0.28, 0.25)
	debris_mat.metallic = 0.5
	debris_mat.roughness = 0.8
	var debris_mm := MultiMesh.new()
	debris_mm.transform_format = MultiMesh.TRANSFORM_3D
	var chip := BoxMesh.new()
	chip.size = Vector3(1.4, 0.5, 1.0)
	chip.material = debris_mat
	debris_mm.mesh = chip
	debris_mm.instance_count = 140
	for i in 140:
		var d_side := 1.0 if rng.randf() < 0.5 else -1.0
		var dx := 9.0 + d_side * rng.randf_range(30.0, 130.0)
		var dy := rng.randf_range(-45.0, 70.0)
		if absf(dx - 9.0) < 42.0 and dy > -12.0 and dy < 12.0:
			dy = -20.0 - rng.randf_range(0.0, 20.0)
		var dz := rng.randf_range(z_min - 60.0, 20.0)
		var db := Basis.from_euler(Vector3(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU)))
		db = db.scaled(Vector3.ONE * rng.randf_range(0.5, 2.2))
		debris_mm.set_instance_transform(i, Transform3D(db, Vector3(dx, dy, dz)))
	var debris_mi := MultiMeshInstance3D.new()
	debris_mi.multimesh = debris_mm
	add_child(debris_mi)

	# wreck A: capital ship snapped amidships, ribs bared at the break
	var a_hull: Array = [
		[box.call(24.0, 6.0, 9.0), _at(Vector3(-17, 0.5, 0), Vector3(0, 0, 6))],
		[box.call(28.0, 7.5, 10.0), _at(Vector3(13, -1.5, 0.8), Vector3(2, 5, -9))],
		[box.call(9.0, 9.0, 11.0), _at(Vector3(26.5, -2.5, 0.8), Vector3(0, 0, -9))],
		[box.call(7.0, 4.0, 4.5), _at(Vector3(10, 4.2, 0), Vector3(0, 0, -9))],
		[cyl.call(0.6, 22.0), _at(Vector3(-26, 5, 2), Vector3(12, 0, 64))],
		[cyl.call(0.8, 8.0), _at(Vector3(-4, 4, -3), Vector3(70, 0, 20))],
	]
	var a_bone: Array = [
		[box.call(23.0, 0.4, 8.2), _at(Vector3(-17, 3.7, 0), Vector3(0, 0, 6))],
		[box.call(0.7, 8.0, 0.7), _at(Vector3(-3.5, 0, 2.8), Vector3(6, 0, 14))],
		[box.call(0.7, 8.5, 0.7), _at(Vector3(-2.6, 0.3, 0), Vector3(-4, 0, -8))],
		[box.call(0.7, 7.5, 0.7), _at(Vector3(-3.8, -0.5, -2.6), Vector3(10, 0, 5))],
		[box.call(3.0, 5.0, 8.0), _at(Vector3(-30.5, 0.5, 0), Vector3(0, 0, 22))],
	]
	var a_glass: Array = [
		[box.call(20.0, 0.7, 0.3), _at(Vector3(-17, 1.6, 4.6), Vector3(0, 0, 6))],
		[box.call(20.0, 0.7, 0.3), _at(Vector3(-17, 1.6, -4.6), Vector3(0, 0, 6))],
		[box.call(24.0, 0.8, 0.3), _at(Vector3(13, 0.4, 5.7), Vector3(2, 5, -9))],
	]
	var a_ember: Array = [
		[box.call(1.0, 4.0, 6.0), _at(Vector3(-3.0, -0.6, 0.5), Vector3(0, 0, -6))],
		[cyl.call(3.0, 0.4), _at(Vector3(31.3, -3.2, 0.8), Vector3(0, 0, 96))],
	]
	var wreck_a := _bake_mesh([
		[hull_mat, a_hull],
		[bone_mat, a_bone],
		[glass_mat, a_glass],
		[ember_mat, a_ember],
	])
	var spacing := absf(z_min) / 4.0
	var reactor_pos := Vector3.ZERO
	for i in 4:
		var inst := MeshInstance3D.new()
		inst.mesh = wreck_a
		var side := 1.0 if i % 2 == 0 else -1.0
		var pos := Vector3(9.0 + side * rng.randf_range(75.0, 110.0), rng.randf_range(-30.0, 55.0), -spacing * (i + 0.5))
		inst.position = pos
		inst.rotation_degrees = Vector3(rng.randf_range(-22.0, 22.0), rng.randf_range(0.0, 360.0), rng.randf_range(-35.0, 35.0))
		inst.scale = Vector3.ONE * rng.randf_range(0.9, 1.25)
		add_child(inst)
		if i == 0:
			reactor_pos = pos

	# wreck B: snapped keel hulk
	var b_hull: Array = [
		[cyl.call(1.1, 30.0), _at(Vector3.ZERO, Vector3(0, 0, 90))],
		[box.call(12.0, 4.5, 7.0), _at(Vector3(-6, -2.2, 1), Vector3(8, 0, -14))],
		[box.call(8.0, 3.5, 6.0), _at(Vector3(7, 1.8, -1.5), Vector3(-5, 10, 18))],
	]
	var b_bone: Array = [
		[box.call(0.6, 7.0, 0.6), _at(Vector3(2, 0, 0), Vector3(0, 0, 15))],
		[box.call(0.6, 6.5, 0.6), _at(Vector3(5, 0.4, 0.6), Vector3(20, 0, -10))],
		[box.call(0.6, 7.5, 0.6), _at(Vector3(-1, -0.3, -0.5), Vector3(-15, 0, 8))],
		[cyl.call(1.3, 3.0), _at(Vector3(-16.2, 0, 0), Vector3(0, 0, 90))],
	]
	var wreck_b := _bake_mesh([
		[hull_mat, b_hull],
		[bone_mat, b_bone],
	])
	for i in 2:
		var inst := MeshInstance3D.new()
		inst.mesh = wreck_b
		var side := -1.0 if i % 2 == 0 else 1.0
		inst.position = Vector3(9.0 + side * rng.randf_range(55.0, 90.0), rng.randf_range(-35.0, 60.0), -spacing * (i + 1.0) + rng.randf_range(-20.0, 20.0))
		inst.rotation_degrees = Vector3(rng.randf_range(-30.0, 30.0), rng.randf_range(0.0, 360.0), rng.randf_range(-50.0, 50.0))
		inst.scale = Vector3.ONE * rng.randf_range(0.8, 1.4)
		add_child(inst)
	var tumbler := MeshInstance3D.new()
	tumbler.mesh = wreck_b
	tumbler.position = Vector3(-69.0, 42.0, -spacing * 3.4)
	tumbler.rotation_degrees = Vector3(18, 140, 0)
	tumbler.scale = Vector3.ONE * 1.1
	add_child(tumbler)
	var tumble_tw := create_tween().set_loops()
	tumble_tw.tween_property(tumbler, "rotation:z", TAU, 110.0).as_relative()

	# dying reactor inside the first wreck: welding-spark flicker
	var reactor := OmniLight3D.new()
	reactor.light_color = Color(1.0, 0.45, 0.15)
	reactor.omni_range = 70.0
	reactor.light_energy = 0.0
	reactor.shadow_enabled = false
	reactor.position = reactor_pos
	add_child(reactor)
	var flicker := create_tween().set_loops()
	flicker.tween_property(reactor, "light_energy", 1.3, 0.12)
	flicker.tween_property(reactor, "light_energy", 0.15, 0.3)
	flicker.tween_property(reactor, "light_energy", 0.9, 0.1)
	flicker.tween_property(reactor, "light_energy", 0.0, 0.6)
	flicker.tween_interval(2.4)
	flicker.tween_property(reactor, "light_energy", 1.1, 0.1)
	flicker.tween_property(reactor, "light_energy", 0.0, 0.4)
	flicker.tween_interval(3.6)

# ---------------- The Bloom (theme 6) ----------------

static var _bloom_moss_tex: ImageTexture

@warning_ignore("unused_parameter")
func _make_bloom_tile(h: int, glow: float, tile_tex: ImageTexture) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var t := (h - 1) / 8.0
	mat.albedo_color = Color(0.82 + 0.14 * t, 0.9 - 0.05 * t, 0.86 - 0.12 * t)
	mat.roughness = 0.85
	mat.metallic = 0.0
	var moss := _get_bloom_moss_texture()
	_apply_tile_texture(mat, moss)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.62).lerp(Color(1.0, 0.78, 0.38), t)
	mat.emission_energy_multiplier = glow * (0.85 + 0.06 * h)
	mat.emission_texture = moss
	mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	return mat

func _get_bloom_moss_texture() -> ImageTexture:
	if _bloom_moss_tex:
		return _bloom_moss_tex
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xB100D
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var n := rng.randf()
			var base := Color(0.16, 0.30, 0.24).lerp(Color(0.24, 0.40, 0.28), n)
			if rng.randf() < 0.04:
				base = base.lerp(Color(0.55, 0.72, 0.50), 0.6)
			img.set_pixel(x, y, base)
	for i in 7:
		var edge := rng.randi_range(0, 3)
		var px := 0.0
		var py := 0.0
		var ang := 0.0
		match edge:
			0:
				px = rng.randf_range(4.0, 60.0)
				py = 1.0
				ang = PI * 0.5
			1:
				px = rng.randf_range(4.0, 60.0)
				py = 62.0
				ang = -PI * 0.5
			2:
				px = 1.0
				py = rng.randf_range(4.0, 60.0)
				ang = 0.0
			_:
				px = 62.0
				py = rng.randf_range(4.0, 60.0)
				ang = PI
		var steps := rng.randi_range(14, 26)
		for s in steps:
			var fade := 1.0 - float(s) / float(steps)
			_bloom_vein_dot(img, int(px), int(py), fade)
			ang += rng.randf_range(-0.6, 0.6)
			px = clampf(px + cos(ang), 1.0, 62.0)
			py = clampf(py + sin(ang), 1.0, 62.0)
	for k in 64:
		for b in 2:
			for p in [Vector2i(k, b), Vector2i(k, 63 - b), Vector2i(b, k), Vector2i(63 - b, k)]:
				var c := img.get_pixel(p.x, p.y)
				img.set_pixel(p.x, p.y, Color(c.r * 0.35, c.g * 0.35, c.b * 0.35))
	img.generate_mipmaps()
	_bloom_moss_tex = ImageTexture.create_from_image(img)
	return _bloom_moss_tex

func _bloom_vein_dot(img: Image, x: int, y: int, fade: float) -> void:
	var vein := Color(0.95, 0.42, 0.58)
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var qx := x + ox
			var qy := y + oy
			if qx < 0 or qx > 63 or qy < 0 or qy > 63:
				continue
			var w := (0.9 * fade) if (ox == 0 and oy == 0) else (0.3 * fade)
			img.set_pixel(qx, qy, img.get_pixel(qx, qy).lerp(vein, w))

func _create_bloom_background():
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xB100
	var z_min := minf(-400.0, _env_end_z - 100.0)

	# Giant luminous fungus: baked once, instanced 6 times
	var stalk_mat := StandardMaterial3D.new()
	stalk_mat.albedo_color = Color(0.10, 0.20, 0.16)
	stalk_mat.roughness = 1.0
	stalk_mat.emission_enabled = true
	stalk_mat.emission = Color(0.15, 0.35, 0.28)
	stalk_mat.emission_energy_multiplier = 0.15
	var cap_mat := StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0.55, 0.20, 0.30)
	cap_mat.roughness = 0.7
	cap_mat.emission_enabled = true
	cap_mat.emission = Color(1.0, 0.45, 0.60)
	cap_mat.emission_energy_multiplier = 1.1
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(1.0, 0.80, 0.50)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(1.0, 0.78, 0.40)
	glow_mat.emission_energy_multiplier = 2.5

	var s1 := CylinderMesh.new()
	s1.bottom_radius = 3.6
	s1.top_radius = 2.6
	s1.height = 34.0
	s1.radial_segments = 10
	s1.rings = 1
	var s2 := CylinderMesh.new()
	s2.bottom_radius = 2.6
	s2.top_radius = 1.9
	s2.height = 26.0
	s2.radial_segments = 10
	s2.rings = 1
	var s3 := CylinderMesh.new()
	s3.bottom_radius = 1.9
	s3.top_radius = 1.2
	s3.height = 18.0
	s3.radial_segments = 10
	s3.rings = 1
	var cap := SphereMesh.new()
	cap.radius = 9.0
	cap.height = 10.0
	cap.radial_segments = 16
	cap.rings = 8
	var gills := TorusMesh.new()
	gills.inner_radius = 4.0
	gills.outer_radius = 8.0
	gills.rings = 24
	gills.ring_segments = 6
	var spot := SphereMesh.new()
	spot.radius = 0.9
	spot.radial_segments = 8
	spot.rings = 4

	var stalk_parts := [
		[s1, _at(Vector3(0.0, 17.0, 0.0), Vector3(0, 0, 4))],
		[s2, _at(Vector3(2.2, 46.0, 0.0), Vector3(0, 0, 11))],
		[s3, _at(Vector3(6.4, 67.0, 0.0), Vector3(0, 0, 20))],
	]
	var cap_parts := [[cap, _at(Vector3(10.5, 79.0, 0.0), Vector3(0, 0, 20))]]
	var glow_parts := [
		[gills, _at(Vector3(10.0, 76.0, 0.0), Vector3(0, 0, 20))],
		[spot, _at(Vector3(8.0, 83.5, 3.0))],
		[spot, _at(Vector3(13.5, 82.5, -2.0))],
		[spot, _at(Vector3(10.5, 84.5, 0.5))],
		[spot, _at(Vector3(7.0, 81.5, -3.5))],
		[spot, _at(Vector3(14.0, 83.0, 2.5))],
	]
	var fungus_mesh := _bake_mesh([[stalk_mat, stalk_parts], [cap_mat, cap_parts], [glow_mat, glow_parts]])
	for i in 6:
		var side := -1.0 if i % 2 == 0 else 1.0
		var fx := 9.0 + side * rng.randf_range(42.0, 70.0)
		var fz := -70.0 - (absf(z_min) - 140.0) * float(i) / 5.0 + rng.randf_range(-20.0, 20.0)
		var mi := MeshInstance3D.new()
		mi.mesh = fungus_mesh
		var sc := rng.randf_range(0.8, 1.35)
		mi.transform = _at(Vector3(fx, -40.0, fz), Vector3(0.0, rng.randf_range(0.0, 360.0), 0.0)).scaled_local(Vector3.ONE * sc)
		add_child(mi)

	# Hanging vine-arcs: 4 tori baked into one mesh
	var vine_mat := StandardMaterial3D.new()
	vine_mat.albedo_color = Color(0.08, 0.17, 0.13)
	vine_mat.roughness = 1.0
	vine_mat.emission_enabled = true
	vine_mat.emission = Color(0.85, 0.40, 0.50)
	vine_mat.emission_energy_multiplier = 0.25
	var arc := TorusMesh.new()
	arc.inner_radius = 43.0
	arc.outer_radius = 45.0
	arc.rings = 40
	arc.ring_segments = 6
	var arc_parts := []
	for i in 4:
		var az := -120.0 - (absf(z_min) - 220.0) * float(i) / 3.0
		arc_parts.append([arc, _at(Vector3(9.0 + rng.randf_range(-8.0, 8.0), -12.0, az), Vector3(90.0, 0.0, rng.randf_range(-10.0, 10.0)))])
	var arcs_mi := MeshInstance3D.new()
	arcs_mi.mesh = _bake_mesh([[vine_mat, arc_parts]])
	add_child(arcs_mi)

	# Garden floor far below
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(700.0, absf(z_min) + 400.0)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.05, 0.10, 0.08)
	floor_mat.roughness = 1.0
	floor_mat.emission_enabled = true
	floor_mat.emission = Color(0.10, 0.22, 0.16)
	floor_mat.emission_energy_multiplier = 0.25
	floor_mesh.material = floor_mat
	var floor_mi := MeshInstance3D.new()
	floor_mi.mesh = floor_mesh
	floor_mi.transform = _at(Vector3(9.0, -55.0, z_min * 0.5))
	add_child(floor_mi)

	# Mother bloom on the horizon: core + corolla baked + 2 aura shells
	var bloom_pos := Vector3(-15.0, 22.0, z_min - 80.0)
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = Color(1.0, 0.60, 0.55)
	core_mat.emission_enabled = true
	core_mat.emission = Color(1.0, 0.55, 0.50)
	core_mat.emission_energy_multiplier = 1.8
	var core_sphere := SphereMesh.new()
	core_sphere.radius = 42.0
	core_sphere.height = 84.0
	core_sphere.radial_segments = 24
	core_sphere.rings = 12
	var corolla := TorusMesh.new()
	corolla.inner_radius = 46.0
	corolla.outer_radius = 58.0
	corolla.rings = 32
	corolla.ring_segments = 8
	var bloom_core := MeshInstance3D.new()
	bloom_core.mesh = _bake_mesh([
		[core_mat, [[core_sphere, Transform3D()]]],
		[glow_mat, [[corolla, _at(Vector3.ZERO, Vector3(70.0, 0.0, 15.0))]]],
	])
	bloom_core.transform = _at(bloom_pos)
	add_child(bloom_core)
	for j in 2:
		var shell := SphereMesh.new()
		shell.radius = 58.0 + 22.0 * j
		shell.height = shell.radius * 2.0
		shell.radial_segments = 20
		shell.rings = 10
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		sm.cull_mode = BaseMaterial3D.CULL_FRONT
		sm.albedo_color = Color(1.0, 0.50, 0.55, 0.16 - 0.07 * j)
		shell.material = sm
		var smi := MeshInstance3D.new()
		smi.mesh = shell
		smi.transform = _at(bloom_pos)
		add_child(smi)

	# Soft radial dot texture shared by motes and fireflies
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var dot_tex := GradientTexture2D.new()
	dot_tex.gradient = grad
	dot_tex.fill = GradientTexture2D.FILL_RADIAL
	dot_tex.fill_from = Vector2(0.5, 0.5)
	dot_tex.fill_to = Vector2(0.5, 0.0)
	dot_tex.width = 32
	dot_tex.height = 32

	# Drifting spore motes: one MultiMesh
	var mote_mat := StandardMaterial3D.new()
	mote_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mote_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mote_mat.albedo_texture = dot_tex
	mote_mat.albedo_color = Color(1.0, 0.75, 0.85, 0.5)
	var mote_quad := QuadMesh.new()
	mote_quad.size = Vector2(0.9, 0.9)
	mote_quad.material = mote_mat
	var motes := MultiMesh.new()
	motes.transform_format = MultiMesh.TRANSFORM_3D
	motes.mesh = mote_quad
	motes.instance_count = 260
	for i in 260:
		var mx := rng.randf_range(-70.0, 90.0)
		var my := rng.randf_range(-15.0, 45.0)
		var mz := rng.randf_range(z_min - 60.0, 20.0)
		if mx > -8.0 and mx < 28.0 and my < 10.0:
			my += 24.0
		motes.set_instance_transform(i, Transform3D(Basis(), Vector3(mx, my, mz)))
	var motes_mi := MultiMeshInstance3D.new()
	motes_mi.multimesh = motes
	add_child(motes_mi)

	# Fireflies: one MultiMesh, material pulsed by tween
	var fly_mat := StandardMaterial3D.new()
	fly_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fly_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fly_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fly_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fly_mat.albedo_texture = dot_tex
	fly_mat.albedo_color = Color(1.0, 0.82, 0.40, 0.8)
	var fly_quad := QuadMesh.new()
	fly_quad.size = Vector2(1.4, 1.4)
	fly_quad.material = fly_mat
	var flies := MultiMesh.new()
	flies.transform_format = MultiMesh.TRANSFORM_3D
	flies.mesh = fly_quad
	flies.instance_count = 70
	for i in 70:
		var fside := -1.0 if rng.randf() < 0.5 else 1.0
		var pos := Vector3(9.0 + fside * rng.randf_range(30.0, 70.0), rng.randf_range(-8.0, 24.0), rng.randf_range(z_min, -20.0))
		flies.set_instance_transform(i, Transform3D(Basis(), pos))
	var flies_mi := MultiMeshInstance3D.new()
	flies_mi.multimesh = flies
	add_child(flies_mi)

	# Two shadowless omni lights
	var l1 := OmniLight3D.new()
	l1.light_color = Color(1.0, 0.55, 0.55)
	l1.light_energy = 1.4
	l1.omni_range = 300.0
	l1.shadow_enabled = false
	l1.position = bloom_pos + Vector3(0.0, 20.0, 60.0)
	add_child(l1)
	var l2 := OmniLight3D.new()
	l2.light_color = Color(1.0, 0.80, 0.50)
	l2.light_energy = 0.7
	l2.omni_range = 140.0
	l2.shadow_enabled = false
	l2.position = Vector3(45.0, 20.0, z_min * 0.4)
	add_child(l2)

	# Ambient motion: the bloom breathes, the fireflies pulse
	var pulse := create_tween().set_loops()
	pulse.tween_property(bloom_core, "scale", Vector3.ONE * 1.03, 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(bloom_core, "scale", Vector3.ONE, 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var flicker2 := create_tween().set_loops()
	flicker2.tween_property(fly_mat, "albedo_color", Color(1.0, 0.86, 0.48, 0.9), 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	flicker2.tween_property(fly_mat, "albedo_color", Color(1.0, 0.72, 0.32, 0.35), 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# ---------------- Wormhole (theme 7) ----------------

static var _worm_ripple_tex: ImageTexture

func _get_worm_ripple_texture() -> ImageTexture:
	if _worm_ripple_tex != null:
		return _worm_ripple_tex
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x4802
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length()
			var band := 0.5 + 0.5 * sin(d * 0.65)
			var v := 0.3 + band * 0.5 + rng.randf() * 0.04
			var edge := mini(mini(x, 63 - x), mini(y, 63 - y))
			if edge == 0:
				v = 1.0
			elif edge == 1:
				v = 0.8
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	_worm_ripple_tex = ImageTexture.create_from_image(img)
	return _worm_ripple_tex

@warning_ignore("unused_parameter")
func _make_wormhole_tile(h: int, glow: float, tile_tex: ImageTexture) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var t := clampf((h - 1) / 8.0, 0.0, 1.0)
	mat.albedo_color = Color(0.10, 0.08, 0.18).lerp(Color(0.16, 0.08, 0.2), t)
	mat.metallic = 0.4
	mat.roughness = 0.3
	var ripple := _get_worm_ripple_texture()
	_apply_tile_texture(mat, ripple)
	mat.emission_enabled = true
	mat.emission = Color(0.45, 0.3, 1.0).lerp(Color(0.3, 0.75, 1.0), t)
	mat.emission_energy_multiplier = glow * (0.9 + 0.4 * t)
	mat.emission_texture = ripple
	return mat

# Twin bores teleport: entering one drops you into the other at the same
# row and height (solve_level.py::find_portal_swaps mirrors this rule)
func _portal_swap(prow: int, pcol: int):
	var row: Array = _tunnels[prow]
	var runs: Array = []
	var c := 0
	while c < _cols:
		if row[c]:
			var start := c
			while c < _cols and row[c]:
				c += 1
			runs.append([start, c - 1])
		else:
			c += 1
	if runs.size() != 2:
		return
	var mine := -1
	for i in runs.size():
		if pcol >= runs[i][0] and pcol <= runs[i][1]:
			mine = i
	if mine < 0:
		return
	var other: Array = runs[1 - mine]
	var own: Array = runs[mine]
	var dx := (float(other[0] + other[1]) - float(own[0] + own[1])) * 0.5 * TILE_SIZE
	_ship.global_position.x += dx
	_ship.reset_physics_interpolation()

func _portal_transit(entering: bool):
	var pal: Color = WORM_PALETTE[_portal_hops % WORM_PALETTE.size()]
	if not entering:
		_portal_hops += 1
		pal = WORM_PALETTE[_portal_hops % WORM_PALETTE.size()]
		if _wormhole_fill:
			_wormhole_fill.light_color = pal
	# Screen flash in the region's color
	var flash := ColorRect.new()
	flash.color = Color(pal.r, pal.g, pal.b, 0.4)
	flash.anchor_right = 1
	flash.anchor_bottom = 1
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_canvas.add_child(flash)
	var ft := create_tween()
	ft.tween_property(flash, "color:a", 0.0, 0.35)
	ft.tween_callback(flash.queue_free)
	# FOV punch sells the jump
	var tw := create_tween()
	tw.tween_property(_camera, "fov", 84.0, 0.1).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_camera, "fov", 75.0, 0.3).set_trans(Tween.TRANS_SINE)

func _create_wormhole_background():
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x40E
	var z_min := minf(-400.0, _env_end_z - 100.0)
	var vortex_pos := Vector3(9.0, 14.0, z_min - 160.0)

	# The vortex maw: nested tilted rings in two colors baked into one
	# mesh, slowly rotating around the view axis
	var violet := StandardMaterial3D.new()
	violet.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	violet.albedo_color = Color(0.55, 0.3, 1.0)
	violet.emission_enabled = true
	violet.emission = Color(0.5, 0.25, 1.0)
	violet.emission_energy_multiplier = 2.2
	var cyan := StandardMaterial3D.new()
	cyan.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cyan.albedo_color = Color(0.3, 0.9, 1.0)
	cyan.emission_enabled = true
	cyan.emission = Color(0.25, 0.85, 1.0)
	cyan.emission_energy_multiplier = 2.2
	var vparts: Array = []
	var cparts: Array = []
	for i in 6:
		var t := TorusMesh.new()
		t.inner_radius = 10.0 + i * 7.0
		t.outer_radius = t.inner_radius + 1.6 + i * 0.3
		t.rings = 48
		t.ring_segments = 6
		var tilt := Vector3(90.0 + rng.randf_range(-13.0, 13.0), rng.randf_range(-9.0, 9.0), 0.0)
		if i % 2 == 0:
			vparts.append([t, _at(Vector3.ZERO, tilt)])
		else:
			cparts.append([t, _at(Vector3.ZERO, tilt)])
	var vortex := MeshInstance3D.new()
	vortex.mesh = _bake_mesh([[violet, vparts], [cyan, cparts]])
	vortex.position = vortex_pos
	add_child(vortex)
	var spin := create_tween().set_loops()
	spin.tween_property(vortex, "rotation:z", TAU, 26.0).as_relative()

	# Blazing singularity core
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(0.95, 0.9, 1.0)
	core_mat.emission_enabled = true
	core_mat.emission = Color(0.85, 0.75, 1.0)
	core_mat.emission_energy_multiplier = 4.0
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 6.0
	core_mesh.height = 12.0
	core_mesh.radial_segments = 16
	core_mesh.rings = 8
	core_mesh.material = core_mat
	var core := MeshInstance3D.new()
	core.mesh = core_mesh
	core.position = vortex_pos
	add_child(core)
	var core_light := OmniLight3D.new()
	core_light.light_color = Color(0.7, 0.55, 1.0)
	core_light.light_energy = 1.8
	core_light.omni_range = 250.0
	core_light.shadow_enabled = false
	core_light.position = vortex_pos
	add_child(core_light)

	# Matter streaks being pulled toward the vortex (one MultiMesh)
	var streak_mesh := BoxMesh.new()
	streak_mesh.size = Vector3(0.14, 0.14, 9.0)
	var streak_mat := StandardMaterial3D.new()
	streak_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak_mat.vertex_color_use_as_albedo = true
	streak_mesh.material = streak_mat
	var streak_mm := MultiMesh.new()
	streak_mm.transform_format = MultiMesh.TRANSFORM_3D
	streak_mm.use_colors = true
	streak_mm.mesh = streak_mesh
	streak_mm.instance_count = 120
	for i in 120:
		var side := -1.0 if i % 2 == 0 else 1.0
		var p := Vector3(
			9.0 + side * rng.randf_range(26.0, 120.0),
			rng.randf_range(-25.0, 65.0),
			rng.randf_range(z_min - 60.0, 10.0)
		)
		var dir := (vortex_pos - p).normalized()
		var sb := Basis.looking_at(dir).scaled(Vector3.ONE * rng.randf_range(0.5, 1.6))
		streak_mm.set_instance_transform(i, Transform3D(sb, p))
		var c := Color(0.6, 0.4, 1.0) if rng.randf() < 0.6 else Color(0.3, 0.85, 1.0)
		streak_mm.set_instance_color(i, c * rng.randf_range(0.5, 1.0))
	var streaks := MultiMeshInstance3D.new()
	streaks.multimesh = streak_mm
	add_child(streaks)

	# Slow spacetime dust (one billboard MultiMesh)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var dot_tex := GradientTexture2D.new()
	dot_tex.gradient = grad
	dot_tex.fill = GradientTexture2D.FILL_RADIAL
	dot_tex.fill_from = Vector2(0.5, 0.5)
	dot_tex.fill_to = Vector2(0.5, 0.0)
	dot_tex.width = 32
	dot_tex.height = 32
	var dust_mat := StandardMaterial3D.new()
	dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dust_mat.albedo_texture = dot_tex
	dust_mat.albedo_color = Color(0.7, 0.55, 1.0, 0.4)
	var dust_quad := QuadMesh.new()
	dust_quad.size = Vector2(0.8, 0.8)
	dust_quad.material = dust_mat
	var dust_mm := MultiMesh.new()
	dust_mm.transform_format = MultiMesh.TRANSFORM_3D
	dust_mm.mesh = dust_quad
	dust_mm.instance_count = 200
	for i in 200:
		var dx := rng.randf_range(-80.0, 100.0)
		var dy := rng.randf_range(-20.0, 55.0)
		if dx > -10.0 and dx < 30.0 and dy < 10.0:
			dy += 28.0
		dust_mm.set_instance_transform(i, Transform3D(Basis(), Vector3(dx, dy, rng.randf_range(z_min - 40.0, 15.0))))
	var dust := MultiMeshInstance3D.new()
	dust.multimesh = dust_mm
	add_child(dust)

	# A second region light mid-track, re-tinted per hop via the fill
	var mid_light := OmniLight3D.new()
	mid_light.light_color = Color(0.4, 0.8, 1.0)
	mid_light.light_energy = 0.8
	mid_light.omni_range = 160.0
	mid_light.shadow_enabled = false
	mid_light.position = Vector3(30.0, 25.0, z_min * 0.45)
	add_child(mid_light)
