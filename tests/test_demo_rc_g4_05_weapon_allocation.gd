extends SceneTree

## Task ID / 공식·새 작업 제목: DEMO-RC-G4-05 — 무기 비율·프리셋·사격 중지 명령
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Weapon := preload("res://core/demo_red_cliffs/red_cliffs_weapon_allocation.gd")
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
	print("DEMO-RC-G4-05 weapon allocation core")
	_test_availability_presets_and_basis_point_normalization()
	_test_invalid_atomic_resolve_and_zero_weapon_hold()
	_test_range_arc_eligibility_and_hold_fire()
	_test_battle_draft_timing_persistence_parity_and_redaction()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)


func _setup() -> Dictionary:
	var loaded := Setup.load_default(); _ok(loaded.ok, "setup loads"); return loaded.setup.duplicate(true)


func _weapon(setup: Dictionary):
	var resolver = Weapon.new(); var initialized: Dictionary = resolver.initialize(setup)
	_ok(initialized.ok, "weapon resolver initializes: %s" % str(initialized.get("errors", []))); return resolver


func _sum(values: Dictionary) -> int:
	var total := 0
	for value in values.values(): total += int(value)
	return total


func _test_availability_presets_and_basis_point_normalization() -> void:
	var resolver = _weapon(_setup()); var rules: Dictionary = resolver.rules_snapshot()
	_eq(rules.profile_id, "normal-demo-weapon-allocation-v1", "explicit weapon-control profile")
	_eq(int(rules.total_basis_points), 10000, "0.01 percent integer precision")
	_ok(resolver.presets().size() >= 3, "at least three data-owned presets")
	_eq(resolver.available_categories("RC-LIU-SQ-01"), ["intercept", "line_fire"], "availability derives from actual composition and equipment")
	var state: Dictionary = resolver.initial_state(); var row: Dictionary = state["RC-LIU-SQ-01"]
	_eq(_sum(row.allocations), 10000, "initial allocation totals exactly 10000 bps")
	_eq(int(row.allocations.artillery), 0, "unavailable artillery forced to zero")
	_eq(int(row.allocations.torpedo), 0, "unavailable torpedo forced to zero")
	var changed: Dictionary = resolver.set_basis_points(state, "RC-LIU-SQ-01", "line_fire", 3333)
	_ok(changed.ok, "direct basis-point edit succeeds")
	_eq(int(changed.row.allocations.line_fire), 3333, "changed weapon remains exact")
	_eq(int(changed.row.allocations.intercept), 6667, "stable residual fills exact total")
	_eq(_sum(changed.row.allocations), 10000, "normalized result remains exact")
	_eq(JSON.stringify(changed), JSON.stringify(resolver.set_basis_points(state, "RC-LIU-SQ-01", "line_fire", 3333)), "normalization deterministic")
	var digest := JSON.stringify(state)
	_ok(not resolver.set_basis_points(state, "RC-LIU-SQ-01", "torpedo", 1).ok, "unavailable weapon nonzero rejected")
	_eq(JSON.stringify(state), digest, "invalid direct edit does not mutate caller")
	for preset in resolver.presets():
		var applied: Dictionary = resolver.apply_preset(state, "RC-LIU-SQ-02", String(preset.preset_id))
		_ok(applied.ok and _sum(applied.row.allocations) == 10000, "preset %s normalizes to exact total" % preset.preset_id)
	var held: Dictionary = resolver.set_hold_fire(changed.state, "RC-LIU-SQ-01", true)
	_ok(held.ok and held.row.hold_fire, "hold-fire enabled")
	_eq(held.row.allocations, changed.row.allocations, "hold-fire preserves allocation")
	var resumed: Dictionary = resolver.set_hold_fire(held.state, "RC-LIU-SQ-01", false)
	_ok(resumed.ok and not resumed.row.hold_fire, "fire resumes")
	_eq(resumed.row.allocations, changed.row.allocations, "resume restores preserved allocation")


