extends SceneTree

## Task ID: DEMO-RC-G3-01
## 공식 작업 제목: 비용 기반 전대·함대 편성 편집기
## 새 작업 제목: DEMO-RC-G3-01 — 비용 기반 전대·함대 편성 편집기

const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Editor := preload("res://scripts/red_cliff_turn/red_cliff_formation_editor.gd")
const Preparation := preload("res://scripts/red_cliff_turn/red_cliff_preparation_view.gd")

var _pass := 0
var _fail := 0


func _ok(value: bool, label: String) -> void:
	if value: _pass += 1
	else:
		_fail += 1
		print("  x %s" % label)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("DEMO-RC-G3-01 formation editor UI")
	root.size = Vector2i(1600, 900)
	await _test_editor_contract()
	await _test_preparation_integration()
	await _test_main_summary_integration()
	_test_source_boundary()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)


func _test_editor_contract() -> void:
	var load_result := Setup.load_default()
	_ok(bool(load_result.get("ok", false)), "validated setup fixture")
	if not bool(load_result.get("ok", false)): return
	var editor := Editor.new()
	_eq(editor.configure(load_result.setup).get("ok"), true, "editor configures from validated setup")
	root.add_child(editor)
	await process_frame
	_eq(editor.size.round(), Vector2(1600, 900), "editor fills 1600x900")
	if DisplayServer.get_name() != "headless":
		var output_dir := "res://out/demo-rc-g3-01-formation-editor"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
		await process_frame
		var capture := root.get_texture().get_image()
		_ok(capture != null and capture.get_size() == Vector2i(1600, 900), "1600x900 GUI capture available")
		if capture != null:
			_ok(capture.save_png(ProjectSettings.globalize_path(output_dir.path_join("formation-editor-1600x900.png"))) == OK, "GUI capture saved")
	for name in ["FactionTab_liu_bei", "FactionTab_sun_quan", "FactionTab_cao_cao", "FormationEditorBody", "FormationEditorFooter"]:
		_ok(editor.find_child(name, true, false) != null, "%s exists" % name)
	_ok(editor.find_child("ShipCompositionScroll", true, false) is ScrollContainer, "ship rows scroll independently")
	_ok(editor.find_child("InventoryScroll", true, false) is ScrollContainer, "inventory scrolls independently")
	for ship_index in range(1, 9):
		_ok(editor.find_child("ShipCount_SHP-%02d" % ship_index, true, false) is SpinBox, "ship count control %02d" % ship_index)
	var draft = editor.draft_controller()
	var initial_digest: String = draft.applied_digest()
	var ship_spin: SpinBox = editor.find_child("ShipCount_SHP-04", true, false)
	ship_spin.value = ship_spin.value + 1
	await process_frame
	_ok(draft.draft_digest() != initial_digest, "count control updates draft")
	_ok(editor.find_child("CommandMetrics", true, false).text.contains("현재 / 권장 비용"), "metrics refresh after edit")
	_ok(editor.find_child("Inventory_SHP-04", true, false).text.contains("가용"), "inventory API summary visible")
	var formation: OptionButton = editor.find_child("FormationSelect", true, false)
	formation.select((formation.selected + 1) % formation.item_count)
	formation.item_selected.emit(formation.selected)
	await process_frame
	var commander: OptionButton = editor.find_child("CommanderSelect", true, false)
	commander.select((commander.selected + 1) % commander.item_count)
	commander.item_selected.emit(commander.selected)
	await process_frame
	var equipment: OptionButton = editor.find_child("Equipment_SHP-08", true, false)
	equipment.select((equipment.selected + 1) % equipment.item_count)
	equipment.item_selected.emit(equipment.selected)
	await process_frame
	var position_x: SpinBox = editor.find_child("PositionX", true, false)
	position_x.value = position_x.value + 1
	await process_frame
	_ok(draft.draft_digest() != initial_digest, "formation and position controls mutate draft")

	editor.call("_select_faction", "sun_quan")
	await process_frame
	_ok(not draft.can_edit_faction("sun_quan"), "Sun starts locked")
	var sun_locked: SpinBox = editor.find_child("ShipCount_SHP-01", true, false)
	_ok(sun_locked != null and not sun_locked.editable, "Sun controls disabled while locked")
	editor.find_child("ToggleSunManual", true, false).pressed.emit()
	await process_frame
	_ok(draft.can_edit_faction("sun_quan"), "Sun opt-in enables manual editing")

	editor.call("_select_faction", "cao_cao")
	await process_frame
	var cao_before: String = draft.draft_digest()
	var rejected: Dictionary = draft.set_ship_count("RC-CAO-SQ-01", "SHP-01", 0)
	_ok(not bool(rejected.get("ok", true)) and draft.draft_digest() == cao_before, "Cao programmatic mutation rejected")
	_ok(not editor.find_child("ShipCount_SHP-01", true, false).editable, "Cao control is read-only")

	editor.call("_select_faction", "liu_bei")
	await process_frame
	var fleet_before: int = draft.draft_snapshot().fleet_groups.size()
	var fleet_name: LineEdit = editor.find_child("NewFleetName", true, false)
	fleet_name.text = "시험 함대"
	editor.find_child("CreateFleet", true, false).pressed.emit()
	await process_frame
	_eq(draft.draft_snapshot().fleet_groups.size(), fleet_before + 1, "fleet creation control")
	fleet_name = editor.find_child("NewFleetName", true, false)
	fleet_name.text = "이름 변경 함대"
	editor.find_child("RenameFleet", true, false).pressed.emit()
	await process_frame
	_ok(draft.draft_snapshot().fleet_groups.any(func(row): return row.name == "이름 변경 함대"),
		"fleet rename control")
	editor.find_child("UnassignSquadron", true, false).pressed.emit()
	await process_frame
	_ok(draft.draft_snapshot().squadrons.any(func(row): return row.id == editor.editor_state().selected_squadron and row.deployment.kind == "independent"), "independent squadron control")

	editor.call("_cancel_draft")
	await process_frame
	_eq(draft.draft_digest(), draft.applied_digest(), "cancel restores applied snapshot")
	editor.call("_restore_historical")
	await process_frame
	_eq(draft.draft_digest(), JSON.stringify(draft.historical_snapshot()), "historical restore changes draft only")
	draft.set_ship_count("RC-LIU-SQ-01", "SHP-04", 5)
	var applied := []
	editor.formation_applied.connect(func(setup, summary): applied.append([setup, summary]))
	editor.call("_apply_draft")
	await process_frame
	_eq(applied.size(), 1, "apply emits exactly once")
	_eq(int(applied[0][1].formation_revision), 1, "apply increments revision")
	editor.call("_apply_draft")
	_eq(applied.size(), 1, "unchanged duplicate apply is ignored")

	# Aggregate inventory excess is a valid draft mutation but an invalid atomic apply.
	editor.call("_select_squadron", "RC-LIU-SQ-01")
	var inventory: Dictionary = draft.faction_inventory_summary("liu_bei").inventory
	_eq(draft.set_ship_count("RC-LIU-SQ-01", "SHP-04", int(inventory["SHP-04"].total)).ok, true, "inventory excess may exist in draft")
	var applied_digest: String = draft.applied_digest()
	_ok(not draft.validate_draft().ok, "inventory excess invalidates draft")
	editor.call("_apply_draft")
	_eq(draft.applied_digest(), applied_digest, "invalid apply is atomic")
	_ok(editor.find_child("FormationEditorStatus", true, false).text.length() > 0, "invalid reason visible in Korean status")
	editor.free()


