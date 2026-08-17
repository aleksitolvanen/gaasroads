extends Node

# Debug status line (bottom right) plus the global gameplay toggles (N/B/P).
# Lives outside GameState so the save/session module stays UI-free.

var _label: Label
var _init := false
var _s_music := false
var _s_sfx := true
var _s_mode := false
var _s_ap := false
var _s_ship := -1

func _ready():
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_label = Label.new()
	_label.anchor_left = 1
	_label.anchor_right = 1
	_label.anchor_top = 1
	_label.anchor_bottom = 1
	_label.offset_left = -420
	_label.offset_top = -24
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55, 0.7))
	_label.add_theme_font_size_override("font_size", 11)
	layer.add_child(_label)

func _process(_delta):
	# Rebuild the status line only when a flag actually changed
	if _init and Music.enabled == _s_music and GameState.sfx_enabled == _s_sfx \
			and GameState.classical_mode == _s_mode and GameState.autopilot == _s_ap \
			and GameState.ship_style == _s_ship:
		return
	_init = true
	_s_music = Music.enabled
	_s_sfx = GameState.sfx_enabled
	_s_mode = GameState.classical_mode
	_s_ap = GameState.autopilot
	_s_ship = GameState.ship_style
	var music_str := "ON" if _s_music else "OFF"
	var sfx_str := "ON" if _s_sfx else "OFF"
	var mode_str := "Classical" if _s_mode else "Normal"
	var ap_str := " | AUTOPILOT" if _s_ap else ""
	var ship_str := "" if _s_ship == 0 else " | Ship: %s" % ShipDesigns.STYLE_NAMES[_s_ship]
	_label.text = "Music: %s | Sounds: %s | Mode: %s%s%s" % [music_str, sfx_str, mode_str, ap_str, ship_str]

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_N:
			GameState.sfx_enabled = not GameState.sfx_enabled
		elif event.keycode == KEY_B:
			GameState.classical_mode = not GameState.classical_mode
		elif event.keycode == KEY_P:
			GameState.autopilot = not GameState.autopilot
		elif event.keycode == KEY_E:
			GameState.ship_style = (GameState.ship_style + 1) % ShipDesigns.STYLE_COUNT
