extends SceneTree

## DEMO-RC-G5-06 — 연쇄 폭발 작전 조건·방해·발동 UI.
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
	print("DEMO-RC-G5-06 chain explosion UI")
	root.size = Vector2i(1600, 900)
	await _test_readiness_cancel_trigger_and_redaction()
	await _test_disruption_and_retry_copy()
	_test_source_boundary()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)

func _test_readiness_cancel_trigger_and_redaction() -> void:
	var loaded := Setup.load_default(); _ok(loaded.ok, "setup loads"); var setup: Dictionary = loaded.setup.duplicate(true)
	var positions := {"RC-LIU-SQ-01":[700,49], "RC-LIU-SQ-02":[700,49], "RC-SUN-SQ-01":[550,100], "RC-CAO-SQ-01":[781,11]}
	for squad in setup.squadrons: squad.initial_position = positions[String(squad.id)].duplicate(); squad.initial_facing_deg = 0
	var battle = Battle.new(); _ok(battle.initialize(setup).ok, "battle initializes")
	var view := View.new(); view.configure(battle, 0, JSON.stringify(setup)); root.add_child(view); await _settle()
	var initial_stage: Button = view.find_child("StageChainExplosion", true, false); _ok(initial_stage != null and initial_stage.disabled, "operation cannot stage before confirmed readiness")
	var condition_rows := view.find_children("ChainCondition_*", "Label", true, false); _eq(condition_rows.size(), 6, "six core readiness conditions render")
	view._clear(view._orders); view._viewer_faction_id = "cao_cao"; view._add_chain_explosion_panel(); _ok(view.find_child("ChainExplosionHidden", true, false) != null and view.find_child("ChainCondition_legal_detection", true, false) == null, "Cao sees no pre-trigger conditions")
	view._viewer_faction_id = "liu_bei"; view._refresh(); await _settle()
	# Turn 1 establishes viewer-safe confirmed contact without moving the allied detachment.
	view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await _settle(); view.find_child("SunManualThisTurn", true, false).pressed.emit(); await _settle(); view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await _settle(); view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await _settle()
	_eq(battle.phase(), "liu_command", "turn 2 Liu command opens")
	var readiness: Dictionary = battle.chain_explosion_readiness(); _ok(readiness.ok and readiness.ready, "fixture reaches all core readiness conditions")
	var readiness_json := JSON.stringify(readiness); _ok(not readiness.has("target_squadron_id") and not readiness_json.contains("formation_id"), "public readiness keeps target identity and enemy formation redacted")
	view._refresh(); await _settle(); var stage: Button = view.find_child("StageChainExplosion", true, false); _ok(stage != null and not stage.disabled, "ready operation stage CTA enabled")
	stage.pressed.emit(); await _settle(); var staged_state: Dictionary = battle.viewer_chain_explosion_state("liu_bei"); _eq(staged_state.status, "staged", "stage CTA stores operation"); _ok(not JSON.stringify(staged_state).contains("target_squadron_id"), "Liu staged viewer state keeps opaque contact only")
	var cancel: Button = view.find_child("CancelChainExplosion", true, false); _ok(cancel != null and not cancel.disabled, "staged operation can cancel before resolve"); cancel.pressed.emit(); await _settle(); _eq(battle.viewer_chain_explosion_state("liu_bei").status, "idle", "cancel returns to idle without combat mutation")
	view.find_child("StageChainExplosion", true, false).pressed.emit(); await _settle(); view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await _settle(); view.find_child("SunManualThisTurn", true, false).pressed.emit(); await _settle(); view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await _settle()
	var state: Dictionary = battle.viewer_chain_explosion_state("liu_bei"); _eq(state.status, "triggered", "all final conditions trigger probability-free operation")
	_ok(state.irreversible and state.get("effect_intents", []).size() == 4 and not state.get("effects_pending", []).is_empty(), "trigger exposes immutable pending intents")
	var status: Label = view.find_child("ChainExplosionStatus", true, false); var pending: Label = view.find_child("ChainExplosionEffectsPending", true, false); var locked: Button = view.find_child("ChainExplosionLocked", true, false)
	_ok(status != null and locked != null and status.text.contains("확률 판정 없음") and status.text.contains("취소 불가") and locked.disabled, "triggered state is explicitly irreversible")
	_ok(pending != null and pending.text.contains("후속 효과 판정 대기") and pending.text.contains("일반 승리 판정 대기"), "damage and victory remain pending")
	var before := JSON.stringify(state); view._on_cancel_chain_explosion(); _eq(JSON.stringify(battle.viewer_chain_explosion_state("liu_bei")), before, "post-trigger cancel cannot mutate state")
	view._clear(view._orders); view._viewer_faction_id = "cao_cao"; view._add_chain_explosion_panel(); var cao_status: Label = view.find_child("ChainExplosionStatus", true, false); _ok(view.find_child("ChainExplosionHidden", true, false) == null and cao_status != null and cao_status.text.contains("발동 확정"), "Cao learns own triggered impact only after trigger")
	var cao_json := JSON.stringify(battle.viewer_chain_explosion_state("cao_cao")); _ok(not cao_json.contains("staged_order") and not cao_json.contains("conditions"), "Cao state omits pre-trigger plan and conditions")
	if DisplayServer.get_name() != "headless":
		var panel_title: Label = view.find_child("ChainExplosionTitle", true, false); var scroll: ScrollContainer = view.find_child("MovementOrderScroll", true, false); scroll.scroll_vertical = maxi(0, int(panel_title.position.y) - 8); await process_frame
		var output_dir := "res://out/demo-rc-g5-06-chain-explosion"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)); var image := root.get_texture().get_image(); _ok(image != null and image.get_size() == Vector2i(1600,900), "1600x900 GPU capture available")
		if image != null: _ok(image.save_png(ProjectSettings.globalize_path(output_dir.path_join("chain-explosion-1600x900.png"))) == OK, "GPU capture saved")
	view.free()

