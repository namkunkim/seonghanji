extends SceneTree

## Task ID / 공식·새 작업 제목: DEMO-RC-G4-04 — 진형과 정면·측면·후면 보정
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Formation := preload("res://core/demo_red_cliffs/red_cliffs_formation_resolver.gd")
const Interception := preload("res://core/demo_red_cliffs/red_cliffs_interception_resolver.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")

var _pass := 0
var _fail := 0


func _ok(value: bool, label: String) -> void:
	if value: _pass += 1
	else: _fail += 1; print("  x %s" % label)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])


func _init() -> void: call_deferred("_run")


func _run() -> void:
	print("DEMO-RC-G4-04 formation sector core")
	_test_rules_state_and_sector_boundaries()
	_test_atomic_orders_and_deep_copy()
	_test_battle_timing_persistence_ai_and_redaction()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)


func _fixture() -> Dictionary:
	var loaded := Setup.load_default(); _ok(loaded.ok, "setup loads")
	var setup: Dictionary = loaded.setup.duplicate(true)
	var positions := {"RC-LIU-SQ-01": [100, 100], "RC-LIU-SQ-02": [100, 800],
		"RC-SUN-SQ-01": [100, 700], "RC-CAO-SQ-01": [400, 100]}
	for squad in setup.squadrons:
		squad.initial_position = positions[String(squad.id)].duplicate()
		if squad.id == "RC-LIU-SQ-01": squad.initial_facing_deg = 0
		if squad.id == "RC-CAO-SQ-01": squad.initial_facing_deg = 180
	return setup


func _resolver(setup: Dictionary):
	var resolver = Formation.new(); var initialized: Dictionary = resolver.initialize(setup)
	_ok(initialized.ok, "formation resolver initializes: %s" % str(initialized.get("errors", [])))
	return resolver


func _test_rules_state_and_sector_boundaries() -> void:
	var resolver = _resolver(_fixture()); var rules: Dictionary = resolver.rules_snapshot()
	_eq(rules.get("profile_id", ""), "normal-demo-formation-v1", "explicit balance profile")
	_eq(resolver.allowed_formations().size(), 7, "FRM-01~07 have one canonical modifier table")
	var initial: Dictionary = resolver.initial_state(); _eq(initial.size(), 4, "all operational formations initialized from G3")
	_eq(initial["RC-LIU-SQ-01"].formation_id, "FRM-01", "G3 applied formation is authority input")
	var front0: Dictionary = resolver.classify_sector([10, 0], [0, 0], 0)
	_eq(front0.sector, "front", "0 degree is front")
	_eq(resolver.classify_sector([10, 0], [0, 0], 359.999).sector, "front", "360 wrap is front")
	var rad60 := deg_to_rad(60.0); var rad120 := deg_to_rad(120.0)
	_eq(resolver.classify_sector([cos(rad60) * 10.0, sin(rad60) * 10.0], [0, 0], 0).sector, "front", "front boundary inclusive")
	_eq(resolver.classify_sector([cos(deg_to_rad(60.0005)) * 10.0, sin(deg_to_rad(60.0005)) * 10.0], [0, 0], 0).sector, "flank", "any value above front boundary is flank")
	_eq(resolver.classify_sector([cos(deg_to_rad(60.01)) * 10.0, sin(deg_to_rad(60.01)) * 10.0], [0, 0], 0).sector, "flank", "above front boundary is flank")
	_eq(resolver.classify_sector([cos(rad120) * 10.0, sin(rad120) * 10.0], [0, 0], 0).sector, "rear", "rear boundary inclusive")
	_eq(resolver.classify_sector([cos(deg_to_rad(119.9995)) * 10.0, sin(deg_to_rad(119.9995)) * 10.0], [0, 0], 0).sector, "flank", "any value below rear boundary is flank")
	_eq(resolver.classify_sector([0, 0], [0, 0], 42).sector, "indeterminate", "same position is indeterminate")
	_eq(resolver.classify_sector([0, 0], [0, 0], 42).sector_defense_percent, 0, "same-position modifier is neutral")
	_ok(not resolver.classify_sector([1, 0], [0, 0], 360).ok, "360 exact facing rejected by live facing contract")


