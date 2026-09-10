extends SceneTree

## Task ID / 공식·새 작업 제목: DEMO-RC-G4-07 — 턴 전투 5단계 판정 원장
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Ledger := preload("res://core/demo_red_cliffs/red_cliffs_phase_ledger.gd")
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
	print("DEMO-RC-G4-07 five phase ledger core")
	_test_phase_order_mapping_digest_and_deep_copy()
	_test_invalid_unknown_duplicate_wrong_turn_atomicity()
	_test_battle_replay_viewer_redaction_and_control_parity()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)


func _ledger():
	var resolver = Ledger.new(); var initialized: Dictionary = resolver.initialize()
	_ok(initialized.ok, "ledger initializes: %s" % str(initialized.get("errors", []))); return resolver


func _receipt() -> Dictionary:
	return {"turn": 1, "rules_pending": ["weapon_fire", "damage", "casualties", "victory"],
		"formation_events": [{"event_type": "formation_applied", "turn": 1, "squadron_id": "SQ-A"}],
		"weapon_allocation_events": [{"event_type": "weapon_allocation_applied", "turn": 1, "squadron_id": "SQ-A"}],
		"resource_recovery_events": [],
		"movement_events": [{"squadron_id": "SQ-A", "action": "hold"}],
		"path_intersection_events": [],
		"detection_events": [{"event_id": "DET-1", "turn": 1}],
		"opportunity_fire_events": [{"event_id": "FIRE-1", "turn": 1, "outcome": "shot_authorized"}],
		"resource_consumption_events": [{"event_type": "resource_consumed", "event_id": "RES-1", "turn": 1, "squadron_id": "SQ-A"}],
		"suppressed_fire_events": [], "victory_check_required": true}


func _test_phase_order_mapping_digest_and_deep_copy() -> void:
	var resolver = _ledger(); var receipt := _receipt(); var digest := JSON.stringify(receipt)
	var first: Dictionary = resolver.build(1, receipt); _ok(first.ok, "ledger builds")
	_eq(first.phase_order, ["contact", "barrage", "engagement", "assault", "resolution"], "five phase IDs exact")
	var names: Array = []; for phase in first.phases: names.append(String(phase.phase_name))
	_eq(names, ["접적", "포화", "교전", "강습", "결착"], "five Korean phase names exact")
	_eq(first.phases.size(), 5, "all five phases always present")
	_eq(first.phases[0].events.size(), 4, "contact maps apply meta movement and detection")
	_eq(first.phases[1].events.size(), 2, "barrage maps authorization and resource consumption")
	_eq(first.phases[2].status, "pending", "engagement empty pending explicit")
	_eq(first.phases[3].status, "pending", "assault empty pending explicit")
	_eq(first.phases[4].events[0].event_type, "resolution_boundary", "resolution records victory-check boundary")
	_ok(first.phases[4].events[0].payload.victory_check_required, "resolution boundary requires later victory check")
	_ok(not first.result_contract.has("winner"), "no winner result created")
	_ok(not String(first.turn_digest).is_empty(), "turn digest exists")
	_eq(first.turn_digest, resolver.build(1, receipt).turn_digest, "same input replay digest stable")
	_eq(JSON.stringify(first), JSON.stringify(resolver.build(1, receipt)), "ledger replay byte-stable")
	_eq(JSON.stringify(receipt), digest, "mapper deep-copies input")
	var leaked := first.duplicate(true); leaked.phases[0].events.clear()
	_eq(resolver.build(1, receipt).phases[0].events.size(), 4, "returned ledger mutation cannot affect replay")
	var summary: Dictionary = resolver.summary(first); _ok(summary.ok and summary.phases.size() == 5, "summary API returns all phases")
	_eq(resolver.phase(first, "barrage").phase.phase_name, "포화", "single phase query works")
	_ok(not resolver.phase(first, "unknown").ok, "unknown phase query rejected")
	var ids := {}
	for phase in first.phases:
		for event in phase.events: ids[String(event.ledger_event_id)] = true
	_eq(ids.size(), 7, "ledger event IDs unique")


func _test_invalid_unknown_duplicate_wrong_turn_atomicity() -> void:
	var resolver = _ledger(); var receipt := _receipt(); var digest := JSON.stringify(receipt)
	var unknown := receipt.duplicate(true); unknown.formation_events[0].event_type = "invented_result"
	_ok(not resolver.build(1, unknown).ok, "unknown mapped event rejected")
	var duplicate := receipt.duplicate(true); duplicate.detection_events.append(duplicate.detection_events[0].duplicate(true))
	_ok(not resolver.build(1, duplicate).ok, "duplicate source event rejected")
	var wrong_turn := receipt.duplicate(true); wrong_turn.detection_events[0].turn = 2
	_ok(not resolver.build(1, wrong_turn).ok, "wrong-turn event rejected")
	var forbidden := receipt.duplicate(true); forbidden.detection_events[0]["nested"] = {"winner": "fake"}
	_ok(not resolver.build(1, forbidden).ok, "nested fabricated winner rejected")
	var malformed := receipt.duplicate(true); malformed.movement_events = {}
	_ok(not resolver.build(1, malformed).ok, "non-array source rejected")
	_eq(JSON.stringify(receipt), digest, "all invalid mapping attempts leave caller unchanged")


