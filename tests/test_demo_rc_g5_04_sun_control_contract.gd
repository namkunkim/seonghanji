extends SceneTree

## Task ID / 공식·새 작업 제목: DEMO-RC-G5-04 — 손권 제어 문의 계약 재검증
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")
var _pass := 0; var _fail := 0
func _ok(value: bool, label: String) -> void:
	if value: _pass += 1
	else: _fail += 1; print("  x %s" % label)
func _eq(actual, expected, label: String) -> void: _ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])
func _init() -> void: call_deferred("_run")

func _run() -> void:
	print("DEMO-RC-G5-04 Sun control prompt contract")
	_test_prompt_manual_ai_skip_reenable_sequence()
	_test_invalid_atomic_deep_copy_save_and_determinism()
	_test_twenty_turn_boundary_with_saved_ai_policy()
	print("PASS %d / FAIL %d" % [_pass, _fail]); quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)

func _fixture() -> Dictionary:
	var loaded := Setup.load_default(); _ok(loaded.ok, "setup loads"); var setup: Dictionary = loaded.setup.duplicate(true)
	var positions := {"RC-LIU-SQ-01": [100, 100], "RC-LIU-SQ-02": [100, 100], "RC-SUN-SQ-01": [100, 100], "RC-CAO-SQ-01": [300, 100]}
	for squad in setup.squadrons: squad.initial_position = positions[String(squad.id)].duplicate(); squad.initial_facing_deg = 0
	return setup

func _battle(setup: Dictionary):
	var battle = Battle.new(); var initialized: Dictionary = battle.initialize(setup); _ok(initialized.ok, "battle initializes: %s" % str(initialized.get("errors", []))); return battle

