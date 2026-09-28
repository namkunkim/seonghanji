class_name RedCliffsInterceptionResolver
extends RefCounted

## DEMO-RC-G4-03 — 경로 교차·탐지·기회 사격의 결정론적 코어 권위.
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const WeaponAllocation := preload("res://core/demo_red_cliffs/red_cliffs_weapon_allocation.gd")
const FogOfWar := preload("res://core/demo_red_cliffs/red_cliffs_fog_of_war.gd")
const DetectionResolver := preload("res://core/demo_red_cliffs/red_cliffs_detection_resolver.gd")
const TerrainResolver := preload("res://core/demo_red_cliffs/red_cliffs_terrain_resolver.gd")
const RULES_PATH := "res://data/red-cliffs-interception-rules.json"
const STATE_RANK := {"undetected": 0, "lost": 1, "estimated": 2, "confirmed": 3}

var _setup: Dictionary = {}
var _rules: Dictionary = {}
var _weapon_control
var _fog
var _detection_resolver
var _terrain


func initialize(applied_setup: Dictionary) -> Dictionary:
	var setup_result := Setup.validate_document(applied_setup)
	if not bool(setup_result.get("ok", false)): return _error("유효한 G3 적용 편성이 필요합니다.")
	var rules_result := _load_rules()
	if not bool(rules_result.get("ok", false)): return rules_result
	var weapon_control = WeaponAllocation.new()
	var weapon_result: Dictionary = weapon_control.initialize(setup_result.setup)
	if not weapon_result.ok: return weapon_result
	var fog = FogOfWar.new(); var fog_result: Dictionary = fog.initialize(setup_result.setup)
	if not fog_result.ok: return fog_result
	var detection_resolver = DetectionResolver.new(); var detection_result: Dictionary = detection_resolver.initialize(setup_result.setup)
	if not detection_result.ok: return detection_result
	var terrain = TerrainResolver.new(); var terrain_result: Dictionary = terrain.initialize(setup_result.setup)
	if not terrain_result.ok: return terrain_result
	_setup = setup_result.setup.duplicate(true)
	_rules = rules_result.rules.duplicate(true)
	_weapon_control = weapon_control
	_fog = fog
	_detection_resolver = detection_resolver
	_terrain = terrain
	return _ok()


func rules_snapshot() -> Dictionary: return _rules.duplicate(true)


func initial_detection_state() -> Dictionary:
	var result := {}
	for observer in _operational_squadrons():
		for target in _operational_squadrons():
			if not _hostile(String(observer.faction_id), String(target.faction_id)): continue
			var key := _contact_key(String(observer.id), String(target.id))
			result[key] = {"observer_squadron_id": String(observer.id), "target_squadron_id": String(target.id),
				"state": "undetected", "last_known_position": null, "last_seen_turn": 0, "detection_margin": -999999, "detection_rationale": {}}
			result[key].merge(_fog.initial_contact_fields())
	return result


func weapon_capabilities() -> Dictionary:
	var result := {}
	var policy: Dictionary = _weapon_control.interception_policy(_weapon_control.initial_state())
	for squadron_id in policy:
		var capabilities: Array = policy[squadron_id].capabilities
		var capability: Dictionary = capabilities[0] if not capabilities.is_empty() else {"weapon_id": "", "range": 0, "arc_deg": 0.0}
		for candidate in capabilities:
			if int(candidate.range) > int(capability.range): capability = candidate
		result[String(squadron_id)] = {"weapon_id": String(capability.weapon_id),
			"range": int(capability.range), "arc_deg": float(capability.arc_deg)}
	return result


