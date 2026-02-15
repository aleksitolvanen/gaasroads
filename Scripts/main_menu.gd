extends Control

const GROUPS := [
	{
		"name": "COSMIC HIGHWAY",
		"color": Color(0.3, 0.5, 0.8),
		"prefix": "cosmic",
		"tracks": ["Orbit", "Drift", "Apex", "Void", "Zenith"]
	},
	{
		"name": "NEBULA RUN",
		"color": Color(0.6, 0.3, 0.7),
		"prefix": "nebula",
		"tracks": ["Haze", "Storm", "Pulse", "Wisp", "Flare"]
	},
	{
		"name": "SOLAR BURN",
		"color": Color(0.8, 0.5, 0.2),
		"prefix": "solar",
		"tracks": ["Ember", "Blaze", "Corona", "Scorch", "Nova"]
	},
	{
		"name": "DARK MATTER",
		"color": Color(0.4, 0.7, 0.5),
		"prefix": "dark",
		"tracks": ["Rift", "Shadow", "Warp", "Abyss", "Omega"]
	},
	{
		"name": "PROCEDURAL",
		"color": Color(0.7, 0.65, 0.3),
		"prefix": "gen",
		"tracks": ["Sprint", "Marathon", "Labyrinth", "Tightrope", "Gauntlet", "ENDLESS"]
	},
	{
		"name": "CUSTOM (Z/X to adjust)",
		"color": Color(0.55, 0.55, 0.6),
		"prefix": "custom",
		"tracks": ["Length", "Max Height", "Tunnels", "Narrow", "Theme", "Gaps", "Lane Tunnels", "Sharpness"]
	}
]

const GEN_PRESETS := [
	{"length": 120, "max_height": 3, "tunnel_weight": 5, "narrow_weight": 10, "gap_weight": 8, "tunnel_lane_weight": 5, "sharpness": 0.12, "theme": 0},
	{"length": 600, "max_height": 4, "tunnel_weight": 10, "narrow_weight": 15, "gap_weight": 10, "tunnel_lane_weight": 8, "sharpness": 0.10, "theme": 2},
	{"length": 300, "max_height": 3, "tunnel_weight": 25, "narrow_weight": 10, "gap_weight": 5, "tunnel_lane_weight": 20, "sharpness": 0.10, "theme": 3},
	{"length": 300, "max_height": 5, "tunnel_weight": 5, "narrow_weight": 30, "gap_weight": 10, "tunnel_lane_weight": 10, "sharpness": 0.08, "theme": 1},
	{"length": 500, "max_height": 6, "tunnel_weight": 20, "narrow_weight": 25, "gap_weight": 15, "tunnel_lane_weight": 15, "sharpness": 0.08, "theme": 2},
	{"length": 0, "max_height": 5, "tunnel_weight": 15, "narrow_weight": 20, "gap_weight": 12, "tunnel_lane_weight": 10, "sharpness": 0.10, "theme": 0, "endless": true},
]

const CUSTOM_OPTIONS := [
	[100, 200, 300, 500, 700, 1000],
	[2, 3, 4, 5, 6, 8],
	[0, 8, 15, 25],
	[0, 10, 20, 35],
	[0, 1, 2, 3],
	[0, 5, 10, 20],
	[0, 5, 12, 25],
	[0.05, 0.08, 0.12, 0.20],
]

const CUSTOM_DISPLAY := [
	["100", "200", "300", "500", "700", "1000"],
	["2", "3", "4", "5", "6", "8"],
	["None", "Low", "Medium", "High"],
	["None", "Low", "Medium", "High"],
	["Cosmic", "Nebula", "Solar", "Dark"],
	["None", "Low", "Medium", "High"],
	["None", "Low", "Medium", "High"],
	["Gentle", "Normal", "Sharp", "Extreme"],
]

var _group := GameState.menu_group
var _track := GameState.menu_track
var _track_labels: Array[Array] = []
var _group_labels: Array[Label] = []
var _custom_hint: Label

func _ready():
	_build_menu()
	_update_selection()
	if Music._current_group < 0:
		Music.play_for_group(0)

func _key(event, keycode) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == keycode