func _test_preparation_integration() -> void:
	var historical: Dictionary = Setup.load_default().setup
	var historical_digest := JSON.stringify(historical)
	var view := Preparation.new()
	root.add_child(view)
	view.configure(Setup.load_default())
	await process_frame
	view.find_child("OpenCustomFormation", true, false).pressed.emit()
	await process_frame
	var editor: Control = view.formation_editor()
	_ok(editor != null and editor.visible, "preparation button opens real editor")
	var instance_id := editor.get_instance_id()
	view.find_child("OpenCustomFormation", true, false).pressed.emit()
	await process_frame
	_eq(view.formation_editor().get_instance_id(), instance_id, "duplicate open reuses editor")
	_eq(view.find_children("RedCliffFormationEditor", "Control", true, false).size(), 1, "single editor instance")
	var draft = editor.draft_controller()
	_ok(draft.set_formation("RC-LIU-SQ-01", "FRM-07").ok, "preparation lifetime custom edit stages")
	editor.call("_apply_draft")
	await process_frame
	var custom_digest: String = draft.applied_digest()
	_ok(custom_digest != historical_digest, "preparation lifetime custom edit applies")
	editor.call("_request_close")
	await process_frame
	view.find_child("OpenCustomFormation", true, false).pressed.emit()
	await process_frame
	draft = view.formation_editor().draft_controller()
	_eq(draft.applied_digest(), custom_digest, "close and reopen preserves current applied setup")
	_eq(JSON.stringify(draft.historical_snapshot()), historical_digest, "close and reopen preserves original historical baseline")
	draft.restore_historical()
	_eq(draft.draft_digest(), historical_digest, "restore stages original historical baseline")
	_eq(draft.applied_digest(), custom_digest, "restore does not apply over current custom setup")
	draft.cancel()
	_eq(draft.draft_digest(), custom_digest, "cancel returns to current custom applied setup")
	view.find_child("RestoreHistoricalFormation", true, false).pressed.emit()
	await process_frame
	draft = view.formation_editor().draft_controller()
	_eq(draft.draft_digest(), historical_digest, "preparation restore button opens historical draft")
	_eq(draft.applied_digest(), custom_digest, "preparation restore button remains non-destructive")
	view.free()


