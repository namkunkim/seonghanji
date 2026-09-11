extends SceneTree

## Task ID / 공식·새 작업 제목: DEMO-RC-G4-03 — 경로 교차 요격·탐지 기반 기회 사격
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Movement := preload("res://core/demo_red_cliffs/red_cliffs_movement_resolver.gd")
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
	print("DEMO-RC-G4-03 interception detection core")
	_test_rules_and_initial_redaction()
	_test_actual_path_intersection_policy()
	_test_detection_estimated_lost_last_known()
	_test_shot_authorized_entry_arc_and_seed()
	_test_turn_battle_integration_and_viewer_receipts()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)


func _fixture(liu_one: Array, liu_two: Array, sun: Array, cao: Array) -> Dictionary:
	var loaded := Setup.load_default(); _ok(loaded.ok, "setup fixture loads")
	var setup: Dictionary = loaded.setup.duplicate(true)
	var positions := {"RC-LIU-SQ-01": liu_one, "RC-LIU-SQ-02": liu_two, "RC-SUN-SQ-01": sun, "RC-CAO-SQ-01": cao}
	for squad in setup.squadrons: squad.initial_position = positions[String(squad.id)].duplicate()
	_ok(Setup.validate_document(setup).ok, "position fixture remains valid")
	return setup


func _new_interception(setup: Dictionary):
	var resolver = Interception.new(); _ok(resolver.initialize(setup).ok, "interception resolver initializes"); return resolver


func _new_movement(setup: Dictionary):
	var resolver = Movement.new(); _ok(resolver.initialize(setup).ok, "movement resolver initializes"); return resolver


func _test_rules_and_initial_redaction() -> void:
	var setup := _fixture([100, 100], [100, 800], [100, 700], [1000, 100])
	var resolver = _new_interception(setup); var rules: Dictionary = resolver.rules_snapshot()
	_eq(rules.profile_id, "normal-demo-interception-v1", "explicit interception balance profile")
	_ok(not String(rules.deterministic_seed).is_empty(), "deterministic seed is data-owned")
	_ok(String(rules.intersection_policy).contains("actual_reached_polyline_only") and String(rules.intersection_policy).contains("hostile_only"), "actual hostile path policy explicit")
	var detection: Dictionary = resolver.initial_detection_state()
	_eq(detection.size(), 6, "directed hostile observer-target pairs initialized")
	for row in detection.values():
		_eq(row.state, "undetected", "initial detection is undetected")
		_eq(row.last_known_position, null, "never-seen contact has no last-known position")
	var movement = _new_movement(setup); var navigation := movement.initial_navigation()
	var contacts: Dictionary = resolver.visible_contacts("liu_bei", detection, navigation)
	_ok(contacts.ok and contacts.contacts.is_empty(), "never-seen enemies omitted from visible contacts")
	var battle = Battle.new(); _ok(battle.initialize(setup).ok, "battle initializes viewer boundary")
	var viewer: Dictionary = battle.viewer_snapshot("liu_bei")
	var serialized := JSON.stringify(viewer)
	_ok(not serialized.contains("RC-CAO-SQ-01") and not serialized.contains("조조"), "unknown viewer snapshot has no enemy identity")
	_ok(viewer.contacts.is_empty() and not viewer.has("enemy_navigation"), "unknown viewer snapshot has no enemy exact position")
	_ok(not viewer.has("applied_setup") and not viewer.has("live_navigation") and not viewer.has("turn_log"), "viewer snapshot omits authoritative nested state")
	_ok(not battle.visible_contacts("unknown").ok, "unknown viewer faction rejected")