func _test_invalid_atomic_resolve_and_zero_weapon_hold() -> void:
	var setup := _setup(); var resolver = _weapon(setup); var state: Dictionary = resolver.initial_state(); var digest := JSON.stringify(state)
	var orders := _orders(state)
	var valid: Dictionary = resolver.resolve_orders(orders, state, 1); _ok(valid.ok, "complete weapon orders resolve")
	_eq(JSON.stringify(state), digest, "resolve deep-copies caller state")
	_eq(JSON.stringify(valid), JSON.stringify(resolver.resolve_orders(orders, state, 1)), "resolve deterministic")
	var invalid: Array = orders.duplicate(true); invalid[0].allocations.line_fire -= 1
	_ok(not resolver.resolve_orders(invalid, state, 1).ok, "9999 bps total rejected")
	_eq(JSON.stringify(state), digest, "invalid resolve atomic")
	invalid = orders.duplicate(true); invalid[0].allocations["unknown"] = 0
	_ok(not resolver.resolve_orders(invalid, state, 1).ok, "unknown weapon rejected")
	invalid = orders.duplicate(true); invalid.pop_back()
	_ok(not resolver.resolve_orders(invalid, state, 1).ok, "missing squadron rejected")
	invalid = orders.duplicate(true); invalid[1] = invalid[0].duplicate(true)
	_ok(not resolver.resolve_orders(invalid, state, 1).ok, "duplicate squadron rejected")

	var zero_setup := setup.duplicate(true)
	for squad in zero_setup.squadrons:
		if squad.id == "RC-LIU-SQ-01":
			squad.composition = [{"ship_type_id": "SHP-05", "count": 1}]
			squad.declared_total_cost = 8
	_ok(Setup.validate_document(zero_setup).ok, "support-only zero-weapon fixture valid")
	var zero = _weapon(zero_setup); var zero_row: Dictionary = zero.initial_state()["RC-LIU-SQ-01"]
	_ok(zero_row.available_categories.is_empty() and zero_row.hold_fire, "zero-weapon squad auto-holds fire")
	_eq(_sum(zero_row.allocations), 0, "zero-weapon allocation forced to zero")
	_ok(not zero.set_hold_fire(zero.initial_state(), "RC-LIU-SQ-01", false).ok, "zero-weapon squad cannot resume fire")


