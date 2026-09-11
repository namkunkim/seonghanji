class_name RedCliffsMovementResolver
extends RefCounted

## DEMO-RC-G4-02 — 자유 좌표·다중 경유점·방향 이동 판정의 단일 권위.
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Draft := preload("res://core/demo_red_cliffs/red_cliffs_formation_draft.gd")
const Terrain := preload("res://core/demo_red_cliffs/red_cliffs_terrain_resolver.gd")
const RULES_PATH := "res://data/red-cliffs-movement-rules.json"

var _setup: Dictionary = {}
var _rules: Dictionary = {}
var _draft
var _terrain


func initialize(applied_setup: Dictionary) -> Dictionary:
	var setup_result := Setup.validate_document(applied_setup)
	if not bool(setup_result.get("ok", false)):
		return _error("유효한 G3 적용 편성이 필요합니다.")
	var rules_result := _load_rules()
	if not bool(rules_result.get("ok", false)): return rules_result
	_setup = setup_result.setup.duplicate(true)
	_rules = rules_result.rules.duplicate(true)
	_draft = Draft.new(_setup)
	var terrain = Terrain.new(); var terrain_result: Dictionary = terrain.initialize(_setup)
	if not terrain_result.ok: return terrain_result
	_terrain = terrain
	return _ok()


func rules_snapshot() -> Dictionary:
	return _rules.duplicate(true)


func initial_navigation() -> Dictionary:
	var result := {}
	if _setup.is_empty(): return result
	var default_facing := float(_rules.get("default_facing_deg", 0))
	for squad in _setup.get("squadrons", []):
		result[String(squad.id)] = {
			"position": squad.initial_position.duplicate(),
			"facing_deg": float(squad.get("initial_facing_deg", default_facing)),
		}
	return result


func effective_speed(squadron_id: String) -> Dictionary:
	var squad := _find_squad(squadron_id)
	if squad.is_empty(): return _error("미지 전대입니다: %s" % squadron_id)
	var slowest := 0
	for component in squad.get("composition", []):
		if int(component.get("count", 0)) <= 0: continue
		var ship_id := String(component.get("ship_type_id", ""))
		var speed := int(_rules.get("base_speed_by_ship_type", {}).get(ship_id, 0))
		if speed <= 0: return _error("함종 기본 속도가 없습니다: %s" % ship_id)
		if slowest == 0 or speed < slowest: slowest = speed
	if slowest <= 0: return _error("operational 함종이 없는 전대입니다: %s" % squadron_id)
	var metrics: Dictionary = _draft.squadron_metrics(squadron_id)
	var mobility_percent := int(metrics.get("mobility_percent", 0))
	var adjusted := maxi(1, int(floor(float(slowest) * float(100 + mobility_percent) / 100.0)))
	return {"ok": true, "errors": [], "base_speed": slowest, "mobility_percent": mobility_percent,
		"effective_speed": adjusted}


func movement_preview(squadron_id: String, waypoints: Array, facing_deg, live_navigation: Dictionary) -> Dictionary:
	if _setup.is_empty(): return _error("이동 판정기가 초기화되지 않았습니다.")
	if not live_navigation.has(squadron_id): return _error("전대 live 위치가 없습니다: %s" % squadron_id)
	var max_waypoints := int(_rules.get("max_waypoints", 5))
	if waypoints.is_empty() or waypoints.size() > max_waypoints:
		return _error("경유점은 1~%d개여야 합니다." % max_waypoints)
	var bounds: Array = _setup.battlefield_bounds
	for waypoint in waypoints:
		if not _valid_point(waypoint, bounds): return _error("경유점이 finite 전장 경계 안 좌표가 아닙니다.")
	if not _valid_facing(facing_deg): return _error("방향은 0 이상 360 미만의 finite 각도여야 합니다.")
	var current_row = live_navigation[squadron_id]
	if not current_row is Dictionary or not _valid_point(current_row.get("position"), bounds):
		return _error("현재 전대 위치가 잘못되었습니다: %s" % squadron_id)
	var speed := effective_speed(squadron_id)
	if not speed.ok: return speed
	var cursor := Vector2(float(current_row.position[0]), float(current_row.position[1]))
	var total_distance := 0.0
	var heading_deg := float(facing_deg)
	var heading_found := false
	for waypoint in waypoints:
		var target := Vector2(float(waypoint[0]), float(waypoint[1]))
		if not heading_found and not cursor.is_equal_approx(target):
			heading_deg = fposmod(rad_to_deg(atan2(target.y - cursor.y, target.x - cursor.x)), 360.0)
			heading_found = true
		total_distance += cursor.distance_to(target)
		cursor = target
	var movement: Dictionary = _terrain.follow_waypoints(current_row.position, waypoints, int(speed.effective_speed))
	var eta_turns := int(ceil(total_distance / float(speed.effective_speed))) if total_distance > 0.0 else 0
	return {"ok": true, "errors": [], "waypoints": waypoints.duplicate(true), "max_waypoints": max_waypoints,
		"heading_deg": heading_deg, "facing_deg": float(facing_deg), "total_distance": total_distance,
		"movement_budget": int(speed.effective_speed), "within_budget": total_distance <= float(speed.effective_speed),
		"eta_turns": eta_turns, "predicted_position": movement.to.duplicate(),
		"path_complete": bool(movement.path_complete), "remaining_distance": float(movement.remaining_distance),
		"effective_speed": int(speed.effective_speed), "terrain_segments": movement.terrain_segments.duplicate(true),
		"terrain_events": movement.terrain_events.duplicate(true)}


