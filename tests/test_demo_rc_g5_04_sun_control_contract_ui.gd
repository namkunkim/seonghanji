extends SceneTree

## DEMO-RC-G5-04 — 손권 제어 문의 계약 재검증 UI integration.
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")
const View := preload("res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd")

var _pass := 0
var _fail := 0
func _ok(value: bool, label: String) -> void:
	if value: _pass += 1
	else: _fail += 1; print("  x %s" % label)
func _eq(actual, expected, label: String) -> void: _ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])
func _init() -> void: call_deferred("_run")

func _run() -> void:
	print("DEMO-RC-G5-04 Sun control contract UI")
	root.size = Vector2i(1600, 900)
	await _test_manual_complete_orders_and_draft_isolation()
	await _test_ai_once_prompts_again()
	await _test_dont_ask_reenable_and_duplicate_guards()
	_test_source_boundary()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)

func _fixture() -> Array:
	var loaded := Setup.load_default(); _ok(loaded.ok, "setup loads")
	var setup: Dictionary = loaded.setup.duplicate(true); var battle = Battle.new(); _ok(battle.initialize(setup).ok, "battle initializes")
	var view := View.new(); view.configure(battle, int(setup.get("formation_revision", 0)), JSON.stringify(setup)); root.add_child(view)
	return [battle, view]

func _open_prompt(view: Control, battle) -> void:
	view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await _settle()
	_eq(battle.phase(), "sun_control_prompt", "Liu submit opens Sun prompt")

func _test_manual_complete_orders_and_draft_isolation() -> void:
	var fixture := _fixture(); var battle = fixture[0]; var view: Control = fixture[1]; await _settle()
	var liu_before: Dictionary = battle.command_draft().duplicate(true)
	await _open_prompt(view, battle)
	var prompt: PanelContainer = view.find_child("SunControlPrompt", true, false); var manual: Button = view.find_child("SunManualThisTurn", true, false); var ai: Button = view.find_child("SunAiThisTurn", true, false); var dont_ask: Button = view.find_child("SunAiDontAsk", true, false)
	var blocker: ColorRect = view.find_child("SunControlModalBlocker", true, false)
	_ok(prompt.visible and manual.text == "이번 턴 직접 명령" and ai.text == "이번 턴 AI 위임" and dont_ask.text == "AI 위임하고 더 이상 묻지 않음", "three prompt choices are explicit")
	_ok(blocker != null and blocker.visible and blocker.mouse_filter == Control.MOUSE_FILTER_STOP, "prompt blocks background pointer input")
	_eq(root.gui_get_focus_owner(), manual, "required prompt focuses manual choice")
	_ok(manual.focus_next == NodePath("../SunAiThisTurn") and dont_ask.focus_next == NodePath("../SunManualThisTurn"), "prompt focus cycles within three choices")
	_ok(manual.custom_minimum_size.y >= 44 and ai.custom_minimum_size.y >= 44 and dont_ask.custom_minimum_size.y >= 44, "prompt targets are at least 44px")
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true; view._unhandled_key_input(escape); await _settle()
	_eq(battle.phase(), "sun_control_prompt", "Esc cannot dismiss required prompt")
	_ok(view.find_child("TurnStatus", true, false).text.contains("Esc로 닫을 수 없습니다"), "Esc rejection is explained in Korean")
	var prompt_digest: String = battle.digest(); view.call("_on_primary"); view.call("_on_primary"); _eq(battle.digest(), prompt_digest, "background primary cannot bypass prompt")
	manual.pressed.emit(); await _settle(); _eq(battle.phase(), "sun_command", "yes/manual opens Sun command")
	_ok(not blocker.visible, "modal blocker clears after required choice")
	_eq(battle.command_draft_summary().faction_id, "sun_quan", "manual branch owns isolated Sun draft")
	_eq(battle.command_draft_summary().total, 1, "manual branch contains every operational Sun squadron")
	_ok(battle.command_order("RC-LIU-SQ-01").get("ok", false) == false, "Liu draft is unavailable during Sun command")
	_ok(JSON.stringify(battle.command_draft()) != JSON.stringify(liu_before), "Sun draft is not reused Liu draft")
	var map = view.find_child("AppliedSquadronMap", true, false); var intelligence: Dictionary = map.intelligence_state_for_test()
	_eq(intelligence.viewer_faction_id, "sun_quan", "viewer switches to directly controlled Sun faction")
	_ok(intelligence.own_squadron_ids == ["RC-SUN-SQ-01"], "map exposes only Sun own squadron as raw own marker")
	view.find_child("SetOrderHold", true, false).pressed.emit(); view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await _settle()
	_eq(battle.phase(), "victory_check", "manual complete draft resolves once")
	var log: Dictionary = battle.turn_log()[0]; _eq(log.sun_orders.size(), 1, "manual Sun submits all operational orders")
	_eq(log.sun_control_decision.control, "manual", "manual decision recorded")
	_ok(battle.viewer_snapshot("liu_bei").get("prompt_policy", {}).is_empty(), "Liu viewer receives no Sun prompt policy")
	view.free()

