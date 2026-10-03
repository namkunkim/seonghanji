extends SceneTree

## Task ID: V-73 A5·A6 (docs/07-production/demo-rc-v73-a5-a6.md)
## A5 진형 기동 %의 이동 반영 · A6 무기 능력의 현재(피해 반영) 편성 기준화.
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Movement := preload("res://core/demo_red_cliffs/red_cliffs_movement_resolver.gd")
const Formation := preload("res://core/demo_red_cliffs/red_cliffs_formation_resolver.gd")
const Weapon := preload("res://core/demo_red_cliffs/red_cliffs_weapon_allocation.gd")
const Effects := preload("res://core/demo_red_cliffs/red_cliffs_combat_effects.gd")
const Interception := preload("res://core/demo_red_cliffs/red_cliffs_interception_resolver.gd")
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


func _init() -> void: call_deferred("_run")


func _run() -> void:
	print("V-73 A5·A6 formation mobility and current-composition weapons")
	_test_a5_speed_formula()
	_test_a5_formation_planning()
	_test_a5_battle_preview_and_resolution()
	_test_a6_current_compositions()
	_test_a6_capabilities_and_refresh()
	_test_a6_interception_authority()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)


func _setup() -> Dictionary:
	var loaded := Setup.load_default(); _ok(loaded.ok, "setup loads"); return loaded.setup.duplicate(true)


func _init_core(script, setup: Dictionary):
	var core = script.new(); var result: Dictionary = core.initialize(setup)
	_ok(result.ok, "core initializes: %s" % str(result.get("errors", []))); return core


func _test_a5_speed_formula() -> void:
	var movement = _init_core(Movement, _setup())
	var plain: Dictionary = movement.effective_speed("RC-LIU-SQ-01")
	_eq([int(plain.base_speed), int(plain.mobility_percent), int(plain.effective_speed)], [140, 0, 140], "omitted formation input keeps the G4-02 contract")
	var fast: Dictionary = movement.effective_speed("RC-LIU-SQ-01", 5)
	_eq(int(fast.effective_speed), 147, "FRM-01 +5% applies to movement: floor(140 × 1.05)")
	_eq([int(fast.command_mobility_percent), int(fast.formation_mobility_percent), int(fast.mobility_percent)], [0, 5, 5], "speed receipt separates command and formation mobility")
	_eq(int(movement.effective_speed("RC-LIU-SQ-01", -10).effective_speed), 126, "FRM-03 −10% slows movement")

	var penalized := _setup()
	for faction in penalized.factions:
		if faction.id == "liu_bei": faction.inventory["SHP-05"] = 40
	for squad in penalized.squadrons:
		if squad.id == "RC-LIU-SQ-01":
			squad.composition = [{"ship_type_id": "SHP-05", "count": 30}]; squad.declared_total_cost = 240
	var slow = _init_core(Movement, penalized)
	var cancelled: Dictionary = slow.effective_speed("RC-LIU-SQ-01", 5)
	_eq([int(cancelled.command_mobility_percent), int(cancelled.mobility_percent), int(cancelled.effective_speed)], [-5, 0, 70], "command −5% and formation +5% add before one floor")
	_eq(int(slow.effective_speed("RC-LIU-SQ-01", -10).effective_speed), 59, "stacked penalties: floor(70 × 0.85)")
	_eq(int(slow.effective_speed("RC-LIU-SQ-01", -200).effective_speed), 1, "speed never drops below one")


func _test_a5_formation_planning() -> void:
	var formation = _init_core(Formation, _setup()); var state: Dictionary = formation.initial_state()
	var current: Dictionary = formation.mobility_percents(state)
	_eq([int(current["RC-LIU-SQ-01"]), int(current["RC-LIU-SQ-02"]), int(current["RC-LIU-FC-01"])], [5, -10, 15], "current formation mobility comes from formation rules")
	var kept: Dictionary = formation.planned_mobility_percent("RC-LIU-SQ-01", "FRM-01", state)
	_eq([int(kept.modifier_effectiveness_basis_points), int(kept.mobility_percent)], [10000, 5], "unchanged formation keeps full mobility")
	var changed: Dictionary = formation.planned_mobility_percent("RC-LIU-SQ-01", "FRM-06", state)
	_eq(int(changed.mobility_percent), 15, "under-cap change applies at full effectiveness")
	_ok(not formation.planned_mobility_percent("RC-LIU-SQ-01", "FRM-99", state).ok, "unknown formation rejected")
	var resolved: Dictionary = formation.resolve_orders([
		{"squadron_id": "RC-LIU-SQ-01", "formation_id": "FRM-06"}, {"squadron_id": "RC-LIU-SQ-02", "formation_id": "FRM-03"},
		{"squadron_id": "RC-LIU-FC-01", "formation_id": "FRM-06"}, {"squadron_id": "RC-SUN-SQ-01", "formation_id": "FRM-02"},
		{"squadron_id": "RC-CAO-SQ-01", "formation_id": "FRM-04"}], state, 1)
	_ok(resolved.ok, "formation resolution succeeds")
	_eq(int(formation.mobility_percents(resolved.formation_state)["RC-LIU-SQ-01"]), int(changed.mobility_percent), "planned value matches resolution-start value")


