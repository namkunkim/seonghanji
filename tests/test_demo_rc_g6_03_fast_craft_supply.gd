extends SceneTree

## DEMO-RC-G6-03 — 자동 보급 영역·한 턴 정박·처리량·결정론적 우선순위
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Supply := preload("res://core/demo_red_cliffs/red_cliffs_fast_craft_supply.gd")
const Resources := preload("res://core/demo_red_cliffs/red_cliffs_combat_resources.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")
var _pass := 0
var _fail := 0
func _ok(v: bool, label: String) -> void:
	if v: _pass += 1
	else: _fail += 1; print("  x %s" % label)
func _eq(a, e, label: String) -> void: _ok(a == e, "%s (%s != %s)" % [label, str(a), str(e)])
func _init() -> void: call_deferred("_run")
func _run() -> void:
	print("DEMO-RC-G6-03 — 자동 보급 영역·한 턴 정박·처리량·결정론적 우선순위")
	_test_sources_hold_entry_and_interrupt()
	_test_capacity_priority_and_no_overfill()
	_test_actual_finite_refill_and_shuffle()
	_test_battle_end_of_turn_and_viewer_safety()
	print("PASS %d / FAIL %d" % [_pass, _fail]); quit(Harness.EXIT_FAIL if _fail else Harness.EXIT_PASS)

func _fixture() -> Dictionary:
	var loaded := Setup.load_default(); _ok(loaded.ok, "setup loads"); return loaded.setup.duplicate(true)
func _resolver(setup: Dictionary):
	var r = Supply.new(); _ok(r.initialize(setup).ok, "supply initializes"); return r
func _nav(setup: Dictionary) -> Dictionary:
	var out := {}
	for squad in setup.squadrons: out[String(squad.id)] = {"squadron_id":String(squad.id), "faction_id":String(squad.faction_id), "position":squad.initial_position.duplicate(), "facing_deg":float(squad.get("initial_facing_deg", 0.0))}
	return out

func _test_sources_hold_entry_and_interrupt() -> void:
	var setup := _fixture(); var r = _resolver(setup); var nav := _nav(setup); var sources: Array = r.source_zones(nav)
	var supply_ship := _source(sources, "SUPPLY_SHIP-RC-LIU-SQ-02"); var carrier := _source(sources, "CARRIER-RC-CAO-SQ-01")
	_eq(supply_ship.radius, 140, "supply ship radius is 140")
	_eq(supply_ship.capacity_squadrons_per_turn, 1, "one supply ship gives one throughput")
	_eq(carrier.radius, 100, "carrier radius is 100")
	_eq(carrier.capacity_squadrons_per_turn, 2, "two carriers give two throughput")
	_eq(_source(sources, "RC-BASE-LIU-01").capacity_squadrons_per_turn, 4, "fixed base throughput is four")
	var state: Dictionary = r.initial_state(nav)
	_eq(state.queue["RC-LIU-FC-01"].docked_turns, 0, "starting inside registers before first resolution")
	var held: Dictionary = r.resolve(state, nav, nav, _moves(nav), 1)
	_ok(held.events.any(func(e): return e.status == "completed"), "target and provider HOLD completes turn-one supply")
	var moved_nav := nav.duplicate(true); moved_nav["RC-LIU-FC-01"].position = [300, 720]
	var entry_state := r.initial_state(nav); entry_state.queue.clear()
	var entered: Dictionary = r.resolve(entry_state, nav, moved_nav, _moves(nav, {"RC-LIU-FC-01":80.0}), 1)
	_eq(entered.state.queue["RC-LIU-FC-01"].docked_turns, 0, "outside movement into zone only registers")
	_ok(not entered.events.any(func(e): return e.status == "completed"), "entry turn cannot complete")
	var left_nav := moved_nav.duplicate(true); left_nav["RC-LIU-FC-01"].position = [800, 800]
	var left: Dictionary = r.resolve(entered.state, moved_nav, left_nav, _moves(nav, {"RC-LIU-FC-01":500.0}), 2)
	_ok(left.events.any(func(e): return e.status == "interrupted"), "leaving zone interrupts progress")
	_ok(not left.state.queue.has("RC-LIU-FC-01"), "interrupted queue is removed")

