extends SceneTree

## Task ID: DEMO-RC-G4-02
## 자유 좌표·다중 경유점·방향 이동 판정 및 전대별 명령 초안 Phase A.
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Resolver := preload("res://core/demo_red_cliffs/red_cliffs_movement_resolver.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")

var _pass := 0
var _fail := 0


func _ok(value: bool, label: String) -> void:
	if value: _pass += 1
	else:
		_fail += 1
		print("  x %s" % label)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])


func _near(actual: float, expected: float, label: String) -> void:
	_ok(is_equal_approx(actual, expected), "%s (%s != %s)" % [label, actual, expected])


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("DEMO-RC-G4-02 movement core")
	_test_rules_speed_and_preview()
	_test_resolver_order_partial_and_atomicity()
	_test_command_draft_and_live_persistence()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)


func _setup() -> Dictionary:
	var loaded := Setup.load_default()
	_ok(bool(loaded.get("ok", false)), "G3 applied setup fixture loads")
	return loaded.get("setup", {})


func _resolver(setup: Dictionary):
	var resolver = Resolver.new()
	_ok(bool(resolver.initialize(setup).get("ok", false)), "movement resolver initializes")
	return resolver


func _test_rules_speed_and_preview() -> void:
	var setup := _setup(); var resolver = _resolver(setup)
	var rules: Dictionary = resolver.rules_snapshot()
	_eq(rules.get("profile_id"), "normal-demo-movement-v1", "movement balance profile explicit")
	_eq(int(rules.get("max_waypoints", 0)), 5, "maximum waypoint count is five")
	_eq(rules.get("base_speed_by_ship_type", {}).size(), 8, "all eight ship speeds are data-driven")
	var speed: Dictionary = resolver.effective_speed("RC-LIU-SQ-01")
	_eq(int(speed.base_speed), 140, "slowest present ship determines base speed")
	_eq(int(speed.mobility_percent), 0, "under-cap formation has no mobility penalty")
	_eq(int(speed.effective_speed), 140, "unpenalized speed retained")
	var navigation: Dictionary = resolver.initial_navigation()
	var preview: Dictionary = resolver.movement_preview("RC-LIU-SQ-01", [[410, 590], [510, 590]], 270, navigation)
	_ok(preview.ok, "one-to-five waypoint preview succeeds")
	_eq(preview.waypoints.size(), 2, "preview preserves multiple waypoints")
	_near(float(preview.total_distance), 200.0, "preview calculates polyline distance")
	_eq(int(preview.movement_budget), 140, "preview exposes one-turn path budget")
	_ok(not preview.within_budget and not preview.path_complete, "over-budget route is explicit partial")
	_eq(preview.predicted_position, [450.0, 590.0], "preview stops partway on current segment")
	_near(float(preview.remaining_distance), 60.0, "preview exposes remaining path distance")
	_near(float(preview.heading_deg), 0.0, "preview exposes first nonzero path heading")
	_near(float(preview.facing_deg), 270.0, "preview preserves requested final facing")
	_eq(int(preview.eta_turns), 2, "preview exposes deterministic ETA")

	var penalized := setup.duplicate(true)
	for faction in penalized.factions:
		if faction.id == "liu_bei": faction.inventory["SHP-05"] = 40
	for squad in penalized.squadrons:
		if squad.id == "RC-LIU-SQ-01":
			squad.composition = [{"ship_type_id": "SHP-05", "count": 30}]
			squad.declared_total_cost = 240
	var penalized_resolver = _resolver(penalized)
	var penalized_speed: Dictionary = penalized_resolver.effective_speed("RC-LIU-SQ-01")
	_eq(int(penalized_speed.base_speed), 70, "penalized speed still starts from slowest ship")
	_eq(int(penalized_speed.mobility_percent), -5, "G3 tier-one mobility penalty reused")
	_eq(int(penalized_speed.effective_speed), 66, "mobility penalty floors deterministic speed")

	for bad in [[], [[310, 590], [320, 590], [330, 590], [340, 590], [350, 590], [360, 590]]]:
		_ok(not resolver.movement_preview("RC-LIU-SQ-01", bad, 0, navigation).ok, "waypoint count boundary rejects invalid input")
	for bad_point in [[-1, 20], [1601, 20], [20], [NAN, 20]]:
		_ok(not resolver.movement_preview("RC-LIU-SQ-01", [bad_point], 0, navigation).ok, "finite battlefield bounds reject invalid waypoint")
	for bad_facing in [-1, 360, INF, NAN]:
		_ok(not resolver.movement_preview("RC-LIU-SQ-01", [[310, 590]], bad_facing, navigation).ok, "facing must be finite in [0,360)")


