extends SceneTree

## Task ID / 공식·새 작업 제목: DEMO-RC-G5-03 — 전장 지형의 이동·탐지·무기 효과
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Terrain := preload("res://core/demo_red_cliffs/red_cliffs_terrain_resolver.gd")
const Movement := preload("res://core/demo_red_cliffs/red_cliffs_movement_resolver.gd")
const Detection := preload("res://core/demo_red_cliffs/red_cliffs_detection_resolver.gd")
const Fog := preload("res://core/demo_red_cliffs/red_cliffs_fog_of_war.gd")
const Weapon := preload("res://core/demo_red_cliffs/red_cliffs_weapon_allocation.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")
var _pass := 0; var _fail := 0
func _ok(value: bool, label: String) -> void:
	if value: _pass += 1
	else: _fail += 1; print("  x %s" % label)
func _eq(actual, expected, label: String) -> void: _ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])
func _init() -> void: call_deferred("_run")

func _run() -> void:
	print("DEMO-RC-G5-03 terrain movement detection weapon core")
	_test_rules_boundary_overlap_and_movement_cost()
	_test_detection_and_weapon_segment_effects()
	_test_estimated_aim_terrain_independence()
	_test_battle_phase_viewer_redaction_and_control_parity()
	print("PASS %d / FAIL %d" % [_pass, _fail]); quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)

func _setup() -> Dictionary:
	var loaded := Setup.load_default(); _ok(loaded.ok, "setup loads"); return loaded.setup.duplicate(true)

func _terrain(setup: Dictionary):
	var resolver = Terrain.new(); var result: Dictionary = resolver.initialize(setup); _ok(result.ok, "terrain initializes: %s" % str(result.get("errors", []))); return resolver

func _test_rules_boundary_overlap_and_movement_cost() -> void:
	var setup := _setup(); var terrain = _terrain(setup); var rules: Dictionary = terrain.rules_snapshot()
	_eq(rules.profile_id, "normal-demo-terrain-v1", "dedicated normal-demo terrain profile")
	_eq(rules.zones.size(), 3, "nebula debris shadow zones exact")
	_eq(terrain.visible_zones().map(func(row): return row.terrain_type), ["debris", "nebula", "planet_shadow"], "zone order stable by ID")
	var boundary: Dictionary = terrain.point_effects([600, 50]); _ok(boundary.zone_ids.has("TRN-NEBULA-01"), "inclusive boundary membership")
	var overlap: Dictionary = terrain.point_effects([700, 120])
	_eq(overlap.zone_ids, ["TRN-DEBRIS-01", "TRN-NEBULA-01"], "overlap IDs stable")
	_eq(overlap.movement_cost_basis_points, 15385, "overlap movement uses max cost without duplicate distance")
	_eq(overlap.observer_sensor_percent, -25, "overlap sensor additive")
	_eq(overlap.target_concealment_points, 11, "overlap concealment additive")
	var tangent: Dictionary = terrain.follow_waypoints([550, 0], [[600, 50]], 1000)
	_ok(tangent.terrain_events.any(func(row): return String(row.event_type) == "terrain_membership" and float(row.traversal_length) == 0.0), "endpoint touch emits zero-length membership")
	var collinear: Dictionary = terrain.follow_waypoints([550, 50], [[750, 50]], 200)
	_ok(collinear.actual_distance < 200.0, "collinear boundary counts inside and consumes terrain cost")
	var traversed: Dictionary = terrain.follow_waypoints([550, 100], [[750, 100]], 140)
	_ok(traversed.actual_distance < 140.0 and traversed.terrain_segments.size() >= 2, "terrain cost reduces geometric movement under fixed budget")
	_eq(JSON.stringify(traversed), JSON.stringify(terrain.follow_waypoints([550, 100], [[750, 100]], 140)), "terrain traversal deterministic")
	var hold_setup := setup.duplicate(true)
	for squad in hold_setup.squadrons:
		if String(squad.id) == "RC-LIU-SQ-01": squad.initial_position = [650, 100]
	var movement = Movement.new(); movement.initialize(hold_setup); var held: Dictionary = movement.resolve_orders(_holds(hold_setup), movement.initial_navigation())
	_ok(held.terrain_events.any(func(row): return String(row.event_type) == "terrain_stay" and String(row.squadron_id) == "RC-LIU-SQ-01"), "stationary terrain residence emits stay event")

func _test_detection_and_weapon_segment_effects() -> void:
	var setup := _setup(); var detection = Detection.new(); _ok(detection.initialize(setup).ok, "detection initializes")
	var formation := detection.initial_formation_state()
	var neutral: Dictionary = detection.evaluate("RC-LIU-SQ-01", "RC-CAO-SQ-01", 100.0, formation, [500, 300], [1000, 300])
	var terrain_hit: Dictionary = detection.evaluate("RC-LIU-SQ-01", "RC-CAO-SQ-01", 100.0, formation, [650, 100], [700, 120])
	_ok(terrain_hit.authoritative.score < neutral.authoritative.score, "observer sensor and target concealment terrain lower detection score")
	_eq(terrain_hit.authoritative.own_sensor_breakdown.own_terrain_zone_ids, ["TRN-NEBULA-01"], "own sensor breakdown records own zone only")
	_eq(terrain_hit.authoritative.target_terrain_concealment_points, 11, "authoritative target concealment stacks")
	var terrain = _terrain(setup); var weapon: Dictionary = terrain.weapon_effect([550, 100], [850, 100], "actual_reached_position")
	_eq(weapon.zone_ids, ["TRN-DEBRIS-01", "TRN-NEBULA-01"], "weapon uses every zone crossed by shot segment")
	_eq(weapon.range_basis_points, 7650, "weapon range sequential half-up by stable zone ID")
	_eq(weapon.arc_delta_deg, -15, "weapon arc additive across crossed zones")