func _test_prompt_manual_ai_skip_reenable_sequence() -> void:
	var battle = _battle(_fixture()); _eq(battle.phase(), "liu_command", "turn1 starts at Liu command")
	_ok(battle.submit_command_draft().ok, "turn1 Liu submits"); _eq(battle.phase(), "sun_control_prompt", "every enabled turn prompts after Liu")
	var prompt_digest := battle.digest(); _ok(not battle.set_sun_prompt_enabled(false).ok, "active prompt cannot be bypassed from settings"); _eq(battle.digest(), prompt_digest, "prompt bypass rejection atomic")
	_ok(battle.submit_sun_control_choice("yes").ok, "yes selects manual this turn"); _eq(battle.phase(), "sun_command", "manual enters Sun command")
	_ok(battle.set_order_hold("RC-SUN-SQ-01").ok, "manual Sun uses movement API")
	_ok(battle.set_formation_order("RC-SUN-SQ-01", "FRM-03").ok, "manual Sun uses formation API")
	_ok(battle.apply_weapon_preset("RC-SUN-SQ-01", "balanced").ok, "manual Sun uses weapon API")
	var draft_before_policy := battle.command_draft(); _ok(battle.set_sun_prompt_enabled(false).ok, "manual draft can set next-turn policy")
	_eq(battle.phase(), "sun_command", "next-turn policy does not change current manual phase"); _eq(battle.command_draft(), draft_before_policy, "policy change preserves current manual draft")
	_ok(battle.set_sun_prompt_enabled(true).ok, "manual draft can restore next-turn prompt")
	_ok(battle.submit_command_draft().ok, "manual Sun submits"); _eq(battle.phase(), "resolution", "manual Sun submission reaches resolution")
	var first: Dictionary = battle.resolve_turn(); _ok(first.ok, "turn1 full G5-03 stack resolves")
	_eq(battle.turn_log()[0].sun_control_decision.control, "manual", "manual choice recorded only for turn")
	battle.continue_turn(); battle.submit_command_draft(); _eq(battle.phase(), "sun_control_prompt", "manual choice does not suppress next turn prompt")
	_ok(battle.submit_sun_control_choice("yes").ok, "turn2 manual selected")
	var fresh_sun: Dictionary = battle.command_draft(); _eq(fresh_sun.estimated_fire_orders, {}, "fresh Sun draft has no stale estimated order")
	_eq(fresh_sun.orders["RC-SUN-SQ-01"].action, "hold", "fresh Sun draft defaults HOLD")
	_eq(fresh_sun.formation_orders["RC-SUN-SQ-01"].formation_id, "FRM-03", "fresh Sun draft carries current formation")
	_eq(fresh_sun.weapon_allocation_orders["RC-SUN-SQ-01"].allocations, battle.weapon_allocation_state()["RC-SUN-SQ-01"].allocations, "fresh Sun draft carries current weapon allocation")
	_eq(fresh_sun.weapon_allocation_orders["RC-SUN-SQ-01"].hold_fire, battle.weapon_allocation_state()["RC-SUN-SQ-01"].hold_fire, "fresh Sun draft carries current hold-fire policy")
	_eq(battle.turn_log()[1].liu_orders[0].action, "hold", "Sun draft is isolated from submitted Liu orders")
	var isolated := fresh_sun.duplicate(true); isolated.orders.clear(); _ok(not battle.command_draft().orders.is_empty(), "draft query deep-copy isolated")
	var contacts: Array = battle.visible_contacts("sun_quan").contacts; var estimated := contacts.filter(func(row): return String(row.get("state", "")) == "estimated")
	_ok(not estimated.is_empty(), "Sun has eligible estimated contact")
	_ok(battle.set_estimated_fire("RC-SUN-SQ-01", String(estimated[0].contact_id)).ok, "manual Sun uses same estimated-fire API")
	_ok(battle.submit_command_draft().ok, "turn2 Sun draft submits")
	var second: Dictionary = battle.resolve_turn(); _ok(second.ok, "manual estimated fire resolves through terrain/resource rules")
	_ok(second.estimated_fire_events.size() + second.estimated_fire_suppressed_events.size() >= 1, "manual Sun gets explicit estimated-fire receipt")
	_ok(JSON.stringify(battle.visible_tactical_events("sun_quan", 2)).contains("estimated_fire_"), "Sun viewer sees own estimated fire")
	_ok(not JSON.stringify(battle.visible_tactical_events("cao_cao", 2)).contains("estimated_fire_"), "Cao viewer cannot inspect enemy estimated fire")

	battle.continue_turn(); battle.submit_command_draft(); _ok(battle.submit_sun_control_choice("no").ok, "no selects AI for current turn")
	_eq(battle.phase(), "resolution", "no goes directly to resolution"); _eq(battle.turn_log()[2].sun_orders[0].action, "hold", "Sun AI deterministic HOLD")
	_eq(battle.turn_log()[2].sun_control_decision.source, "turn_prompt", "one-turn AI remains a prompt decision")
	_ok(battle.prompt_policy().enabled, "one-turn AI no leaves prompt policy enabled")
	battle.resolve_turn(); battle.continue_turn(); battle.submit_command_draft()
	_eq(battle.phase(), "sun_control_prompt", "plain no asks again next turn")
	_ok(battle.submit_sun_control_choice("no", true).ok, "do-not-ask selects current battle AI default")
	_ok(not battle.prompt_policy().enabled, "saved prompt policy disabled")
	battle.resolve_turn(); battle.continue_turn(); battle.submit_command_draft()
	_eq(battle.phase(), "resolution", "disabled prompt skips next turn")
	_eq(battle.turn_log()[4].sun_control_decision.source, "saved_policy", "skip records saved-policy AI source")
	battle.resolve_turn(); _ok(battle.set_sun_prompt_enabled(true).ok, "settings re-enable after resolution")
	_ok(battle.continue_turn().ok and battle.submit_command_draft().ok, "next turn Liu submits after re-enable")
	_eq(battle.phase(), "sun_control_prompt", "re-enabled setting prompts on next turn")

