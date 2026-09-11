extends SceneTree

## Task ID / 공식·새 작업 제목: DEMO-RC-G5-01 — 전쟁 안개·마지막 확인·추정 사격
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Fog := preload("res://core/demo_red_cliffs/red_cliffs_fog_of_war.gd")
const Interception := preload("res://core/demo_red_cliffs/red_cliffs_interception_resolver.gd")
const Movement := preload("res://core/demo_red_cliffs/red_cliffs_movement_resolver.gd")
const Weapon := preload("res://core/demo_red_cliffs/red_cliffs_weapon_allocation.gd")
const Resources := preload("res://core/demo_red_cliffs/red_cliffs_combat_resources.gd")
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
	print("DEMO-RC-G5-01 fog and estimated fire core")
	_test_lifecycle_and_redaction()
	_test_estimated_fire_seal_determinism_and_resource_gate()
	_test_battle_command_ai_redaction_and_ledger()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)

func _fixture(cao_position: Array = [300, 100]) -> Dictionary:
	var loaded := Setup.load_default(); _ok(loaded.ok, "setup loads")
	var setup: Dictionary = loaded.setup.duplicate(true)
	var positions := {"RC-LIU-SQ-01": [100, 100], "RC-LIU-SQ-02": [100, 100],
		"RC-SUN-SQ-01": [100, 100], "RC-CAO-SQ-01": cao_position}
	for squad in setup.squadrons:
		squad.initial_position = positions[String(squad.id)].duplicate(); squad.initial_facing_deg = 0
	_ok(Setup.validate_document(setup).ok, "fixture valid")
	return setup

func _test_lifecycle_and_redaction() -> void:
	var setup := _fixture(); var fog = Fog.new(); _ok(fog.initialize(setup).ok, "fog initializes")
	var id1 := fog.contact_id("liu_bei", "RC-CAO-SQ-01")
	var row := {"state": "undetected", "last_known_position": null, "last_seen_turn": 0}
	row.merge(fog.initial_contact_fields())
	row = fog.transition(row, "estimated", [300.0, 100.0], 1)
	_eq(row.state, "estimated", "turn 1 estimate"); _eq(row.error_radius, 30, "base error radius")
	for turn_number in [2, 3]:
		row = fog.transition(row, "undetected", null, turn_number)
		_eq(row.state, "estimated", "age %d remains estimated" % (turn_number - 1))
		_eq(row.staleness_turns, turn_number - 1, "staleness increments")
	row = fog.transition(row, "undetected", null, 4)
	_eq(row.state, "lost", "age 3 is lost/stale"); _eq(row.last_known_position, [300.0, 100.0], "lost keeps only last-known")
	row = fog.transition(row, "undetected", null, 5)
	_eq(row.state, "undetected", "age >3 expires"); _eq(row.last_known_position, null, "expired clears last-known")
	row = fog.transition(row, "confirmed", [222.0, 111.0], 6)
	_eq(fog.contact_id("liu_bei", "RC-CAO-SQ-01"), id1, "reacquisition reuses opaque contact id")
	_eq(row.state, "confirmed", "reacquisition refreshes state")

	var interception = Interception.new(); var interception_init: Dictionary = interception.initialize(setup); _ok(interception_init.ok, "interception initializes: %s" % str(interception_init.get("errors", [])))
	var state := interception.initial_detection_state(); var movement = Movement.new(); _ok(movement.initialize(setup).ok, "movement initializes")
	var moved: Dictionary = movement.resolve_orders(_holds(setup), movement.initial_navigation())
	var resolved: Dictionary = interception.resolve(moved.events, moved.live_navigation, state, 1)
	_ok(resolved.ok, "estimated detection resolves")
	var contacts: Dictionary = interception.visible_contacts("liu_bei", resolved.detection_state, movement.initial_navigation())
	_ok(not contacts.contacts.is_empty(), "estimated contact visible")
	var encoded := JSON.stringify(contacts)
	_ok(not encoded.contains("target_squadron_id") and not encoded.contains("composition") and not encoded.contains("requested_waypoints"), "estimated contact leaks no target identity composition or orders")
	var expired_state: Dictionary = resolved.detection_state.duplicate(true)
	for key in expired_state:
		if String(expired_state[key].observer_squadron_id).begins_with("RC-LIU-"):
			expired_state[key].state = "undetected"; expired_state[key].last_known_position = null
	var raw_cross := {"path_intersection_events": [{"event_id": "PROX-EXPIRED", "turn": 5,
		"squadron_a_id": "RC-LIU-SQ-01", "squadron_b_id": "RC-CAO-SQ-01"}]}
	_eq(interception.visible_tactical_events("liu_bei", raw_cross, expired_state).events.size(), 0,
		"expired contact cannot reappear through tactical event redaction")
	for key in expired_state:
		if String(expired_state[key].observer_squadron_id).begins_with("RC-LIU-"):
			expired_state[key].state = "lost"; expired_state[key].last_known_position = [300.0, 100.0]
	_eq(interception.visible_tactical_events("liu_bei", raw_cross, expired_state).events.size(), 1,
		"age 3 lost contact remains viewer-visible until expiry")