func _test_range_arc_eligibility_and_hold_fire() -> void:
	var setup := _setup()
	var angle := deg_to_rad(70.0)
	var positions := {"RC-LIU-SQ-01": [100.0, 100.0], "RC-LIU-SQ-02": [100, 800], "RC-LIU-FC-01": [1600, 900], "RC-SUN-SQ-01": [100, 700],
		"RC-CAO-SQ-01": [100.0 + cos(angle) * 230.0, 100.0 + sin(angle) * 230.0]}
	for squad in setup.squadrons:
		squad.initial_position = positions[String(squad.id)].duplicate()
		if squad.id == "RC-LIU-SQ-01": squad.initial_facing_deg = 0
	var movement = Movement.new(); _ok(movement.initialize(setup).ok, "movement initializes eligibility fixture")
	var orders := _movement_orders(setup)
	var target := [100.0 + cos(angle) * 160.0, 100.0 + sin(angle) * 160.0]
	_set_move(orders, "RC-CAO-SQ-01", [target], 180)
	var moved: Dictionary = movement.resolve_orders(orders, movement.initial_navigation()); _ok(moved.ok, "target moves into detection/range")
	var interception = Interception.new(); _ok(interception.initialize(setup).ok, "interception initializes promoted weapon rules")
	var weapon = _weapon(setup); var initial: Dictionary = weapon.initial_state()
	var intercept_only: Dictionary = weapon.set_basis_points(initial, "RC-LIU-SQ-01", "intercept", 10000).state
	var allowed: Dictionary = interception.resolve(moved.events, moved.live_navigation, interception.initial_detection_state(), 1, weapon.interception_policy(intercept_only))
	var fire := _fire(allowed.opportunity_fire_events, "RC-LIU-SQ-01", "RC-CAO-SQ-01")
	_ok(not fire.is_empty(), "allocated intercept weapon with matching range/arc authorizes shot")
	_eq(fire.selected_weapon_id, "intercept", "eligible allocated weapon selected")
	_eq(int(fire.allocation_basis_points), 10000, "event records selected allocation")
	var raw_receipt := {"path_intersection_events": [], "detection_events": allowed.detection_events,
		"opportunity_fire_events": allowed.opportunity_fire_events}
	var shooter_view: Dictionary = interception.visible_tactical_events("liu_bei", raw_receipt, allowed.detection_state)
	var shooter_fire: Dictionary = shooter_view.events.filter(func(row): return row.get("event_type") == "shot_authorized")[0]
	_ok(shooter_fire.fire_control_snapshot is Dictionary, "shooter viewer receives immutable fire-control snapshot")
	_eq(shooter_fire.fire_control_snapshot.selected_weapon_id, "intercept", "shooter sees selected eligible weapon")
	var target_view: Dictionary = interception.visible_tactical_events("cao_cao", raw_receipt, allowed.detection_state)
	var target_fire: Dictionary = target_view.events.filter(func(row): return row.get("event_type") == "shot_authorized")[0]
	_ok(not target_fire.has("fire_control_snapshot") and not target_fire.has("selected_weapon_id"), "target viewer sees no hostile allocation or weapon")
	shooter_fire.fire_control_snapshot.allocations.intercept = 0
	var shooter_again: Dictionary = interception.visible_tactical_events("liu_bei", raw_receipt, allowed.detection_state)
	_eq(shooter_again.events.filter(func(row): return row.get("event_type") == "shot_authorized")[0].fire_control_snapshot.allocations.intercept, 10000, "viewer fire-control snapshot is deep copied")
	var line_only: Dictionary = weapon.set_basis_points(initial, "RC-LIU-SQ-01", "line_fire", 10000).state
	var blocked: Dictionary = interception.resolve(moved.events, moved.live_navigation, interception.initial_detection_state(), 1, weapon.interception_policy(line_only))
	_eq(_fire(blocked.opportunity_fire_events, "RC-LIU-SQ-01", "RC-CAO-SQ-01"), {}, "allocated line weapon outside arc is ineligible")
	var held: Dictionary = weapon.set_hold_fire(intercept_only, "RC-LIU-SQ-01", true).state
	var silenced: Dictionary = interception.resolve(moved.events, moved.live_navigation, interception.initial_detection_state(), 1, weapon.interception_policy(held))
	_eq(_fire(silenced.opportunity_fire_events, "RC-LIU-SQ-01", "RC-CAO-SQ-01"), {}, "hold-fire suppresses opportunity event generation")
	var forged := weapon.interception_policy(intercept_only); forged["RC-LIU-SQ-01"].capabilities[0].range = 9999
	_ok(not interception.resolve(moved.events, moved.live_navigation, interception.initial_detection_state(), 1, forged).ok, "forged range capability rejected")


