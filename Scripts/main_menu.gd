extends Control

const GROUPS := [
	{
		"name": "NEBULA RUN",
		"sub": "ethereal skies through the accretion rings",
		"color": Color(0.7, 0.4, 0.9),
		"prefix": "nebula", "theme": 1, "save_id": 1,
		"tracks": ["Haze", "Storm", "Pulse", "Wisp", "Flare"],
	},
	{
		"name": "SOLAR BURN",
		"sub": "grazing the corona - low gravity, high jumps",
		"color": Color(1.0, 0.6, 0.25),
		"prefix": "solar", "theme": 2, "save_id": 2,
		"tracks": ["Ember", "Blaze", "Corona", "Scorch", "Nova"],
	},
	{
		"name": "DARK MATTER",
		"sub": "through the hostile fleet - floaty jumps",
		"color": Color(0.4, 0.9, 0.6),
		"prefix": "dark", "theme": 3, "save_id": 3,
		"tracks": ["Rift", "Shadow", "Warp", "Abyss", "Omega"],
	},
	{
		"name": "PROCEDURAL",
		"sub": "generated tracks and endless mode",
		"color": Color(0.85, 0.75, 0.35),
		"prefix": "gen", "theme": -1, "save_id": 4,
		"tracks": ["Sprint", "Marathon", "Labyrinth", "Tightrope", "Gauntlet", "ENDLESS"],
	},
	{
		"name": "SETTINGS",
		"sub": "build your own track",
		"color": Color(0.6, 0.6, 0.68),
		"prefix": "custom", "theme": -1, "save_id": 5,
		"tracks": [],
	},
]

const GEN_PRESETS := [
	{"length": 120, "max_height": 3, "tunnel_weight": 5, "narrow_weight": 10, "gap_weight": 8, "tunnel_lane_weight": 5, "sharpness": 0.12, "theme": 1},
	{"length": 600, "max_height": 4, "tunnel_weight": 10, "narrow_weight": 15, "gap_weight": 10, "tunnel_lane_weight": 8, "sharpness": 0.10, "theme": 2},
	{"length": 300, "max_height": 3, "tunnel_weight": 25, "narrow_weight": 10, "gap_weight": 5, "tunnel_lane_weight": 20, "sharpness": 0.10, "theme": 3},
	{"length": 300, "max_height": 5, "tunnel_weight": 5, "narrow_weight": 30, "gap_weight": 10, "tunnel_lane_weight": 10, "sharpness": 0.08, "theme": 1},
	{"length": 500, "max_height": 6, "tunnel_weight": 20, "narrow_weight": 25, "gap_weight": 15, "tunnel_lane_weight": 15, "sharpness": 0.08, "theme": 2},
	{"length": 0, "max_height": 5, "tunnel_weight": 15, "narrow_weight": 20, "gap_weight": 12, "tunnel_lane_weight": 10, "sharpness": 0.10, "theme": 3, "endless": true},
]

const CUSTOM_NAMES := ["Length", "Max Height", "Tunnels", "Narrow", "Theme", "Gaps", "Lane Tunnels", "Sharpness"]
const CUSTOM_OPTIONS := [
	[100, 200, 300, 500, 700, 1000],
	[2, 3, 4, 5, 6, 8],
	[0, 8, 15, 25],
	[0, 10, 20, 35],
	[1, 2, 3],
	[0, 5, 10, 20],
	[0, 5, 12, 25],
	[0.05, 0.08, 0.12, 0.20],
]
const CUSTOM_DISPLAY := [
	["100", "200", "300", "500", "700", "1000"],
	["2", "3", "4", "5", "6", "8"],
	["None", "Low", "Medium", "High"],
	["None", "Low", "Medium", "High"],
	["Nebula", "Solar", "Dark"],
	["None", "Low", "Medium", "High"],
	["None", "Low", "Medium", "High"],
	["Gentle", "Normal", "Sharp", "Extreme"],
]

enum { SCREEN_HOME, SCREEN_TRACKS, SCREEN_SETTINGS }

var _screen := SCREEN_HOME
var _sel := 0
var _track := 0
var _home_root: Control
var _sub_root: Control
var _home_names: Array[Label] = []
var _home_subs: Array[Label] = []
var _sub_labels: Array[Label] = []