func _test_capacity_priority_and_no_overfill() -> void:
	var setup := _fixture(); var r = _resolver(setup); var nav := _nav(setup); var state: Dictionary = r.initial_state(nav)
	state.resources = {}; state.queue = {}; state.events_by_turn = {}; state.next_event_serial = 1
	for row in [["FC-A", 4000, 1], ["FC-B", 2000, 2], ["FC-C", 2000, 1]]:
		var sid := String(row[0]); state.resources[sid] = {"squadron_id":sid,"faction_id":"liu_bei","fuel_basis_points":int(row[1]),"maximum_basis_points":10000}
		state.queue[sid] = {"squadron_id":sid,"faction_id":"liu_bei","source_id":"CARRIER-RC-SUN-SQ-01","entry_turn":int(row[2]),"docked_turns":0}
		nav[sid] = {"position":[410,500]}
	var holds := _moves(nav)
	var result: Dictionary = r.resolve(state, nav, nav, holds, 3)
	var completed: Array = result.events.filter(func(e): return e.status == "completed")
	_eq(completed.size(), 1, "one allied carrier craft serves one squadron")
	_eq(completed[0].squadron_id, "FC-C", "priority is raw fuel then earlier entry then stable ID")
	_eq(result.state.resources["FC-C"].fuel_basis_points, 10000, "fuel refills only to maximum")
	_eq(completed[0].fuel_granted_basis_points, 8000, "receipt discloses exact authorized fuel delta")
	var visible: Dictionary = r.visible("liu_bei", result.state, nav)
	var next_priority: Dictionary = visible.queue.filter(func(row): return row.squadron_id == "FC-B")[0]
	_eq(next_priority.priority_rank, 1, "viewer receipt provides source-local priority rank")
	_eq(next_priority.capacity_squadrons_per_turn, 1, "viewer receipt provides capacity without UI calculation")
	_eq(JSON.stringify(result.state).contains("Vector2"), false, "supply state uses save-safe primitives")
	var out_back: Dictionary = r.initial_state(nav)
	var out_back_result := r.resolve(out_back, nav, nav, _moves(nav, {"RC-LIU-FC-01":25.0}), 1)
	_ok(not out_back_result.events.any(func(e): return e.status == "completed"), "actual-distance out-and-back cannot count as HOLD")
	var provider_nav := nav.duplicate(true); provider_nav["RC-LIU-FC-01"].position = [200,600]
	var provider_state := r.initial_state(provider_nav)
	_eq(provider_state.queue["RC-LIU-FC-01"].source_id, "SUPPLY_SHIP-RC-LIU-SQ-02", "provider-movement fixture selects supply ship")
	var provider_moves := _moves(provider_nav, {"RC-LIU-SQ-02":20.0})
	var provider_interrupted := r.resolve(provider_state, provider_nav, provider_nav, provider_moves, 1)
	_ok(not provider_interrupted.events.any(func(e): return e.status == "completed"), "provider out-and-back also prevents docking completion")
	_ok(provider_interrupted.events.any(func(e): return e.reason == "provider_moved"), "provider movement interruption is explicit")

func _test_battle_end_of_turn_and_viewer_safety() -> void:
	var battle = Battle.new(); _ok(battle.initialize(_fixture()).ok, "battle initializes")
	var before_resources: Dictionary = battle.snapshot().combat_resource_state.duplicate(true)
	_ok(battle.submit_command_draft().ok and battle.submit_sun_control_choice("ai").ok, "turn reaches resolution")
	var receipt: Dictionary = battle.resolve_turn(); _ok(receipt.ok, "battle resolves supply after movement and fire")
	_ok(receipt.fast_craft_supply_events.any(func(e): return e.status == "completed"), "battle receipt includes supply completion")
	var completion: Dictionary = receipt.fast_craft_supply_events.filter(func(e): return e.status == "completed")[0]
	_ok(completion.get("combat_resource_refill") is Dictionary, "raw completion carries authoritative G4 refill receipt")
	_eq(battle.snapshot().combat_resource_state, before_resources, "fast-craft supply does not fabricate energy or heat changes")
	var liu: Dictionary = battle.viewer_fast_craft_supply("liu_bei"); var cao: Dictionary = battle.viewer_fast_craft_supply("cao_cao")
	_eq(liu.resources.size(), 1, "viewer sees own fast-craft resources")
	_eq(cao.resources.size(), 0, "viewer cannot see hostile fast-craft resources")
	_ok(liu.sources.any(func(s): return s.faction_id == "sun_quan"), "Liu sees allied Sun mutual supply zones")
	_ok(not cao.sources.any(func(s): return s.faction_id != "cao_cao"), "Cao sees self-only supply zones")
	var viewer_completion: Dictionary = liu.events.filter(func(e): return e.status == "completed")[0]
	_ok(viewer_completion.get("combat_resource_refill") is Dictionary, "viewer completion retains authoritative G4 refill receipt")