func _test_a5_battle_preview_and_resolution() -> void:
	var battle := Battle.new(); _ok(battle.initialize(_setup()).ok, "battle initializes")
	var preview: Dictionary = battle.movement_preview("RC-LIU-SQ-01", [[900, 590]], 0)
	_eq(int(preview.movement_budget), 147, "preview applies the current FRM-01 +5%")
	_ok(battle.set_formation_order("RC-LIU-SQ-01", "FRM-06").ok, "draft formation change staged")
	var planned: Dictionary = battle.set_order_move("RC-LIU-SQ-01", [[900, 590]], 0)
	_eq(int(planned.movement_budget), 161, "preview follows the drafted FRM-06 +15%: floor(140 × 1.15)")
	_ok(planned.predicted_position != preview.predicted_position, "the faster drafted formation predicts a farther stop")
	_ok(battle.submit_command_draft().ok, "Liu draft submits")
	_ok(battle.submit_sun_control_choice("ai").ok, "Sun AI selected")
	var receipt: Dictionary = battle.resolve_turn()
	_ok(receipt.ok, "turn resolves: %s" % str(receipt.get("errors", [])))
	_eq(battle.live_navigation()["RC-LIU-SQ-01"].position, planned.predicted_position, "resolution moves exactly as the formation-adjusted preview predicted")


func _test_a6_current_compositions() -> void:
	var effects = _init_core(Effects, _setup()); var state: Dictionary = effects.initial_state()
	var untouched: Dictionary = effects.current_compositions(state)
	_eq(untouched["RC-SUN-SQ-01"].back(), {"ship_type_id": "SHP-08", "count": 8, "mission_equipment_id": "FAST-EQ-TORPEDO"}, "mission equipment survives the projection")
	var damaged := state.duplicate(true)
	damaged.squadrons["RC-SUN-SQ-01"].current_composition = [{"ship_type_id": "SHP-04", "count": 2}, {"ship_type_id": "SHP-08", "count": 3}]
	var rows: Array = effects.current_compositions(damaged)["RC-SUN-SQ-01"]
	var counts := {}; for row in rows: counts[String(row.ship_type_id)] = int(row.count)
	_eq(counts, {"SHP-01": 0, "SHP-03": 0, "SHP-04": 2, "SHP-06": 0, "SHP-07": 0, "SHP-08": 3}, "losses apply per setup component")
	_eq(String(rows.back().get("mission_equipment_id", "")), "FAST-EQ-TORPEDO", "surviving fast craft keep equipment")
	_eq(state.squadrons["RC-SUN-SQ-01"].original_composition.size(), 6, "original composition stays immutable")


