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
	}
]

var _group := 0
var _track := 0
var _track_labels: Array[Array] = []
var _group_labels: Array[Label] = []

func _ready():
	_build_menu()
	_update_selection()
	Music.play_for_group(0)

func _input(event):
	if event.is_action_pressed("ui_right"):
		_group = (_group + 1) % 4
		_update_selection()
	elif event.is_action_pressed("ui_left"):
		_group = (_group + 3) % 4
		_update_selection()
	elif event.is_action_pressed("ui_down"):
		_track = (_track + 1) % 5
		_update_selection()
	elif event.is_action_pressed("ui_up"):
		_track = (_track + 4) % 5
		_update_selection()
	elif event.is_action_pressed("ui_accept"):
		_start_game()

func _start_game():
	GameState.selected_group = _group
	GameState.selected_track = _track
	var prefix: String = GROUPS[_group]["prefix"]
	GameState.selected_level = "res://Levels/%s_%d.txt" % [prefix, _track + 1]
	get_tree().change_scene_to_file("res://Scenes/Game.tscn")

func _update_selection():
	for g in 4:
		var group_color: Color = GROUPS[g]["color"]
		_group_labels[g].add_theme_color_override("font_color",
			group_color if g == _group else group_color.darkened(0.5))
		for t in 5:
			var label: Label = _track_labels[g][t]
			var check := " [OK]" if GameState.is_completed(g, t) else ""
			if g == _group and t == _track:
				label.add_theme_color_override("font_color", Color(1, 1, 1))
				label.text = "> " + GROUPS[g]["tracks"][t] + check
			else:
				var dimmed := Color(0.5, 0.5, 0.55) if g == _group else Color(0.3, 0.3, 0.35)
				label.add_theme_color_override("font_color", dimmed)
				label.text = "  " + GROUPS[g]["tracks"][t] + check

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
	title.offset_top = 40
	title.offset_bottom = 100
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	title.add_theme_font_size_override("font_size", 52)
	add_child(title)

	# Subtitle
	var subtitle := Label.new()
	subtitle.text = "Select a track"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.anchor_left = 0
	subtitle.anchor_right = 1
	subtitle.offset_top = 100
	subtitle.offset_bottom = 125
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	subtitle.add_theme_font_size_override("font_size", 16)
	add_child(subtitle)

	# Track groups
	var container := HBoxContainer.new()
	container.anchor_left = 0.05
	container.anchor_right = 0.95
	container.anchor_top = 0.25
	container.anchor_bottom = 0.85
	container.add_theme_constant_override("separation", 20)
	add_child(container)

	for g in 4:
		var group_box := VBoxContainer.new()
		group_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		group_box.add_theme_constant_override("separation", 8)
		container.add_child(group_box)

		var group_label := Label.new()
		group_label.text = GROUPS[g]["name"]
		group_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		group_label.add_theme_font_size_override("font_size", 18)
		group_box.add_child(group_label)
		_group_labels.append(group_label)

		var sep := HSeparator.new()
		sep.add_theme_constant_override("separation", 8)
		group_box.add_child(sep)

		var tracks: Array[Label] = []
		for t in 5:
			var track_label := Label.new()
			track_label.text = "  " + GROUPS[g]["tracks"][t]
			track_label.add_theme_font_size_override("font_size", 16)
			group_box.add_child(track_label)
			tracks.append(track_label)
		_track_labels.append(tracks)

	var music_hint := Label.new()
	music_hint.text = "Press M to toggle music"
	music_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	music_hint.anchor_left = 0
	music_hint.anchor_right = 1
	music_hint.anchor_top = 1
	music_hint.anchor_bottom = 1
	music_hint.offset_top = -50
	music_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	music_hint.add_theme_font_size_override("font_size", 13)
	add_child(music_hint)

	var credit := Label.new()
	credit.text = "Inspired by SkyRoads (1993)."
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credit.anchor_left = 0
	credit.anchor_right = 1
	credit.anchor_top = 1
	credit.anchor_bottom = 1
	credit.offset_top = -30
	credit.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
	credit.add_theme_font_size_override("font_size", 13)
	add_child(credit)
