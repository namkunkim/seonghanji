extends SceneTree

## Task ID: DEMO-RC-G2-01
## 공식 작업 제목: 유비 직행 전투 준비 화면 및 역사적 초기 상태 경계
## 새 작업 제목: DEMO-RC-G2-01 — 유비 직행 전투 준비 화면 및 역사적 초기 상태 경계

const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const PreparationView := preload("res://scripts/red_cliff_turn/red_cliff_preparation_view.gd")

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


func _run() -> void:
	print("DEMO-RC-G2-01 direct Liu Bei preparation")
	_test_setup_contract()
	await _test_invalid_boundaries()
	await _test_product_entry()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)


func _test_setup_contract() -> void:
	var result := Setup.load_default()
	_ok(bool(result.get("ok", false)), "default setup validates")
	if not bool(result.get("ok", false)):
		return
	var setup: Dictionary = result["setup"]
	_eq(setup.get("player_faction_id"), "liu_bei", "player is Liu Bei")
	_eq(setup.get("balance_profile", {}).get("id"), "normal-demo-v1", "balance profile is explicit")
	var faction_ids: Array[String] = []
	for faction in setup["factions"]:
		faction_ids.append(String(faction.get("id", "")))
	for expected in ["liu_bei", "sun_quan", "cao_cao"]:
		_ok(faction_ids.has(expected), "required faction %s" % expected)
		_ok(setup["squadrons"].any(func(row): return String(row.get("faction_id", "")) == expected),
			"faction has a squadron: %s" % expected)
	var ship_names: Array[String] = []
	var fast_craft: Dictionary = {}
	for ship in setup["ship_types"]:
		ship_names.append(String(ship.get("name", "")))
		if String(ship.get("id", "")) == "SHP-08":
			fast_craft = ship
	_ok(ship_names.has("요격함") and not ship_names.has("구축함"), "interceptor naming boundary")
	_eq(fast_craft.get("mission_equipment", []).size(), 4, "fast craft has four equipment extensions")
	var formation_rows = JSON.parse_string(FileAccess.get_file_as_string("res://data/formations.json"))
	var formation_ids: Array = []
	for formation in formation_rows:
		formation_ids.append(String(formation.get("id", "")))
	formation_ids.sort()
	var allowed_formation_ids: Array = Setup.ALLOWED_FORMATION_IDS.duplicate()
	allowed_formation_ids.sort()
	_eq(allowed_formation_ids, formation_ids, "formation allow-list matches canonical data")
	for squadron in setup["squadrons"]:
		_ok(String(squadron.get("id", "")).begins_with("RC-"), "squadron has stable ID")
		_ok(squadron.get("commander") is Dictionary, "squadron has commander")
		_ok(squadron.get("flagship") is bool, "squadron has flagship state")
		_eq(squadron.get("initial_position", []).size(), 2, "squadron has 2D position")
		_ok(not String(squadron.get("formation_id", "")).is_empty(), "squadron has formation")
		_eq(squadron.get("declared_total_cost"), squadron.get("calculated_total_cost"),
			"declared and calculated cost match")
	var setup_source := FileAccess.get_file_as_string("res://data/red-cliffs-demo-setup.json")
	_ok("SQUADRON_SHIPS" not in setup_source and '"count": 28' not in setup_source,
		"new setup does not use the legacy 28-ship constant")
	var view_source := FileAccess.get_file_as_string("res://scripts/red_cliff_turn/red_cliff_preparation_view.gd")
	_ok("Node3D" not in view_source and ".glb" not in view_source and "voyage_3d" not in view_source,
		"preparation path has no 3D reference")


