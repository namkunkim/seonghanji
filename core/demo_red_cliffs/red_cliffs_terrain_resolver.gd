class_name RedCliffsTerrainResolver
extends RefCounted

## DEMO-RC-G5-03 — 적벽 전용 2D terrain 교차·체류·stacking 권위.
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const RULES_PATH := "res://data/red-cliffs-terrain-rules.json"
var _setup: Dictionary = {}; var _rules: Dictionary = {}

func initialize(applied_setup: Dictionary) -> Dictionary:
	var checked := Setup.validate_document(applied_setup); if not checked.ok: return _error("유효한 G3 적용 편성이 필요합니다.")
	var loaded := _load_rules(checked.setup.battlefield_bounds); if not loaded.ok: return loaded
	_setup = checked.setup.duplicate(true); _rules = loaded.rules.duplicate(true); return _ok()

func rules_snapshot() -> Dictionary: return _rules.duplicate(true)
func visible_zones() -> Array:
	var result: Array = []
	for zone in _rules.zones: result.append({"zone_id": String(zone.id), "terrain_type": String(zone.type), "name": String(zone.name), "shape": zone.shape.duplicate(true)})
	return result

func point_effects(point: Array) -> Dictionary:
	var ids: Array = []
	for zone in _rules.zones:
		if _inside(point, zone.shape): ids.append(String(zone.id))
	ids.sort(); return _stack(ids)

func weapon_effect(shooter_position: Array, target_or_aim_position: Array, target_source: String = "actual_reached_position") -> Dictionary:
	var ids := _segment_zone_ids(Vector2(float(shooter_position[0]), float(shooter_position[1])), Vector2(float(target_or_aim_position[0]), float(target_or_aim_position[1])))
	var range_bps := 10000; var arc_delta := 0
	for zone_id in ids:
		var effects: Dictionary = _zone(zone_id).effects
		range_bps = int(floor(float(range_bps * int(effects.weapon_range_basis_points) + 5000) / 10000.0))
		arc_delta += int(effects.weapon_arc_delta_deg)
	return {"zone_ids": ids, "range_basis_points": range_bps, "arc_delta_deg": arc_delta,
		"target_source": target_source, "rounding": "zone_id_asc_sequential_half_up"}

func follow_waypoints(from: Array, waypoints: Array, budget: float) -> Dictionary:
	var current := Vector2(float(from[0]), float(from[1])); var remaining_budget := budget; var actual := 0.0; var reached: Array = []; var segments: Array = []
	for waypoint in waypoints:
		var target := Vector2(float(waypoint[0]), float(waypoint[1])); var interval_rows := _segment_intervals(current, target)
		var completed := true
		for interval in interval_rows:
			var length := float(interval.length); var bps := int(interval.effects.movement_cost_basis_points); var cost := length * float(bps) / 10000.0
			if cost <= remaining_budget + 0.000001:
				remaining_budget -= cost; actual += length; current = Vector2(float(interval.to[0]), float(interval.to[1])); segments.append(interval.duplicate(true))
			else:
				var traversed := remaining_budget * 10000.0 / float(bps); var start := Vector2(float(interval.from[0]), float(interval.from[1])); var finish := Vector2(float(interval.to[0]), float(interval.to[1]))
				current = start if length <= 0.000001 else start + (finish - start) * (traversed / length); actual += traversed
				var partial: Dictionary = interval.duplicate(true); partial.to = [current.x, current.y]; partial.length = traversed; partial["partial"] = true; segments.append(partial)
				remaining_budget = 0.0; completed = false; break
		if completed: reached.append([target.x, target.y])
		else: break
	var remaining_distance := 0.0; var remainder := current
	for index in range(reached.size(), waypoints.size()):
		var target := Vector2(float(waypoints[index][0]), float(waypoints[index][1])); remaining_distance += remainder.distance_to(target); remainder = target
	var terrain_events := _transition_events(segments); terrain_events.append_array(_touch_events(segments))
	return {"to": [current.x, current.y], "actual_distance": actual, "reached_waypoints": reached, "remaining_distance": remaining_distance,
		"path_complete": remaining_distance <= 0.000001, "terrain_segments": segments, "terrain_events": terrain_events}