func _test_estimated_fire_seal_determinism_and_resource_gate() -> void:
	var setup := _fixture(); var fog = Fog.new(); _ok(fog.initialize(setup).ok, "fog fire initializes")
	var contact := {"contact_id": fog.contact_id("liu_bei", "RC-CAO-SQ-01"), "state": "estimated",
		"last_known_position": [200.0, 100.0], "last_seen_turn": 1, "staleness_turns": 1,
		"confidence_basis_points": 4000, "error_radius": 55}
	var made: Dictionary = fog.make_order("liu_bei", "RC-LIU-SQ-02", contact, 2)
	_ok(made.ok, "estimated order seals from public contact")
	var lost_contact := contact.duplicate(true); lost_contact.state = "lost"
	_ok(not fog.make_order("liu_bei", "RC-LIU-SQ-02", lost_contact, 2).ok, "age 3 lost contact cannot be targeted")
	var expired_contact := contact.duplicate(true); expired_contact.state = "undetected"; expired_contact.last_known_position = null
	_ok(not fog.make_order("liu_bei", "RC-LIU-SQ-02", expired_contact, 2).ok, "expired contact cannot be targeted")
	_eq(made.order.aim_position, [made.order.last_known_position[0] + made.order.error_offset[0], made.order.last_known_position[1] + made.order.error_offset[1]], "aim is last-known plus deterministic error")
	var edge_contact := contact.duplicate(true); edge_contact.last_known_position = [0.0, 0.0]; edge_contact.error_radius = 10000
	var edge_order: Dictionary = fog.make_order("liu_bei", "RC-LIU-SQ-02", edge_contact, 2)
	_ok(edge_order.ok and float(edge_order.order.aim_position[0]) >= 0.0 and float(edge_order.order.aim_position[0]) <= 1600.0
		and float(edge_order.order.aim_position[1]) >= 0.0 and float(edge_order.order.aim_position[1]) <= 900.0,
		"deterministic uncertainty aim is clamped to battlefield bounds")
	_eq(JSON.stringify(made), JSON.stringify(fog.make_order("liu_bei", "RC-LIU-SQ-02", contact, 2)), "same seed is byte-stable")
	_ok(not fog.make_order("sun_quan", "RC-LIU-SQ-02", contact, 2).ok, "cross-faction shooter rejected")
	var movement = Movement.new(); movement.initialize(setup)
	var weapon = Weapon.new(); weapon.initialize(setup); var policy := weapon.interception_policy(weapon.initial_state())
	var nav_a := movement.initial_navigation(); var nav_b := nav_a.duplicate(true); nav_b["RC-CAO-SQ-01"].position = [1500, 800]
	var a: Dictionary = fog.authorize_orders([made.order], "liu_bei", nav_a, policy, 2)
	var b: Dictionary = fog.authorize_orders([made.order], "liu_bei", nav_b, policy, 2)
	_ok(a.ok and a.estimated_fire_events.size() == 1, "estimated fire authorized at sealed aim")
	_eq(JSON.stringify(a), JSON.stringify(b), "authorization independent of true target position/path")
	var event: Dictionary = a.estimated_fire_events[0]
	_ok(not event.has("target_squadron_id") and not event.has("current_position") and event.actual_target_position_used == false, "authorization contains no true target")
	_ok(not event.has("hit") and not event.has("damage") and not event.has("winner"), "no fabricated result")
	var tampered: Dictionary = made.order.duplicate(true); tampered.error_offset[0] += 1
	_ok(not fog.authorize_orders([tampered], "liu_bei", nav_a, policy, 2).ok, "tampered sealed order rejected atomically")
	var resources = Resources.new(); _ok(resources.initialize(setup).ok, "resources initialize")
	var resource_result: Dictionary = resources.resolve_shots([event], resources.initial_state(), 2)
	_ok(resource_result.ok and resource_result.authorized_events.size() == 1 and resource_result.consumption_events.size() == 1, "estimated authorization uses common resource gate")
	_ok(resource_result.authorized_events[0].has("resource_reservation"), "resource receipt decorates estimated authorization")