func resolve(movement_events: Array, live_navigation: Dictionary, prior_detection: Dictionary,
		turn_number: int, weapon_policy: Dictionary = {}, formation_state: Dictionary = {}, sensor_effects: Dictionary = {}, temporary_zones: Array = []) -> Dictionary:
	if _setup.is_empty(): return _error("요격 판정기가 초기화되지 않았습니다.")
	var checked: Dictionary = _validate_inputs(movement_events, live_navigation, prior_detection, turn_number)
	if not checked.ok: return checked
	var event_by_squad: Dictionary = checked.event_by_squad
	var detection: Dictionary = prior_detection.duplicate(true)
	var intersection_events: Array = _resolve_intersections(event_by_squad, turn_number)
	var active_formation: Dictionary = formation_state.duplicate(true) if not formation_state.is_empty() else _detection_resolver.initial_formation_state()
	var detection_result: Dictionary = _resolve_detection(event_by_squad, detection, turn_number, active_formation, sensor_effects, temporary_zones)
	if not detection_result.ok: return detection_result
	var active_policy: Dictionary = weapon_policy.duplicate(true) if not weapon_policy.is_empty() else _weapon_control.interception_policy(_weapon_control.initial_state())
	var policy_check := _validate_weapon_policy(active_policy)
	if not policy_check.ok: return policy_check
	var fire_events: Array = _resolve_opportunity_fire(event_by_squad, detection, turn_number, active_policy, temporary_zones)
	return {"ok": true, "errors": [], "path_intersection_events": intersection_events,
		"detection_events": detection_result.events, "opportunity_fire_events": fire_events,
		"detection_state": detection}


func visible_contacts(viewer_faction_id: String, detection_state: Dictionary,
		live_navigation: Dictionary) -> Dictionary:
	if not _faction_ids().has(viewer_faction_id): return _error("미지 관측 세력입니다: %s" % viewer_faction_id)
	var best_by_target := {}
	for value in detection_state.values():
		if not value is Dictionary: continue
		var row: Dictionary = value
		var observer := _find_squad(String(row.get("observer_squadron_id", "")))
		if String(observer.get("faction_id", "")) != viewer_faction_id: continue
		var target_id := String(row.get("target_squadron_id", ""))
		if not best_by_target.has(target_id) or _contact_precedes(row, best_by_target[target_id]):
			best_by_target[target_id] = row
	var target_ids: Array = best_by_target.keys(); target_ids.sort()
	var contacts: Array = []
	for target_id in target_ids:
		var row: Dictionary = best_by_target[target_id]; var state := String(row.get("state", "undetected"))
		var last_known = row.get("last_known_position")
		var display_position = null
		if state == "confirmed" and live_navigation.has(target_id): display_position = live_navigation[target_id].position.duplicate()
		elif ["estimated", "lost"].has(state) and last_known is Array: display_position = last_known.duplicate()
		if state == "undetected": continue
		var contact := {"contact_id": _fog.contact_id(viewer_faction_id, target_id), "state": state,
			"display_position": display_position,
			"last_known_position": last_known.duplicate() if last_known is Array else null,
			"last_seen_turn": int(row.get("last_seen_turn", 0)),
			"staleness_turns": int(row.get("staleness_turns", 0)),
			"confidence_basis_points": int(row.get("confidence_basis_points", 0)),
			"error_radius": int(row.get("error_radius", 0)),
			"expires_after_turn": int(row.get("expires_after_turn", 0)),
			"stale": state != "confirmed",
			"detection_rationale": row.get("detection_rationale", {}).duplicate(true),
			"source_observer_squadron_id": String(row.get("observer_squadron_id", ""))}
		if state == "confirmed": contact["target_squadron_id"] = target_id
		contacts.append(contact)
	return {"ok": true, "errors": [], "viewer_faction_id": viewer_faction_id, "contacts": contacts}