func _test_actual_path_intersection_policy() -> void:
	var setup := _fixture([100, 100], [100, 800], [100, 700], [240, 100])
	var movement = _new_movement(setup); var interception = _new_interception(setup)
	var navigation := movement.initial_navigation(); var detection := interception.initial_detection_state()
	var crossing_orders := _holds(setup)
	_set_move(crossing_orders, "RC-LIU-SQ-01", [[240, 100]], 0)
	_set_move(crossing_orders, "RC-CAO-SQ-01", [[100, 100]], 180)
	var moved: Dictionary = movement.resolve_orders(crossing_orders, navigation); _ok(moved.ok, "collinear opposing movement resolves")
	var crossed: Dictionary = interception.resolve(moved.events, moved.live_navigation, detection, 1)
	_ok(crossed.ok, "collinear interception resolves")
	_eq(crossed.path_intersection_events.size(), 1, "collinear overlap deduplicates to one hostile pair event")
	_ok(crossed.path_intersection_events[0].path_crossed, "collinear overlap marked crossed")
	_eq(crossed.path_intersection_events[0].dedup_policy, "one_pair_per_turn", "dedup policy explicit")

	setup = _fixture([100, 100], [100, 800], [100, 700], [240, 100])
	movement = _new_movement(setup); interception = _new_interception(setup); navigation = movement.initial_navigation()
	var endpoint_orders := _holds(setup); _set_move(endpoint_orders, "RC-LIU-SQ-01", [[240, 100]], 0)
	moved = movement.resolve_orders(endpoint_orders, navigation)
	var endpoint := interception.resolve(moved.events, moved.live_navigation, interception.initial_detection_state(), 1)
	_eq(endpoint.path_intersection_events.size(), 1, "reached endpoint touching hostile hold path counts")

	setup = _fixture([100, 100], [100, 800], [100, 700], [240, 101])
	movement = _new_movement(setup); interception = _new_interception(setup); navigation = movement.initial_navigation()
	var near_orders := _holds(setup); _set_move(near_orders, "RC-LIU-SQ-01", [[240, 100]], 0); _set_move(near_orders, "RC-CAO-SQ-01", [[100, 101]], 180)
	moved = movement.resolve_orders(near_orders, navigation)
	var nearby := interception.resolve(moved.events, moved.live_navigation, interception.initial_detection_state(), 1)
	_eq(nearby.path_intersection_events.size(), 0, "simple proximity without epsilon intersection is excluded")

	setup = _fixture([100, 100], [100, 800], [240, 100], [1200, 800])
	movement = _new_movement(setup); interception = _new_interception(setup); navigation = movement.initial_navigation()
	var allied_orders := _holds(setup); _set_move(allied_orders, "RC-LIU-SQ-01", [[240, 100]], 0)
	moved = movement.resolve_orders(allied_orders, navigation)
	var allied := interception.resolve(moved.events, moved.live_navigation, interception.initial_detection_state(), 1)
	_eq(allied.path_intersection_events.size(), 0, "allied endpoint crossing is excluded")

	setup = _fixture([100, 100], [100, 800], [100, 700], [500, 100])
	movement = _new_movement(setup); interception = _new_interception(setup); navigation = movement.initial_navigation()
	var future_orders := _holds(setup); _set_move(future_orders, "RC-LIU-SQ-01", [[500, 100]], 0)
	moved = movement.resolve_orders(future_orders, navigation)
	_ok(not moved.events[0].path_complete, "future-path fixture is partial")
	var future := interception.resolve(moved.events, moved.live_navigation, interception.initial_detection_state(), 1)
	_eq(future.path_intersection_events.size(), 0, "unreached requested path cannot create interception")


func _test_detection_estimated_lost_last_known() -> void:
	var setup := _fixture([100, 100], [100, 800], [100, 700], [350, 100])
	var movement = _new_movement(setup); var interception = _new_interception(setup)
	var navigation := movement.initial_navigation(); var detection := interception.initial_detection_state()
	var orders := _holds(setup); _set_move(orders, "RC-CAO-SQ-01", [[200, 100]], 180)
	var moved: Dictionary = movement.resolve_orders(orders, navigation)
	var result: Dictionary = interception.resolve(moved.events, moved.live_navigation, detection, 1)
	var contact := _contact(result.detection_state, "RC-LIU-SQ-01", "RC-CAO-SQ-01")
	_eq(contact.state, "confirmed", "G5 sensor score confirms the close path point")
	_eq(contact.last_known_position, [291.0, 100.0], "estimated contact stores actual last-known at observation time")
	_eq(contact.last_seen_turn, 1, "estimated contact stores last-seen turn")
	var estimated_public: Dictionary = interception.visible_contacts("liu_bei", result.detection_state, moved.live_navigation).contacts[0]
	_ok(not estimated_public.stale and estimated_public.has("target_squadron_id"), "confirmed public contact exposes current identified contact")

	navigation = moved.live_navigation; detection = result.detection_state; orders = _holds(setup)
	_set_move(orders, "RC-CAO-SQ-01", [[500, 100]], 0)
	moved = movement.resolve_orders(orders, navigation)
	result = interception.resolve(moved.events, moved.live_navigation, detection, 2)
	contact = _contact(result.detection_state, "RC-LIU-SQ-01", "RC-CAO-SQ-01")
	_eq(contact.state, "confirmed", "contact remains confirmed at the same close path point")
	_eq(contact.last_known_position, [291.0, 100.0], "last-known does not advance past the observed path point")
	navigation = moved.live_navigation; detection = result.detection_state; orders = _holds(setup)
	_set_move(orders, "RC-CAO-SQ-01", [[500, 100]], 0)
	moved = movement.resolve_orders(orders, navigation)
	result = interception.resolve(moved.events, moved.live_navigation, detection, 3)
	contact = _contact(result.detection_state, "RC-LIU-SQ-01", "RC-CAO-SQ-01")
	_eq(contact.state, "estimated", "contact remains estimated when the reached path starts inside sensor range")
	_eq(contact.last_known_position, [350.0, 100.0], "last-known stops at actually observed path point")
	navigation = moved.live_navigation; detection = result.detection_state; orders = _holds(setup)
	_set_move(orders, "RC-CAO-SQ-01", [[500, 100]], 0)
	moved = movement.resolve_orders(orders, navigation)
	result = interception.resolve(moved.events, moved.live_navigation, detection, 4)
	contact = _contact(result.detection_state, "RC-LIU-SQ-01", "RC-CAO-SQ-01")
	_eq(contact.state, "estimated", "G5 memory keeps age-1 contact estimated outside sensor range")
	_eq(contact.last_known_position, [409.0, 100.0], "estimated contact advances only to the observed actual path point")
	_eq(contact.last_seen_turn, 4, "estimated contact refreshes last-seen turn")
	var visible: Dictionary = interception.visible_contacts("liu_bei", result.detection_state, moved.live_navigation)
	var public_contact: Dictionary = visible.contacts[0]
	_ok(public_contact.stale and public_contact.state == "estimated", "remembered public contact is marked stale")
	_ok(not public_contact.has("target_squadron_id"), "lost contact does not reveal exact enemy squadron ID")
	_eq(public_contact.display_position, [409.0, 100.0], "estimated contact displays only last-known position")
	_eq(public_contact.last_known_position, [409.0, 100.0], "estimated public contact exposes only last-known position")