func _test_battle_command_ai_redaction_and_ledger() -> void:
	# G5-05 Cao patrol advances 60 units; start farther out so this fixture still
	# exercises the intended estimated-contact lifecycle after that legal AI move.
	var setup := _fixture([400, 100]); var battle = Battle.new(); var battle_init: Dictionary = battle.initialize(setup); _ok(battle_init.ok, "battle initializes: %s" % str(battle_init.get("errors", [])))
	_ok(battle.submit_command_draft().ok and battle.submit_sun_control_choice("ai").ok, "turn1 Liu then AI HOLD submit")
	var first: Dictionary = battle.resolve_turn(); _ok(first.ok, "turn1 detection resolves")
	_eq(first.estimated_fire_events.size(), 0, "AI factions do not synthesize estimated fire")
	battle.continue_turn()
	var contacts: Array = battle.visible_contacts("liu_bei").contacts
	var estimated := contacts.filter(func(row): return String(row.get("state", "")) == "estimated")
	_ok(not estimated.is_empty(), "turn2 Liu sees estimated contact")
	var before := battle.digest(); _ok(not battle.set_estimated_fire("RC-LIU-SQ-02", "CONTACT-forged").ok, "unknown opaque contact rejected")
	_eq(battle.digest(), before, "invalid estimated selection is atomic")
	var cross_viewer_id := Fog.new(); cross_viewer_id.initialize(setup)
	_ok(not battle.set_estimated_fire("RC-LIU-SQ-02", cross_viewer_id.contact_id("sun_quan", "RC-CAO-SQ-01")).ok,
		"cross-viewer opaque contact rejected")
	_eq(battle.digest(), before, "cross-viewer rejection is atomic")
	var selected: Dictionary = battle.set_estimated_fire("RC-LIU-SQ-02", String(estimated[0].contact_id))
	_ok(selected.ok and battle.command_draft_summary().estimated_fire_count == 1, "Liu directly stages estimated fire")
	_ok(battle.submit_command_draft().ok and battle.submit_sun_control_choice("ai").ok, "turn2 commands submit")
	var second: Dictionary = battle.resolve_turn(); _ok(second.ok, "turn2 estimated fire resolves")
	_ok(second.estimated_fire_events.size() + second.estimated_fire_suppressed_events.size() >= 1, "estimated fire produces authorized or explicit suppression receipt")
	var liu_events := JSON.stringify(battle.visible_tactical_events("liu_bei", 2))
	var cao_events := JSON.stringify(battle.visible_tactical_events("cao_cao", 2))
	_ok(liu_events.contains("estimated_fire_"), "shooter viewer receives estimated fire event")
	_ok(not cao_events.contains("estimated_fire_"), "target viewer receives no enemy estimated-fire allocation or geometry")
	var barrage: Dictionary = battle.viewer_phase("liu_bei", "barrage", 2)
	_ok(barrage.ok and JSON.stringify(barrage).contains("estimated_fire_"), "estimated fire maps to viewer barrage ledger")
	_ok(not second.has("hit") and not second.has("damage") and not second.has("winner"), "integrated receipt creates no hit damage or winner outcome")
	_ok(battle.continue_turn().ok and battle.submit_command_draft().ok and battle.submit_sun_control_choice("manual").ok, "manual Sun reaches same direct command boundary")
	var sun_contacts: Array = battle.visible_contacts("sun_quan").contacts
	var sun_estimated := sun_contacts.filter(func(row): return String(row.get("state", "")) == "estimated")
	_ok(not sun_estimated.is_empty(), "manual Sun has viewer-scoped estimated contact")
	_ok(battle.set_estimated_fire("RC-SUN-SQ-01", String(sun_estimated[0].contact_id)).ok, "manual Sun stages estimated fire through same API")
	_ok(battle.submit_command_draft().ok, "manual Sun estimated order submits")
	var third: Dictionary = battle.resolve_turn(); _ok(third.ok, "manual Sun uses same resolver")
	_ok(third.estimated_fire_events.size() + third.estimated_fire_suppressed_events.size() >= 1, "manual Sun receives deterministic estimated-fire receipt")
	_eq(battle.turn_log()[0].sun_estimated_fire_orders, [], "AI Sun turn keeps estimated orders empty")
	_eq(battle.turn_log()[0].cao_estimated_fire_orders, [], "AI Cao never synthesizes estimated order")

func _holds(setup: Dictionary) -> Array:
	var result: Array = []
	for squad in setup.squadrons:
		if bool(squad.get("operational", true)): result.append({"squadron_id": String(squad.id), "action": "hold"})
	return result