func visible_tactical_events(viewer_faction_id: String, raw_receipt: Dictionary,
		detection_state: Dictionary) -> Dictionary:
	if not _faction_ids().has(viewer_faction_id): return _error("미지 관측 세력입니다: %s" % viewer_faction_id)
	var events: Array = []
	for value in raw_receipt.get("path_intersection_events", []):
		var row: Dictionary = value; var a := String(row.squadron_a_id); var b := String(row.squadron_b_id)
		var own_id := a if String(_find_squad(a).faction_id) == viewer_faction_id else (b if String(_find_squad(b).faction_id) == viewer_faction_id else "")
		if own_id.is_empty(): continue
		var enemy_id := b if own_id == a else a
		if not _viewer_has_contact(viewer_faction_id, enemy_id, detection_state): continue
		events.append({"event_id": String(row.event_id), "event_type": "path_intersection",
			"own_squadron_id": own_id, "contact_id": _contact_id(viewer_faction_id, enemy_id), "turn": int(row.turn)})
	for value in raw_receipt.get("detection_events", []):
		var row: Dictionary = value; var observer_id := String(row.observer_squadron_id)
		if String(_find_squad(observer_id).faction_id) != viewer_faction_id: continue
		if String(row.state) == "undetected": continue
		events.append({"event_id": String(row.event_id), "event_type": "detection", "observer_squadron_id": observer_id,
			"contact_id": _contact_id(viewer_faction_id, String(row.target_squadron_id)), "previous_state": String(row.previous_state),
			"state": String(row.state), "last_known_position": row.last_known_position.duplicate() if row.last_known_position is Array else null,
			"last_seen_turn": int(row.last_seen_turn), "stale": String(row.state) != "confirmed",
			"detection_rationale": row.get("detection_rationale", {}).duplicate(true)})
	for value in raw_receipt.get("opportunity_fire_events", []):
		var row: Dictionary = value; var shooter := String(row.shooter_squadron_id); var target := String(row.target_squadron_id)
		var shooter_own := String(_find_squad(shooter).faction_id) == viewer_faction_id
		var target_own := String(_find_squad(target).faction_id) == viewer_faction_id
		if not shooter_own and not target_own: continue
		var enemy_id := target if shooter_own else shooter
		if not _viewer_has_contact(viewer_faction_id, enemy_id, detection_state): continue
		var visible_event := {"event_id": String(row.event_id), "event_type": "shot_authorized", "turn": int(row.turn),
			"own_squadron_id": shooter if shooter_own else target, "contact_id": _contact_id(viewer_faction_id, enemy_id),
			"own_role": "shooter" if shooter_own else "target",
			"outcome": "shot_authorized", "damage_pending": true}
		# A target may know that hostile fire was authorized without learning the
		# hostile shooter's exact range, bearing, facing, or firing arc.
		if shooter_own:
			visible_event.merge({"range": int(row.range), "distance": float(row.distance),
				"bearing_deg": float(row.bearing_deg), "facing_deg": float(row.facing_deg),
				"arc_deg": float(row.arc_deg)})
			if row.get("fire_control_snapshot") is Dictionary:
				visible_event["fire_control_snapshot"] = row.fire_control_snapshot.duplicate(true)
			if row.get("resource_reservation") is Dictionary:
				visible_event["resource_reservation"] = row.resource_reservation.duplicate(true)
			if row.get("terrain_weapon_modifier") is Dictionary:
				visible_event["terrain_weapon_modifier"] = row.terrain_weapon_modifier.duplicate(true)
			if row.get("command_penalty") is Dictionary:
				visible_event["command_penalty"] = row.command_penalty.duplicate(true)
		# Formation/sector detail is exact tactical information. A shooter already
		# has the confirmed contact required to authorize the shot; a target only
		# receives this detail when its own contact on the shooter is confirmed.
		var exact_modifier_visible := shooter_own or _viewer_contact_state(viewer_faction_id, enemy_id, detection_state) == "confirmed"
		if exact_modifier_visible and row.get("formation_modifier") is Dictionary:
			var modifier: Dictionary = row.formation_modifier
			if shooter_own:
				visible_event["formation_modifier"] = {"own_role": "shooter",
					"own_formation_id": String(modifier.shooter.formation_id),
					"own_fire_percent": int(modifier.shooter.fire_percent),
					"target_sector": String(modifier.target.sector),
					"result_pending": modifier.result_pending.duplicate()}
			else:
				visible_event["formation_modifier"] = {"own_role": "target",
					"own_formation_id": String(modifier.target.formation_id),
					"own_defense_percent": int(modifier.target.defense_percent),
					"incoming_sector": String(modifier.target.sector),
					"own_sector_defense_percent": int(modifier.target.sector_defense_percent),
					"own_total_defense_percent": int(modifier.target.total_defense_percent),
					"result_pending": modifier.result_pending.duplicate()}
		events.append(visible_event)
	events.sort_custom(func(a, b): return String(a.event_id) < String(b.event_id))
	return {"ok": true, "errors": [], "viewer_faction_id": viewer_faction_id, "events": events}


