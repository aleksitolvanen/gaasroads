# Music smoke test: all four baked OGG tracks load, loop, play and stop
# through the Music autoload.
#
# Run:  godot --headless --path . -s tests/smoke_music.gd
# Pass: one "group N" line per track + "MUSIC SMOKE OK".
extends SceneTree

var _done := false

func _process(_delta) -> bool:
	if _done:
		return true
	_done = true
	var music = root.get_node_or_null("Music")
	if music == null:
		printerr("FAIL: Music autoload missing")
		return true
	music.toggle()
	for g in 4:
		music.play_for_group(g)
		var player: AudioStreamPlayer = music._player
		assert(player.playing, "player not playing for group %d" % g)
		assert(player.stream != null, "no stream for group %d" % g)
		assert(player.stream.loop, "stream not looping for group %d" % g)
		print("group %d: %s len=%.2fs loop=%s" % [g, player.stream.resource_path, player.stream.get_length(), player.stream.loop])
	music.toggle()
	assert(not music._player.playing, "player still playing after toggle off")
	print("MUSIC SMOKE OK")
	return true