func _test_main_summary_integration() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	_ok(main._start_red_cliff_demo(), "Main opens G3 preparation")
	await process_frame
	var view: Control = main.red_cliff_preparation_view
	view.find_child("OpenCustomFormation", true, false).pressed.emit()
	await process_frame
	var editor: Control = view.formation_editor()
	var main_draft = editor.draft_controller()
	main_draft.set_ship_count("RC-LIU-SQ-01", "SHP-04", 5)
	editor.call("_apply_draft")
	await process_frame
	var state: Dictionary = main.red_cliff_preparation_state
	_eq(int(state.get("applied_revision", -1)), 1, "Main exposes applied revision")
	_ok(int(state.get("total_cost", 0)) > 0, "Main exposes player total cost")
	_ok(state.get("overcap_summary") is Array, "Main exposes overcap summary")
	var applied_revision := int(state.get("applied_revision", -1))
	var applied_digest := String(state.get("applied_digest", ""))
	var applied_setup: Dictionary = state.get("applied_setup", {}).duplicate(true)
	main._close_red_cliff_preparation()
	_ok(main._start_red_cliff_demo(), "Main reopens preparation in the same runtime session")
	await process_frame
	_eq(int(main.red_cliff_preparation_state.get("applied_revision", -1)), applied_revision,
		"Main reopen preserves applied revision")
	_eq(String(main.red_cliff_preparation_state.get("applied_digest", "")), applied_digest,
		"Main reopen preserves applied digest")
	_eq(main.red_cliff_preparation_state.get("applied_setup", {}), applied_setup,
		"Main reopen preserves applied setup")
	view = main.red_cliff_preparation_view
	view.find_child("OpenCustomFormation", true, false).pressed.emit()
	await process_frame
	_eq(view.formation_editor().draft_controller().applied_digest(), applied_digest,
		"reopened Main editor receives current applied setup")
	main.free()


func _test_source_boundary() -> void:
	for path in ["res://scripts/red_cliff_turn/red_cliff_formation_editor.gd", "res://scripts/red_cliff_turn/red_cliff_preparation_view.gd"]:
		var source := FileAccess.get_file_as_string(path)
		_ok("Node3D" not in source and ".glb" not in source and "voyage_3d" not in source, "%s remains pure 2D" % path)