func _resolve_intersections(event_by_squad: Dictionary, turn_number: int) -> Array:
	var result: Array = []; var ids: Array = event_by_squad.keys(); ids.sort()
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			var a := String(ids[i]); var b := String(ids[j]); var sa := _find_squad(a); var sb := _find_squad(b)
			if not _hostile(String(sa.faction_id), String(sb.faction_id)): continue
			var intersection := _first_path_intersection(_event_path(event_by_squad[a]), _event_path(event_by_squad[b]))
			if not intersection.intersects: continue
			result.append({"event_id": _event_id("PROX", turn_number, a, b), "turn": turn_number,
				"squadron_a_id": a, "squadron_b_id": b, "path_crossed": true,
				"intersection_point": intersection.point.duplicate(), "dedup_policy": "one_pair_per_turn"})
	return result


func _resolve_detection(event_by_squad: Dictionary, detection: Dictionary, turn_number: int,
		formation_state: Dictionary, sensor_effects: Dictionary = {}, temporary_zones: Array = []) -> Dictionary:
	var result: Array = []; var keys: Array = detection.keys(); keys.sort()
	for key_value in keys:
		var key := String(key_value); var row: Dictionary = detection[key]
		var observer_id := String(row.observer_squadron_id); var target_id := String(row.target_squadron_id)
		var closest := _closest_paths(_event_path(event_by_squad[observer_id]), _event_path(event_by_squad[target_id]))
		var distance := float(closest.distance); var previous := String(row.state)
		var evaluated: Dictionary = _detection_resolver.evaluate(observer_id, target_id, distance, formation_state,
			closest.point_a, closest.point_b, int(sensor_effects.get(observer_id, 0)), temporary_zones)
		if not evaluated.ok: return evaluated
		var state := String(evaluated.state)
		var observed = closest.point_b.duplicate() if state != "undetected" else null
		row = _fog.transition(row, state, observed, turn_number)
		var rationale: Dictionary = evaluated.viewer_basis.duplicate(true)
		if String(row.state) != state:
			rationale.result_state = String(row.state)
			rationale.reason_code = "contact_memory_%s" % String(row.state)
			rationale.reason_label = "마지막 확인 정보 유지" if String(row.state) == "estimated" else "마지막 확인 정보 신선도 저하"
		row.detection_rationale = rationale
		row.detection_margin = int(evaluated.margin)
		detection[key] = row
		result.append({"event_id": _event_id("DET", turn_number, observer_id, target_id), "turn": turn_number,
			"observer_squadron_id": observer_id, "target_squadron_id": target_id,
			"previous_state": previous, "state": String(row.state), "minimum_distance": distance,
			"last_known_position": row.last_known_position.duplicate() if row.last_known_position is Array else null,
			"last_seen_turn": int(row.last_seen_turn), "staleness_turns": int(row.staleness_turns),
			"confidence_basis_points": int(row.confidence_basis_points), "error_radius": int(row.error_radius),
			"detection_evaluation": evaluated.authoritative.duplicate(true),
			"detection_rationale": rationale.duplicate(true)})
	return {"ok": true, "errors": [], "events": result}