func _test_invalid_atomic_deep_copy_save_and_determinism() -> void:
	var setup := _fixture(); var battle = _battle(setup); var digest := battle.digest()
	_ok(battle.set_sun_prompt_enabled(false).ok, "settings can schedule next-turn disable during Liu draft")
	_eq(battle.phase(), "liu_command", "scheduled policy does not redirect current Liu draft")
	_ok(battle.submit_command_draft().ok, "current turn Liu draft still submits")
	_eq(battle.phase(), "sun_control_prompt", "scheduled disable cannot skip current turn prompt")
	_ok(battle.submit_sun_control_choice("no").ok and battle.resolve_turn().ok and battle.continue_turn().ok, "scheduled policy reaches next turn")
	_ok(battle.submit_command_draft().ok and battle.phase() == "resolution", "scheduled disable applies on next turn only")
	battle = _battle(setup); digest = battle.digest()
	_ok(not battle.submit_sun_control_choice("yes").ok, "Sun choice rejected in Liu phase"); _eq(battle.digest(), digest, "wrong-phase choice atomic")
	battle.submit_command_draft(); digest = battle.digest(); _ok(not battle.submit_command_draft().ok, "duplicate Liu submit rejected while prompt active"); _eq(battle.digest(), digest, "duplicate submit idempotent")
	_ok(not battle.submit_sun_control_choice("unknown").ok, "unknown prompt answer rejected"); _eq(battle.digest(), digest, "invalid answer atomic")
	_ok(not battle.submit_sun_control_choice("yes", true).ok, "manual plus do-not-ask rejected"); _eq(battle.digest(), digest, "invalid combined choice atomic")
	var policy := battle.prompt_policy(); policy.enabled = false; _ok(battle.prompt_policy().enabled, "prompt policy query deep copy")
	var saved := battle.snapshot(); var encoded := JSON.stringify(saved); _ok(not encoded.is_empty() and encoded.contains("sun_prompt_policy"), "save-oriented snapshot is JSON primitive")
	saved.sun_prompt_policy.enabled = false; saved.turn_log.clear(); _ok(battle.prompt_policy().enabled and battle.turn_log().size() == 1, "snapshot deep copy protects live state")
	var viewer: Dictionary = battle.viewer_snapshot("liu_bei")
	_ok(not viewer.has("command_draft") and not viewer.has("applied_setup") and not viewer.has("live_navigation") and not viewer.has("sun_prompt_policy"), "viewer snapshot excludes raw authoritative state and prompt internals")
	var viewer_log: Dictionary = battle.viewer_turn_log("liu_bei")
	_ok(not JSON.stringify(viewer_log).contains("sun_orders") and not JSON.stringify(viewer_log).contains("cao_orders"), "viewer turn log excludes other factions' raw drafts and orders")
	var a = _battle(setup); var b = _battle(setup)
	for candidate in [a, b]: candidate.submit_command_draft(); candidate.submit_sun_control_choice("no"); candidate.resolve_turn()
	_eq(a.digest(), b.digest(), "same AI choice and inputs produce deterministic battle state")
	_eq(JSON.stringify(a.turn_log()[0].resolution_receipt), JSON.stringify(b.turn_log()[0].resolution_receipt), "AI detection terrain resource receipt byte-stable")
	_ok(not encoded.contains("Node3D") and not encoded.contains(".glb"), "save state has no 3D dependency")

func _test_twenty_turn_boundary_with_saved_ai_policy() -> void:
	var battle = _battle(_fixture())
	for turn_number in range(1, 21):
		_ok(battle.submit_command_draft().ok, "turn %d Liu submit" % turn_number)
		if turn_number == 1: _ok(battle.submit_sun_control_choice("no", true).ok, "turn1 saves AI default")
		else: _eq(battle.phase(), "resolution", "turn %d skips prompt" % turn_number)
		var receipt: Dictionary = battle.resolve_turn(); _ok(receipt.ok, "turn %d resolves" % turn_number)
		_ok(not receipt.has("hit") and not receipt.has("damage") and not receipt.has("winner"), "turn %d invents no result" % turn_number)
		if turn_number < 20: _ok(battle.continue_turn().ok, "turn %d continues" % turn_number)
	_eq(battle.phase(), "turn_limit_reached", "turn20 reaches explicit limit")
	var final_digest := battle.digest(); _ok(not battle.resolve_turn().ok and not battle.continue_turn().ok, "turn20 cannot resolve or continue twice")
	_eq(battle.digest(), final_digest, "turn-limit retries are idempotent")