func resolve_orders(orders: Array, live_navigation: Dictionary) -> Dictionary:
	if _setup.is_empty(): return _error("이동 판정기가 초기화되지 않았습니다.")
	var navigation_check := _validate_navigation(live_navigation)
	if not navigation_check.ok: return navigation_check
	var rows: Array = []
	var seen := {}
	for value in orders:
		if not value is Dictionary: return _error("이동 판정 명령은 객체여야 합니다.")
		var order: Dictionary = value
		var squadron_id := String(order.get("squadron_id", ""))
		if not _operational_squadron_ids().has(squadron_id) or seen.has(squadron_id):
			return _error("미지 또는 중복 전대 이동 명령입니다: %s" % squadron_id)
		seen[squadron_id] = true
		if String(order.get("action", "")) == "hold":
			if order.size() != 2: return _error("hold 명령에는 이동 필드를 지정할 수 없습니다.")
		elif String(order.get("action", "")) == "move":
			if order.size() != 4 or not order.has("waypoints") or not order.has("facing_deg") or not order.waypoints is Array:
				return _error("move 명령에는 waypoints와 facing_deg가 필요합니다.")
			var preview := movement_preview(squadron_id, order.waypoints, order.facing_deg, live_navigation)
			if not preview.ok: return preview
		else:
			return _error("hold 또는 move 명령만 허용합니다.")
		var speed_result := effective_speed(squadron_id)
		if not speed_result.ok: return speed_result
		rows.append({"order": order.duplicate(true), "speed": speed_result})
	if seen.size() != _operational_squadron_ids().size():
		return _error("모든 operational 전대의 이동 명령이 필요합니다.")
	rows.sort_custom(func(a, b):
		if int(a.speed.effective_speed) != int(b.speed.effective_speed):
			return int(a.speed.effective_speed) > int(b.speed.effective_speed)
		return String(a.order.squadron_id) < String(b.order.squadron_id))
	var next_navigation := live_navigation.duplicate(true)
	var events: Array = []; var terrain_events: Array = []
	for index in range(rows.size()):
		var row: Dictionary = rows[index]
		var order: Dictionary = row.order
		var squadron_id := String(order.squadron_id)
		var current: Dictionary = next_navigation[squadron_id]
		var from: Array = current.position.duplicate()
		if String(order.action) == "hold":
			var hold_effects: Dictionary = _terrain.point_effects(from)
			events.append({"squadron_id": squadron_id, "action": "hold", "order_index": index,
				"from": from, "to": from.duplicate(), "requested_waypoints": [], "reached_waypoints": [],
				"actual_distance": 0.0, "remaining_distance": 0.0, "path_complete": true,
				"from_facing_deg": float(current.facing_deg), "facing_deg": float(current.facing_deg),
				"base_speed": int(row.speed.base_speed), "effective_speed": int(row.speed.effective_speed),
				"terrain_segments": [{"from": from.duplicate(), "to": from.duplicate(), "length": 0.0,
					"zone_ids": hold_effects.zone_ids.duplicate(), "effects": hold_effects.duplicate(true)}], "terrain_budget_applied": false})
			if not hold_effects.zone_ids.is_empty(): terrain_events.append({"event_type": "terrain_stay", "squadron_id": squadron_id,
				"position": from.duplicate(), "active_zone_ids": hold_effects.zone_ids.duplicate(), "traversal_length": 0.0})
			continue
		var movement: Dictionary = _terrain.follow_waypoints(from, order.waypoints, int(row.speed.effective_speed))
		current.position = movement.to.duplicate()
		current.facing_deg = float(order.facing_deg)
		events.append({"squadron_id": squadron_id, "action": "move", "order_index": index,
			"from": from, "to": movement.to.duplicate(), "requested_waypoints": order.waypoints.duplicate(true),
			"reached_waypoints": movement.reached_waypoints.duplicate(true),
			"actual_distance": movement.actual_distance, "remaining_distance": movement.remaining_distance,
			"path_complete": movement.path_complete, "from_facing_deg": float(current.facing_deg),
			"facing_deg": float(order.facing_deg),
			"base_speed": int(row.speed.base_speed), "effective_speed": int(row.speed.effective_speed),
			"terrain_segments": movement.terrain_segments.duplicate(true), "terrain_budget_applied": true})
		for terrain_event in movement.terrain_events:
			var decorated: Dictionary = terrain_event.duplicate(true); decorated["squadron_id"] = squadron_id; terrain_events.append(decorated)
	return {"ok": true, "errors": [], "events": events, "terrain_events": terrain_events, "live_navigation": next_navigation}


