extends SceneTree

## DEMO-RC-G3-03R — 지휘 한도 초과 명중·진형 변경 불이익 실제 적용
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Draft := preload("res://core/demo_red_cliffs/red_cliffs_formation_draft.gd")
const Formation := preload("res://core/demo_red_cliffs/red_cliffs_formation_resolver.gd")
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
	print("DEMO-RC-G3-03R — 지휘 한도 초과 명중·진형 변경 불이익 실제 적용")
	_test_tier_boundaries_and_authority()
	_test_change_turn_effectiveness_and_recovery()
	_test_accuracy_snapshot_contract()
	_test_viewer_safe_public_metrics()
	_test_ai_actual_fire_pipeline_and_redaction()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)


func _overcap_setup(count: int) -> Dictionary:
	var loaded := Setup.load_default(); _ok(loaded.ok, "default setup loads")
	var setup: Dictionary = loaded.setup.duplicate(true)
	for faction in setup.factions:
		if String(faction.id) == "liu_bei": faction.inventory["SHP-08"] = 200
	var squad := _squad(setup, "RC-LIU-FC-01")
	squad.composition[0].count = count
	squad.declared_total_cost = count * 3
	squad.calculated_total_cost = count * 3
	return setup


func _resolver(setup: Dictionary):
	var resolver = Formation.new(); var initialized: Dictionary = resolver.initialize(setup)
	_ok(initialized.ok, "formation resolver initializes: %s" % str(initialized.get("errors", [])))
	return resolver


func _orders(state: Dictionary, changed_id: String = "", formation_id: String = "") -> Array:
	var result: Array = []
	for squadron_id in state.keys():
		result.append({"squadron_id": squadron_id,
			"formation_id": formation_id if String(squadron_id) == changed_id else String(state[squadron_id].formation_id)})
	return result


func _test_tier_boundaries_and_authority() -> void:
	var tier1_setup := _overcap_setup(75); var draft = Draft.new(tier1_setup)
	var tier1: Dictionary = draft.squadron_metrics("RC-LIU-FC-01")
	_eq(tier1.recommended_cost, 222, "commander authority keeps recommended cost 222")
	_eq(tier1.total_cost, 225, "tier-one boundary fixture cost")
	_eq(tier1.penalty_tier, 1, "first started 25-percent band is tier one")
	_eq(tier1.accuracy_percent, -4, "tier one accuracy is 96 percent")
	_eq(tier1.formation_change_percent, -8, "tier one change effectiveness is 92 percent")
	_eq(tier1.pending_penalties, [], "all three penalty consumers are active")
	_eq(tier1.penalty_application.accuracy_percent, "active_pre_resource_accuracy_snapshot", "accuracy consumer label is canonical")
	_eq(tier1.penalty_application.formation_change_percent, "active_resolution_start_modifier_effectiveness", "formation consumer label is canonical")
	var tier4: Dictionary = Draft.new(_overcap_setup(130)).squadron_metrics("RC-LIU-FC-01")
	_eq(tier4.penalty_tier, 4, "cost just beyond three full bands starts tier four")
	_eq(tier4.accuracy_percent, -16, "tier four accuracy is 84 percent")
	_eq(tier4.formation_change_percent, -32, "tier four change effectiveness is 68 percent")


func _test_change_turn_effectiveness_and_recovery() -> void:
	var resolver = _resolver(_overcap_setup(75)); var state: Dictionary = resolver.initial_state()
	var changed: Dictionary = resolver.resolve_orders(_orders(state, "RC-LIU-FC-01", "FRM-05"), state, 1)
	_ok(changed.ok, "tier-one formation change resolves")
	var event := _event(changed.formation_events, "RC-LIU-FC-01")
	_eq(event.command_penalty.modifier_effectiveness_basis_points, 9200, "tier one change turn uses 92 percent")
	var snapshot: Dictionary = changed.modifier_snapshots["RC-LIU-FC-01"]
	_eq(snapshot.base_modifiers, {"mobility_percent": 10, "detection_percent": -5, "fire_percent": 10, "defense_percent": -10}, "base modifier authority remains visible")
	_eq(snapshot.modifiers, {"mobility_percent": 9, "detection_percent": -4, "fire_percent": 9, "defense_percent": -9}, "positive and negative modifiers scale toward zero")
	var held: Dictionary = resolver.resolve_orders(_orders(changed.formation_state), changed.formation_state, 2)
	_ok(held.ok, "unchanged formation resolves next turn")
	_eq(held.modifier_snapshots["RC-LIU-FC-01"].modifier_effectiveness_basis_points, 10000, "maintained formation returns to full effect next turn")
	_eq(held.modifier_snapshots["RC-LIU-FC-01"].modifiers, snapshot.base_modifiers, "full modifier authority is restored")
	var tier4_resolver = _resolver(_overcap_setup(130)); var tier4_state: Dictionary = tier4_resolver.initial_state()
	var tier4: Dictionary = tier4_resolver.resolve_orders(_orders(tier4_state, "RC-LIU-FC-01", "FRM-05"), tier4_state, 1)
	_eq(tier4.modifier_snapshots["RC-LIU-FC-01"].modifier_effectiveness_basis_points, 6800, "tier four change turn uses 68 percent")
	_eq(tier4.modifier_snapshots["RC-LIU-FC-01"].modifiers, {"mobility_percent": 6, "detection_percent": -3, "fire_percent": 6, "defense_percent": -6}, "tier four never reverses or amplifies modifier direction")