func _ready():
	if GameState.background_texture:
		var bg := TextureRect.new()
		bg.texture = GameState.background_texture
		bg.anchor_right = 1
		bg.anchor_bottom = 1
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_SCALE
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.anchor_right = 1
	overlay.anchor_bottom = 1
	add_child(overlay)

	_build_home()
	for g in GROUPS.size():
		if GROUPS[g]["save_id"] == GameState.menu_group:
			_sel = g
	_update_home()
	if Music._current_group < 0:
		Music.play_for_group(1)

func _key(event, keycode) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == keycode

func _input(event):
	match _screen:
		SCREEN_HOME:
			_input_home(event)
		SCREEN_TRACKS:
			_input_tracks(event)
		SCREEN_SETTINGS:
			_input_settings(event)

func _input_home(event):
	if event.is_action_pressed("ui_down") or _key(event, KEY_S):
		_sel = (_sel + 1) % GROUPS.size()
		_update_home()
	elif event.is_action_pressed("ui_up") or _key(event, KEY_W):
		_sel = (_sel - 1 + GROUPS.size()) % GROUPS.size()
		_update_home()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_right") or _key(event, KEY_D):
		_open_group(_sel)
	elif _key(event, KEY_V):
		_import_share_code()
	elif _key(event, KEY_L):
		_open_load_dialog()

func _input_tracks(event):
	var count: int = GROUPS[_sel]["tracks"].size()
	if event.is_action_pressed("ui_down") or _key(event, KEY_S):
		_track = (_track + 1) % count
		_update_tracks()
	elif event.is_action_pressed("ui_up") or _key(event, KEY_W):
		_track = (_track - 1 + count) % count
		_update_tracks()
	elif event.is_action_pressed("ui_accept"):
		_start_game()
	elif event.is_action_pressed("ui_cancel") or _key(event, KEY_Q) or event.is_action_pressed("ui_left") or _key(event, KEY_A):
		_close_sub()

func _input_settings(event):
	var rows := CUSTOM_NAMES.size()
	if event.is_action_pressed("ui_down") or _key(event, KEY_S):
		_track = (_track + 1) % rows
		_update_settings()
	elif event.is_action_pressed("ui_up") or _key(event, KEY_W):
		_track = (_track - 1 + rows) % rows
		_update_settings()
	elif event.is_action_pressed("ui_right") or _key(event, KEY_D) or _key(event, KEY_X):
		_adjust_custom(1)
	elif event.is_action_pressed("ui_left") or _key(event, KEY_A) or _key(event, KEY_Z):
		_adjust_custom(-1)
	elif event.is_action_pressed("ui_accept"):
		_start_game()
	elif event.is_action_pressed("ui_cancel") or _key(event, KEY_Q):
		_close_sub()

func _adjust_custom(dir: int):
	var opts: int = CUSTOM_OPTIONS[_track].size()
	GameState.custom_idx[_track] = (_cidx(_track) + dir + opts) % opts
	GameState.save_custom_idx()
	_update_settings()

func _cidx(row: int) -> int:
	return clampi(GameState.custom_idx[row], 0, CUSTOM_OPTIONS[row].size() - 1)

# ---------------- home screen ----------------

func _build_home():
	_home_root = Control.new()
	_home_root.anchor_right = 1
	_home_root.anchor_bottom = 1
	add_child(_home_root)

	var title := Label.new()
	title.text = "GaasRoads"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_right = 1
	title.anchor_top = 0.09
	title.anchor_bottom = 0.09
	title.offset_bottom = 74
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	title.add_theme_font_size_override("font_size", 64)
	_home_root.add_child(title)

	var tagline := Label.new()
	tagline.text = "a skyway racer"
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.anchor_right = 1
	tagline.anchor_top = 0.09
	tagline.anchor_bottom = 0.09
	tagline.offset_top = 76
	tagline.offset_bottom = 96
	tagline.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	tagline.add_theme_font_size_override("font_size", 14)
	_home_root.add_child(tagline)

	for g in GROUPS.size():
		var frac := 0.30 + g * 0.105
		var name_label := Label.new()
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.anchor_right = 1
		name_label.anchor_top = frac
		name_label.anchor_bottom = frac
		name_label.offset_bottom = 38
		name_label.add_theme_font_size_override("font_size", 32)
		_home_root.add_child(name_label)
		_home_names.append(name_label)

		var sub_label := Label.new()
		sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub_label.anchor_right = 1
		sub_label.anchor_top = frac
		sub_label.anchor_bottom = frac
		sub_label.offset_top = 38
		sub_label.offset_bottom = 56
		sub_label.add_theme_font_size_override("font_size", 13)
		_home_root.add_child(sub_label)
		_home_subs.append(sub_label)

	var hint := Label.new()
	hint.text = "Enter: select   |   V: paste track   |   L: load track file"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.anchor_right = 1
	hint.anchor_top = 1
	hint.anchor_bottom = 1
	hint.offset_top = -34
	hint.add_theme_color_override("font_color", Color(0.45, 0.45, 0.5))
	hint.add_theme_font_size_override("font_size", 12)
	_home_root.add_child(hint)