func _test_shot_authorized_entry_arc_and_seed() -> void:
	var setup := _fixture([100, 100], [100, 800], [100, 700], [320, 100])
	var movement = _new_movement(setup); var interception = _new_interception(setup)
	var navigation := movement.initial_navigation(); var orders := _holds(setup)
	_set_move(orders, "RC-CAO-SQ-01", [[200, 100]], 180)
	var moved: Dictionary = movement.resolve_orders(orders, navigation)
	var first: Dictionary = interception.resolve(moved.events, moved.live_navigation, interception.initial_detection_state(), 1)
	var second: Dictionary = interception.resolve(moved.events, moved.live_navigation, interception.initial_detection_state(), 1)
	_eq(JSON.stringify(first), JSON.stringify(second), "same seed and inputs produce byte-stable tactical receipt")
	var untouched_detection := interception.initial_detection_state(); var untouched_digest := JSON.stringify(untouched_detection)
	interception.resolve(moved.events, moved.live_navigation, untouched_detection, 1)
	_eq(JSON.stringify(untouched_detection), untouched_digest, "resolver deep-copies caller detection state")
	var invalid_events: Array = moved.events.duplicate(true); invalid_events.pop_back()
	var invalid := interception.resolve(invalid_events, moved.live_navigation, untouched_detection, 1)
	_ok(not invalid.ok, "missing movement event rejects tactical resolve")
	_eq(JSON.stringify(untouched_detection), untouched_digest, "invalid tactical resolve is atomic")
	var fire := _fire(first.opportunity_fire_events, "RC-LIU-SQ-01", "RC-CAO-SQ-01")
	_ok(not fire.is_empty(), "confirmed moving enemy entering range and forward arc authorizes shot")
	_eq(fire.outcome, "shot_authorized", "fire event authorizes only the shot boundary")
	_ok(fire.damage_pending and not fire.has("hit") and not fire.has("damage") and not fire.has("winner"), "shot event invents no hit damage or winner")
	_ok(not first.has("resource_consumption") and not fire.has("ammo_before"), "G5 resource consumption is not invented")

	var away_setup := setup.duplicate(true)
	for squad in away_setup.squadrons:
		if squad.id == "RC-LIU-SQ-01": squad.initial_facing_deg = 180
	movement = _new_movement(away_setup); interception = _new_interception(away_setup); navigation = movement.initial_navigation(); orders = _holds(away_setup)
	_set_move(orders, "RC-CAO-SQ-01", [[200, 100]], 180); moved = movement.resolve_orders(orders, navigation)
	var away := interception.resolve(moved.events, moved.live_navigation, interception.initial_detection_state(), 1)
	_eq(_fire(away.opportunity_fire_events, "RC-LIU-SQ-01", "RC-CAO-SQ-01"), {}, "target entering range behind firing arc authorizes no shot")

	var hold_orders := _holds(setup); moved = movement.resolve_orders(hold_orders, movement.initial_navigation())
	var hold_result := interception.resolve(moved.events, moved.live_navigation, interception.initial_detection_state(), 1)
	_eq(hold_result.opportunity_fire_events.size(), 0, "stationary in-range target creates no entry opportunity")