func _test_accuracy_snapshot_contract() -> void:
	var resolver = _resolver(_overcap_setup(75))
	var actual := {"event_id": "B", "turn": 1, "outcome": "shot_authorized", "shooter_squadron_id": "RC-LIU-FC-01", "target_squadron_id": "RC-CAO-SQ-01"}
	var estimated := {"event_id": "A", "turn": 1, "outcome": "estimated_fire_authorized", "shooter_squadron_id": "RC-LIU-FC-01", "contact_id": "CONTACT-X"}
	var original := JSON.stringify([actual, estimated]); var result: Dictionary = resolver.apply_accuracy_penalty([actual, estimated], 1)
	_ok(result.ok, "actual and estimated authorized fire accept one shared accuracy consumer")
	_eq(result.eligible_events.size(), 2, "accuracy does not probabilistically suppress authorized fire")
	_eq(result.suppressed_events, [], "accuracy snapshot creates no suppression event")
	_eq(result.eligible_events[0].event_id, "A", "receipt ordering is deterministic")
	for event in result.eligible_events:
		_eq(event.command_penalty.accuracy_basis_points, 9600, "tier one accuracy snapshot is 96 percent")
		_eq(event.command_penalty.result_contract, "authorized_fire_accuracy_input_only; hit_and_damage_pending", "downstream-only contract is explicit")
		_ok(not event.has("hit") and not event.has("damage"), "accuracy consumer fabricates no hit or damage")
	_eq(JSON.stringify([actual, estimated]), original, "accuracy consumer deep-copies caller events")
	_eq(JSON.stringify(result), JSON.stringify(resolver.apply_accuracy_penalty([estimated, actual], 1)), "input order cannot change accuracy receipt")
	var tier4 := _resolver(_overcap_setup(130)).apply_accuracy_penalty([actual], 1)
	_eq(tier4.eligible_events[0].command_penalty.accuracy_basis_points, 8400, "tier four accuracy snapshot is 84 percent")
	_ok(not resolver.apply_accuracy_penalty(["invalid"], 1).ok, "malformed batch is rejected atomically")


func _test_viewer_safe_public_metrics() -> void:
	var battle = Battle.new(); var initialized: Dictionary = battle.initialize(_overcap_setup(75))
	_ok(initialized.ok, "battle initializes with valid over-cap setup")
	var own: Dictionary = battle.viewer_command_penalty_metrics("liu_bei", "RC-LIU-FC-01")
	_ok(own.ok and int(own.accuracy_percent) == -4, "viewer can query own exact penalty")
	_ok(not battle.viewer_command_penalty_metrics("cao_cao", "RC-LIU-FC-01").ok, "enemy cannot query shooter exact penalty")
	var own_copy := own.duplicate(true); own_copy.penalty_application.clear()
	_ok(not battle.viewer_command_penalty_metrics("liu_bei", "RC-LIU-FC-01").penalty_application.is_empty(), "viewer receipt is deep copied")


func _test_ai_actual_fire_pipeline_and_redaction() -> void:
	var setup := _overcap_setup(75)
	var positions := {"RC-LIU-SQ-01": [100, 100], "RC-LIU-SQ-02": [100, 800],
		"RC-LIU-FC-01": [1600, 900], "RC-SUN-SQ-01": [100, 700], "RC-CAO-SQ-01": [400, 100]}
	for squad in setup.squadrons:
		squad.initial_position = positions[String(squad.id)].duplicate()
		if String(squad.id) == "RC-CAO-SQ-01": squad.initial_facing_deg = 180
	var battle = Battle.new(); _ok(battle.initialize(setup).ok, "pipeline fixture initializes")
	_ok(battle.set_order_move("RC-LIU-SQ-01", [[240, 100]], 0).ok, "manual side stages interception move")
	_ok(battle.submit_command_draft().ok, "manual command draft submits")
	_ok(battle.submit_sun_control_choice("ai").ok, "allied AI path submits")
	var receipt: Dictionary = battle.resolve_turn(); _ok(receipt.ok, "AI and manual turn uses shared command-penalty pipeline")
	var raw := _fire(receipt.opportunity_fire_events, "RC-CAO-SQ-01", "RC-LIU-SQ-01")
	_ok(not raw.is_empty() and raw.command_penalty is Dictionary, "AI actual authorized fire carries accuracy snapshot")
	_eq(raw.command_penalty.accuracy_basis_points, 8800, "AI over-cap tier three uses 88 percent accuracy input")
	_ok(not raw.has("hit") and not raw.has("damage"), "integrated receipt still fabricates no hit or damage")
	var shooter_visible := _visible_fire(battle.visible_tactical_events("cao_cao").events, "RC-CAO-SQ-01")
	_ok(shooter_visible.get("command_penalty") is Dictionary, "shooter sees own exact accuracy snapshot")
	var target_visible := _visible_fire(battle.visible_tactical_events("liu_bei").events, "RC-LIU-SQ-01")
	_ok(not target_visible.has("command_penalty"), "target cannot see hostile accuracy penalty")


func _event(events: Array, squadron_id: String) -> Dictionary:
	for event in events:
		if String(event.get("squadron_id", "")) == squadron_id: return event
	return {}


func _fire(events: Array, shooter_id: String, target_id: String) -> Dictionary:
	for event in events:
		if String(event.get("shooter_squadron_id", "")) == shooter_id and String(event.get("target_squadron_id", "")) == target_id:
			return event
	return {}


func _visible_fire(events: Array, own_squadron_id: String) -> Dictionary:
	for event in events:
		if String(event.get("event_type", "")) == "shot_authorized" and String(event.get("own_squadron_id", "")) == own_squadron_id:
			return event
	return {}


func _squad(setup: Dictionary, squadron_id: String) -> Dictionary:
	for squad in setup.squadrons:
		if String(squad.id) == squadron_id: return squad
	return {}
