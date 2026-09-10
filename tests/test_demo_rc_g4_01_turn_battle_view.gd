extends SceneTree

## Task ID: DEMO-RC-G4-01
## 공식 작업 제목: 유비 명령·손권 제어 선택·20턴 판정 루프
## 새 작업 제목: DEMO-RC-G4-01 — 유비 명령·손권 제어 선택·20턴 판정 루프

const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")
const View := preload("res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd")

var _pass := 0
var _fail := 0


func _ok(value: bool, label: String) -> void:
	if value: _pass += 1
	else: _fail += 1; print("  x %s" % label)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])


func _init() -> void: call_deferred("_run")


func _run() -> void:
	print("DEMO-RC-G4-01 turn battle UI")
	root.size = Vector2i(1600, 900)
	await _test_view_flow()
	await _test_turn_limit()
	await _test_main_entry_and_reentry()
	_test_source_boundary()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)


func _fixture() -> Array:
	var loaded := Setup.load_default(); _ok(bool(loaded.get("ok", false)), "setup fixture validates")
	var setup: Dictionary = loaded.get("setup", {}).duplicate(true)
	var battle = Battle.new(); _ok(bool(battle.initialize(setup).get("ok", false)), "battle initializes")
	return [battle, setup]


func _test_view_flow() -> void:
	var fixture := _fixture(); var battle = fixture[0]; var setup: Dictionary = fixture[1]
	var digest := JSON.stringify(setup); var view := View.new()
	_eq(view.configure(battle, int(setup.get("formation_revision", 0)), digest).get("ok"), true, "view configures")
	root.add_child(view); await _settle()
	_eq(view.size.round(), Vector2(1600, 900), "view fills 1600x900")
	_eq(view.view_state().applied_digest, digest, "exact applied digest retained")
	var tactical_map = view.find_child("AppliedSquadronMap", true, false)
	_ok(tactical_map != null and tactical_map.marker_local_position("RC-LIU-SQ-01") != Vector2.ZERO, "live tactical squadron markers visible")
	for name in ["Disabled무기", "Disabled진형 변경", "Disabled탐지"]:
		var control: Button = view.find_child(name, true, false); _ok(control != null and control.disabled, "%s disabled" % name)
	var first_digest: String = battle.digest(); view.call("_on_primary"); await _settle()
	_eq(battle.phase(), "sun_control_prompt", "Liu HOLD opens prompt")
	_ok(view.find_child("SunControlPrompt", true, false).visible, "Sun prompt visible exactly once")
	var prompt_digest: String = battle.digest(); view.call("_on_primary"); _eq(battle.phase(), "sun_control_prompt", "duplicate primary gated")
	_ok(battle.digest() == prompt_digest and battle.digest() != first_digest, "duplicate action does not advance")
	view.find_child("SunManualThisTurn", true, false).pressed.emit(); await _settle()
	_eq(battle.phase(), "sun_command", "manual branch opens Sun command")
	view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await _settle()
	_eq(battle.phase(), "victory_check", "manual Sun HOLD resolves ledger once")
	var receipt: Dictionary = battle.turn_log()[0].resolution_receipt
	_ok(not receipt.get("rules_pending", []).has("movement") and not receipt.get("movement_events", []).is_empty() \
		and not receipt.has("winner") and not receipt.has("damage"), "movement resolves while remaining rules stay pending without fake result")
	_ok(view.find_child("TurnStatus", true, false).text.contains("후속 구현 대기"), "pending victory copy visible")
	view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await _settle()
	_eq(battle.turn(), 2, "next turn increments once")
	view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await _settle()
	view.find_child("SunAiDontAsk", true, false).pressed.emit(); await _settle()
	_eq(battle.phase(), "victory_check", "AI dont-ask resolves")
	_ok(not battle.prompt_policy().enabled, "dont-ask stores AI-only policy")
	view.find_child("PrimaryTurnAction", true, false).pressed.emit(); view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await _settle()
	_eq(battle.turn(), 3, "double next click advances once")
	_eq(battle.phase(), "liu_command", "double next click cannot submit next phase")
	view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await _settle()
	_eq(battle.phase(), "victory_check", "saved AI skips prompt and resolves")
	view.find_child("ReenableSunPrompt", true, false).pressed.emit(); await _settle()
	_ok(battle.prompt_policy().enabled, "settings re-enable prompt")
	view.find_child("PrimaryTurnAction", true, false).pressed.emit(); view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await _settle()
	_eq(battle.turn(), 4, "continue and Liu command are phase gated")
	_eq(battle.phase(), "liu_command", "double click cannot cross phase boundary")
	view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await _settle()
	_eq(battle.phase(), "sun_control_prompt", "re-enabled policy prompts next turn")
	_ok(view.find_child("TurnLedger", true, false).text.contains("rules_pending"), "turn ledger visibly records boundary")
	if DisplayServer.get_name() != "headless":
		var output_dir := "res://out/demo-rc-g4-01-turn-loop"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)); await process_frame
		var image := root.get_texture().get_image(); _ok(image != null and image.get_size() == Vector2i(1600, 900), "1600x900 GPU capture available")
		if image != null: _ok(image.save_png(ProjectSettings.globalize_path(output_dir.path_join("turn-loop-1600x900.png"))) == OK, "GPU capture saved")
	view.free()


