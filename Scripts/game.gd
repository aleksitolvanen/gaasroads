extends Node3D

@export var level_path := "res://Levels/level1.txt"

const TILE_SIZE := 2.0
const TILE_HEIGHT := 0.5

var _fallback_level := [
	"11111", "11111", "11111", "11111", "11111", "11111",
	"11 11", "11 11", "11111", "11111", "1   1", "1   1",
	"11111", "11111", "", "11111", "11111", "1 1 1", "1 1 1",
	"11111", "11111", "  1  ", "  1  ", "  1  ", "11111",
	"11111", "11311", "11311", "11111", "22222", "22222",
	"11111", "11111", "1   1", "1   1", "1   1", "1   1",
	"11111", "11111", "11111", "11411", "11111", "11111", "11111"
]

var _camera: Camera3D
var _ship: CharacterBody3D
var _bg_quad: MeshInstance3D
var _speed_gauge: ProgressBar
var _speed_label: Label

func _ready():
	_ship = $Ship
	_camera = $Camera3D
	_create_space_environment()
	_create_hud()
	_load_level()

func _process(_delta):
	var ship_pos := _ship.global_position
	_camera.global_position = Vector3(ship_pos.x, ship_pos.y + 2.5, ship_pos.z + 3.5)
	_camera.look_at(ship_pos + Vector3(0, -1.5, -6), Vector3.UP)

	if _bg_quad:
		_bg_quad.global_position = Vector3(ship_pos.x, ship_pos.y - 20, ship_pos.z - 120)

	_speed_gauge.value = _ship.current_speed
	_speed_label.text = "%d" % _ship.current_speed

func _create_hud():
	var canvas := CanvasLayer.new()
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
	_speed_gauge.max_value = 25
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

func _create_space_environment():
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.15, 0.12, 0.2)
	env.ambient_light_energy = 0.3

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

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

func _load_level():
	var level_node := $Level
	var content: String

	var file := FileAccess.open(level_path, FileAccess.READ)
	if file:
		content = file.get_as_text()
		file.close()
	else:
		printerr("Failed to open level file: %s - using built-in level" % level_path)
		content = "\n".join(_fallback_level)

	var lines := content.split("\n")
	var rows := lines.size()
	var cols := 0
	for line in lines:
		if line.length() > cols:
			cols = line.length()

	var grid: Array[Array] = []
	for r in rows:
		var row: Array[int] = []
		row.resize(cols)
		row.fill(0)
		for c in lines[r].length():
			var ch := lines[r][c]
			if ch >= "1" and ch <= "9":
				row[c] = ch.unicode_at(0) - "0".unicode_at(0)
			elif ch == "#":
				row[c] = 1
		grid.append(row)

	var used: Array[Array] = []
	for r in rows:
		var row: Array[bool] = []
		row.resize(cols)
		row.fill(false)
		used.append(row)

	var tile_material := StandardMaterial3D.new()
	tile_material.albedo_color = Color(0.3, 0.5, 0.8)

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
			var tile := _create_merged_tile(w, h, actual_height, tile_material)
			tile.position = Vector3(
				c * TILE_SIZE + (w - 1) * TILE_SIZE / 2.0,
				actual_height / 2.0,
				-r * TILE_SIZE - (h - 1) * TILE_SIZE / 2.0
			)
			level_node.add_child(tile)

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
