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
	_ok(view.find_child("BattleStillImageOneThird", true, false) != null, "one-third battle still exists")
	var map = view.find_child("TacticalMapTwoThirds", true, false)
	var evidence = view.find_child("BattleStillImageOneThird", true, false)
	_ok(map != null and evidence != null and map.size_flags_stretch_ratio > evidence.size_flags_stretch_ratio,
		"split ratio favors tactical map")
	_ok(evidence.find_children("BattleConceptStill", "TextureRect", true, false).size() == 1,
		"evidence owns exactly one static battle image")
	_ok(evidence.find_children("*", "SubViewport", true, false).is_empty(),
		"static evidence creates no realtime 3D viewport")
	var report = view.find_child("PhaseBattleReport", true, false)
	_ok(report != null, "phase battle report is mounted")
	var report_fixture: Array[Dictionary] = [{"phase":2, "attacker_loss":7, "defender_loss":11,
		"attacker_morale_delta":-4, "defender_morale_delta":-6, "schemes":[{"id":"fire"}]}]
	report.set_results(report_fixture)
	report.set_phase(3, "교전", false)
	_ok("2단계 포화" in report.summary and report.wei_loss == 7 and report.allied_loss == 11,
		"phase report exposes canonical losses and phase name")
	_ok(report.wei_morale_delta == -4 and report.allied_morale_delta == -6,
		"phase report exposes both morale deltas")
	_ok("진형 상성" in report.current_directive and "3단계 교전" in report.current_directive,
		"phase report exposes an actionable current directive")
	var advance_button: Button = view._buttons.filter(
		func(button: Button): return String(button.get_meta("action", "")) == "advance_phase")[0]
	_ok(advance_button.has_theme_stylebox_override("normal")
		and advance_button.has_theme_stylebox_override("disabled"),
		"primary phase action has explicit active and disabled visual states")
	map.set_battle(1, "접적", 140, 120, 113, 120)
	var contact_anchor: Vector2 = map.fleet_anchor_points()["allied_primary"]
	var hub := Vector2(map.size.x * .52, map.size.y * .55)
	map.set_battle(4, "강습", 140, 120, 113, 120)
	var assault_anchor: Vector2 = map.fleet_anchor_points()["allied_primary"]
	_ok(assault_anchor.distance_to(hub) < contact_anchor.distance_to(hub),
		"fleet advances along its route as combat phases progress")
	var clock_before: float = map.clock
	map._process(.5)
	_ok(map.clock > clock_before, "tactical route animation advances continuously")
	# The image remains static while authoritative figures continue to update.
	evidence.set_battle(4, "강습", 140, 0, 113, 0)
	map.set_battle(4, "강습", 140, 0, 113, 0)
	await process_frame
	await process_frame
	_ok(map.fleet_icon_counts() == Vector2i(0,20),
		"zero allied ships clears allied tactical icons and caps live Wei icons")
	_ok("연합군  0척" in evidence.allied_label.text,
		"static evidence overlay reports zero allied ships")
	evidence.set_battle(5, "결착", 0, 0, 0, 0)
	map.set_battle(5, "결착", 0, 0, 0, 0)
	await process_frame
	await process_frame
	_ok(map.fleet_icon_counts() == Vector2i.ZERO,
		"zero ships on both sides clears every tactical fleet icon")
	_ok("위군  0척" in evidence.wei_label.text and "연합군  0척" in evidence.allied_label.text,
		"static evidence overlay reports both fleets at zero")
	view.free()
	print("DEMO-RC-03/04 battle view: %d failures" % _fail)
	quit(0 if _fail == 0 else 1)
