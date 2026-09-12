extends SceneTree

const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Effects := preload("res://core/demo_red_cliffs/red_cliffs_combat_effects.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")
const Terrain := preload("res://core/demo_red_cliffs/red_cliffs_terrain_resolver.gd")
const Detection := preload("res://core/demo_red_cliffs/red_cliffs_detection_resolver.gd")

var passed := 0
var failed := 0
func check(value: bool, label: String) -> void:
	if value: passed += 1
	else: failed += 1; print("  x %s" % label)

func _init() -> void:
	var loaded := Setup.load_default(); check(loaded.ok, "default setup")
	var effects := Effects.new(); var initialized: Dictionary = effects.initialize(loaded.setup)
	check(initialized.ok, "effects initializes: %s" % str(initialized.get("errors", [])))
	if initialized.ok:
		var state: Dictionary = effects.initial_state()
		check(not state.squadrons.is_empty(), "immutable combat baseline created")
		var visible: Dictionary = effects.visible("liu_bei", state, [], 1)
		check(visible.ok and visible.own_squadrons.size() == 3, "own exact projection")
		check(not JSON.stringify(visible).contains("\"winner\":"), "projection contains no winner")
		_test_chain_atomic_effects(effects, state, loaded.setup)
		_test_shot_determinism(effects, state)
	var battle := Battle.new(); var battle_initialized: Dictionary = battle.initialize(loaded.setup)
	check(battle_initialized.ok, "battle integrates effects: %s" % str(battle_initialized.get("errors", [])))
	if battle_initialized.ok:
		var public: Dictionary = battle.viewer_combat_effects("liu_bei")
		check(public.ok and public.has("phase"), "battle public API available")
		for turn_number in range(1, 21):
			var submitted: Dictionary = battle.submit_command_draft()
			check(submitted.ok, "twenty-turn command %d" % turn_number)
			if turn_number == 1: check(battle.submit_sun_control_choice("no", true).ok, "persistent allied AI selected")
			var resolution: Dictionary = battle.resolve_turn()
			check(resolution.ok, "twenty-turn effects resolve %d: %s" % [turn_number, str(resolution.get("errors", []))])
			if not resolution.ok: break
			if turn_number < 20: check(battle.continue_turn().ok, "twenty-turn boundary %d" % turn_number)
	print("PASS %d / FAIL %d" % [passed, failed])
	quit(Harness.EXIT_FAIL if failed else Harness.EXIT_PASS)