func _test_estimated_aim_terrain_independence() -> void:
	var setup := _setup()
	for squad in setup.squadrons:
		if String(squad.id) == "RC-LIU-SQ-02": squad.initial_position = [550, 100]; squad.initial_facing_deg = 0
	var fog = Fog.new(); _ok(fog.initialize(setup).ok, "fog initializes terrain")
	var contact := {"contact_id": fog.contact_id("liu_bei", "RC-CAO-SQ-01"), "state": "estimated", "last_known_position": [650.0, 100.0], "last_seen_turn": 1, "staleness_turns": 1, "confidence_basis_points": 4000, "error_radius": 0}
	var order: Dictionary = fog.make_order("liu_bei", "RC-LIU-SQ-02", contact, 2).order
	var movement = Movement.new(); movement.initialize(setup); var nav_a := movement.initial_navigation(); var nav_b := nav_a.duplicate(true); nav_b["RC-CAO-SQ-01"].position = [1400, 800]
	var weapon_control = Weapon.new(); weapon_control.initialize(setup); var policy := weapon_control.interception_policy(weapon_control.initial_state())
	var a: Dictionary = fog.authorize_orders([order], "liu_bei", nav_a, policy, 2); var b: Dictionary = fog.authorize_orders([order], "liu_bei", nav_b, policy, 2)
	_ok(a.ok and a.estimated_fire_events.size() == 1, "estimated fire remains eligible through sealed aim terrain")
	_eq(JSON.stringify(a), JSON.stringify(b), "estimated terrain is independent of true target position/zone")
	_eq(a.estimated_fire_events[0].terrain_weapon_modifier.target_source, "sealed_estimated_aim", "estimated fire terrain source explicit")
	_ok(not JSON.stringify(a).contains("RC-CAO-SQ-01"), "estimated terrain receipt leaks no true target ID")

func _test_battle_phase_viewer_redaction_and_control_parity() -> void:
	var setup := _setup(); var positions := {"RC-LIU-SQ-01": [550, 100], "RC-LIU-SQ-02": [200, 600], "RC-SUN-SQ-01": [300, 700], "RC-CAO-SQ-01": [1300, 350]}
	for squad in setup.squadrons: squad.initial_position = positions[String(squad.id)].duplicate(); squad.initial_facing_deg = 0
	var ai = Battle.new(); _ok(ai.initialize(setup).ok, "AI battle initializes"); var preview: Dictionary = ai.set_order_move("RC-LIU-SQ-01", [[750, 100]], 0)
	_ok(preview.ok and not preview.terrain_segments.is_empty(), "movement preview consumes terrain resolver receipt")
	ai.submit_command_draft(); ai.submit_sun_control_choice("ai"); var ai_receipt: Dictionary = ai.resolve_turn(); _ok(ai_receipt.ok and not ai_receipt.terrain_events.is_empty(), "terrain events resolve")
	_ok(ai.phase_ledger(1).phases[0].events.any(func(row): return String(row.event_type).begins_with("terrain_")), "terrain event maps to contact phase")
	var liu_visible := JSON.stringify(ai.visible_tactical_events("liu_bei", 1)); var cao_visible := JSON.stringify(ai.visible_tactical_events("cao_cao", 1))
	_ok(liu_visible.contains("terrain_") and not cao_visible.contains("TRN-NEBULA-01"), "enemy viewer cannot infer undetected hostile terrain crossing")
	_ok(ai.viewer_snapshot("liu_bei").terrain_zones.size() == 3 and ai.own_terrain_membership("liu_bei").ok, "public terrain geometry and own membership APIs available")
	var manual = Battle.new(); manual.initialize(setup); manual.set_order_move("RC-LIU-SQ-01", [[750, 100]], 0); manual.submit_command_draft(); manual.submit_sun_control_choice("manual"); manual.submit_command_draft(); var manual_receipt: Dictionary = manual.resolve_turn()
	_eq(JSON.stringify(ai_receipt.movement_events), JSON.stringify(manual_receipt.movement_events), "AI/manual choice uses identical terrain movement resolver")
	_eq(JSON.stringify(ai_receipt.terrain_events), JSON.stringify(manual_receipt.terrain_events), "AI/manual terrain events deterministic")
	_ok(not ai_receipt.has("hit") and not ai_receipt.has("damage") and not ai_receipt.has("winner"), "terrain creates no hit damage winner")

func _holds(setup: Dictionary) -> Array:
	var result: Array = []
	for squad in setup.squadrons:
		if bool(squad.get("operational", true)): result.append({"squadron_id": String(squad.id), "action": "hold"})
	return result
