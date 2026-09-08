extends SceneTree

## Presentation-only verification: no private campaign field injection and no
## combat state mutation is required to construct the DEMO-RC-03/04 view.

var _fail := 0

func _ok(value: bool, label: String) -> void:
	if not value:
		_fail += 1
		print("  x %s" % label)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("DEMO-RC-03/04 battle view")
	get_root().size = Vector2i(1600, 900)
	var view := RedCliffBattleView.new()
	root.add_child(view)
	await process_frame
	_ok(view.find_child("TacticalMapTwoThirds", true, false) != null, "two-third tactical map exists")
	_ok(view.find_child("Primitive3DEvidenceOneThird", true, false) != null, "one-third primitive 3D evidence exists")
	var map = view.find_child("TacticalMapTwoThirds", true, false)
	var evidence = view.find_child("Primitive3DEvidenceOneThird", true, false)
	_ok(map != null and evidence != null and map.size_flags_stretch_ratio > evidence.size_flags_stretch_ratio,
		"split ratio favors tactical map")
	_ok(view.find_child("Primitive3DEvidenceOneThird", true, false).get_child_count() == 1,
		"evidence owns a single SubViewport")
	view.free()
	print("DEMO-RC-03/04 battle view: %d failures" % _fail)
	quit(0 if _fail == 0 else 1)