func _update_home():
	for g in GROUPS.size():
		var col: Color = GROUPS[g]["color"]
		var selected := g == _sel
		_home_names[g].text = ("> %s <" if selected else "%s") % GROUPS[g]["name"]
		_home_names[g].add_theme_color_override("font_color", col if selected else col.darkened(0.45))
		_home_names[g].add_theme_font_size_override("font_size", 36 if selected else 30)
		_home_subs[g].text = _group_subtitle(g)
		_home_subs[g].add_theme_color_override("font_color",
			Color(0.75, 0.75, 0.8) if selected else Color(0.38, 0.38, 0.42))

func _group_subtitle(g: int) -> String:
	var info: Dictionary = GROUPS[g]
	var sub: String = info["sub"]
	if info["save_id"] <= 4 and info["tracks"].size() > 0:
		var done := 0
		for t in info["tracks"].size():
			if GameState.is_completed(info["save_id"], t):
				done += 1
		if done > 0:
			sub += "  -  %d/%d" % [done, info["tracks"].size()]
	if info["save_id"] == 4 and GameState.endless_best_dist > 0.0:
		sub += "  -  endless best %dm" % int(GameState.endless_best_dist)
	return sub

# ---------------- sub screens ----------------

func _open_group(g: int):
	_sel = g
	GameState.menu_group = GROUPS[g]["save_id"]
	_track = 0
	_home_root.visible = false
	_sub_root = Control.new()
	_sub_root.anchor_right = 1
	_sub_root.anchor_bottom = 1
	add_child(_sub_root)

	var info: Dictionary = GROUPS[g]
	var title := Label.new()
	title.text = info["name"]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_right = 1
	title.anchor_top = 0.12
	title.anchor_bottom = 0.12
	title.offset_bottom = 52
	title.add_theme_color_override("font_color", info["color"])
	title.add_theme_font_size_override("font_size", 44)
	_sub_root.add_child(title)

	var rows: int = CUSTOM_NAMES.size() if g == 4 else info["tracks"].size()
	_sub_labels.clear()
	for i in rows:
		var frac := 0.30 + i * 0.062
		var l := Label.new()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.anchor_right = 1
		l.anchor_top = frac
		l.anchor_bottom = frac
		l.offset_bottom = 26
		l.add_theme_font_size_override("font_size", 20)
		_sub_root.add_child(l)
		_sub_labels.append(l)

	var hint := Label.new()
	hint.text = "A/D or Z/X: adjust   |   Enter: launch   |   Esc: back" if g == 4 \
		else "Enter: launch   |   Esc: back"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.anchor_right = 1
	hint.anchor_top = 1
	hint.anchor_bottom = 1
	hint.offset_top = -34
	hint.add_theme_color_override("font_color", Color(0.45, 0.45, 0.5))
	hint.add_theme_font_size_override("font_size", 12)
	_sub_root.add_child(hint)

	if g == 4:
		_screen = SCREEN_SETTINGS
		_update_settings()
	else:
		_screen = SCREEN_TRACKS
		_update_tracks()

func _close_sub():
	_screen = SCREEN_HOME
	_sub_root.queue_free()
	_sub_root = null
	_home_root.visible = true
	_update_home()

func _update_tracks():
	var info: Dictionary = GROUPS[_sel]
	for t in _sub_labels.size():
		var name_str: String = info["tracks"][t]
		var display := name_str
		if info["save_id"] == 4 and t == 5:
			if GameState.endless_best_dist > 0.0:
				display += "  [%dm]" % int(GameState.endless_best_dist)
		else:
			var best := GameState.get_best_time(info["save_id"], t)
			if best > 0.0:
				display += "  [%s]" % GameState.format_time(best)
			elif GameState.is_completed(info["save_id"], t):
				display += "  [OK]"
		var selected := t == _track
		var is_endless: bool = info["save_id"] == 4 and t == 5
		var col: Color
		if selected:
			col = Color(1.0, 0.35, 0.35) if is_endless else Color(1, 1, 1)
		else:
			col = Color(0.5, 0.22, 0.22) if is_endless else Color(0.5, 0.5, 0.55)
		_sub_labels[t].text = ("> %s" if selected else "  %s") % display
		_sub_labels[t].add_theme_color_override("font_color", col)