func _test_battle_draft_timing_persistence_parity_and_redaction() -> void:
	var setup := _setup(); var battle = Battle.new(); _ok(battle.initialize(setup).ok, "battle initializes weapon state")
	_eq(battle.weapon_categories().size(), 4, "public category rows are data-owned")
	_ok(battle.weapon_presets().size() >= 3, "public preset rows available")
	var query: Dictionary = battle.weapon_allocation_order("RC-LIU-SQ-01")
	_eq(query.total_basis_points, 10000, "query receipt owns total")
	var before_live: Dictionary = battle.weapon_allocation_state()["RC-LIU-SQ-01"].allocations.duplicate(true)
	var before_digest := battle.digest()
	_ok(not battle.set_weapon_basis_points("RC-LIU-SQ-01", "torpedo", 1).ok, "invalid unavailable edit rejected")
	_eq(battle.digest(), before_digest, "invalid battle edit atomic")
	var changed: Dictionary = battle.set_weapon_basis_points("RC-LIU-SQ-01", "line_fire", 4321)
	_ok(changed.ok and changed.total_basis_points == 10000, "battle setter returns normalized total")
	_ok(battle.set_hold_fire("RC-LIU-SQ-01", true).ok, "Liu stages hold-fire alongside HOLD")
	_eq(battle.weapon_allocation_state()["RC-LIU-SQ-01"].allocations, before_live, "draft does not mutate live allocation")
	_ok(battle.submit_command_draft().ok and battle.submit_sun_control_choice("ai").ok, "Liu submit and AI path")
	var first: Dictionary = battle.resolve_turn(); _ok(first.ok, "weapon orders apply at resolve start")
	_ok(first.rules_pending.has("weapon_fire"), "actual weapon fire remains pending")
	_eq(battle.weapon_allocation_state()["RC-LIU-SQ-01"].allocations.line_fire, 4321, "allocation applied")
	_ok(battle.weapon_allocation_state()["RC-LIU-SQ-01"].hold_fire, "hold-fire applied")
	_eq(first.weapon_allocation_events.size(), 5, "AI and player share complete resolver including fast craft")
	_ok(not first.has("ammo") and not first.has("energy") and not first.has("heat") and not first.has("hit") and not first.has("damage") and not first.has("winner"), "no G4-06 result fabricated")
	var liu_view: Dictionary = battle.viewer_snapshot("liu_bei")
	_ok(liu_view.own_weapon_allocation_state.has("RC-LIU-SQ-01") and not liu_view.own_weapon_allocation_state.has("RC-CAO-SQ-01"), "viewer snapshot exposes own allocation only")
	_ok(battle.continue_turn().ok, "next turn begins")
	_eq(battle.weapon_allocation_order("RC-LIU-SQ-01").order.allocations.line_fire, 4321, "allocation persists to next draft")
	_ok(battle.submit_command_draft().ok and battle.submit_sun_control_choice("manual").ok, "manual Sun path")
	_ok(battle.apply_weapon_preset("RC-SUN-SQ-01", "close_strike").ok, "manual Sun uses same preset API")
	_ok(battle.set_hold_fire("RC-SUN-SQ-01", true).ok, "manual Sun stages hold-fire")
	_ok(battle.submit_command_draft().ok, "manual Sun combined draft submits")
	var second: Dictionary = battle.resolve_turn(); _ok(second.ok, "manual Sun resolves")
	_ok(battle.weapon_allocation_state()["RC-SUN-SQ-01"].hold_fire, "manual Sun hold-fire applies")


func _orders(state: Dictionary) -> Array:
	var result: Array = []
	for squadron_id in state:
		result.append({"squadron_id": squadron_id, "allocations": state[squadron_id].allocations.duplicate(true), "hold_fire": bool(state[squadron_id].hold_fire)})
	return result


func _movement_orders(setup: Dictionary) -> Array:
	var result: Array = []
	for squad in setup.squadrons:
		if bool(squad.get("operational", true)): result.append({"squadron_id": String(squad.id), "action": "hold"})
	return result


func _set_move(orders: Array, squadron_id: String, waypoints: Array, facing: float) -> void:
	for order in orders:
		if String(order.squadron_id) == squadron_id:
			order.action = "move"; order.waypoints = waypoints.duplicate(true); order.facing_deg = facing; return


func _fire(events: Array, shooter_id: String, target_id: String) -> Dictionary:
	for event in events:
		if String(event.shooter_squadron_id) == shooter_id and String(event.target_squadron_id) == target_id: return event
	return {}