func _segment_intervals(start: Vector2, finish: Vector2) -> Array:
	var breaks: Array = [0.0, 1.0]
	for zone in _rules.zones:
		var clipped := _clip_rect(start, finish, zone.shape)
		if clipped.hit: breaks.append(float(clipped.enter)); breaks.append(float(clipped.exit))
	breaks.sort(); var unique: Array = []
	for value in breaks:
		if unique.is_empty() or absf(float(value) - float(unique.back())) > float(_rules.epsilon): unique.append(value)
	var result: Array = []
	for index in range(unique.size() - 1):
		var a := float(unique[index]); var b := float(unique[index + 1]); if b - a <= 0.000001: continue
		var mid := start.lerp(finish, (a + b) * 0.5); var effects := point_effects([mid.x, mid.y]); var p0 := start.lerp(finish, a); var p1 := start.lerp(finish, b)
		result.append({"from": [p0.x, p0.y], "to": [p1.x, p1.y], "length": p0.distance_to(p1), "zone_ids": effects.zone_ids.duplicate(), "effects": effects})
	if result.is_empty():
		var effects := point_effects([start.x, start.y]); result.append({"from": [start.x, start.y], "to": [finish.x, finish.y], "length": start.distance_to(finish), "zone_ids": effects.zone_ids.duplicate(), "effects": effects})
	return result

func _clip_rect(start: Vector2, finish: Vector2, shape: Dictionary) -> Dictionary:
	var dx := finish.x - start.x; var dy := finish.y - start.y; var t0 := 0.0; var t1 := 1.0
	var checks := [[-dx, start.x - float(shape.x)], [dx, float(shape.x + shape.width) - start.x], [-dy, start.y - float(shape.y)], [dy, float(shape.y + shape.height) - start.y]]
	for check in checks:
		var p := float(check[0]); var q := float(check[1])
		if absf(p) <= 0.000001:
			if q < -float(_rules.epsilon): return {"hit": false}
		else:
			var t := q / p
			if p < 0.0: t0 = maxf(t0, t)
			else: t1 = minf(t1, t)
			if t0 > t1 + float(_rules.epsilon): return {"hit": false}
	return {"hit": true, "enter": clampf(t0, 0.0, 1.0), "exit": clampf(t1, 0.0, 1.0)}

func _inside(point: Array, shape: Dictionary) -> bool:
	var e := float(_rules.epsilon); return float(point[0]) >= float(shape.x) - e and float(point[0]) <= float(shape.x + shape.width) + e and float(point[1]) >= float(shape.y) - e and float(point[1]) <= float(shape.y + shape.height) + e

func _stack(zone_ids: Array) -> Dictionary:
	var movement_cost := 10000; var sensor := 0; var concealment := 0
	for zone_id in zone_ids:
		var effects: Dictionary = _zone(zone_id).effects; movement_cost = maxi(movement_cost, int(effects.movement_cost_basis_points))
		sensor += int(effects.observer_sensor_percent); concealment += int(effects.target_concealment_points)
	return {"zone_ids": zone_ids.duplicate(), "movement_cost_basis_points": movement_cost, "observer_sensor_percent": clampi(sensor, -60, 30),
		"target_concealment_points": concealment}

func _segment_zone_ids(start: Vector2, finish: Vector2) -> Array:
	var ids: Array = []
	for zone in _rules.zones:
		if _clip_rect(start, finish, zone.shape).hit: ids.append(String(zone.id))
	ids.sort(); return ids

func _transition_events(segments: Array) -> Array:
	var result: Array = []; var previous: Array = []
	for index in range(segments.size()):
		var current: Array = segments[index].zone_ids
		if current != previous: result.append({"event_type": "terrain_transition", "segment_index": index, "position": segments[index].from.duplicate(), "entered_zone_ids": current.filter(func(id): return not previous.has(id)), "exited_zone_ids": previous.filter(func(id): return not current.has(id)), "active_zone_ids": current.duplicate()})
		previous = current.duplicate()
	return result