func _test_disruption_and_retry_copy() -> void:
	var loaded := Setup.load_default(); var setup: Dictionary = loaded.setup.duplicate(true)
	var positions := {"RC-LIU-SQ-01":[700,49], "RC-LIU-SQ-02":[700,49], "RC-SUN-SQ-01":[550,100], "RC-CAO-SQ-01":[781,11]}
	for squad in setup.squadrons: squad.initial_position = positions[String(squad.id)].duplicate(); squad.initial_facing_deg = 0
	var battle = Battle.new(); _ok(battle.initialize(setup).ok, "disruption fixture initializes")
	# Turn 1 creates the legal confirmed contact. Turn 2 is left unstaged so the
	# following Cao policy cycle can exercise pre-trigger interference.
	_ok(battle.submit_command_draft().ok, "turn1 Liu draft submits"); _ok(battle.submit_sun_control_choice("manual", false).ok, "turn1 Sun manual selected"); _ok(battle.submit_command_draft().ok, "turn1 Sun draft submits"); _ok(battle.resolve_turn().ok, "turn1 resolves"); _ok(battle.continue_turn().ok, "turn2 starts")
	_ok(battle.submit_command_draft().ok, "turn2 Liu draft submits"); _ok(battle.submit_sun_control_choice("manual", false).ok, "turn2 Sun manual selected"); _ok(battle.submit_command_draft().ok, "turn2 Sun draft submits"); _ok(battle.resolve_turn().ok, "turn2 resolves"); _ok(battle.continue_turn().ok, "turn3 starts")
	var readiness: Dictionary = battle.chain_explosion_readiness(); _ok(readiness.get("ready", false), "turn3 operation is stageable before interference")
	if not readiness.get("ready", false): return
	_ok(battle.stage_chain_explosion(String(readiness.detachment_id), String(readiness.contact_id)).ok, "turn3 operation staged")
	_ok(battle.submit_command_draft().ok, "turn3 Liu draft submits"); _ok(battle.submit_sun_control_choice("manual", false).ok, "turn3 Sun manual selected")
	_ok(battle.set_order_move("RC-SUN-SQ-01", [[650,100]], 0).ok, "allied payload host movement uses core order")
	_ok(battle.submit_command_draft().ok, "turn3 Sun moving draft submits"); _ok(battle.resolve_turn().ok, "turn3 resolves staged operation")
	var state: Dictionary = battle.viewer_chain_explosion_state("liu_bei")
	_ok(state.status == "disrupted", "pre-trigger interception or changed conditions disrupts staged operation")
	if state.status != "disrupted": print("  disruption debug ", state, " events ", battle.visible_tactical_events("liu_bei"))
	var view := View.new(); view.configure(battle, 0, JSON.stringify(setup)); root.add_child(view); await _settle()
	var event_label: Label = view.find_child("ChainExplosionDisruptedEvent", true, false); var status_label: Label = view.find_child("ChainExplosionStatus", true, false)
	_ok(event_label != null and event_label.text.contains("재시도 가능"), "disruption receipt is visible in turn log")
	_ok(status_label != null and status_label.text.contains("조건 재확보"), "disrupted state explains recovery boundary")
	_ok(not bool(state.get("can_stage", true)), "same resolved turn cannot immediately retry")
	_ok(battle.continue_turn().ok, "next Liu command turn starts after disruption")
	_ok(bool(battle.viewer_chain_explosion_state("liu_bei").get("can_stage", false)), "retry becomes available next Liu command turn")
	view.free()

func _settle() -> void:
	await process_frame
	await process_frame

func _test_source_boundary() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd")
	_ok("Node3D" not in source and ".glb" not in source and "voyage_3d" not in source, "chain operation UI has zero 3D refs")
	for forbidden in ["maximum_deviation_deg", "dense_formation_ids", "probability_roll_used"]: _ok(forbidden not in source, "UI does not duplicate operation rule %s" % forbidden)
