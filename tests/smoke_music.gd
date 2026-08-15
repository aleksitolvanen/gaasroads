# Music smoke test: all four baked OGG tracks load, loop, play and stop
# through the Music autoload.
#
# Run:  godot --headless --path . -s tests/smoke_music.gd
# Pass: one "group N" line per track + "MUSIC SMOKE OK", exit code 0.
extends SceneTree

var _done := false

func _process(_delta) -> bool:
	if _done:
		return true
	_done = true
	var music = root.get_node_or_null("Music")
	if music == null:
		printerr("FAIL: Music autoload missing")
		quit(1)
		return true
	music.toggle()
	for g in 4:
		music.play_for_group(g)
		var player: AudioStreamPlayer = music._player
		if not player.playing or player.stream == null or not player.stream.loop:
			printerr("FAIL: group %d not playing a looping stream" % g)
			quit(1)
			return true
		print("group %d: %s len=%.2fs loop=%s" % [g, player.stream.resource_path, player.stream.get_length(), player.stream.loop])
	music.toggle()
	if music._player.playing:
		printerr("FAIL: player still playing after toggle off")
		quit(1)
		return true
	print("MUSIC SMOKE OK")
	return true