func _test_ai_once_prompts_again() -> void:
	var fixture := _fixture(); var battle = fixture[0]; var view: Control = fixture[1]; await _settle(); await _open_prompt(view, battle)
	view.find_child("SunAiThisTurn", true, false).pressed.emit(); await _settle()
	_eq(battle.phase(), "victory_check", "no/AI resolves current turn")
	_ok(battle.prompt_policy().enabled, "AI once keeps future prompt enabled")
	var decision: Dictionary = battle.turn_log()[0].sun_control_decision; _eq(decision.control, "ai", "AI once decision recorded"); _ok(not decision.dont_ask_again, "AI once does not save policy")
	view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await _settle(); view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await _settle()
	_eq(battle.phase(), "sun_control_prompt", "AI once prompts again next turn")
	view.free()

func _test_dont_ask_reenable_and_duplicate_guards() -> void:
	var fixture := _fixture(); var battle = fixture[0]; var view: Control = fixture[1]; await _settle(); await _open_prompt(view, battle)
	var prompt_count_before: int = battle.turn_log().size(); var dont_ask: Button = view.find_child("SunAiDontAsk", true, false)
	dont_ask.pressed.emit(); dont_ask.pressed.emit(); await _settle()
	_eq(battle.phase(), "victory_check", "dont-ask double signal resolves only once")
	_eq(battle.turn_log().size(), prompt_count_before, "duplicate prompt signal does not add turn log")
	_ok(not battle.prompt_policy().enabled, "dont-ask saves AI-only policy")
	var decision: Dictionary = battle.turn_log()[0].sun_control_decision; _ok(decision.control == "ai" and decision.dont_ask_again, "saved policy is AI, never manual")
	var reenable: Button = view.find_child("ReenableSunPrompt", true, false); _ok(not reenable.disabled, "settings re-enable is available after dont-ask"); reenable.pressed.emit(); await _settle(); _ok(battle.prompt_policy().enabled, "settings re-enables prompt"); _eq(battle.phase(), "victory_check", "re-enable does not rewind current turn")
	view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await _settle(); _eq(battle.turn(), 2, "next turn advances once")
	var submit: Button = view.find_child("PrimaryTurnAction", true, false); submit.pressed.emit(); submit.pressed.emit(); await _settle()
	_eq(battle.phase(), "sun_control_prompt", "re-enabled prompt returns after next Liu submit")
	_ok(view.find_child("SunControlPrompt", true, false).visible, "single prompt visible after re-enable")
	if DisplayServer.get_name() != "headless":
		var output_dir := "res://out/demo-rc-g5-04-sun-control-contract"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)); var image := root.get_texture().get_image(); _ok(image != null and image.get_size() == Vector2i(1600, 900), "1600x900 GPU capture available")
		if image != null: _ok(image.save_png(ProjectSettings.globalize_path(output_dir.path_join("sun-control-contract-1600x900.png"))) == OK, "GPU capture saved")
	view.free()

func _settle() -> void:
	await process_frame
	await process_frame

func _test_source_boundary() -> void:
	for path in ["res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd", "res://scripts/red_cliff_turn/red_cliff_tactical_map.gd"]:
		var source := FileAccess.get_file_as_string(path); _ok("Node3D" not in source and ".glb" not in source and "voyage_3d" not in source, "%s has zero 3D refs" % path)