func _follow_waypoints(from: Array, waypoints: Array, budget: int) -> Dictionary:
	var current := Vector2(float(from[0]), float(from[1]))
	var remaining := float(budget)
	var actual := 0.0
	var reached: Array = []
	for waypoint in waypoints:
		var target := Vector2(float(waypoint[0]), float(waypoint[1]))
		var distance := current.distance_to(target)
		if distance <= remaining + 0.000001:
			current = target
			remaining -= distance
			actual += distance
			reached.append([target.x, target.y])
		elif remaining > 0.0 and distance > 0.0:
			current += (target - current) * (remaining / distance)
			actual += remaining
			remaining = 0.0
			break
		else:
			break
	var remaining_distance := 0.0
	var remainder_cursor := current
	for index in range(reached.size(), waypoints.size()):
		var target := Vector2(float(waypoints[index][0]), float(waypoints[index][1]))
		remaining_distance += remainder_cursor.distance_to(target)
		remainder_cursor = target
	return {"to": [current.x, current.y], "actual_distance": actual, "reached_waypoints": reached,
		"remaining_distance": remaining_distance, "path_complete": remaining_distance <= 0.000001}


func _operational_squadron_ids() -> Array:
	var result: Array = []
	for squad in _setup.get("squadrons", []):
		if bool(squad.get("operational", true)): result.append(String(squad.get("id", "")))
	result.sort()
	return result


func _validate_navigation(navigation: Dictionary) -> Dictionary:
	var bounds: Array = _setup.battlefield_bounds
	for squad in _setup.squadrons:
		var squadron_id := String(squad.id)
		if not navigation.has(squadron_id) or not navigation[squadron_id] is Dictionary:
			return _error("전대 live 위치가 누락되었습니다: %s" % squadron_id)
		var row: Dictionary = navigation[squadron_id]
		if not _valid_point(row.get("position"), bounds) or not _valid_facing(row.get("facing_deg")):
			return _error("전대 live 위치 또는 방향이 잘못되었습니다: %s" % squadron_id)
	return _ok()


func _load_rules() -> Dictionary:
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null: return _error("이동 규칙 파일을 열 수 없습니다.")
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary: return _error("이동 규칙 JSON이 올바르지 않습니다.")
	if int(parsed.get("schema_version", 0)) != 1 or String(parsed.get("profile_id", "")) != "normal-demo-movement-v1":
		return _error("지원하지 않는 이동 규칙 프로필입니다.")
	if String(parsed.get("statement", "")).is_empty() or int(parsed.get("max_waypoints", 0)) != 5:
		return _error("이동 규칙의 밸런스 고지 또는 최대 경유점이 잘못되었습니다.")
	if not parsed.get("base_speed_by_ship_type") is Dictionary: return _error("함종 기본 속도가 필요합니다.")
	var speeds: Dictionary = parsed.base_speed_by_ship_type
	for index in range(1, 9):
		var ship_id := "SHP-%02d" % index
		if not _positive_integer(speeds.get(ship_id)):
			return _error("양의 정수 함종 기본 속도가 필요합니다: %s" % ship_id)
	return {"ok": true, "errors": [], "rules": parsed.duplicate(true)}


func _find_squad(squadron_id: String) -> Dictionary:
	for squad in _setup.get("squadrons", []):
		if String(squad.get("id", "")) == squadron_id: return squad
	return {}


func _valid_point(value, bounds: Array) -> bool:
	return value is Array and value.size() == 2 and _finite_number(value[0]) and _finite_number(value[1]) \
		and float(value[0]) >= float(bounds[0]) and float(value[1]) >= float(bounds[1]) \
		and float(value[0]) <= float(bounds[0]) + float(bounds[2]) \
		and float(value[1]) <= float(bounds[1]) + float(bounds[3])


func _valid_facing(value) -> bool:
	return _finite_number(value) and float(value) >= 0.0 and float(value) < 360.0


func _finite_number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _positive_integer(value) -> bool:
	return _finite_number(value) and float(value) > 0.0 and is_equal_approx(float(value), floor(float(value)))


func _ok() -> Dictionary: return {"ok": true, "errors": []}
func _error(message: String) -> Dictionary: return {"ok": false, "errors": [message]}