func _test_atomic_orders_and_deep_copy() -> void:
	var resolver = _resolver(_fixture()); var state: Dictionary = resolver.initial_state(); var digest := JSON.stringify(state)
	var orders: Array = []
	for squadron_id in state.keys(): orders.append({"squadron_id": squadron_id, "formation_id": String(state[squadron_id].formation_id)})
	orders[0].formation_id = "FRM-07"
	var result: Dictionary = resolver.resolve_orders(orders, state, 1); _ok(result.ok, "complete formation orders resolve")
	_eq(JSON.stringify(result), JSON.stringify(resolver.resolve_orders(orders, state, 1)), "same formation inputs are deterministic")
	_eq(JSON.stringify(state), digest, "resolver deep-copies caller state")
	_eq(result.formation_state[String(orders[0].squadron_id)].formation_id, "FRM-07", "valid formation applies")
	_eq(result.formation_events.size(), 4, "every squad formation order is recorded")
	_eq(result.formation_events[0].application_timing, "submitted_with_command_draft; applied_atomically_at_resolution_start_before_movement_detection_and_fire; persists_until_changed", "application timing explicit")
	var invalid: Array = orders.duplicate(true); invalid[0].formation_id = "FRM-99"
	_ok(not resolver.resolve_orders(invalid, state, 1).ok, "unknown formation rejected")
	_eq(JSON.stringify(state), digest, "invalid formation application is atomic")
	invalid = orders.duplicate(true); invalid.pop_back()
	_ok(not resolver.resolve_orders(invalid, state, 1).ok, "missing squadron formation rejected")
	var duplicate: Array = orders.duplicate(true); duplicate[1] = duplicate[0].duplicate(true)
	_ok(not resolver.resolve_orders(duplicate, state, 1).ok, "duplicate squadron formation rejected")
	_ok(not resolver.validate_order("UNKNOWN", "FRM-01").ok, "unknown squadron rejected")