func _update_settings():
	for i in _sub_labels.size():
		var selected := i == _track
		var value: String = CUSTOM_DISPLAY[i][_cidx(i)]
		_sub_labels[i].text = ("> %-14s %s" if selected else "  %-14s %s") % [CUSTOM_NAMES[i], value]
		_sub_labels[i].add_theme_color_override("font_color",
			Color(1, 1, 1) if selected else Color(0.5, 0.5, 0.55))

# ---------------- launching ----------------

func _start_game():
	GameState.is_generated = false
	GameState.is_endless = false
	GameState.generated_content = ""
	GameState.endless_params = {}
	GameState.gen_params = {}
	GameState.menu_track = _track

	var info: Dictionary = GROUPS[_sel]
	if _sel == 3:  # PROCEDURAL
		var preset: Dictionary = GEN_PRESETS[_track].duplicate()
		preset["seed"] = randi()
		preset["min_height"] = 1
		GameState.selected_group = preset["theme"]
		GameState.selected_track = _track
		GameState.is_generated = true
		GameState.gen_params = preset.duplicate()
		if preset.get("endless", false):
			GameState.is_endless = true
			preset["length"] = 300
			GameState.endless_params = preset.duplicate()
		GameState.generated_content = LevelGenerator.generate(preset)
	elif _sel == 4:  # SETTINGS / custom track
		var params := {
			"length": CUSTOM_OPTIONS[0][_cidx(0)],
			"min_height": 1,
			"max_height": CUSTOM_OPTIONS[1][_cidx(1)],
			"tunnel_weight": CUSTOM_OPTIONS[2][_cidx(2)],
			"narrow_weight": CUSTOM_OPTIONS[3][_cidx(3)],
			"gap_weight": CUSTOM_OPTIONS[5][_cidx(5)],
			"tunnel_lane_weight": CUSTOM_OPTIONS[6][_cidx(6)],
			"sharpness": CUSTOM_OPTIONS[7][_cidx(7)],
			"theme": CUSTOM_OPTIONS[4][_cidx(4)],
			"seed": randi(),
		}
		GameState.selected_group = params["theme"]
		GameState.selected_track = 0
		GameState.is_generated = true
		GameState.gen_params = params.duplicate()
		GameState.generated_content = LevelGenerator.generate(params)
	else:
		GameState.selected_group = info["theme"]
		GameState.selected_track = _track
		GameState.selected_level = "res://Levels/%s_%d.txt" % [info["prefix"], _track + 1]

	get_tree().change_scene_to_file("res://Scenes/Game.tscn")

func _open_load_dialog():
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.txt ; Track Files"])
	dialog.title = "Load Track"
	dialog.size = Vector2i(600, 400)
	dialog.file_selected.connect(func(path: String):
		var file := FileAccess.open(path, FileAccess.READ)
		if file:
			var content := file.get_as_text()
			file.close()
			if content.strip_edges() != "":
				GameState.is_generated = true
				GameState.is_endless = false
				GameState.gen_params = {}
				GameState.selected_group = 1
				GameState.selected_track = 0
				GameState.generated_content = content
				get_tree().change_scene_to_file("res://Scenes/Game.tscn")
	)
	add_child(dialog)
	dialog.popup_centered()

func _import_share_code():
	var clipboard := DisplayServer.clipboard_get().strip_edges()
	if clipboard == "":
		return
	GameState.is_generated = true
	GameState.is_endless = false
	GameState.gen_params = {}

	var params := GameState.decode_share_code(clipboard)
	if not params.is_empty():
		GameState.gen_params = params.duplicate()
		GameState.selected_group = params.get("theme", 1)
		GameState.selected_track = 0
		GameState.generated_content = LevelGenerator.generate(params)
	else:
		GameState.selected_group = 1
		GameState.selected_track = 0
		GameState.generated_content = clipboard

	get_tree().change_scene_to_file("res://Scenes/Game.tscn")
