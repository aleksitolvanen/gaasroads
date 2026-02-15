extends Node3D

var level_path: String

const TILE_SIZE := 2.0
const TILE_HEIGHT := 0.5
const TUNNEL_CLEARANCE := 3.5

var _fallback_level := [
	"1.1.1.1.1.1.1.1.1.1.", "1.1.1.1.1.1.1.1.1.1.",
	"1.1.1.1.1.1.1.1.1.1.", "1.1.1.1.1.1.1.1.1.1.",
	"1.1.1.1.1.1.1.1.1.1.", "1.1.1.1.1.1.1.1.1.1.",
	"1.1.1.......1.1.1.", "1.1.1.......1.1.1.",
	"1.1.1.1.1.1.1.1.1.1.", "1.1.1.1.1.1.1.1.1.1.",
	"1...............1.", "1...............1.",
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
var _finishing := false
var _laser_timer := 0.0
var _laser_rng := RandomNumberGenerator.new()
var _mothership_active := false
var _fighters: Array[Node3D] = []
var _green_laser_mat: StandardMaterial3D
var _red_laser_mat: StandardMaterial3D
var _timer_label: Label
var _share_panel: Control
var _share_text: LineEdit
var _timer_running := false
var _share_open := false
var _level_content := ""
var _endless_generated_rows := 0

func _ready():
	level_path = GameState.selected_level
	_ship = $Ship
	_ship.frozen = false
	_ship.current_speed = 12.0
	_ship.warped.connect(_on_ship_warped)
	_ship.exploded.connect(_on_ship_exploded)

	match GameState.selected_group:
		2: # Solar Burn - low gravity
			_ship.gravity = 12.0
			_ship.jump_velocity = 10.0
		3: # Dark Matter - low gravity, floaty jumps
			_ship.gravity = 8.0
			_ship.jump_velocity = 7.8
	_camera = $Camera3D
	GameState.elapsed_time = 0.0
	_timer_running = false
	_create_space_environment()
	_create_hud()
	_load_level()
	Music.play_for_group(GameState.selected_group)

func _process(delta):
	if _share_open:
		return
	if Input.is_action_just_pressed("ui_cancel") or Input.is_physical_key_pressed(KEY_Q):
		get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")
		return

	var ship_pos := _ship.global_position

	if _mothership_active and not _finishing:
		_update_fighters(ship_pos)
		_laser_timer -= delta
		if _laser_timer <= 0:
			_laser_timer = _laser_rng.randf_range(0.08, 0.25)
			_spawn_laser(ship_pos)

	if not GameState.is_endless and not _finishing and ship_pos.z < _level_end_z - 5.0:
		_finishing = true
		_ship.start_warp()
		_create_warp_streaks()

	if not _finishing:
		_camera.global_position = Vector3(ship_pos.x, ship_pos.y + 2.5, ship_pos.z + 4.2)
		_camera.look_at(ship_pos + Vector3(0, -1.5, -6), Vector3.UP)
	else:
		# Camera stays put, looks at the ship as it flies up and away
		_camera.look_at(ship_pos, Vector3.UP)

	if _bg_quad:
		_bg_quad.global_position = Vector3(ship_pos.x, ship_pos.y - 20, ship_pos.z - 120)

	_speed_gauge.value = _ship.current_speed
	_speed_label.text = "%d" % _ship.current_speed

	# Timer
	if not _timer_running and _ship.current_speed > 0 and not _finishing:
		_timer_running = true
	if _timer_running and not _finishing:
		GameState.elapsed_time += delta
	if _timer_label:
		if GameState.is_endless:
			var dist := int(absf(ship_pos.z))
			_timer_label.text = "%dm" % dist
		else:
			_timer_label.text = GameState.format_time(GameState.elapsed_time) if GameState.elapsed_time > 0.0 else "0:00.00"

	# Endless mode: generate more chunks as player approaches end
	if GameState.is_endless and not _finishing:
		var dist_to_end := ship_pos.z - _level_end_z
		if dist_to_end < 600:
			_generate_endless_chunk()

func _create_hud():
	var canvas := CanvasLayer.new()
	_hud_canvas = canvas
	add_child(canvas)

	if ResourceLoader.exists("res://cockpit.png"):
		var cockpit_rect := TextureRect.new()
		cockpit_rect.texture = load("res://cockpit.png")
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
	share_hint.text = "C: share track"
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

func _create_space_environment():
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	match GameState.selected_group:
		2:  # Solar - very dark ambient, sun does the work
			env.ambient_light_color = Color(0.08, 0.06, 0.04)
			env.ambient_light_energy = 0.3
		1:  # Nebula
			env.ambient_light_color = Color(0.12, 0.08, 0.15)
			env.ambient_light_energy = 0.4
		3:  # Dark Matter
			env.ambient_light_color = Color(0.06, 0.1, 0.08)
			env.ambient_light_energy = 0.3
		_:  # Cosmic Highway
			env.ambient_light_color = Color(0.08, 0.08, 0.12)
			env.ambient_light_energy = 0.4

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
			sun.light_energy = 1.2
		_:  # Cosmic Highway - cool starlight from upper-left
			sun.basis = Basis.looking_at((light_target - Vector3(-30, 40, -200)).normalized())
			sun.light_color = Color(0.8, 0.85, 1.0)
			sun.light_energy = 1.0
	add_child(sun)

	match GameState.selected_group:
		1:
			_create_nebula_background()
		2:
			_create_solar_background()
		3:
			_create_dark_matter_background()
		_:
			_create_image_background()

func _create_image_background():
	if ResourceLoader.exists("res://background.png"):
		_bg_quad = MeshInstance3D.new()
		var quad_mesh := QuadMesh.new()
		quad_mesh.size = Vector2(500, 300)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = load("res://background.png")
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

	var star_z_min := minf(-400, _level_end_z - 100)
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
	var track_length := absf(_level_end_z)
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
		haze_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
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

		# Dust particles scattered around the ring
		var dust_count := rng.randi_range(12, 25)
		for _j in dust_count:
			var angle := rng.randf() * TAU
			var r := rng.randf_range(inner * 0.7, outer * 1.1)
			var dust := MeshInstance3D.new()
			var dm := QuadMesh.new()
			var ds := rng.randf_range(0.3, 0.8)
			dm.size = Vector2(ds, ds)
			dm.material = dust_mat
			dust.mesh = dm
			dust.position = Vector3(cos(angle) * r, sin(angle) * r, rng.randf_range(-2, 2))
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

	var solar_z_min := minf(-400, _level_end_z - 100)
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
	haze_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
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

	var dark_z_min := minf(-500, _level_end_z - 100)
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
	var track_length := absf(_level_end_z)
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

	# Create a small fighter: body + two prongs + engine glow
	for i in 8:
		var fighter := Node3D.new()

		var fbody := MeshInstance3D.new()
		var fbody_mesh := BoxMesh.new()
		fbody_mesh.size = Vector3(1.5, 0.6, 3.0)
		fbody_mesh.material = fighter_mat
		fbody.mesh = fbody_mesh
		fighter.add_child(fbody)

		var lprong := MeshInstance3D.new()
		var prong_m := BoxMesh.new()
		prong_m.size = Vector3(0.4, 0.3, 2.0)
		prong_m.material = fighter_mat
		lprong.mesh = prong_m
		lprong.position = Vector3(-1.2, 0, -0.8)
		fighter.add_child(lprong)

		var rprong := MeshInstance3D.new()
		rprong.mesh = prong_m
		rprong.position = Vector3(1.2, 0, -0.8)
		fighter.add_child(rprong)

		var feng := MeshInstance3D.new()
		var feng_mesh := BoxMesh.new()
		feng_mesh.size = Vector3(0.8, 0.3, 0.3)
		feng_mesh.material = fighter_glow
		feng.mesh = feng_mesh
		feng.position = Vector3(0, 0, 1.6)
		fighter.add_child(feng)

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

func _build_mothership(ship_root: Node3D, hull_mat: StandardMaterial3D, glow_mat: StandardMaterial3D, red_glow_mat: StandardMaterial3D, rng: RandomNumberGenerator):
	var hull := MeshInstance3D.new()
	var hull_mesh := CylinderMesh.new()
	hull_mesh.top_radius = 25.0
	hull_mesh.bottom_radius = 28.0
	hull_mesh.height = 6.0
	hull_mesh.material = hull_mat
	hull.mesh = hull_mesh
	ship_root.add_child(hull)

	var bridge := MeshInstance3D.new()
	var bridge_mesh := CylinderMesh.new()
	bridge_mesh.top_radius = 6.0
	bridge_mesh.bottom_radius = 10.0
	bridge_mesh.height = 10.0
	bridge_mesh.material = hull_mat
	bridge.mesh = bridge_mesh
	bridge.position = Vector3(0, 8, 0)
	ship_root.add_child(bridge)

	var dome := MeshInstance3D.new()
	var dome_mesh := SphereMesh.new()
	dome_mesh.radius = 6.5
	dome_mesh.height = 7.0
	dome_mesh.material = hull_mat
	dome.mesh = dome_mesh
	dome.position = Vector3(0, 13, 0)
	ship_root.add_child(dome)

	var prong_mesh := BoxMesh.new()
	prong_mesh.size = Vector3(3.0, 2.0, 35.0)
	prong_mesh.material = hull_mat
	var prong_l := MeshInstance3D.new()
	prong_l.mesh = prong_mesh
	prong_l.position = Vector3(-8, -1, -25)
	ship_root.add_child(prong_l)
	var prong_r := MeshInstance3D.new()
	prong_r.mesh = prong_mesh
	prong_r.position = Vector3(8, -1, -25)
	ship_root.add_child(prong_r)

	var engine_block := MeshInstance3D.new()
	var engine_mesh := BoxMesh.new()
	engine_mesh.size = Vector3(18.0, 5.0, 12.0)
	engine_mesh.material = hull_mat
	engine_block.mesh = engine_mesh
	engine_block.position = Vector3(0, -1, 22)
	ship_root.add_child(engine_block)

	var strip_mesh := BoxMesh.new()
	strip_mesh.size = Vector3(20.0, 0.3, 1.0)
	strip_mesh.material = glow_mat
	for z_off in [-10.0, -3.0, 4.0, 11.0]:
		var strip := MeshInstance3D.new()
		strip.mesh = strip_mesh
		strip.position = Vector3(0, -3.2, z_off)
		ship_root.add_child(strip)

	var tip_mesh := BoxMesh.new()
	tip_mesh.size = Vector3(2.0, 1.5, 2.0)
	tip_mesh.material = glow_mat
	var tip_l := MeshInstance3D.new()
	tip_l.mesh = tip_mesh
	tip_l.position = Vector3(-8, -1, -43)
	ship_root.add_child(tip_l)
	var tip_r := MeshInstance3D.new()
	tip_r.mesh = tip_mesh
	tip_r.position = Vector3(8, -1, -43)
	ship_root.add_child(tip_r)

	var engine_glow_mesh := CylinderMesh.new()
	engine_glow_mesh.top_radius = 2.0
	engine_glow_mesh.bottom_radius = 2.5
	engine_glow_mesh.height = 1.5
	engine_glow_mesh.material = red_glow_mat
	for x_off in [-5.0, 0.0, 5.0]:
		var eg := MeshInstance3D.new()
		eg.mesh = engine_glow_mesh
		eg.position = Vector3(x_off, -1, 28.5)
		eg.rotation_degrees = Vector3(90, 0, 0)
		ship_root.add_child(eg)

	var window_mesh := BoxMesh.new()
	window_mesh.size = Vector3(8.0, 1.5, 0.3)
	window_mesh.material = glow_mat
	var window := MeshInstance3D.new()
	window.mesh = window_mesh
	window.position = Vector3(0, 12, -6.5)
	ship_root.add_child(window)

	var aura_mat := StandardMaterial3D.new()
	aura_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	aura_mat.albedo_color = Color(0.1, 0.25, 0.15, 0.04)
	aura_mat.emission_enabled = true
	aura_mat.emission = Color(0.05, 0.15, 0.1)
	aura_mat.emission_energy_multiplier = 1.0
	aura_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	aura_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
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

	var escort_offsets := [
		Vector3(-35, 5, 10), Vector3(40, -3, -5), Vector3(-15, 12, -20),
		Vector3(50, 8, 15), Vector3(-45, -2, -10), Vector3(20, -6, 25),
	]

	for i in escort_offsets.size():
		var escort := Node3D.new()
		escort.position = escort_offsets[i]
		escort.rotation_degrees = Vector3(rng.randf_range(-8, 8), rng.randf_range(-40, 40), rng.randf_range(-8, 8))

		var ehull := MeshInstance3D.new()
		var ehull_mesh := CylinderMesh.new()
		ehull_mesh.top_radius = 5.0
		ehull_mesh.bottom_radius = 7.0
		ehull_mesh.height = 2.0
		ehull_mesh.material = escort_hull_mat
		ehull.mesh = ehull_mesh
		escort.add_child(ehull)

		var ebridge := MeshInstance3D.new()
		var ebridge_mesh := CylinderMesh.new()
		ebridge_mesh.top_radius = 1.5
		ebridge_mesh.bottom_radius = 2.2
		ebridge_mesh.height = 1.8
		ebridge_mesh.material = escort_hull_mat
		ebridge.mesh = ebridge_mesh
		ebridge.position = Vector3(0, 1.8, 0)
		escort.add_child(ebridge)

		var spike := MeshInstance3D.new()
		var spike_mesh := BoxMesh.new()
		spike_mesh.size = Vector3(0.7, 0.5, 8.0)
		spike_mesh.material = escort_hull_mat
		spike.mesh = spike_mesh
		spike.position = Vector3(0, -0.3, -8.0)
		escort.add_child(spike)

		var light_mesh := BoxMesh.new()
		light_mesh.size = Vector3(0.6, 0.6, 0.6)
		light_mesh.material = white_light_mat
		var lw1 := MeshInstance3D.new()
		lw1.mesh = light_mesh
		lw1.position = Vector3(-6.5, 0, 0)
		escort.add_child(lw1)
		var lw2 := MeshInstance3D.new()
		lw2.mesh = light_mesh
		lw2.position = Vector3(6.5, 0, 0)
		escort.add_child(lw2)

		var lo_mesh := BoxMesh.new()
		lo_mesh.size = Vector3(0.7, 0.4, 0.7)
		lo_mesh.material = orange_light_mat
		var lo1 := MeshInstance3D.new()
		lo1.mesh = lo_mesh
		lo1.position = Vector3(0, -1.2, 3.0)
		escort.add_child(lo1)
		var lo2 := MeshInstance3D.new()
		lo2.mesh = lo_mesh
		lo2.position = Vector3(0, -1.2, -3.0)
		escort.add_child(lo2)

		var eeng := MeshInstance3D.new()
		var eeng_mesh := BoxMesh.new()
		eeng_mesh.size = Vector3(2.5, 0.8, 0.8)
		eeng_mesh.material = glow_mat
		eeng.mesh = eeng_mesh
		eeng.position = Vector3(0, -0.2, 7.5)
		escort.add_child(eeng)

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

	var laser := MeshInstance3D.new()
	var laser_mesh := BoxMesh.new()
	laser_mesh.size = Vector3(0.15, 0.15, 15.0)
	laser_mesh.material = mat
	laser.mesh = laser_mesh
	laser.global_position = origin
	laser.look_at(origin + dir)
	add_child(laser)

	var speed := _laser_rng.randf_range(40.0, 70.0)
	var dist := origin.distance_to(target) + 80.0
	var travel_time := dist / speed
	var end_pos := origin + dir * dist
	var tween := create_tween()
	tween.tween_property(laser, "global_position", end_pos, travel_time).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(laser.queue_free)

func _load_level():
	var level_node := $Level
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
		content = "\n".join(_fallback_level)
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

	_level_content = content

	# Prepend a flat runway before the level content
	var runway_row := "..".repeat(2) + "1.".repeat(6) + "..".repeat(2)
	var runway_lines := PackedStringArray()
	for _i in 24:
		runway_lines.append(runway_row)

	var lines := runway_lines + content.split("\n")
	# Remove trailing empty lines
	while lines.size() > 0 and lines[-1].strip_edges() == "":
		lines.remove_at(lines.size() - 1)
	var rows := lines.size()

	# Parse 2-char tile format: each tile = [height_char][modifier_char]
	var cols := 0
	for line in lines:
		var c := line.length() / 2
		if c > cols:
			cols = c

	_level_end_z = -(rows - 1) * TILE_SIZE
	if GameState.is_endless:
		_endless_generated_rows = rows - 24  # subtract runway

	var grid: Array[Array] = []
	var tunnels: Array[Array] = []
	for r in rows:
		var floor_row: Array[int] = []
		floor_row.resize(cols)
		floor_row.fill(0)
		var tunnel_row: Array[bool] = []
		tunnel_row.resize(cols)
		tunnel_row.fill(false)

		var line := lines[r]
		for ci in range(0, line.length(), 2):
			var tile_idx := ci / 2
			if tile_idx >= cols:
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

	var group_colors := [
		Color(0.4, 0.65, 1.0),
		Color(0.7, 0.4, 0.9),
		Color(1.0, 0.6, 0.25),
		Color(0.4, 0.9, 0.6),
	]
	var base_color: Color = group_colors[clampi(GameState.selected_group, 0, 3)]

	var height_materials: Dictionary = {}
	for h in range(1, 10):
		var mat := StandardMaterial3D.new()
		var brightness := 1.2 + (h - 1) * 0.1
		mat.albedo_color = base_color * brightness
		mat.albedo_color.a = 1.0
		mat.emission_enabled = true
		mat.emission = base_color * 0.3
		mat.emission_energy_multiplier = 0.5
		height_materials[h] = mat

	# Tunnel ceiling material - darker variant
	var ceil_mat := StandardMaterial3D.new()
	ceil_mat.albedo_color = base_color.darkened(0.3)
	ceil_mat.albedo_color.a = 1.0
	ceil_mat.emission_enabled = true
	ceil_mat.emission = base_color * 0.15
	ceil_mat.emission_energy_multiplier = 0.3

	# Greedy-merge floor tiles
	var used: Array[Array] = []
	for r in rows:
		var row: Array[bool] = []
		row.resize(cols)
		row.fill(false)
		used.append(row)

	for r in rows:
		for c in cols:
			var height: int = grid[r][c]
			if height == 0 or used[r][c]:
				continue

			var w := 0
			while c + w < cols and grid[r][c + w] == height and not used[r][c + w]:
				w += 1

			var h := 1
			while r + h < rows:
				var ok := true
				for cc in range(c, c + w):
					if cc >= cols or grid[r + h][cc] != height or used[r + h][cc]:
						ok = false
						break
				if not ok:
					break
				h += 1

			for rr in range(r, r + h):
				for cc in range(c, c + w):
					used[rr][cc] = true

			var actual_height := height * TILE_HEIGHT
			var tile := _create_merged_tile(w, h, actual_height, height_materials[height])
			tile.position = Vector3(
				c * TILE_SIZE + (w - 1) * TILE_SIZE / 2.0,
				actual_height / 2.0,
				-r * TILE_SIZE - (h - 1) * TILE_SIZE / 2.0
			)
			level_node.add_child(tile)

	# Build arched tunnels — merge consecutive tunnel rows at same column/height
	var t_used: Array[Array] = []
	for r in rows:
		var row: Array[bool] = []
		row.resize(cols)
		row.fill(false)
		t_used.append(row)

	var tunnel_wall_mat := StandardMaterial3D.new()
	tunnel_wall_mat.albedo_color = base_color.darkened(0.4)
	tunnel_wall_mat.emission_enabled = true
	tunnel_wall_mat.emission = base_color * 0.1
	tunnel_wall_mat.emission_energy_multiplier = 0.3
	tunnel_wall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	for r in rows:
		for c in cols:
			if not tunnels[r][c] or t_used[r][c] or grid[r][c] == 0:
				continue
			var floor_h: int = grid[r][c]
			# Merge along Z (consecutive rows, same column and height)
			var depth := 0
			while r + depth < rows and tunnels[r + depth][c] and grid[r + depth][c] == floor_h and not t_used[r + depth][c]:
				depth += 1
			for rr in range(r, r + depth):
				t_used[rr][c] = true

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
			arch_mesh.surface_set_material(0, tunnel_wall_mat)

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

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_C and not _finishing:
			if _share_open:
				_close_share_dialog()
			else:
				_open_share_dialog()
		elif event.keycode == KEY_ESCAPE and _share_open:
			_close_share_dialog()
			get_viewport().set_input_as_handled()

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
	_share_text.text = _level_content
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
	DisplayServer.clipboard_set(_level_content)
	btn.text = "Copied!"

func _close_share_dialog():
	_share_open = false
	get_tree().paused = false
	if _share_panel:
		_share_panel.queue_free()
		_share_panel = null
		_share_text = null

func _generate_endless_chunk():
	var params: Dictionary = GameState.endless_params.duplicate()
	params["seed"] = randi()
	params["length"] = 200
	var content := LevelGenerator.generate(params)
	var lines := content.split("\n")
	while lines.size() > 0 and lines[-1].strip_edges() == "":
		lines.remove_at(lines.size() - 1)

	var level_node := $Level
	var row_offset := _endless_generated_rows
	var chunk_rows := lines.size()
	_endless_generated_rows += chunk_rows
	_level_end_z = -(_endless_generated_rows + 24) * TILE_SIZE

	var cols := 10
	var group_colors := [
		Color(0.4, 0.65, 1.0), Color(0.7, 0.4, 0.9),
		Color(1.0, 0.6, 0.25), Color(0.4, 0.9, 0.6),
	]
	var base_color: Color = group_colors[clampi(GameState.selected_group, 0, 3)]

	var height_materials: Dictionary = {}
	for h in range(1, 10):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = base_color * (1.2 + (h - 1) * 0.1)
		mat.albedo_color.a = 1.0
		mat.emission_enabled = true
		mat.emission = base_color * 0.3
		mat.emission_energy_multiplier = 0.5
		height_materials[h] = mat

	var tunnel_wall_mat := StandardMaterial3D.new()
	tunnel_wall_mat.albedo_color = base_color.darkened(0.4)
	tunnel_wall_mat.emission_enabled = true
	tunnel_wall_mat.emission = base_color * 0.1
	tunnel_wall_mat.emission_energy_multiplier = 0.3
	tunnel_wall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Parse chunk
	var grid: Array[Array] = []
	var tunnels_arr: Array[Array] = []
	for r in chunk_rows:
		var floor_row: Array[int] = []
		floor_row.resize(cols)
		floor_row.fill(0)
		var tunnel_row: Array[bool] = []
		tunnel_row.resize(cols)
		tunnel_row.fill(false)
		var line := lines[r]
		for ci in range(0, line.length(), 2):
			var tile_idx := ci / 2
			if tile_idx >= cols:
				break
			var h_char := line[ci]
			var m_char := line[ci + 1] if ci + 1 < line.length() else "."
			if h_char >= "1" and h_char <= "9":
				floor_row[tile_idx] = h_char.unicode_at(0) - "0".unicode_at(0)
			if m_char == "T" or m_char == "t":
				tunnel_row[tile_idx] = true
		grid.append(floor_row)
		tunnels_arr.append(tunnel_row)

	# Build floor tiles (simple per-tile, no greedy merge for chunks)
	for r in chunk_rows:
		for c in cols:
			var height: int = grid[r][c]
			if height == 0:
				continue
			var actual_height := height * TILE_HEIGHT
			var tile := _create_merged_tile(1, 1, actual_height, height_materials[height])
			tile.position = Vector3(
				c * TILE_SIZE,
				actual_height / 2.0,
				-(row_offset + 24 + r) * TILE_SIZE
			)
			level_node.add_child(tile)

	# Build tunnel arches
	var t_used: Array[Array] = []
	for r in chunk_rows:
		var row: Array[bool] = []
		row.resize(cols)
		row.fill(false)
		t_used.append(row)

	for r in chunk_rows:
		for c in cols:
			if not tunnels_arr[r][c] or t_used[r][c] or grid[r][c] == 0:
				continue
			var floor_h: int = grid[r][c]
			var depth := 0
			while r + depth < chunk_rows and tunnels_arr[r + depth][c] and grid[r + depth][c] == floor_h and not t_used[r + depth][c]:
				depth += 1
			for rr in range(r, r + depth):
				t_used[rr][c] = true

			var base_y := floor_h * TILE_HEIGHT
			var arch_height := 1.2
			var half_w := TILE_SIZE / 2.0
			var wall_thickness := 0.06
			var center_x := c * TILE_SIZE
			var center_z := -(row_offset + 24 + r) * TILE_SIZE - (depth - 1) * TILE_SIZE / 2.0
			var tunnel_depth := depth * TILE_SIZE

			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var z_front := tunnel_depth / 2.0
			var z_back := -tunnel_depth / 2.0
			var arch_segments := 24
			var min_y := 0.1
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
				var o0f := Vector3(x0, y0, z_front)
				var o1f := Vector3(x1, y1, z_front)
				var o0b := Vector3(x0, y0, z_back)
				var o1b := Vector3(x1, y1, z_back)
				var i0f := o0f - n0 * wall_thickness
				var i1f := o1f - n1 * wall_thickness
				var i0b := o0b - n0 * wall_thickness
				var i1b := o1b - n1 * wall_thickness
				st.set_normal(n0); st.add_vertex(o0f)
				st.set_normal(n1); st.add_vertex(o1f)
				st.set_normal(n0); st.add_vertex(o0b)
				st.set_normal(n1); st.add_vertex(o1f)
				st.set_normal(n1); st.add_vertex(o1b)
				st.set_normal(n0); st.add_vertex(o0b)
				st.set_normal(-n0); st.add_vertex(i0b)
				st.set_normal(-n1); st.add_vertex(i1f)
				st.set_normal(-n0); st.add_vertex(i0f)
				st.set_normal(-n0); st.add_vertex(i0b)
				st.set_normal(-n1); st.add_vertex(i1b)
				st.set_normal(-n1); st.add_vertex(i1f)
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
				var fz := Vector3(0, 0, z_front)
				var fn := Vector3(0, 0, 1)
				st.set_normal(fn); st.add_vertex(o0 + fz)
				st.set_normal(fn); st.add_vertex(i1 + fz)
				st.set_normal(fn); st.add_vertex(i0 + fz)
				st.set_normal(fn); st.add_vertex(o0 + fz)
				st.set_normal(fn); st.add_vertex(o1 + fz)
				st.set_normal(fn); st.add_vertex(i1 + fz)
				var bz := Vector3(0, 0, z_back)
				var bn := Vector3(0, 0, -1)
				st.set_normal(bn); st.add_vertex(i0 + bz)
				st.set_normal(bn); st.add_vertex(i1 + bz)
				st.set_normal(bn); st.add_vertex(o0 + bz)
				st.set_normal(bn); st.add_vertex(o1 + bz)
				st.set_normal(bn); st.add_vertex(o0 + bz)
				st.set_normal(bn); st.add_vertex(i1 + bz)
			var arch_mesh := st.commit()
			arch_mesh.surface_set_material(0, tunnel_wall_mat)
			var arch_body := StaticBody3D.new()
			arch_body.set_meta("tunnel_wall", true)
			var mesh_inst := MeshInstance3D.new()
			mesh_inst.mesh = arch_mesh
			arch_body.add_child(mesh_inst)
			var trimesh_shape := arch_mesh.create_trimesh_shape()
			var col_shape := CollisionShape3D.new()
			col_shape.shape = trimesh_shape
			arch_body.add_child(col_shape)
			arch_body.position = Vector3(center_x, base_y, center_z)
			level_node.add_child(arch_body)
			var roof_body := StaticBody3D.new()
			roof_body.set_meta("tunnel_wall", true)
			var roof_col := CollisionShape3D.new()
			var roof_box := BoxShape3D.new()
			roof_box.size = Vector3(TILE_SIZE, 0.3, tunnel_depth)
			roof_col.shape = roof_box
			roof_body.add_child(roof_col)
			roof_body.position = Vector3(center_x, base_y + arch_height + 0.15, center_z)
			level_node.add_child(roof_body)

func _create_warp_streaks():
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

	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 100:
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(1.5, 15.0)
		var depth := rng.randf_range(8.0, 50.0)

		var pos := cam_pos + cam_fwd * depth + cam_right * cos(angle) * radius + cam_up * sin(angle) * radius

		var streak := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.05, 0.05, 1.0)
		mesh.material = streak_mat
		streak.mesh = mesh
		streak.global_position = pos
		streak.look_at(cam_pos)
		add_child(streak)

		var duration := rng.randf_range(0.6, 1.6)
		var stretch := rng.randf_range(30.0, 80.0)
		var tween := create_tween()
		tween.tween_property(streak, "scale:z", stretch, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _on_ship_warped():
	if not GameState.is_endless:
		GameState.mark_completed(GameState.menu_group, GameState.menu_track)
	get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")

func _on_ship_exploded():
	if GameState.is_endless:
		# Save best distance before resetting
		var dist := absf(_ship.global_position.z)
		GameState.save_endless_best(dist)
	GameState.elapsed_time = 0.0
	_timer_running = false
	_ship.reset_ship()

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