func _test_battle_timing_persistence_ai_and_redaction() -> void:
	var setup := _fixture(); var battle = Battle.new(); var initialized: Dictionary = battle.initialize(setup)
	_ok(initialized.ok, "battle initializes: %s" % str(initialized.get("errors", [])))
	var before := battle.digest()
	_ok(not battle.set_formation_order("RC-LIU-SQ-01", "FRM-99").ok, "invalid draft formation rejected")
	_eq(battle.digest(), before, "invalid draft mutation is atomic")
	_ok(battle.set_formation_order("RC-LIU-SQ-01", "FRM-07").ok, "Liu formation staged")
	_eq(battle.formation_state()["RC-LIU-SQ-01"].formation_id, "FRM-01", "draft does not alter live formation")
	_ok(battle.set_order_move("RC-LIU-SQ-01", [[240, 100]], 0).ok, "move and formation can be staged together")
	_ok(not battle.set_formation_order("RC-CAO-SQ-01", "FRM-07").ok, "other faction formation edit rejected")
	_ok(battle.submit_command_draft().ok, "Liu combined draft submits")
	_ok(battle.submit_sun_control_choice("ai").ok, "AI Sun parity path")
	var receipt: Dictionary = battle.resolve_turn(); _ok(receipt.ok, "turn resolves with formation first")
	_ok(not receipt.rules_pending.has("formation_change"), "implemented formation change removed from pending")
	_eq(battle.formation_state()["RC-LIU-SQ-01"].formation_id, "FRM-07", "formation applied at resolve start")
	_eq(receipt.formation_modifier_snapshots["RC-LIU-SQ-01"].modifiers.fire_percent, 10, "same-turn modifier snapshot uses new formation")
	var fire := _fire(receipt.opportunity_fire_events, "RC-CAO-SQ-01", "RC-LIU-SQ-01")
	_ok(not fire.is_empty() and fire.formation_modifier is Dictionary, "shot_authorized alone receives formation evaluation")
	_eq(fire.formation_modifier.target.formation_id, "FRM-07", "same-turn shot uses newly applied target formation")
	_ok(not fire.has("hit") and not fire.has("damage") and not fire.has("ammo") and not fire.has("heat") and not fire.has("winner"), "no G4-05/06 result fabricated")
	var target_view: Dictionary = battle.visible_tactical_events("liu_bei")
	var visible_fire: Dictionary = target_view.events.filter(func(row): return row.get("event_type") == "shot_authorized")[0]
	_eq(visible_fire.formation_modifier.own_formation_id, "FRM-07", "target sees own formation modifier")
	_eq(battle.viewer_snapshot("liu_bei").own_squadrons[0].formation_id, "FRM-07", "own squadron summary uses live formation")
	_ok(not JSON.stringify(visible_fire).contains("FRM-04"), "target cannot see hostile shooter formation")
	_ok(not visible_fire.has("bearing_deg") and not visible_fire.has("facing_deg"), "target cannot see hostile shooter geometry")
	var asymmetric_detection: Dictionary = battle.detection_state()
	for key in asymmetric_detection:
		var contact: Dictionary = asymmetric_detection[key]
		if String(contact.target_squadron_id) == "RC-CAO-SQ-01": contact.state = "estimated"
	var redactor = Interception.new(); _ok(redactor.initialize(setup).ok, "redactor initializes for asymmetric contact boundary")
	var estimated_target_events: Array = redactor.visible_tactical_events("liu_bei", receipt, asymmetric_detection).events
	var estimated_target_fire: Dictionary = estimated_target_events.filter(func(row): return row.get("event_type") == "shot_authorized")[0]
	_ok(not estimated_target_fire.has("formation_modifier"), "estimated target contact leaks no exact sector or modifier")
	var unknown_setup := _fixture(); unknown_setup.squadrons.filter(func(s): return s.id == "RC-CAO-SQ-01")[0].initial_position = [1000, 100]
	var unknown_battle = Battle.new(); _ok(unknown_battle.initialize(unknown_setup).ok, "unknown-contact battle initializes")
	var unknown_view: Dictionary = unknown_battle.viewer_snapshot("liu_bei")
	_ok(not unknown_view.own_formation_state.has("RC-CAO-SQ-01") and unknown_view.contacts.is_empty(), "unknown contact leaks no enemy formation or identity")
	var estimated_setup := _fixture(); estimated_setup.squadrons.filter(func(s): return s.id == "RC-CAO-SQ-01")[0].initial_position = [350, 100]
	var estimated_battle = Battle.new(); _ok(estimated_battle.initialize(estimated_setup).ok, "estimated-contact battle initializes")
	_ok(estimated_battle.submit_command_draft().ok and estimated_battle.submit_sun_control_choice("ai").ok, "estimated fixture orders submit")
	_ok(estimated_battle.resolve_turn().ok, "estimated fixture resolves")
	var estimated_json := JSON.stringify(estimated_battle.viewer_snapshot("liu_bei"))
	_ok(not estimated_json.contains("RC-CAO-SQ-01"), "estimated contact leaks no enemy identity")
	_ok(battle.continue_turn().ok, "next turn begins")
	_eq(battle.formation_order("RC-LIU-SQ-01").order.formation_id, "FRM-07", "formation persists into next command draft")
	_ok(battle.submit_command_draft().ok and battle.submit_sun_control_choice("manual").ok, "manual Sun path begins")
	_ok(battle.set_formation_order("RC-SUN-SQ-01", "FRM-05").ok, "manual Sun uses same formation API")
	_ok(battle.submit_command_draft().ok, "manual Sun draft submits")
	var second: Dictionary = battle.resolve_turn(); _ok(second.ok, "manual Sun turn resolves")
	_eq(battle.formation_state()["RC-SUN-SQ-01"].formation_id, "FRM-05", "manual Sun formation applies with parity")
	_eq(second.formation_events.size(), 4, "AI/manual formations share complete resolver")


func _fire(events: Array, shooter_id: String, target_id: String) -> Dictionary:
	for event in events:
		if String(event.shooter_squadron_id) == shooter_id and String(event.target_squadron_id) == target_id: return event
	return {}