func _test_chain_atomic_effects(effects, state: Dictionary, setup: Dictionary) -> void:
	var target_id := "RC-CAO-SQ-01"
	var trigger := {"event_id":"CHAIN-TRIGGER-01","event_type":"chain_explosion_triggered","turn":1,
		"source_squadron_id":"RC-SUN-SQ-01","target_squadron_id":target_id,"conditions":[],"probability_roll_used":false,"irreversible":true,
		"effect_intents":["reactor_chain_blast","morale_shock","sensor_disruption","temporary_terrain_hazard"],"effects_pending":["commander_casualties","victory"]}
	var navigation := {target_id:{"position":[700, 100]}}
	var before_digest := JSON.stringify(state)
	var resolved: Dictionary = effects.resolve(state, [], [trigger], navigation, {}, 1)
	check(resolved.ok, "chain batch resolves atomically")
	if not resolved.ok: return
	var before: Dictionary = state.squadrons[target_id]; var after: Dictionary = resolved.state.squadrons[target_id]
	check(int(after.hull_points) == int(before.maximum_hull_points) * 60 / 100, "chain applies 40 percent pre-damage hull")
	var expected_morale := maxi(0, 10000 - 3500 - int(after.casualties_total) * 200)
	check(int(after.morale_basis_points) == expected_morale and String(after.morale_status) == ("shaken" if expected_morale >= 3000 else "retreating"), "chain and ship losses apply frozen morale costs")
	check(effects.sensor_modifier_percent(resolved.state, target_id, 1) == 0 and effects.sensor_modifier_percent(resolved.state, target_id, 2) == -40, "sensor disruption starts next turn")
	var active: Array = effects.active_temporary_zones(resolved.state, 2)
	check(active.size() == 1 and String(active[0].status) == "active", "hazard is active next turn")
	var terrain := Terrain.new(); check(terrain.initialize(setup).ok, "terrain accepts G8 temporary zones")
	var point_effect: Dictionary = terrain.point_effects([700,100], active)
	check(int(point_effect.movement_cost_basis_points) >= 15000 and int(point_effect.observer_sensor_percent) <= -15, "active hazard changes movement and sensor rules: %s" % str(point_effect))
	var detection := Detection.new(); check(detection.initialize(setup).ok, "detection accepts G8 sensor state")
	var formations: Dictionary = detection.initial_formation_state()
	var normal_detection: Dictionary = detection.evaluate("RC-CAO-SQ-01", "RC-LIU-SQ-01", 400.0, formations, [700,100], [100,100])
	var disrupted_detection: Dictionary = detection.evaluate("RC-CAO-SQ-01", "RC-LIU-SQ-01", 400.0, formations, [700,100], [100,100], -40, active)
	check(disrupted_detection.ok and int(disrupted_detection.authoritative.score) < int(normal_detection.authoritative.score), "next-turn sensor and hazard affect actual detection score")
	check(effects.active_temporary_zones(resolved.state, 4).is_empty(), "hazard expires after two active turns")
	var original_ship_total := 0
	for component in before.original_composition: original_ship_total += int(component.count)
	check(int(after.casualties_total) == int(floor(float(original_ship_total * 40) / 100.0)), "mixed composition casualties use cumulative hull ratio")
	var supply_status: Dictionary = resolved.supply_ship_statuses[0]
	check(String(supply_status.damage_state) == String(after.damage_state) and int(supply_status.original_ship_count) == 3 and int(supply_status.surviving_ship_count) == 3, "squadron hull band applies to every surviving SHP-05")
	check(JSON.stringify(state) == before_digest, "resolve preserves immutable caller state")
	var restored = JSON.parse_string(JSON.stringify(resolved.state))
	check(restored is Dictionary and int(restored.squadrons[target_id].hull_points) == int(resolved.state.squadrons[target_id].hull_points)
		and restored.processed_event_ids == resolved.state.processed_event_ids and restored.temporary_terrain_zones.keys() == resolved.state.temporary_terrain_zones.keys(), "combat effect state survives JSON save round-trip")
	var replay_digest := JSON.stringify(resolved.state)
	var replay: Dictionary = effects.resolve(resolved.state, [], [trigger], navigation, {}, 1)
	check(not replay.ok and JSON.stringify(resolved.state) == replay_digest, "trigger replay rejects without mutation")
	_test_malformed_chain_boundaries(effects, state, trigger, navigation)
	var public: Dictionary = effects.visible("liu_bei", resolved.state,
		[{"contact_id":"CONTACT-EST","state":"estimated","display_position":[710,110],"target_squadron_id":target_id}], 2)
	check(public.contacts.size() == 1 and not public.contacts[0].has("target_squadron_id"), "enemy effect projection removes sealed target id")
	check(public.events.any(func(row): return String(row.viewer_state) == "estimated_contact"), "estimated events retain estimated viewer state")
	check(not JSON.stringify(public).contains(target_id), "public enemy projection contains no raw target id")
	var hidden: Dictionary = effects.visible("liu_bei", resolved.state,
		[{"contact_id":"CONTACT-HIDDEN","state":"expired","display_position":[710,110],"target_squadron_id":target_id}], 2)
	check(hidden.contacts.is_empty() and hidden.events.all(func(row): return String(row.viewer_state) == "public_hazard"), "hidden and expired enemy effects produce zero target rows")
	check(not resolved.victory_inputs.has("winner") and String(resolved.victory_inputs.victory_status) == "pending_G8_01", "victory receipt stops before winner")

func _test_malformed_chain_boundaries(effects, state: Dictionary, valid_trigger: Dictionary, navigation: Dictionary) -> void:
	var variants: Array = []
	var row := valid_trigger.duplicate(true); row.event_id = "CHAIN-FABRICATED-01"; variants.append(row)
	row = valid_trigger.duplicate(true); row.source_squadron_id = "RC-LIU-SQ-01"; variants.append(row)
	row = valid_trigger.duplicate(true); row.target_squadron_id = "RC-LIU-SQ-01"; variants.append(row)
	row = valid_trigger.duplicate(true); row.irreversible = false; variants.append(row)
	row = valid_trigger.duplicate(true); row.probability_roll_used = true; variants.append(row)
	row = valid_trigger.duplicate(true); row.effects_pending = ["damage", "victory"]; variants.append(row)
	row = valid_trigger.duplicate(true); row.conditions = ["fabricated"]; variants.append(row)
	var digest := JSON.stringify(state)
	for index in range(variants.size()):
		var rejected: Dictionary = effects.resolve(state, [], [variants[index]], navigation, {}, 1)
		check(not rejected.ok and JSON.stringify(state) == digest, "fabricated chain payload %d rejects atomically" % index)