func _test_actual_finite_refill_and_shuffle() -> void:
	var setup := _fixture(); var fc: Dictionary
	for squad in setup.squadrons:
		if String(squad.id) == "RC-LIU-FC-01": fc = squad
	fc.composition[0].mission_equipment_id = "FAST-EQ-TORPEDO"; fc.declared_total_cost = 24; fc.calculated_total_cost = 24
	var resources = Resources.new(); _ok(resources.initialize(setup).ok, "G4 resources initialize for torpedo fast craft")
	var state: Dictionary = resources.initial_state()
	var current_shot := {"event_id":"CURRENT-TURN-FC", "turn":1, "outcome":"shot_authorized", "shooter_squadron_id":"RC-LIU-FC-01", "target_squadron_id":"TARGET", "selected_weapon_id":"torpedo", "fire_control_snapshot":{"selected_platform_id":"FAST-EQ-TORPEDO"}}
	var consumed: Dictionary = resources.resolve_shots([current_shot], state, 1); _eq(consumed.authorized_events.size(), 1, "current-turn fast-craft shot consumes finite special first")
	var energy := int(consumed.resource_state["RC-LIU-FC-01"].shared.energy); var heat := int(consumed.resource_state["RC-LIU-FC-01"].shared.heat)
	var refilled: Dictionary = resources.refill_fast_craft_finite(["RC-LIU-FC-01"], consumed.resource_state, 1)
	_ok(refilled.ok, "actual G4 finite resource refill resolves")
	_eq(refilled.resource_state["RC-LIU-FC-01"].weapons.torpedo.special, 12, "torpedo special refills to actual G4 capacity")
	_eq(refilled.resource_state["RC-LIU-FC-01"].shared.energy, energy, "refill leaves energy unchanged")
	_eq(refilled.resource_state["RC-LIU-FC-01"].shared.heat, heat, "refill leaves heat unchanged")
	_eq(refilled.events[0].combat_resource_refill.torpedo.special_granted, 1, "actual finite delta is receipted")
	_eq(consumed.authorized_events[0].resource_reservation.after.weapons.torpedo.special, 11, "end-turn refill does not rewrite current-turn shot result")
	var shot := {"event_id":"NEXT-TURN-FC", "turn":2, "outcome":"shot_authorized", "shooter_squadron_id":"RC-LIU-FC-01", "target_squadron_id":"TARGET", "selected_weapon_id":"torpedo", "fire_control_snapshot":{"selected_platform_id":"FAST-EQ-TORPEDO"}}
	var next_turn: Dictionary = resources.resolve_shots([shot], refilled.resource_state, 2)
	_eq(next_turn.authorized_events.size(), 1, "refilled finite special is usable on the next turn")
	_eq(refilled.events[0].combat_resource_before.torpedo.special, 11, "refill receipt preserves post-consumption pre-refill snapshot")
	var supply = _resolver(_fixture()); var nav := _nav(_fixture()); var base: Dictionary = supply.initial_state(nav)
	base.resources = {}; base.queue = {}; base.events_by_turn = {}; base.next_event_serial = 1
	for sid in ["FC-A", "FC-B"]:
		base.resources[sid] = {"squadron_id":sid,"faction_id":"liu_bei","fuel_basis_points":2000,"maximum_basis_points":10000}
		base.queue[sid] = {"squadron_id":sid,"faction_id":"liu_bei","source_id":"CARRIER-RC-SUN-SQ-01","entry_turn":1,"docked_turns":0}; nav[sid] = {"position":[410,500]}
	var moves := _moves(nav)
	var shuffled := base.duplicate(true); shuffled.resources = {"FC-B":base.resources["FC-B"].duplicate(true),"FC-A":base.resources["FC-A"].duplicate(true)}; shuffled.queue = {"FC-B":base.queue["FC-B"].duplicate(true),"FC-A":base.queue["FC-A"].duplicate(true)}; moves.reverse()
	_eq(JSON.stringify(supply.resolve(base, nav, nav, _moves(nav), 1)), JSON.stringify(supply.resolve(shuffled, nav, nav, moves, 1)), "source/resource/movement input order cannot change receipt or digest")

func _source(sources: Array, id: String) -> Dictionary:
	for source in sources:
		if String(source.source_id) == id: return source
	return {}

func _moves(nav: Dictionary, distances: Dictionary = {}) -> Array:
	var events: Array = []; var ids: Array = nav.keys(); ids.sort()
	for sid in ids: events.append({"squadron_id":String(sid), "actual_distance":float(distances.get(sid, 0.0))})
	return events