func _resolve_opportunity_fire(event_by_squad: Dictionary, detection: Dictionary,
		turn_number: int, weapon_policy: Dictionary, temporary_zones: Array = []) -> Array:
	var candidates: Array = []
	for key_value in detection.keys():
		var contact: Dictionary = detection[key_value]
		if String(contact.state) != "confirmed": continue
		var shooter_id := String(contact.observer_squadron_id); var target_id := String(contact.target_squadron_id)
		if bool(weapon_policy[shooter_id].hold_fire): continue
		var target_event: Dictionary = event_by_squad[target_id]
		if String(target_event.action) != "move" or float(target_event.get("actual_distance", 0.0)) <= 0.000001: continue
		var closest := _closest_paths(_event_path(event_by_squad[shooter_id]), _event_path(event_by_squad[target_id]))
		var facing := float(event_by_squad[shooter_id].facing_deg)
		var vector := Vector2(float(closest.point_b[0]) - float(closest.point_a[0]), float(closest.point_b[1]) - float(closest.point_a[1]))
		var bearing := facing if vector.length_squared() <= 0.000001 else fposmod(rad_to_deg(atan2(vector.y, vector.x)), 360.0)
		var angle_delta := absf(wrapf(bearing - facing, -180.0, 180.0))
		var shooter_event: Dictionary = event_by_squad[shooter_id]
		var initial_vector := _v(target_event.from) - _v(shooter_event.from)
		var initial_distance := initial_vector.length()
		var initial_bearing := float(shooter_event.get("from_facing_deg", facing)) if initial_vector.length_squared() <= 0.000001 else fposmod(rad_to_deg(atan2(initial_vector.y, initial_vector.x)), 360.0)
		var initial_delta := absf(wrapf(initial_bearing - float(shooter_event.get("from_facing_deg", facing)), -180.0, 180.0))
		var eligible: Array = []
		for value in weapon_policy[shooter_id].capabilities:
			var capability: Dictionary = value; var weapon_id := String(capability.weapon_id)
			var allocation := int(weapon_policy[shooter_id].allocations.get(weapon_id, 0))
			var terrain_effect: Dictionary = _terrain.weapon_effect(closest.point_a, closest.point_b, "actual_reached_position", temporary_zones)
			var effective_range := int(floor(float(int(capability.range) * int(terrain_effect.range_basis_points) + 5000) / 10000.0))
			var effective_arc := clampf(float(capability.arc_deg) + float(terrain_effect.arc_delta_deg), 0.0, 360.0)
			if allocation <= 0 or float(closest.distance) > float(effective_range) or angle_delta > effective_arc * 0.5 + 0.000001: continue
			var initial_effect: Dictionary = _terrain.weapon_effect(shooter_event.from, target_event.from, "actual_reached_position", temporary_zones)
			var initial_range := int(floor(float(int(capability.range) * int(initial_effect.range_basis_points) + 5000) / 10000.0))
			var initial_arc := clampf(float(capability.arc_deg) + float(initial_effect.arc_delta_deg), 0.0, 360.0)
			if initial_distance <= float(initial_range) and initial_delta <= initial_arc * 0.5 + 0.000001: continue
			eligible.append({"weapon_id": weapon_id, "allocation_basis_points": allocation,
				"platform_id": String(capability.get("platform_id", "")),
				"range": effective_range, "arc_deg": effective_arc, "terrain_weapon_modifier": terrain_effect})
		if eligible.is_empty(): continue
		eligible.sort_custom(func(a, b):
			if int(a.allocation_basis_points) != int(b.allocation_basis_points): return int(a.allocation_basis_points) > int(b.allocation_basis_points)
			return String(a.weapon_id) < String(b.weapon_id))
		var capability: Dictionary = eligible[0]
		candidates.append({"shooter_squadron_id": shooter_id, "target_squadron_id": target_id,
			"distance": float(closest.distance), "bearing_deg": bearing, "facing_deg": facing,
			"arc_deg": float(capability.arc_deg), "range": int(capability.range),
			"selected_weapon_id": String(capability.weapon_id),
			"selected_platform_id": String(capability.platform_id),
			"allocation_basis_points": int(capability.allocation_basis_points),
			"terrain_weapon_modifier": capability.terrain_weapon_modifier.duplicate(true),
			"movement_order_index": int(event_by_squad[shooter_id].order_index)})
	candidates.sort_custom(func(a, b):
		if int(a.movement_order_index) != int(b.movement_order_index): return int(a.movement_order_index) < int(b.movement_order_index)
		if String(a.shooter_squadron_id) != String(b.shooter_squadron_id): return String(a.shooter_squadron_id) < String(b.shooter_squadron_id)
		return String(a.target_squadron_id) < String(b.target_squadron_id))
	var events: Array = []
	for candidate in candidates:
		var shooter_id := String(candidate.shooter_squadron_id)
		var index := events.size(); var event_id := _event_id("FIRE", turn_number, shooter_id, String(candidate.target_squadron_id))
		var event: Dictionary = candidate.duplicate(true); event.event_id = event_id; event.turn = turn_number; event.order_index = index
		event.outcome = "shot_authorized"; event.damage_pending = true; event.tie_breaker = String(_rules.deterministic_seed)
		event.fire_control_snapshot = {"hold_fire": false,
			"allocations": weapon_policy[shooter_id].allocations.duplicate(true),
			"selected_weapon_id": String(candidate.selected_weapon_id),
			"selected_platform_id": String(candidate.selected_platform_id),
			"selected_allocation_basis_points": int(candidate.allocation_basis_points),
			"eligibility": {"range": int(candidate.range), "arc_deg": float(candidate.arc_deg)}}
		events.append(event)
	return events