func _test_shot_determinism(effects, state: Dictionary) -> void:
	var shot := {"event_id":"SHOT-DETERMINISTIC-01","turn":1,"outcome":"shot_authorized","shooter_squadron_id":"RC-LIU-SQ-01",
		"target_squadron_id":"RC-CAO-SQ-01","selected_weapon_id":"line_fire","formation_modifier":{"shooter":{"fire_percent":0},"target":{"total_defense_percent":0}},
		"command_penalty":{"accuracy_basis_points":10000},"terrain_weapon_modifier":{"zone_ids":[],"range_basis_points":10000,"arc_delta_deg":0,"target_source":"actual_reached_position","rounding":"zone_id_asc_sequential_half_up"}}
	var navigation := {"RC-CAO-SQ-01":{"position":[500,100]}}
	var first: Dictionary = effects.resolve(state, [shot], [], navigation, {}, 1)
	var second: Dictionary = effects.resolve(state, [shot], [], navigation, {}, 1)
	check(first.ok and second.ok and JSON.stringify(first) == JSON.stringify(second), "authorized shot resolution is deterministic")
	var wrong_turn: Dictionary = effects.resolve(state, [shot], [], navigation, {}, 2)
	check(not wrong_turn.ok and JSON.stringify(state) == JSON.stringify(effects.initial_state()), "wrong-turn batch rejects atomically")
	var estimated := shot.duplicate(true); estimated.event_id = "SHOT-ESTIMATED-01"; estimated.outcome = "estimated_fire_authorized"; estimated.erase("target_squadron_id")
	estimated["contact_id"] = "SEALED-1"; estimated["aim_position"] = [900,900]; estimated["confidence_basis_points"] = 10000
	var missed: Dictionary = effects.resolve(state, [estimated], [], navigation, {"SEALED-1":"RC-CAO-SQ-01"}, 1)
	var shot_receipt: Dictionary = {}
	for event in missed.get("events", []):
		if String(event.get("event_type", "")) == "shot_effect_resolved": shot_receipt = event
	check(missed.ok and not shot_receipt.is_empty() and not bool(shot_receipt.hit) and not bool(shot_receipt.estimated_impact_gate), "estimated fire requires sealed aim radius gate")
	_test_malformed_shot_boundaries(effects, state, shot, navigation)

func _test_malformed_shot_boundaries(effects, state: Dictionary, valid_shot: Dictionary, navigation: Dictionary) -> void:
	var variants: Array = []
	var row := valid_shot.duplicate(true); row.formation_modifier = []; variants.append(row)
	row = valid_shot.duplicate(true); row.formation_modifier.shooter = []; variants.append(row)
	row = valid_shot.duplicate(true); row.formation_modifier.target = "bad"; variants.append(row)
	row = valid_shot.duplicate(true); row.formation_modifier.shooter.fire_percent = {}; variants.append(row)
	row = valid_shot.duplicate(true); row.command_penalty = []; variants.append(row)
	row = valid_shot.duplicate(true); row.command_penalty.accuracy_basis_points = "10000"; variants.append(row)
	row = valid_shot.duplicate(true); row.terrain_weapon_modifier = []; variants.append(row)
	row = valid_shot.duplicate(true); row.terrain_weapon_modifier.zone_ids = {}; variants.append(row)
	row = valid_shot.duplicate(true); row.outcome = "estimated_fire_authorized"; row.erase("target_squadron_id"); row.contact_id = "SEALED-BAD"; row.aim_position = {}; row.confidence_basis_points = 10000; variants.append(row)
	row = valid_shot.duplicate(true); row.outcome = "estimated_fire_authorized"; row.erase("target_squadron_id"); row.contact_id = "SEALED-BAD"; row.aim_position = [500,100]; row.confidence_basis_points = []; variants.append(row)
	var digest := JSON.stringify(state)
	for malformed_batch in [[[]], [{"event_id":7,"turn":1}], [{"event_id":"BAD-TURN","turn":"1"}]]:
		var rejected_batch: Dictionary = effects.resolve(state, malformed_batch, [], navigation, {}, 1)
		check(not rejected_batch.ok and JSON.stringify(state) == digest, "malformed top-level shot rejects before sorting")
	for index in range(variants.size()):
		var rejected: Dictionary = effects.resolve(state, [variants[index]], [], navigation, {"SEALED-BAD":"RC-CAO-SQ-01"}, 1)
		check(not rejected.ok and JSON.stringify(state) == digest, "malformed nested shot %d rejects atomically" % index)
	var late_malformed: Dictionary = variants[0].duplicate(true); late_malformed.event_id = "SHOT-MALFORMED-LATE"
	var whole_batch: Dictionary = effects.resolve(state, [valid_shot, late_malformed], [], navigation, {}, 1)
	check(not whole_batch.ok and JSON.stringify(state) == digest, "late malformed row rejects the whole batch without partial commit")
	var estimated_navigation := valid_shot.duplicate(true); estimated_navigation.outcome = "estimated_fire_authorized"; estimated_navigation.erase("target_squadron_id"); estimated_navigation.contact_id = "SEALED-NAV"; estimated_navigation.aim_position = [500,100]; estimated_navigation.confidence_basis_points = 10000
	var rejected_navigation: Dictionary = effects.resolve(state, [estimated_navigation], [], {"RC-CAO-SQ-01":[]}, {"SEALED-NAV":"RC-CAO-SQ-01"}, 1)
	check(not rejected_navigation.ok and JSON.stringify(state) == digest, "malformed estimated navigation rejects atomically")
