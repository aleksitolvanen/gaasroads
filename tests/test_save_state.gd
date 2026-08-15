# Save/session state test: config round-trip, best-time ordering, and
# share-code decode validation - the only persistent user data in the game.
# Uses a throwaway save file, never the real user://completed.cfg.
#
# Run:  godot --headless --path . -s tests/test_save_state.gd
# Pass: "SAVE STATE OK", exit code 0.
extends SceneTree

const TEST_SAVE := "user://test_completed.cfg"

func _initialize():
	var fails := 0
	var gs_script := load("res://Scripts/game_state.gd")

	var a = gs_script.new()
	a.save_path = TEST_SAVE
	a.elapsed_time = 61.5
	a.mark_completed(1, 0)
	a.elapsed_time = 45.0
	a.mark_completed(1, 0)  # faster: overwrites
	a.elapsed_time = 50.0
	a.mark_completed(1, 0)  # slower: must NOT overwrite
	a.elapsed_time = 0.0
	a.mark_completed(3, 4)  # no time recorded, completion only
	a.save_endless_best(123.4)
	a.custom_idx[0] = 5
	a.save_custom_idx()

	var b = gs_script.new()
	b.save_path = TEST_SAVE
	b._load()
	fails += _check(b.is_completed(1, 0), "completion 1_0 survives reload")
	fails += _check(b.is_completed(3, 4), "completion 3_4 survives reload")
	fails += _check(not b.is_completed(2, 0), "unmarked track stays incomplete")
	fails += _check(absf(b.get_best_time(1, 0) - 45.0) < 0.001, "best time keeps the faster run")
	fails += _check(b.get_best_time(3, 4) == 0.0, "no best time without a timed run")
	fails += _check(absf(b.endless_best_dist - 123.4) < 0.001, "endless best survives reload")
	fails += _check(b.custom_idx[0] == 5, "custom settings survive reload")

	var good: Dictionary = a.decode_share_code("GAAS:300:4:10:15:10:8:0.10:2:777")
	fails += _check(good.get("length", 0) == 300 and good.get("theme", -1) == 2, "valid share code decodes")
	fails += _check(good.get("seed", 0) == 777, "seed survives decode")
	fails += _check(a.decode_share_code("not a code").is_empty(), "garbage rejected")
	fails += _check(a.decode_share_code("GAAS:1:2:3").is_empty(), "short code rejected")
	fails += _check(a.decode_share_code("SAAG:300:4:10:15:10:8:0.10:2:777").is_empty(), "wrong prefix rejected")
	var hostile: Dictionary = a.decode_share_code("GAAS:2000000000:99:999:999:999:999:9.9:9:1")
	fails += _check(not hostile.is_empty() and hostile["length"] <= 2000, "hostile length clamped")
	fails += _check(hostile["max_height"] <= 8 and hostile["theme"] <= 3 and hostile["sharpness"] <= 0.5, "hostile fields clamped")

	# Round trip: encode(decode(code)) reproduces the code
	var code := "GAAS:300:4:10:15:10:8:0.10:2:777"
	fails += _check(a.encode_share_code(a.decode_share_code(code)) == code, "encode/decode round-trips")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	a.free()
	b.free()
	print("SAVE STATE %s" % ("OK" if fails == 0 else "FAIL (%d checks)" % fails))
	quit(0 if fails == 0 else 1)

func _check(cond: bool, what: String) -> int:
	if cond:
		return 0
	printerr("FAIL: " + what)
	return 1