func _validate_inputs(events: Array, live_navigation: Dictionary, detection: Dictionary,
		turn_number: int) -> Dictionary:
	if turn_number < 1: return _error("턴 번호는 1 이상이어야 합니다.")
	var event_by_squad := {}
	for value in events:
		if not value is Dictionary: return _error("이동 이벤트는 객체여야 합니다.")
		var event: Dictionary = value; var squadron_id := String(event.get("squadron_id", ""))
		if not _operational_ids().has(squadron_id) or event_by_squad.has(squadron_id): return _error("미지 또는 중복 이동 이벤트입니다: %s" % squadron_id)
		if not event.get("from") is Array or not event.get("to") is Array or not _finite_number(event.get("facing_deg")): return _error("이동 이벤트 좌표·방향이 잘못되었습니다: %s" % squadron_id)
		event_by_squad[squadron_id] = event.duplicate(true)
	if event_by_squad.size() != _operational_ids().size(): return _error("모든 operational 전대의 이동 이벤트가 필요합니다.")
	for squadron_id in _operational_ids():
		if not live_navigation.has(squadron_id): return _error("live 위치가 누락되었습니다: %s" % squadron_id)
	var expected_detection := initial_detection_state()
	if detection.size() != expected_detection.size(): return _error("탐지 상태 쌍이 누락되었습니다.")
	for key in expected_detection:
		if not detection.has(key) or not detection[key] is Dictionary or not STATE_RANK.has(String(detection[key].get("state", ""))): return _error("탐지 상태가 잘못되었습니다: %s" % key)
	return {"ok": true, "errors": [], "event_by_squad": event_by_squad}


func _event_path(event: Dictionary) -> Array:
	var path: Array = [event.from.duplicate()]
	for point in event.get("reached_waypoints", []):
		if path.back() != point: path.append(point.duplicate())
	if path.back() != event.to: path.append(event.to.duplicate())
	if path.size() == 1: path.append(path[0].duplicate())
	return path


func _closest_paths(path_a: Array, path_b: Array) -> Dictionary:
	var best := {"distance": INF, "point_a": [], "point_b": []}
	for i in range(path_a.size() - 1):
		for j in range(path_b.size() - 1):
			var candidate := _closest_segments(_v(path_a[i]), _v(path_a[i + 1]), _v(path_b[j]), _v(path_b[j + 1]))
			if float(candidate.distance) < float(best.distance) - 0.000001: best = candidate
	return best


func _first_path_intersection(path_a: Array, path_b: Array) -> Dictionary:
	for i in range(path_a.size() - 1):
		for j in range(path_b.size() - 1):
			var hit := _segment_intersection(_v(path_a[i]), _v(path_a[i + 1]), _v(path_b[j]), _v(path_b[j + 1]))
			if hit.intersects: return hit
	return {"intersects": false, "point": []}