func _test_a6_capabilities_and_refresh() -> void:
	var setup := _setup(); var weapon = _init_core(Weapon, setup); var effects = _init_core(Effects, setup)
	var state: Dictionary = weapon.initial_state()
	var effect_state: Dictionary = effects.initial_state()
	var before: Dictionary = _capability(weapon.interception_policy(state), "RC-CAO-SQ-01", "line_fire")
	_eq([String(before.platform_id), int(before.range)], ["SHP-01", 190], "intact squadron fires line from the assault carrier")
	# G8-00 loses ships in ship-type order, so the first two losses are the two SHP-01.
	effect_state.squadrons["RC-CAO-SQ-01"].current_composition = effects._composition_after_losses(effect_state.squadrons["RC-CAO-SQ-01"].original_composition, 2)
	var current: Dictionary = effects.current_compositions(effect_state)
	var after: Dictionary = _capability(weapon.interception_policy(state, current), "RC-CAO-SQ-01", "line_fire")
	_eq([String(after.platform_id), int(after.range)], ["SHP-04", 180], "carrier loss drops line fire to the line ship 180 range")
	var sun_unchanged: Dictionary = _capability(weapon.interception_policy(state, current), "RC-SUN-SQ-01", "line_fire")
	_eq(int(sun_unchanged.range), 190, "undamaged squadrons keep their capability")
	var unchanged: Dictionary = weapon.refresh_capabilities(state, current, 1)
	_ok(unchanged.ok and unchanged.weapon_capability_events.is_empty(), "same weapon categories → no refresh event")
	_eq(unchanged.weapon_allocation_state, state, "same weapon categories → allocations untouched")

	# Lose SHP-01·02·03 (2+2+6): artillery disappears entirely.
	effect_state.squadrons["RC-CAO-SQ-01"].current_composition = effects._composition_after_losses(effect_state.squadrons["RC-CAO-SQ-01"].original_composition, 10)
	current = effects.current_compositions(effect_state)
	_eq(weapon.available_categories("RC-CAO-SQ-01", current), ["intercept", "line_fire"], "availability follows current composition")
	var refreshed: Dictionary = weapon.refresh_capabilities(state, current, 3)
	var row: Dictionary = refreshed.weapon_allocation_state["RC-CAO-SQ-01"]
	_eq(int(row.allocations.artillery), 0, "lost weapon category is zeroed")
	_eq(int(row.allocations.intercept) + int(row.allocations.line_fire), 10000, "remaining categories total exactly 10000 bps")
	_eq(row.available_categories, ["intercept", "line_fire"], "state row records current availability")
	_eq(refreshed.weapon_capability_events.size(), 1, "one capability change event")
	_eq(String(refreshed.weapon_capability_events[0].squadron_id), "RC-CAO-SQ-01", "event names the damaged squadron")
	var orders: Array = []
	for squadron_id in refreshed.weapon_allocation_state:
		var source: Dictionary = refreshed.weapon_allocation_state[squadron_id]
		orders.append({"squadron_id": squadron_id, "allocations": source.allocations.duplicate(true), "hold_fire": bool(source.hold_fire)})
	_ok(weapon.resolve_orders(orders, refreshed.weapon_allocation_state, 4, current).ok, "refreshed allocations validate against current composition")
	_ok(not weapon.resolve_orders(_orders(state), state, 4, current).ok, "stale artillery allocation is rejected once artillery is gone")
	var conformed: Array = weapon.conform_orders(_orders(state), current)
	_ok(weapon.resolve_orders(conformed, state, 4, current).ok, "battle-side conformance turns stale orders into valid current-composition orders")
	_eq(_orders(state).filter(func(o): return o.squadron_id != "RC-CAO-SQ-01"), conformed.filter(func(o): return o.squadron_id != "RC-CAO-SQ-01"), "conformance leaves undamaged squadrons untouched")
	var forged: Array = _orders(state)
	for order in forged:
		if order.squadron_id == "RC-CAO-SQ-01": order.allocations = {"artillery": 0, "intercept": 0, "line_fire": 0, "torpedo": 10000}
	_ok(not weapon.resolve_orders(weapon.conform_orders(forged, current), state, 4, current).ok, "never-available weapons are not laundered by conformance")
	var preset: Dictionary = weapon.apply_preset(refreshed.weapon_allocation_state, "RC-CAO-SQ-01", "balanced")
	_ok(preset.ok and int(preset.row.allocations.artillery) == 0, "presets use the row's current availability")

	effect_state.squadrons["RC-CAO-SQ-01"].current_composition = []
	var wiped: Dictionary = weapon.refresh_capabilities(state, effects.current_compositions(effect_state), 5)
	var wiped_row: Dictionary = wiped.weapon_allocation_state["RC-CAO-SQ-01"]
	_ok(wiped_row.available_categories.is_empty() and bool(wiped_row.hold_fire) and _sum(wiped_row.allocations) == 0, "no surviving weapons → automatic hold fire")


func _test_a6_interception_authority() -> void:
	var setup := _setup(); var weapon = _init_core(Weapon, setup); var effects = _init_core(Effects, setup)
	var interception = _init_core(Interception, setup); var movement = _init_core(Movement, setup)
	var orders: Array = []
	for squad in setup.squadrons:
		if bool(squad.get("operational", true)): orders.append({"squadron_id": String(squad.id), "action": "hold"})
	var moved: Dictionary = movement.resolve_orders(orders, movement.initial_navigation())
	_ok(moved.ok, "hold movement resolves")
	var effect_state: Dictionary = effects.initial_state()
	effect_state.squadrons["RC-CAO-SQ-01"].current_composition = effects._composition_after_losses(effect_state.squadrons["RC-CAO-SQ-01"].original_composition, 2)
	var current: Dictionary = effects.current_compositions(effect_state); var state: Dictionary = weapon.initial_state()
	_ok(interception.resolve(moved.events, moved.live_navigation, interception.initial_detection_state(), 1,
		weapon.interception_policy(state, current), {}, {}, [], current).ok, "current-composition policy is the authority")
	_ok(not interception.resolve(moved.events, moved.live_navigation, interception.initial_detection_state(), 1,
		weapon.interception_policy(state), {}, {}, [], current).ok, "stale setup-composition capability is rejected")


func _capability(policy: Dictionary, squadron_id: String, weapon_id: String) -> Dictionary:
	for capability in policy[squadron_id].capabilities:
		if String(capability.weapon_id) == weapon_id: return capability
	return {}


func _orders(state: Dictionary) -> Array:
	var result: Array = []
	for squadron_id in state:
		result.append({"squadron_id": squadron_id, "allocations": state[squadron_id].allocations.duplicate(true), "hold_fire": bool(state[squadron_id].hold_fire)})
	return result


func _sum(values: Dictionary) -> int:
	var total := 0
	for value in values.values(): total += int(value)
	return total
