extends SceneTree

## DEMO-RC-QA-04 — manual squadron composition/deployment loop acceptance.
##
## "Manual deployment" in the canonical demo means the G3-01 cost-based
## formation editor (ship composition, formation, position, fleet grouping)
## reached from the G2-01 preparation screen — not the superseded long-range
## Campaign voyage to RGN-04/SYS-13 via FleetMovePanel, which is out of
## scope for this demo (docs/07-production/demo-rc-completion-review-checklist.md
## §2). This test presses only real Button/SpinBox signals exposed by
## red_cliff_preparation_view/red_cliff_formation_editor and reads back their
## public state; it never writes squadron composition or cost directly.

const Harness := preload("res://tests/harness.gd")
const OUTPUT_DIR := "res://out/demo-rc-qa04-manual-deployment"

var _pass := 0
var _fail := 0


func _ok(value: bool, label: String) -> void:
	if value:
		_pass += 1
	else:
		_fail += 1
		print("  x %s" % label)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])


func _init() -> void:
	call_deferred("_run")


func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	var image := root.get_texture().get_image()
	_ok(image != null and image.get_size() == Vector2i(1600, 900), "%s 1600x900 capture available" % label)
	if image != null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
		_ok(image.save_png(ProjectSettings.globalize_path(OUTPUT_DIR.path_join(label + ".png"))) == OK,
			"%s capture saved" % label)


func _run() -> void:
	print("DEMO-RC-QA-04 manual composition/deployment editor product loop")
	root.size = Vector2i(1600, 900)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.red_cliff_demo_button.pressed.emit()
	await process_frame

	var prep: Control = main.red_cliff_preparation_view
	var open_button: Button = prep.find_child("OpenCustomFormation", true, false)
	_ok(open_button != null and not open_button.disabled, "OpenCustomFormation is visible and enabled")
	open_button.pressed.emit()
	await process_frame

	var editor: Control = prep.formation_editor()
	_ok(editor != null and editor.visible, "manual editor opens from the real preparation button")
	var draft = editor.draft_controller()
	await _capture("01-editor-open")

	# Liu Bei: an editable faction. Raise one hull count and confirm the draft
	# and the visible cost metrics both change through real controls only.
	var before_digest: String = draft.draft_digest()
	var ship_spin: SpinBox = editor.find_child("ShipCount_SHP-04", true, false)
	_ok(ship_spin != null and ship_spin.editable, "Liu Bei ship count control is editable")
	var raised_count: float = ship_spin.value + 1
	ship_spin.value = raised_count
	await process_frame
	_ok(draft.draft_digest() != before_digest, "raising a ship count mutates the draft")
	_ok(editor.find_child("CommandMetrics", true, false).text.contains("현재 / 권장 비용"),
		"cost metrics reflect the manual edit")

	var fleet_before: int = draft.draft_snapshot().fleet_groups.size()
	var fleet_name: LineEdit = editor.find_child("NewFleetName", true, false)
	fleet_name.text = "시험 함대"
	editor.find_child("CreateFleet", true, false).pressed.emit()
	await process_frame
	_eq(draft.draft_snapshot().fleet_groups.size(), fleet_before + 1, "manual fleet grouping control works")
	await _capture("02-liu-bei-edited")

	# Sun Quan: locked by default; opt-in required before manual edits apply.
	editor.call("_select_faction", "sun_quan")
	await process_frame
	_ok(not draft.can_edit_faction("sun_quan"), "Sun Quan starts locked to the historical deployment")
	var sun_spin: SpinBox = editor.find_child("ShipCount_SHP-01", true, false)
	_ok(sun_spin != null and not sun_spin.editable, "locked Sun Quan control is read-only")
	editor.find_child("ToggleSunManual", true, false).pressed.emit()
	await process_frame
	_ok(draft.can_edit_faction("sun_quan"), "manual opt-in unlocks Sun Quan editing")

	# Cao Cao: never editable in this demo.
	editor.call("_select_faction", "cao_cao")
	await process_frame
	var cao_spin: SpinBox = editor.find_child("ShipCount_SHP-01", true, false)
	_ok(cao_spin != null and not cao_spin.editable, "Cao Cao remains read-only")

	editor.call("_select_faction", "liu_bei")
	await process_frame
	var apply_button: Button = editor.find_child("ApplyFormationDraft", true, false)
	_ok(apply_button != null and not apply_button.disabled, "ApplyFormationDraft is available with a pending edit")
	var applied_events: Array = []
	editor.formation_applied.connect(func(setup, summary): applied_events.append([setup, summary]))
	apply_button.pressed.emit()
	await process_frame
	_eq(applied_events.size(), 1, "manual composition applies exactly once through the real button")
	var applied_setup: Dictionary = applied_events[0][0]
	var applied_liu_squadron: Dictionary = {}
	for squad in applied_setup.get("squadrons", []):
		if String(squad.get("id", "")) == "RC-LIU-SQ-01":
			applied_liu_squadron = squad
	var applied_count := 0
	for row in applied_liu_squadron.get("composition", []):
		if String(row.get("ship_type_id", "")) == "SHP-04":
			applied_count = int(row.get("count", 0))
	_eq(float(applied_count), raised_count, "the applied setup carries the manually edited hull count")
	await _capture("03-formation-applied")

	editor.find_child("CloseFormationEditor", true, false).pressed.emit()
	await process_frame
	_ok(not editor.visible and prep.visible, "closing the editor returns to preparation")

	var start_button: Button = prep.find_child("StartTurnBattle", true, false)
	start_button.pressed.emit()
	await process_frame
	var view: Control = main.red_cliff_turn_battle_view
	_ok(view != null and view.visible, "battle starts from the manually edited deployment")
	var controller_setup: Dictionary = view.battle_controller().snapshot().get("applied_setup", {})
	var battle_liu_squadron: Dictionary = {}
	for squad in controller_setup.get("squadrons", []):
		if String(squad.get("id", "")) == "RC-LIU-SQ-01":
			battle_liu_squadron = squad
	var battle_count := 0
	for row in battle_liu_squadron.get("composition", []):
		if String(row.get("ship_type_id", "")) == "SHP-04":
			battle_count = int(row.get("count", 0))
	_eq(float(battle_count), raised_count,
		"the manually edited hull count reaches the actual battle, not just the editor UI")
	await _capture("04-battle-uses-manual-deployment")

	main.free()
	print("DEMO-RC-QA-04: %d passed / %d failed" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)