func _segment_intersection(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> Dictionary:
	var epsilon := float(_rules.intersection_epsilon)
	var direct = Geometry2D.segment_intersects_segment(a0, a1, b0, b1)
	if direct is Vector2: return {"intersects": true, "point": [direct.x, direct.y]}
	# Godot returns null for parallel/collinear segments, so endpoints are checked
	# explicitly. Lexicographic order makes overlapping segments deterministic.
	var candidates: Array[Vector2] = []
	for point in [a0, a1]:
		if _point_on_segment(point, b0, b1, epsilon): candidates.append(point)
	for point in [b0, b1]:
		if _point_on_segment(point, a0, a1, epsilon): candidates.append(point)
	if candidates.is_empty(): return {"intersects": false, "point": []}
	candidates.sort_custom(func(a, b): return a.x < b.x or is_equal_approx(a.x, b.x) and a.y < b.y)
	return {"intersects": true, "point": [candidates[0].x, candidates[0].y]}


func _point_on_segment(point: Vector2, start: Vector2, finish: Vector2, epsilon: float) -> bool:
	var closest := Geometry2D.get_closest_point_to_segment(point, start, finish)
	return point.distance_to(closest) <= epsilon


func _closest_segments(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> Dictionary:
	var intersection = Geometry2D.segment_intersects_segment(a0, a1, b0, b1)
	if intersection is Vector2: return {"distance": 0.0, "point_a": [intersection.x, intersection.y], "point_b": [intersection.x, intersection.y]}
	var candidates := [
		[a0, Geometry2D.get_closest_point_to_segment(a0, b0, b1)],
		[a1, Geometry2D.get_closest_point_to_segment(a1, b0, b1)],
		[Geometry2D.get_closest_point_to_segment(b0, a0, a1), b0],
		[Geometry2D.get_closest_point_to_segment(b1, a0, a1), b1],
	]
	var best_distance: float = INF; var best_pair: Array = candidates[0]
	for pair in candidates:
		var distance: float = pair[0].distance_to(pair[1])
		if distance < best_distance - 0.000001: best_distance = distance; best_pair = pair
	return {"distance": best_distance, "point_a": [best_pair[0].x, best_pair[0].y], "point_b": [best_pair[1].x, best_pair[1].y]}


func _validate_weapon_policy(policy: Dictionary) -> Dictionary:
	if policy.size() != _operational_ids().size(): return _error("모든 operational 전대의 무기 정책이 필요합니다.")
	var canonical: Dictionary = _weapon_control.interception_policy(_weapon_control.initial_state())
	for squadron_id in _operational_ids():
		if not policy.has(squadron_id) or not policy[squadron_id] is Dictionary: return _error("무기 정책이 누락되었습니다: %s" % squadron_id)
		var row: Dictionary = policy[squadron_id]
		if not row.get("hold_fire") is bool or not row.get("allocations") is Dictionary or not row.get("capabilities") is Array: return _error("무기 정책 스키마가 잘못되었습니다: %s" % squadron_id)
		if row.capabilities != canonical[squadron_id].capabilities: return _error("무기 range/arc capability는 권위 규칙과 같아야 합니다: %s" % squadron_id)
		var allocation_keys: Array = row.allocations.keys(); allocation_keys.sort()
		if allocation_keys != ["artillery", "intercept", "line_fire", "torpedo"]: return _error("무기 정책 배분 키가 잘못되었습니다: %s" % squadron_id)
		var available: Array = []; for capability in row.capabilities: available.append(String(capability.weapon_id))
		var total := 0
		for weapon_id in allocation_keys:
			var value = row.allocations[weapon_id]
			if not (value is int or value is float) or int(value) < 0 or int(value) > 10000 or not is_equal_approx(float(value), floor(float(value))): return _error("무기 정책 basis points가 잘못되었습니다: %s" % squadron_id)
			if not available.has(weapon_id) and int(value) != 0: return _error("사용 불가 무기 정책은 0이어야 합니다: %s" % squadron_id)
			total += int(value)
		if total != (0 if available.is_empty() else 10000): return _error("무기 정책 합계가 잘못되었습니다: %s" % squadron_id)
		if available.is_empty() and not bool(row.hold_fire): return _error("무장 0 전대는 사격 보류여야 합니다: %s" % squadron_id)
	return _ok()


func _contact_precedes(a: Dictionary, b: Dictionary) -> bool:
	var rank_a := int(STATE_RANK.get(String(a.state), 0)); var rank_b := int(STATE_RANK.get(String(b.state), 0))
	if rank_a != rank_b: return rank_a > rank_b
	if int(a.last_seen_turn) != int(b.last_seen_turn): return int(a.last_seen_turn) > int(b.last_seen_turn)
	if int(a.get("detection_margin", -999999)) != int(b.get("detection_margin", -999999)): return int(a.get("detection_margin", -999999)) > int(b.get("detection_margin", -999999))
	return String(a.observer_squadron_id) < String(b.observer_squadron_id)


func _viewer_has_contact(viewer_faction_id: String, target_id: String, detection_state: Dictionary) -> bool:
	return _viewer_contact_state(viewer_faction_id, target_id, detection_state) != "undetected"


func _viewer_contact_state(viewer_faction_id: String, target_id: String, detection_state: Dictionary) -> String:
	var best := "undetected"
	for value in detection_state.values():
		if not value is Dictionary or String(value.target_squadron_id) != target_id: continue
		var observer := _find_squad(String(value.observer_squadron_id))
		if String(observer.get("faction_id", "")) != viewer_faction_id: continue
		var state := String(value.get("state", "undetected"))
		if int(STATE_RANK.get(state, 0)) > int(STATE_RANK.get(best, 0)): best = state
	return best


func _hostile(a: String, b: String) -> bool:
	for pair in _rules.get("hostile_faction_pairs", []):
		if pair is Array and pair.size() == 2 and (String(pair[0]) == a and String(pair[1]) == b or String(pair[0]) == b and String(pair[1]) == a): return true
	return false


func _operational_squadrons() -> Array:
	var rows: Array = []
	for squad in _setup.get("squadrons", []):
		if bool(squad.get("operational", true)): rows.append(squad)
	rows.sort_custom(func(a, b): return String(a.id) < String(b.id))
	return rows


func _operational_ids() -> Array:
	var result: Array = []
	for squad in _operational_squadrons(): result.append(String(squad.id))
	return result


func _faction_ids() -> Array:
	var result: Array = []
	for faction in _setup.get("factions", []): result.append(String(faction.id))
	return result


func _find_squad(squadron_id: String) -> Dictionary:
	for squad in _setup.get("squadrons", []):
		if String(squad.id) == squadron_id: return squad
	return {}


func _contact_key(observer_id: String, target_id: String) -> String: return "%s>%s" % [observer_id, target_id]


func _contact_id(viewer_faction_id: String, target_id: String) -> String:
	return _fog.contact_id(viewer_faction_id, target_id)


func _event_id(kind: String, turn_number: int, a: String, b: String) -> String:
	return "%s-%02d-%s" % [kind, turn_number, ("%s|%s|%d|%s|%s" % [_rules.deterministic_seed, kind, turn_number, a, b]).sha256_text().substr(0, 16)]


func _load_rules() -> Dictionary:
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null: return _error("요격 규칙 파일을 열 수 없습니다.")
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1 or String(parsed.get("profile_id", "")) != "normal-demo-interception-v1": return _error("지원하지 않는 요격 규칙 프로필입니다.")
	for key in ["deterministic_seed", "statement"]:
		if String(parsed.get(key, "")).is_empty(): return _error("요격 규칙 필수 문자열 누락: %s" % key)
	if not _positive_number(parsed.get("intersection_epsilon")): return _error("교차 epsilon은 양수여야 합니다.")
	if String(parsed.get("intersection_policy", "")) != "actual_reached_polyline_only; hostile_only; endpoint_and_collinear_overlap_count; one_event_per_pair_per_turn": return _error("교차 판정 정책이 지원 계약과 다릅니다.")
	if String(parsed.get("opportunity_fire_policy", "")) != "confirmed_target_enters_range_and_arc_while_target_moves; one_authorization_per_shooter_target_turn": return _error("기회 사격 정책이 지원 계약과 다릅니다.")
	for key in ["hostile_faction_pairs", "detection_modifier_profile", "weapon_control_profile"]:
		if not parsed.has(key): return _error("요격 규칙 필수 항목 누락: %s" % key)
	if not parsed.hostile_faction_pairs is Array or parsed.hostile_faction_pairs.size() != 2: return _error("적대 세력 쌍은 유비-조조, 손권-조조여야 합니다.")
	var hostile_keys: Array = []
	for pair in parsed.hostile_faction_pairs:
		if not pair is Array or pair.size() != 2: return _error("적대 세력 쌍 형식이 잘못되었습니다.")
		var ids := [String(pair[0]), String(pair[1])]; ids.sort(); hostile_keys.append("|".join(ids))
	hostile_keys.sort()
	if hostile_keys != ["cao_cao|liu_bei", "cao_cao|sun_quan"]: return _error("적대 세력 쌍이 지원 계약과 다릅니다.")
	if String(parsed.detection_modifier_profile) != "normal-demo-sensor-ew-v1": return _error("탐지 보정 규칙 연결이 잘못되었습니다.")
	if String(parsed.weapon_control_profile) != "normal-demo-weapon-allocation-v1": return _error("무기 제어 규칙 연결이 잘못되었습니다.")
	return {"ok": true, "errors": [], "rules": parsed.duplicate(true)}


func _v(value: Array) -> Vector2: return Vector2(float(value[0]), float(value[1]))
func _finite_number(value) -> bool: return (value is int or value is float) and is_finite(float(value))
func _positive_number(value) -> bool: return _finite_number(value) and float(value) > 0.0
func _positive_integer(value) -> bool: return _positive_number(value) and is_equal_approx(float(value), floor(float(value)))
func _ok() -> Dictionary: return {"ok": true, "errors": []}
func _error(message: String) -> Dictionary: return {"ok": false, "errors": [message]}
