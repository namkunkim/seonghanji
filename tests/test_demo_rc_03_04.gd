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
		"attacker_morale_delta":-4, "defender_morale_delta":-6, "schemes":[{"id":"fire","name":"화공"}]}]
	report.set_results(report_fixture)
	report.set_phase(3, "교전", false)
	_ok("2단계 포화" in report.summary and report.wei_loss == 7 and report.allied_loss == 11,
		"phase report exposes canonical losses and phase name")
	_ok(report.wei_morale_delta == -4 and report.allied_morale_delta == -6,
		"phase report exposes both morale deltas")
	_ok("계략 발동: 화공" in report.summary and report.scheme_summary == "계략 발동: 화공",
		"phase report identifies the canonical scheme by name")
	view._refresh_history(report_fixture, null)
	_ok("2단계  포화" in view._history_text.text and "연합  -11척 / 사기 -6" in view._history_text.text
		and "위군  -7척 / 사기 -4" in view._history_text.text and "계략  화공" in view._history_text.text,
		"battle history expands the canonical outcome without changing it")
	_ok(not view._history_panel.visible, "battle history starts closed")
	view._toggle_history()
	_ok(view._history_panel.visible, "battle history can be opened during combat")
	view._toggle_history()
	_ok(not view._history_panel.visible, "battle history close returns to combat")
	_ok("진형 상성" in report.current_directive and "3단계 교전" in report.current_directive,
		"phase report exposes an actionable current directive")
	var advance_button: Button = view._buttons.filter(
		func(button: Button): return String(button.get_meta("action", "")) == "advance_phase")[0]
	_ok(advance_button.has_theme_stylebox_override("normal")
		and advance_button.has_theme_stylebox_override("disabled"),
		"primary phase action has explicit active and disabled visual states")
	view._formation.select(3)
	view._formation.item_selected.emit(3)
	_ok("안행진" in view._feedback.text and "강점 포화 ×1.4" in view._feedback.text
		and "필요 통솔 65" in view._feedback.text,
		"formation selection previews canonical strengths and requirements")
	view._show_phase_alert(3,"교전")
	_ok(view._phase_alert.visible and "주력 전열 충돌" in view._phase_alert.text,
		"phase transition alert exposes the current battle cue")
	view._process(2.0)
	_ok(not view._phase_alert.visible,"phase transition alert expires without blocking play")
	map.set_battle(1, "접적", 140, 120, 113, 120, "어린진", "선봉형")
	var contact_anchor: Vector2 = map.fleet_anchor_points()["allied_primary"]
	var select_event:=InputEventMouseButton.new(); select_event.button_index=MOUSE_BUTTON_LEFT; select_event.pressed=true; select_event.position=contact_anchor
	map._gui_input(select_event)
	var selected: Dictionary=map.selection_snapshot()
	_ok(selected.get("name","")=="우비 돌격단" and selected.get("faction","")=="손권·유비 연합"
		and int(selected.get("ships",0))==120 and int(selected.get("morale",0))==120,
		"clicking a fleet exposes canonical faction strength and morale")
	_ok(selected.get("formation","")=="선봉형" and selected.get("objective","")=="교전권 진입"
		and selected.get("engagement","")=="접근 중",
		"selected fleet detail exposes formation, objective, and engagement state")
	var hub := Vector2(map.size.x * .52, map.size.y * .55)
	map.set_battle(4, "강습", 140, 120, 113, 120, "어린진", "선봉형")
	var assault_anchor: Vector2 = map.fleet_anchor_points()["allied_primary"]
	_ok(assault_anchor.distance_to(hub) < contact_anchor.distance_to(hub),
		"fleet advances along its route as combat phases progress")
	_ok(map.selection_snapshot().get("objective","")=="구지 거점 돌파"
		and map.selection_snapshot().get("engagement","")=="강습 중",
		"fleet detail follows the current phase without inventing combat state")
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
	_ok(map.selection_snapshot().is_empty(), "destroyed selected fleet clears its detail panel")
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