func _test_resolver_order_partial_and_atomicity() -> void:
	var setup := _setup(); var resolver = _resolver(setup); var navigation: Dictionary = resolver.initial_navigation()
	var original_digest := JSON.stringify(navigation)
	var orders := _all_hold_orders(setup)
	for order in orders:
		if order.squadron_id == "RC-LIU-SQ-01":
			order.action = "move"; order.waypoints = [[510, 590]]; order.facing_deg = 90
	var result: Dictionary = resolver.resolve_orders(orders, navigation)
	_ok(result.ok, "mixed move and AI hold orders resolve")
	_eq(JSON.stringify(navigation), original_digest, "resolver does not mutate caller navigation")
	_eq(result.events.size(), setup.squadrons.size(), "receipt contains every operational squadron")
	var resolved_ids: Array = []
	for event in result.events: resolved_ids.append(String(event.squadron_id))
	_eq(resolved_ids, ["RC-LIU-FC-01", "RC-LIU-SQ-01", "RC-SUN-SQ-01", "RC-LIU-SQ-02", "RC-CAO-SQ-01"], "fast-craft then effective speed descending and stable ID resolution order")
	var move := _event(result.events, "RC-LIU-SQ-01")
	_eq(move.from, [310.0, 590.0], "movement receipt exposes live origin")
	_eq(move.to, [450.0, 590.0], "movement receipt exposes partial destination")
	_near(float(move.actual_distance), 140.0, "movement consumes exact budget")
	_ok(not move.path_complete and float(move.remaining_distance) > 0.0, "movement receipt marks partial path")
	_near(float(move.facing_deg), 90.0, "resolved move persists requested facing")
	var hold := _event(result.events, "RC-CAO-SQ-01")
	_eq(hold.action, "hold", "AI order remains hold")
	_eq(hold.from, hold.to, "hold preserves position")
	var bad_orders := orders.duplicate(true); bad_orders.pop_back()
	var bad: Dictionary = resolver.resolve_orders(bad_orders, navigation)
	_ok(not bad.ok, "missing operational order rejected atomically")
	_eq(JSON.stringify(navigation), original_digest, "invalid resolution leaves caller navigation unchanged")


func _test_command_draft_and_live_persistence() -> void:
	var setup := _setup(); var battle = Battle.new()
	_ok(battle.initialize(setup).ok, "turn battle initializes movement boundary")
	_eq(battle.current_direct_faction_id(), "liu_bei", "Liu is current direct-control faction")
	var summary: Dictionary = battle.command_draft_summary()
	_eq(summary, {"faction_id": "liu_bei", "total": 3, "hold_count": 3, "move_count": 0, "estimated_fire_count": 0, "all_orders_ready": true}, "new direct-control draft includes independent fast-craft HOLD")
	_eq(battle.command_order("RC-LIU-SQ-02").order.action, "hold", "per-squad query exposes persisted hold")
	var before := battle.digest()
	_ok(not battle.set_order_move("RC-LIU-SQ-01", [], 0).ok, "invalid move draft rejected")
	_ok(not battle.set_order_hold("RC-SUN-SQ-01").ok, "other faction draft edit rejected")
	_eq(battle.digest(), before, "invalid draft mutations are atomic")
	var waypoints := [[510, 590]]
	var preview: Dictionary = battle.set_order_move("RC-LIU-SQ-01", waypoints, 90)
	_ok(preview.ok and not preview.path_complete, "valid move staged with public preview receipt")
	waypoints[0][0] = 999
	_eq(battle.command_order("RC-LIU-SQ-01").order.waypoints, [[510, 590]], "staged per-squad move is deep copied")
	_eq(battle.command_order("RC-LIU-SQ-02").order.action, "hold", "editing one squad preserves another squad draft")
	_eq(battle.command_draft_summary().move_count, 1, "draft summary updates move count")
	_ok(battle.submit_command_draft().ok, "Liu command draft submits")
	_eq(battle.current_direct_faction_id(), "", "Sun prompt has no direct-control faction yet")
	_ok(battle.submit_sun_control_choice("ai").ok, "Sun AI selection accepted")
	var receipt: Dictionary = battle.resolve_turn()
	_ok(receipt.ok, "turn resolves movement")
	_ok(not receipt.rules_pending.has("movement"), "movement removed from pending rule list")
	_ok(receipt.rules_pending.has("weapon_fire"), "combat rules remain explicitly pending")
	_ok(not receipt.has("winner") and not receipt.has("damage") and not receipt.has("casualties"), "movement resolution invents no combat or result")
	_eq(battle.live_navigation()["RC-LIU-SQ-01"].position, [450.0, 590.0], "partial live position persists after resolution")
	_eq(float(battle.live_navigation()["RC-LIU-SQ-01"].facing_deg), 90.0, "live facing persists after resolution")
	_ok(battle.set_sun_prompt_enabled(false).ok, "AI prompt policy is scheduled for the next turn")
	_ok(battle.continue_turn().ok, "next turn opens")
	_eq(battle.current_direct_faction_id(), "liu_bei", "direct control returns to Liu")
	var next_preview: Dictionary = battle.movement_preview("RC-LIU-SQ-01", [[500, 590]], 180)
	_eq(next_preview.predicted_position, [500.0, 590.0], "next-turn preview starts at persisted live position")
	_ok(battle.set_order_move("RC-LIU-SQ-01", [[500, 590]], 180).ok, "second-turn move stages")
	_ok(battle.submit_command_draft().ok, "second-turn draft submits")
	_eq(battle.phase(), "resolution", "saved AI policy creates stable Sun/Cao holds")
	var log: Dictionary = battle.turn_log()[1]
	_ok(not log.sun_orders.is_empty() and not log.cao_orders.is_empty(), "AI hold orders are present before resolution")
	_ok(battle.resolve_turn().ok, "second-turn movement resolves")
	_eq(battle.live_navigation()["RC-LIU-SQ-01"].position, [500.0, 590.0], "live position persists across turn resolutions")


func _all_hold_orders(setup: Dictionary) -> Array:
	var result: Array = []
	for squad in setup.squadrons:
		if bool(squad.get("operational", true)): result.append({"squadron_id": String(squad.id), "action": "hold"})
	return result


func _event(events: Array, squadron_id: String) -> Dictionary:
	for event in events:
		if String(event.get("squadron_id", "")) == squadron_id: return event
	return {}