func _input(event):
	var group_count := GROUPS.size()
	var track_count: int = GROUPS[_group]["tracks"].size()

	if event.is_action_pressed("ui_right") or _key(event, KEY_D):
		if _group == 5:
			pass
		else:
			_group = (_group + 1) % group_count
			_track = mini(_track, GROUPS[_group]["tracks"].size() - 1)
			_update_selection()
	elif event.is_action_pressed("ui_left") or _key(event, KEY_A):
		if _group == 5:
			_group = 4
			_track = mini(_track, GROUPS[_group]["tracks"].size() - 1)
			_update_selection()
		else:
			_group = (_group - 1 + group_count) % group_count
			_track = mini(_track, GROUPS[_group]["tracks"].size() - 1)
			_update_selection()
	elif event.is_action_pressed("ui_down") or _key(event, KEY_S):
		_track = (_track + 1) % track_count
		_update_selection()
	elif event.is_action_pressed("ui_up") or _key(event, KEY_W):
		_track = (_track - 1 + track_count) % track_count
		_update_selection()
	elif event.is_action_pressed("ui_accept"):
		_start_game()

	# Z/X to adjust custom parameters
	if _group == 5 and event is InputEventKey and event.pressed and not event.echo:
		var opts_count: int = CUSTOM_OPTIONS[_track].size()
		if event.keycode == KEY_X:
			GameState.custom_idx[_track] = (GameState.custom_idx[_track] + 1) % opts_count
			GameState.save_custom_idx()
			_update_selection()
		elif event.keycode == KEY_Z:
			GameState.custom_idx[_track] = (GameState.custom_idx[_track] - 1 + opts_count) % opts_count
			GameState.save_custom_idx()
			_update_selection()

func _start_game():
	GameState.is_generated = false
	GameState.is_endless = false
	GameState.generated_content = ""
	GameState.endless_params = {}

	if _group == 4:  # GENERATED
		var preset: Dictionary = GEN_PRESETS[_track].duplicate()
		preset["seed"] = randi()
		preset["min_height"] = 1
		GameState.selected_group = preset["theme"]
		GameState.selected_track = _track
		GameState.is_generated = true
		if preset.get("endless", false):
			GameState.is_endless = true
			preset["length"] = 300
			GameState.endless_params = preset.duplicate()
			GameState.endless_params["seed"] = preset["seed"]
		GameState.generated_content = LevelGenerator.generate(preset)
	elif _group == 5:  # CUSTOM
		var params := {
			"length": CUSTOM_OPTIONS[0][GameState.custom_idx[0]],
			"min_height": 1,
			"max_height": CUSTOM_OPTIONS[1][GameState.custom_idx[1]],
			"tunnel_weight": CUSTOM_OPTIONS[2][GameState.custom_idx[2]],
			"narrow_weight": CUSTOM_OPTIONS[3][GameState.custom_idx[3]],
			"gap_weight": CUSTOM_OPTIONS[5][GameState.custom_idx[5]],
			"tunnel_lane_weight": CUSTOM_OPTIONS[6][GameState.custom_idx[6]],
			"sharpness": CUSTOM_OPTIONS[7][GameState.custom_idx[7]],
			"seed": randi(),
		}
		GameState.selected_group = CUSTOM_OPTIONS[4][GameState.custom_idx[4]]
		GameState.selected_track = 0
		GameState.is_generated = true
		GameState.generated_content = LevelGenerator.generate(params)
	else:
		GameState.selected_group = _group
		GameState.selected_track = _track
		var prefix: String = GROUPS[_group]["prefix"]
		GameState.selected_level = "res://Levels/%s_%d.txt" % [prefix, _track + 1]

	get_tree().change_scene_to_file("res://Scenes/Game.tscn")

func _update_selection():
	GameState.menu_group = _group
	GameState.menu_track = _track
	for g in GROUPS.size():
		var group_color: Color = GROUPS[g]["color"]
		_group_labels[g].add_theme_color_override("font_color",
			group_color if g == _group else group_color.darkened(0.5))
		var track_count: int = GROUPS[g]["tracks"].size()
		for t in track_count:
			var label: Label = _track_labels[g][t]
			var name_str: String = GROUPS[g]["tracks"][t]

			# Build display text
			var display := name_str
			if g == 5:  # CUSTOM - show parameter values
				display = name_str + ": " + CUSTOM_DISPLAY[t][GameState.custom_idx[t]]
			elif g == 4 and t == 5:  # ENDLESS
				var best := GameState.endless_best_dist
				if best > 0.0:
					display = name_str + " [%dm]" % int(best)
			elif g <= 4:
				var best_time := GameState.get_best_time(g, t)
				if best_time > 0.0:
					display = name_str + " [" + GameState.format_time(best_time) + "]"
				elif GameState.is_completed(g, t):
					display = name_str + " [OK]"

			var is_endless := (g == 4 and t == 5)
			if g == _group and t == _track:
				var sel_color := Color(1, 0.3, 0.3) if is_endless else Color(1, 1, 1)
				label.add_theme_color_override("font_color", sel_color)
				label.text = "> " + display
			else:
				var dimmed := Color(0.5, 0.5, 0.55) if g == _group else Color(0.3, 0.3, 0.35)
				if is_endless:
					dimmed = Color(0.5, 0.2, 0.2) if g == _group else Color(0.35, 0.15, 0.15)
				label.add_theme_color_override("font_color", dimmed)
				label.text = "  " + display

	# Show/hide custom hint
	if _custom_hint:
		_custom_hint.visible = (_group == 5)