func _test_invalid_boundaries() -> void:
	var valid := Setup.load_default()
	if not bool(valid.get("ok", false)):
		_ok(false, "invalid tests require valid fixture")
		return
	var duplicate: Dictionary = valid["setup"].duplicate(true)
	duplicate["squadrons"].append(duplicate["squadrons"][0].duplicate(true))
	_ok(not bool(Setup.validate_document(duplicate).get("ok", true)), "duplicate squadron rejected")
	var unknown: Dictionary = valid["setup"].duplicate(true)
	unknown["squadrons"][0]["composition"][0]["ship_type_id"] = "SHP-UNKNOWN"
	_ok(not bool(Setup.validate_document(unknown).get("ok", true)), "unknown ship type rejected")
	var negative: Dictionary = valid["setup"].duplicate(true)
	negative["squadrons"][0]["composition"][0]["count"] = -1
	_ok(not bool(Setup.validate_document(negative).get("ok", true)), "negative count rejected")
	var mismatch: Dictionary = valid["setup"].duplicate(true)
	mismatch["squadrons"][0]["declared_total_cost"] = 999
	_ok(not bool(Setup.validate_document(mismatch).get("ok", true)), "cost mismatch rejected")
	var missing: Dictionary = valid["setup"].duplicate(true)
	missing.erase("battle_id")
	_ok(not bool(Setup.validate_document(missing).get("ok", true)), "missing required field rejected")
	var wrong_profile: Dictionary = valid["setup"].duplicate(true)
	wrong_profile["balance_profile"]["id"] = "normal-demo-v2"
	_ok(not bool(Setup.validate_document(wrong_profile).get("ok", true)),
		"non-canonical balance profile rejected")
	var missing_equipment: Dictionary = valid["setup"].duplicate(true)
	missing_equipment["ship_types"][7]["mission_equipment"].remove_at(0)
	_ok(not bool(Setup.validate_document(missing_equipment).get("ok", true)),
		"missing fast-craft mission equipment rejected")
	var extra_equipment: Dictionary = valid["setup"].duplicate(true)
	extra_equipment["ship_types"][7]["mission_equipment"].append(
		{"id": "FAST-EQ-EXTRA", "name": "추가", "unit_cost": 1})
	_ok(not bool(Setup.validate_document(extra_equipment).get("ok", true)),
		"extra fast-craft mission equipment rejected")
	var duplicate_equipment: Dictionary = valid["setup"].duplicate(true)
	duplicate_equipment["ship_types"][7]["mission_equipment"].append(
		duplicate_equipment["ship_types"][7]["mission_equipment"][0].duplicate(true))
	_ok(not bool(Setup.validate_document(duplicate_equipment).get("ok", true)),
		"duplicate fast-craft mission equipment rejected")
	for control_case in [["liu_bei", "ai"], ["sun_quan", "player"], ["cao_cao", "turn_prompt_ai"]]:
		var wrong_control: Dictionary = valid["setup"].duplicate(true)
		for faction in wrong_control["factions"]:
			if String(faction.get("id", "")) == String(control_case[0]):
				faction["control"] = String(control_case[1])
		_ok(not bool(Setup.validate_document(wrong_control).get("ok", true)),
			"wrong control rejected: %s" % control_case[0])
	var unknown_formation: Dictionary = valid["setup"].duplicate(true)
	unknown_formation["squadrons"][0]["formation_id"] = "FRM-UNKNOWN"
	_ok(not bool(Setup.validate_document(unknown_formation).get("ok", true)),
		"unknown formation ID rejected")

	var error_view := PreparationView.new()
	root.add_child(error_view)
	error_view.configure({"ok": false, "errors": ["시험용 오류"], "setup": {}})
	await process_frame
	var error_start: Button = error_view.find_child("StartTurnBattle", true, false)
	var error_status: Label = error_view.find_child("PreparationStatus", true, false)
	_ok(error_start != null and error_start.disabled, "invalid setup disables battle start")
	_ok(error_status != null and "시험용 오류" in error_status.text, "invalid setup is visible")
	error_view.free()