func _touch_events(segments: Array) -> Array:
	var result: Array = []; var seen := {}
	for index in range(segments.size()):
		var segment: Dictionary = segments[index]; var start := Vector2(float(segment.from[0]), float(segment.from[1])); var finish := Vector2(float(segment.to[0]), float(segment.to[1]))
		for zone_id in _segment_zone_ids(start, finish):
			if segment.zone_ids.has(zone_id) or seen.has(zone_id): continue
			seen[zone_id] = true; result.append({"event_type": "terrain_membership", "segment_index": index,
				"position": segment.to.duplicate(), "zone_id": zone_id, "traversal_length": 0.0, "membership": "boundary_touch"})
	return result

func _zone(zone_id: String) -> Dictionary:
	for zone in _rules.zones:
		if String(zone.id) == zone_id: return zone
	return {}

func _load_rules(bounds: Array) -> Dictionary:
	var file := FileAccess.open(RULES_PATH, FileAccess.READ); if file == null: return _error("적벽 terrain 규칙을 열 수 없습니다.")
	var parsed = JSON.parse_string(file.get_as_text()); if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1 or String(parsed.get("profile_id", "")) != "normal-demo-terrain-v1": return _error("지원하지 않는 적벽 terrain 프로필입니다.")
	if String(parsed.get("boundary_policy", "")) != "inclusive_with_epsilon; segment_clip_entry_exit; zero_length_samples_point" or String(parsed.get("same_turn_order", "")) != "movement_budget_then_detection_then_weapon_eligibility_then_phase_ledger": return _error("terrain 경계·순서 계약이 잘못되었습니다.")
	if String(parsed.get("numeric_policy", "")) != "integer_basis_points_and_half_up_modifiers; deterministic_float_geometry_epsilon_0.001": return _error("terrain 수치 정밀도 계약이 잘못되었습니다.")
	var stacking = parsed.get("stacking", {})
	if not stacking is Dictionary or String(stacking.get("zone_order", "")) != "zone_id_asc" or String(stacking.get("movement", "")) != "max_cost_basis_points_no_duplicate_distance" or String(stacking.get("sensor", "")) != "additive_percent_clamp_minus60_plus30" or String(stacking.get("concealment", "")) != "additive_points" or String(stacking.get("weapon_range", "")) != "segment_membership_zone_id_asc_sequential_half_up_basis_points" or String(stacking.get("weapon_arc", "")) != "segment_membership_additive_degrees_clamp_0_360": return _error("terrain stacking 계약이 잘못되었습니다.")
	if not parsed.get("zones") is Array or parsed.zones.size() != 3: return _error("성운·잔해·행성 그림자 3개 zone이 필요합니다.")
	var ids := {}; var types: Array = []
	for zone in parsed.zones:
		if not zone is Dictionary or ids.has(String(zone.get("id", ""))) or not zone.get("shape") is Dictionary or String(zone.shape.get("kind", "")) != "rect" or not zone.get("effects") is Dictionary: return _error("terrain zone 스키마가 잘못되었습니다.")
		ids[String(zone.id)] = true; types.append(String(zone.type)); var s: Dictionary = zone.shape
		if float(s.get("width", 0)) <= 0 or float(s.get("height", 0)) <= 0 or float(s.get("x", -1)) < float(bounds[0]) or float(s.x + s.width) > float(bounds[0] + bounds[2]) or float(s.get("y", -1)) < float(bounds[1]) or float(s.y + s.height) > float(bounds[1] + bounds[3]): return _error("terrain zone이 전장 경계 밖입니다.")
		var effects: Dictionary = zone.effects
		if int(effects.get("movement_cost_basis_points", 0)) < 10000 or int(effects.get("weapon_range_basis_points", 0)) <= 0 or int(effects.weapon_range_basis_points) > 10000 or int(effects.get("observer_sensor_percent", -999)) < -100 or int(effects.get("target_concealment_points", -1)) < 0 or int(effects.get("weapon_arc_delta_deg", 1)) > 0: return _error("terrain 효과 값이 잘못되었습니다: %s" % String(zone.id))
	types.sort(); if types != ["debris", "nebula", "planet_shadow"]: return _error("terrain 종류가 정확하지 않습니다.")
	parsed.zones.sort_custom(func(a, b): return String(a.id) < String(b.id)); return {"ok": true, "errors": [], "rules": parsed.duplicate(true)}

func _ok() -> Dictionary: return {"ok": true, "errors": []}
func _error(message: String) -> Dictionary: return {"ok": false, "errors": [message]}