func _test_turn_limit() -> void:
	var fixture := _fixture(); var battle = fixture[0]; var setup: Dictionary = fixture[1]
	battle.set_sun_prompt_enabled(false)
	for turn_number in range(1, 21):
		battle.submit_liu_orders(_orders(setup, "liu_bei")); battle.resolve_turn()
		if turn_number < 20: battle.continue_turn()
	var view := View.new(); view.configure(battle, int(setup.get("formation_revision", 0)), JSON.stringify(setup)); root.add_child(view); await process_frame
	_eq(battle.phase(), "turn_limit_reached", "turn 20 reaches result pending")
	_ok(view.find_child("TurnHeader", true, false).text.contains("20/20"), "20/20 visible")
	_ok(view.find_child("TurnStatus", true, false).text.contains("결과 판정 대기"), "result pending copy visible")
	_ok(view.find_child("PrimaryTurnAction", true, false).disabled, "next turn disabled at limit")
	view.free()


func _test_main_entry_and_reentry() -> void:
	var main = load("res://scenes/main.tscn").instantiate(); root.add_child(main); await process_frame; await process_frame
	_ok(main._start_red_cliff_demo(), "Main opens preparation"); await process_frame
	var prep: Control = main.red_cliff_preparation_view; var expected_digest: String = main.red_cliff_preparation_state.applied_digest
	prep.find_child("StartTurnBattle", true, false).pressed.emit(); await process_frame
	var view: Control = main.red_cliff_turn_battle_view
	_ok(view != null and view.visible and not prep.visible, "start opens one turn view")
	_eq(main.red_cliff_turn_battle_state.applied_digest, expected_digest, "Main exposes exact applied digest")
	_eq(main.red_cliff_turn_battle_state.phase, "liu_command", "Main exposes phase")
	var view_id := view.get_instance_id(); view.find_child("ReturnToPreparation", true, false).pressed.emit(); await process_frame
	_ok(prep.visible and not view.visible, "return shows preparation without destroying battle")
	prep.find_child("StartTurnBattle", true, false).pressed.emit(); await process_frame
	_eq(main.red_cliff_turn_battle_view.get_instance_id(), view_id, "re-entry reuses active battle view")
	_eq(main.find_children("RedCliffTurnBattleView", "Control", true, false).size(), 1, "single view after duplicate entry")
	main.free()


func _orders(setup: Dictionary, faction_id: String) -> Array:
	var result: Array = []
	for squad in setup.get("squadrons", []):
		if String(squad.get("faction_id", "")) == faction_id and bool(squad.get("operational", true)): result.append({"squadron_id": String(squad.get("id", "")), "action": "hold"})
	return result


func _settle() -> void:
	await process_frame
	await process_frame


func _test_source_boundary() -> void:
	for path in ["res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd", "res://scripts/red_cliff_turn/red_cliff_preparation_view.gd"]:
		var source := FileAccess.get_file_as_string(path); _ok("Node3D" not in source and ".glb" not in source and "voyage_3d" not in source, "%s has zero 3D refs" % path)