func _build_menu():
	# Background
	if ResourceLoader.exists("res://background.png"):
		var bg := TextureRect.new()
		bg.texture = load("res://background.png")
		bg.anchor_right = 1
		bg.anchor_bottom = 1
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_SCALE
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)

	# Dim overlay
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.5)
	overlay.anchor_right = 1
	overlay.anchor_bottom = 1
	add_child(overlay)

	# Title
	var title := Label.new()
	title.text = "GaasRoads"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0
	title.anchor_right = 1
	title.offset_top = 20
	title.offset_bottom = 70
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	title.add_theme_font_size_override("font_size", 46)
	add_child(title)

	# Controls instruction
	var controls := Label.new()
	controls.text = "WASD / Arrow Keys: steer & speed | Space: jump | Q / Esc: menu"
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.anchor_left = 0
	controls.anchor_right = 1
	controls.offset_top = 72
	controls.offset_bottom = 90
	controls.add_theme_color_override("font_color", Color(0.45, 0.45, 0.5))
	controls.add_theme_font_size_override("font_size", 12)
	add_child(controls)

	# Top row: 4 authored groups
	var top_container := HBoxContainer.new()
	top_container.anchor_left = 0.03
	top_container.anchor_right = 0.97
	top_container.anchor_top = 0.18
	top_container.anchor_bottom = 0.58
	top_container.add_theme_constant_override("separation", 16)
	add_child(top_container)

	# Bottom row: generated + custom
	var bottom_container := HBoxContainer.new()
	bottom_container.anchor_left = 0.15
	bottom_container.anchor_right = 0.85
	bottom_container.anchor_top = 0.60
	bottom_container.anchor_bottom = 0.88
	bottom_container.add_theme_constant_override("separation", 30)
	add_child(bottom_container)

	for g in GROUPS.size():
		var group_box := VBoxContainer.new()
		group_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		group_box.add_theme_constant_override("separation", 5)

		var group_label := Label.new()
		group_label.text = GROUPS[g]["name"]
		group_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		group_label.add_theme_font_size_override("font_size", 16)
		group_box.add_child(group_label)
		_group_labels.append(group_label)

		var sep := HSeparator.new()
		sep.add_theme_constant_override("separation", 4)
		group_box.add_child(sep)

		var tracks: Array[Label] = []
		var track_count: int = GROUPS[g]["tracks"].size()
		if g == 5:
			# CUSTOM: two sub-columns
			var cols := HBoxContainer.new()
			cols.add_theme_constant_override("separation", 20)
			var left_col := VBoxContainer.new()
			left_col.add_theme_constant_override("separation", 5)
			var right_col := VBoxContainer.new()
			right_col.add_theme_constant_override("separation", 5)
			for t in track_count:
				var track_label := Label.new()
				track_label.text = "  " + GROUPS[g]["tracks"][t]
				track_label.add_theme_font_size_override("font_size", 14)
				if t < 5:
					left_col.add_child(track_label)
				else:
					right_col.add_child(track_label)
				tracks.append(track_label)
			cols.add_child(left_col)
			cols.add_child(right_col)
			group_box.add_child(cols)
		else:
			for t in track_count:
				var track_label := Label.new()
				track_label.text = "  " + GROUPS[g]["tracks"][t]
				track_label.add_theme_font_size_override("font_size", 14)
				group_box.add_child(track_label)
				tracks.append(track_label)
		_track_labels.append(tracks)

		if g < 4:
			top_container.add_child(group_box)
		else:
			bottom_container.add_child(group_box)

	_custom_hint = null

	# Mode hint
	var mode_hint := Label.new()
	mode_hint.text = "B: toggle Classical / Normal (Classical = SkyRoads steering, no air control, speed-based turning)"
	mode_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_hint.anchor_left = 0
	mode_hint.anchor_right = 1
	mode_hint.anchor_top = 1
	mode_hint.anchor_bottom = 1
	mode_hint.offset_top = -68
	mode_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	mode_hint.add_theme_font_size_override("font_size", 12)
	add_child(mode_hint)

	# Audio hints
	var audio_hint := Label.new()
	audio_hint.text = "M: toggle music | N: toggle sounds"
	audio_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	audio_hint.anchor_left = 0
	audio_hint.anchor_right = 1
	audio_hint.anchor_top = 1
	audio_hint.anchor_bottom = 1
	audio_hint.offset_top = -48
	audio_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	audio_hint.add_theme_font_size_override("font_size", 12)
	add_child(audio_hint)

	# Credit
	var credit := Label.new()
	credit.text = "Inspired by SkyRoads (1993). A GenAI test project."
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credit.anchor_left = 0
	credit.anchor_right = 1
	credit.anchor_top = 1
	credit.anchor_bottom = 1
	credit.offset_top = -28
	credit.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
	credit.add_theme_font_size_override("font_size", 12)
	add_child(credit)