func _test_turn_battle_integration_and_viewer_receipts() -> void:
	var setup := _fixture([100, 100], [100, 800], [100, 700], [400, 100])
	for squad in setup.squadrons:
		if squad.id == "RC-CAO-SQ-01": squad.initial_facing_deg = 180
	var battle = Battle.new(); _ok(battle.initialize(setup).ok, "turn battle initializes G4-03 state")
	_ok(battle.set_order_move("RC-LIU-SQ-01", [[240, 100]], 0).ok, "Liu moving target order staged")
	_ok(battle.submit_command_draft().ok, "Liu mixed command draft submits")
	_ok(battle.submit_sun_control_choice("ai").ok, "Sun AI HOLD contract preserved")
	var receipt: Dictionary = battle.resolve_turn(); _ok(receipt.ok, "integrated tactical resolve succeeds")
	_ok(not receipt.rules_pending.has("movement") and not receipt.rules_pending.has("detection"), "implemented movement and detection removed from pending")
	_ok(receipt.rules_pending.has("weapon_fire") and receipt.rules_pending.has("damage") and receipt.rules_pending.has("victory"), "general fire damage and victory remain pending")
	_ok(not receipt.has("damage") and not receipt.has("winner") and not receipt.has("resource_consumption"), "integrated receipt has no fabricated G5 result")
	var cao_fire := _fire(receipt.opportunity_fire_events, "RC-CAO-SQ-01", "RC-LIU-SQ-01")
	_ok(not cao_fire.is_empty(), "Cao HOLD can authorize deterministic opportunity shot on moving Liu target")
	var liu_visible: Dictionary = battle.visible_tactical_events("liu_bei")
	_ok(liu_visible.ok and not liu_visible.events.is_empty(), "viewer-specific tactical event receipt available")
	var visible_json := JSON.stringify(liu_visible)
	_ok(not visible_json.contains("target_squadron_id") and not visible_json.contains("shooter_squadron_id"), "viewer receipt contains no raw enemy identity keys")
	_ok(not visible_json.contains("requested_waypoints") and not visible_json.contains("composition"), "viewer receipt contains no enemy path or composition")
	var target_fire: Dictionary = liu_visible.events.filter(func(row): return String(row.get("event_type", "")) == "shot_authorized")[0]
	_ok(String(target_fire.get("own_role", "")) == "target", "target viewer receives only its own role")
	_ok(not target_fire.has("range") and not target_fire.has("distance") and not target_fire.has("bearing_deg") and not target_fire.has("facing_deg") and not target_fire.has("arc_deg"), "target viewer cannot infer hostile shooter geometry")
	var viewer: Dictionary = battle.viewer_snapshot("liu_bei")
	_ok(not viewer.has("applied_setup") and not viewer.has("live_navigation"), "viewer snapshot stays redacted after contact")
	var public_log: Dictionary = battle.viewer_turn_log("liu_bei")
	_ok(public_log.ok and not JSON.stringify(public_log).contains("cao_orders"), "viewer turn log omits enemy raw orders")
	_eq(battle.turn_log()[0].sun_orders[0].action, "hold", "authoritative AI Sun HOLD remains stable")
	_eq(battle.turn_log()[0].cao_orders, battle.viewer_ai_decision("cao_cao", 1).orders, "authoritative Cao AI decision remains stable")


func _holds(setup: Dictionary) -> Array:
	var orders: Array = []
	for squad in setup.squadrons:
		if bool(squad.get("operational", true)): orders.append({"squadron_id": String(squad.id), "action": "hold"})
	return orders


func _set_move(orders: Array, squadron_id: String, waypoints: Array, facing: float) -> void:
	for order in orders:
		if String(order.squadron_id) == squadron_id:
			order.action = "move"; order.waypoints = waypoints.duplicate(true); order.facing_deg = facing; return


func _contact(state: Dictionary, observer_id: String, target_id: String) -> Dictionary:
	return state.get("%s>%s" % [observer_id, target_id], {})


func _fire(events: Array, shooter_id: String, target_id: String) -> Dictionary:
	for event in events:
		if String(event.shooter_squadron_id) == shooter_id and String(event.target_squadron_id) == target_id: return event
	return {}