func _test_product_entry() -> void:
	root.size = Vector2i(1600, 900)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	_ok(main._start_red_cliff_demo(), "existing Red Cliffs action opens preparation")
	await process_frame
	var view: Control = main.get("red_cliff_preparation_view")
	_ok(view != null and view.visible, "preparation view is visible")
	_eq(view.size.round(), Vector2(1600, 900), "preparation fills 1600x900 viewport")
	var state: Dictionary = main.get("red_cliff_preparation_state")
	_ok(bool(state.get("ready", false)), "preparation state is ready")
	_eq(state.get("player_faction_id"), "liu_bei", "Main exposes Liu Bei player state")
	_ok(view.find_child("Faction_liu_bei", true, false) != null, "Liu Bei column visible")
	_ok(view.find_child("Faction_sun_quan", true, false) != null, "Sun Quan column visible")
	_ok(view.find_child("Faction_cao_cao", true, false) != null, "Cao Cao column visible")
	if DisplayServer.get_name() != "headless":
		var output_dir := "res://out/demo-rc-g2-01-direct-preparation"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
		await process_frame
		var image := root.get_texture().get_image()
		_ok(image != null and image.get_size() == Vector2i(1600, 900), "1600x900 GUI capture available")
		if image != null:
			_ok(image.save_png(ProjectSettings.globalize_path(output_dir.path_join("preparation-1600x900.png"))) == OK,
				"GUI capture saved")
	for node_name in ["RestoreHistoricalFormation", "OpenCustomFormation", "StartTurnBattle"]:
		_ok(view.find_child(node_name, true, false) is Button, "%s action visible" % node_name)
	var first_view_id := view.get_instance_id()
	_ok(main._start_red_cliff_demo(), "duplicate entry remains accepted")
	await process_frame
	_eq(main.get("red_cliff_preparation_view").get_instance_id(), first_view_id,
		"duplicate entry reuses one view")
	_eq(main.find_children("RedCliffPreparationView", "Control", true, false).size(), 1,
		"only one preparation view exists")
	var preparation_state_before: Dictionary = main.red_cliff_preparation_state.duplicate(true)
	var expected_applied: Dictionary = Setup.load_default().get("setup", {})
	var expected_applied_digest: String = JSON.stringify(expected_applied)
	var custom: Button = view.find_child("OpenCustomFormation", true, false)
	custom.pressed.emit()
	await process_frame
	var status: Label = view.find_child("PreparationStatus", true, false)
	var editor: Control = view.formation_editor()
	_ok(editor != null and editor.visible, "custom formation opens the G3 editor")
	var draft = editor.draft_controller()
	_eq(main.red_cliff_preparation_state, preparation_state_before,
		"opening editor does not mutate Main preparation state")
	_eq(int(draft.applied_snapshot().get("formation_revision", -1)), 0,
		"opening editor preserves applied revision")
	_eq(draft.applied_digest(), expected_applied_digest,
		"opening editor preserves applied setup digest")
	var start: Button = view.find_child("StartTurnBattle", true, false)
	start.pressed.emit()
	await process_frame
	var turn_view: Control = main.red_cliff_turn_battle_view
	_ok(bool(main.red_cliff_turn_battle_state.get("active", false)),
		"battle start activates the validated G4 turn battle")
	_ok(turn_view != null and turn_view.visible, "battle start opens the G4 turn view")
	_eq(main.red_cliff_turn_battle_state.get("applied_digest"),
		preparation_state_before.get("applied_digest"), "G4 receives current applied setup digest")
	_eq(JSON.stringify(turn_view.battle_controller().snapshot().get("applied_setup", {})),
		expected_applied_digest, "G4 controller receives the validated current applied setup")
	_eq(main.find_children("RedCliffTurnBattleView", "Control", true, false).size(), 1,
		"battle start creates a single G4 turn view")
	var initial_log: Dictionary = turn_view.battle_controller().turn_log()[0]
	_ok(not initial_log.get("resolution_receipt", {}).has("winner")
		and not initial_log.get("resolution_receipt", {}).has("damage"),
		"G4 start invents no winner or damage")
	main.free()