func _fixture(enemy_position: Array = [1200, 100]) -> Dictionary:
	var loaded := Setup.load_default(); _ok(loaded.ok, "battle setup loads")
	var setup: Dictionary = loaded.setup.duplicate(true)
	var positions := {"RC-LIU-SQ-01": [100, 100], "RC-LIU-SQ-02": [100, 800],
		"RC-SUN-SQ-01": [100, 700], "RC-CAO-SQ-01": enemy_position}
	for squad in setup.squadrons: squad.initial_position = positions[String(squad.id)].duplicate()
	return setup


func _resolve_ai(setup: Dictionary):
	var battle = Battle.new(); _ok(battle.initialize(setup).ok, "battle initializes")
	_ok(battle.submit_command_draft().ok, "Liu draft submits")
	_ok(battle.submit_sun_control_choice("ai").ok, "Sun AI path submits")
	var receipt: Dictionary = battle.resolve_turn(); _ok(receipt.ok, "battle resolves ledger")
	return battle


func _test_battle_replay_viewer_redaction_and_control_parity() -> void:
	var setup := _fixture(); var first = _resolve_ai(setup); var second = _resolve_ai(setup)
	var ledger: Dictionary = first.phase_ledger(1); _ok(ledger.ok and ledger.phases.size() == 5, "authoritative battle ledger available")
	_eq(ledger.turn_digest, second.phase_ledger(1).turn_digest, "independent battle replay digest identical")
	_ok(first.phase() == "victory_check", "external command phases remain outside internal ledger")
	var viewer: Dictionary = first.viewer_phase_ledger("liu_bei", 1); _ok(viewer.ok and viewer.viewer_redacted, "viewer ledger explicitly redacted")
	_eq(viewer.phases.size(), 5, "viewer always receives five phases")
	_eq(viewer.phases[2].status, "no_visible_events", "viewer hidden and empty events use same status")
	_ok(not JSON.stringify(viewer).contains("RC-CAO-SQ-01"), "unknown enemy ID absent recursively")
	_ok(not JSON.stringify(viewer).contains("authoritative_count") and not JSON.stringify(viewer).contains("hidden_count"), "viewer exposes no hidden event count")
	var viewer_summary: Dictionary = first.viewer_phase_summary("liu_bei", 1)
	_ok(viewer_summary.ok and viewer_summary.turn_digest == viewer.turn_digest, "viewer summary uses viewer ledger digest")
	_eq(first.viewer_phase("liu_bei", "contact", 1).phase.phase_name, "접적", "viewer single phase query")
	var returned := first.viewer_phase_ledger("liu_bei", 1); returned.phases.clear()
	_eq(first.viewer_phase_ledger("liu_bei", 1).phases.size(), 5, "viewer ledger API deep copies")
	_ok(not first.viewer_phase_ledger("unknown", 1).ok, "unknown viewer rejected")

	_ok(first.continue_turn().ok, "turn 2 starts")
	_ok(first.submit_command_draft().ok and first.submit_sun_control_choice("manual").ok, "manual Sun path begins")
	_ok(first.submit_command_draft().ok, "manual Sun draft submits")
	var manual_receipt: Dictionary = first.resolve_turn(); _ok(manual_receipt.ok, "manual Sun/AI Cao ledger resolves")
	_eq(manual_receipt.phase_ledger.phases.size(), 5, "manual/AI parity retains five phases")
	_ok(first.viewer_phase_ledger("sun_quan", 2).ok, "manual Sun viewer ledger available")

	var rollback_battle = Battle.new(); _ok(rollback_battle.initialize(setup).ok, "rollback fixture initializes")
	_ok(rollback_battle.submit_command_draft().ok and rollback_battle.submit_sun_control_choice("ai").ok, "rollback fixture reaches resolution")
	var before := rollback_battle.digest()
	rollback_battle._phase_ledger._rules.phases.contact.sources.append("movement_events")
	var rejected: Dictionary = rollback_battle.resolve_turn()
	_ok(not rejected.ok, "mapper duplicate failure rejects whole resolution")
	_eq(rollback_battle.digest(), before, "mapper failure rolls back all battle state")
