class_name RedCliffsAiPlanner
extends RefCounted

## DEMO-RC-G5-05 — viewer-safe 입력만 소비하는 결정론적 손권·조조 AI planner.
const RULES_PATH := "res://data/red-cliffs-ai-rules.json"
var _rules: Dictionary = {}

func initialize() -> Dictionary:
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null: return _error("AI 규칙 파일을 열 수 없습니다.")
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1 \
			or String(parsed.get("profile_id", "")) != "normal-demo-ai-v1": return _error("지원하지 않는 AI 규칙입니다.")
	if not parsed.get("postures") is Dictionary or parsed.postures.keys().size() != 2 \
			or not parsed.postures.has("sun_quan") or not parsed.postures.has("cao_cao"): return _error("손권·조조 AI 자세 규칙이 필요합니다.")
	if not parsed.get("alliances") is Array or parsed.alliances != [["liu_bei", "sun_quan"]]: return _error("데모 동맹 규칙이 잘못되었습니다.")
	for faction_id in ["sun_quan", "cao_cao"]:
		var row = parsed.postures[faction_id]
		if not row is Dictionary or String(row.get("formation_id", "")).is_empty() or String(row.get("weapon_preset_id", "")).is_empty(): return _error("AI 진형·무기 규칙이 누락되었습니다: %s" % faction_id)
		if not row.get("patrol_offset") is Array or row.patrol_offset.size() != 2 or not row.get("estimated_fire") is Dictionary: return _error("AI 순찰·추정 사격 규칙이 잘못되었습니다: %s" % faction_id)
		var chain_rule = row.get("chain_explosion_risk_response")
		if not chain_rule is Dictionary or not chain_rule.get("enabled") is bool or not chain_rule.get("turn_modulo_actions") is Array or chain_rule.turn_modulo_actions.is_empty(): return _error("연쇄 폭발 위험 대응 규칙이 잘못되었습니다: %s" % faction_id)
		if bool(chain_rule.enabled) != (String(faction_id) == "cao_cao"): return _error("연쇄 폭발 위험 대응 권한은 조조 AI에만 있어야 합니다.")
		var allowed_actions := ["hold", "ew_conceal", "formation_disperse", "standard_pressure", "interception_screen", "range_exit"]
		var seen_actions := {}
		for action in chain_rule.turn_modulo_actions:
			if not allowed_actions.has(String(action)) or seen_actions.has(String(action)): return _error("연쇄 폭발 위험 대응 행동이 잘못되었습니다: %s" % faction_id)
			seen_actions[String(action)] = true
		if bool(chain_rule.enabled) and not ["ew_conceal", "formation_disperse", "interception_screen", "range_exit"].all(func(action): return seen_actions.has(action)): return _error("조조 AI의 연쇄 폭발 방해 행동이 누락되었습니다.")
	_rules = parsed.duplicate(true)
	return _ok()

func rules_snapshot() -> Dictionary: return _rules.duplicate(true)

func disposition(viewer_faction_id: String, target_faction_id: String) -> String:
	if viewer_faction_id == target_faction_id: return "friendly"
	for pair in _rules.get("alliances", []):
		if pair is Array and pair.has(viewer_faction_id) and pair.has(target_faction_id): return "allied"
	return "hostile"

func plan(viewer: Dictionary, scheduled_resources: Dictionary, turn_number: int) -> Dictionary:
	if _rules.is_empty(): return _error("AI planner가 초기화되지 않았습니다.")
	var faction_id := String(viewer.get("viewer_faction_id", ""))
	if not _rules.postures.has(faction_id) or turn_number < 1: return _error("지원하지 않는 AI 세력 또는 턴입니다.")
	if int(viewer.get("turn", 0)) != turn_number or not viewer.get("own_squadrons") is Array \
			or not viewer.get("own_navigation") is Dictionary or not viewer.get("contacts") is Array \
			or not viewer.get("terrain_zones") is Array or not viewer.get("own_terrain_membership") is Dictionary: return _error("viewer-safe AI snapshot이 잘못되었습니다.")
	if String(scheduled_resources.get("viewer_faction_id", "")) != faction_id or not scheduled_resources.get("resource_state") is Dictionary: return _error("자기 예약 자원 preview가 필요합니다.")
	var posture: Dictionary = _rules.postures[faction_id]
	var target := _select_contact(viewer.contacts)
	var chain_risk: Dictionary = _chain_risk_contact(viewer, posture)
	var risk_action := ""
	if not chain_risk.is_empty(): risk_action = String(posture.chain_explosion_risk_response.turn_modulo_actions[turn_number % posture.chain_explosion_risk_response.turn_modulo_actions.size()])
	var bounds: Array = viewer.get("battlefield_bounds", [])
	if bounds.size() != 4: return _error("공개 전장 경계가 필요합니다.")
	var orders: Array = []; var formations: Array = []; var presets: Array = []; var estimates: Array = []; var intents: Array = []
	var squads: Array = viewer.own_squadrons.duplicate(true)
	squads.sort_custom(func(a, b): return String(a.get("id", "")) < String(b.get("id", "")))
	for squad in squads:
		var squadron_id := String(squad.get("id", "")); var navigation: Dictionary = viewer.own_navigation.get(squadron_id, {})
		if not navigation.get("position") is Array: return _error("자기 전대 위치가 누락되었습니다: %s" % squadron_id)
		var resource_row: Dictionary = scheduled_resources.resource_state.get(squadron_id, {})
		var reserve := int(resource_row.get("reserve_basis_points", 0)); var ready: bool = not resource_row.get("ready_weapon_ids", []).is_empty()
		var confirmed: bool = not target.is_empty() and String(target.state) == "confirmed"
		var estimated_allowed: bool = not target.is_empty() and String(target.state) == "estimated" and _estimated_allowed(target, reserve, posture.estimated_fire)
		# Faction behavior must be entirely posture-driven.  This keeps Sun and Cao
		# on the same planner path and makes the profile the only source of variance.
		var preserve: bool = String(posture.no_contact_action) == "hold" and not confirmed and not estimated_allowed
		var formation_id := String(viewer.get("own_formation_state", {}).get(squadron_id, {}).get("formation_id", posture.formation_id)) if preserve else String(posture.formation_id)
		var current_weapon: Dictionary = viewer.get("own_weapon_allocation_state", {}).get(squadron_id, {}); var preset_id := "" if preserve else String(posture.weapon_preset_id)
		if risk_action == "formation_disperse" or risk_action == "range_exit": formation_id = String(posture.chain_explosion_risk_response.dispersed_formation_id)
		if risk_action == "interception_screen": preset_id = String(posture.chain_explosion_risk_response.interception_preset_id)
		formations.append({"squadron_id": squadron_id, "formation_id": formation_id})
		presets.append({"squadron_id": squadron_id, "preset_id": preset_id,
			"hold_fire": bool(current_weapon.get("hold_fire", false)) if preserve else not ready})
		if not risk_action.is_empty() and risk_action != "standard_pressure":
			if risk_action == "range_exit": orders.append(_evade_order(squadron_id, navigation.position, chain_risk.display_position, float(posture.chain_explosion_risk_response.evade_step), bounds))
			elif risk_action == "ew_conceal": orders.append(_flow_zone_order(squadron_id, navigation.position, viewer.terrain_zones, String(posture.chain_explosion_risk_response.public_flow_zone_id), bounds))
			else: orders.append({"squadron_id": squadron_id, "action": "hold"})
			intents.append({"squadron_id": squadron_id, "category": "chain_counter_%s" % risk_action, "reason_label": "공개 접촉·성운 흐름 기반 연쇄 폭발 위험 대응", "contact_id": String(chain_risk.contact_id), "reserve_basis_points": reserve})
		elif confirmed:
			var move := _pursuit_order(squadron_id, navigation.position, target.display_position, posture, bounds)
			orders.append(move)
			intents.append({"squadron_id": squadron_id, "category": "confirmed_engage", "reason_label": "확인 표적에 공개 위치 기반 접근·교전", "contact_id": String(target.contact_id), "reserve_basis_points": reserve})
		elif estimated_allowed:
			orders.append({"squadron_id": squadron_id, "action": "hold"})
			estimates.append({"squadron_id": squadron_id, "contact_id": String(target.contact_id)})
			intents.append({"squadron_id": squadron_id, "category": "estimated_fire", "reason_label": "신뢰도·자원 기준을 충족한 제한 추정 사격", "contact_id": String(target.contact_id), "confidence_basis_points": int(target.confidence_basis_points), "reserve_basis_points": reserve})
		else:
			orders.append(_no_contact_order(squadron_id, navigation.position, posture, bounds))
			var category := "resource_conserve" if not target.is_empty() else String(posture.no_contact_action)
			intents.append({"squadron_id": squadron_id, "category": category, "reason_label": "접촉 없음 또는 추정 사격 기준 미달", "reserve_basis_points": reserve})
	return {"ok": true, "errors": [], "source": "normal-demo-ai-v1", "faction_id": faction_id,
		"posture": String(posture.id), "orders": orders, "formation_orders": formations,
		"weapon_preset_orders": presets, "estimated_fire_intents": estimates, "intents": intents}

func _chain_risk_contact(viewer: Dictionary, posture: Dictionary) -> Dictionary:
	var response: Dictionary = posture.chain_explosion_risk_response
	if not bool(response.enabled): return {}
	var own_rows: Array = viewer.own_navigation.values()
	if own_rows.is_empty(): return {}
	var own: Array = own_rows[0].position; var zone := {}
	for value in viewer.terrain_zones:
		if String(value.get("zone_id", "")) == String(response.public_flow_zone_id): zone = value; break
	if zone.is_empty(): return {}
	var risks: Array = []
	for value in viewer.contacts:
		if not value is Dictionary or String(value.get("state", "")) != "confirmed" or String(value.get("disposition", "")) != "hostile" or not value.get("display_position") is Array: continue
		var target: Array = value.display_position; var distance := Vector2(float(own[0]), float(own[1])).distance_to(Vector2(float(target[0]), float(target[1])))
		if distance <= float(response.trigger_distance) and _segment_bbox_touches_rect(own, target, zone.shape):
			var row: Dictionary = value.duplicate(true)
			row["risk_distance"] = distance
			risks.append(row)
	risks.sort_custom(func(a, b):
		if not is_equal_approx(float(a.risk_distance), float(b.risk_distance)): return float(a.risk_distance) < float(b.risk_distance)
		return String(a.contact_id) < String(b.contact_id))
	return {} if risks.is_empty() else risks[0]

func _segment_bbox_touches_rect(a: Array, b: Array, shape: Dictionary) -> bool:
	return maxf(float(a[0]), float(b[0])) >= float(shape.x) and minf(float(a[0]), float(b[0])) <= float(shape.x + shape.width) and maxf(float(a[1]), float(b[1])) >= float(shape.y) and minf(float(a[1]), float(b[1])) <= float(shape.y + shape.height)

func _evade_order(squadron_id: String, from: Array, threat: Array, step: float, bounds: Array) -> Dictionary:
	var start := Vector2(float(from[0]), float(from[1])); var away := start - Vector2(float(threat[0]), float(threat[1])); if away.length() <= 0.0001: away = Vector2.RIGHT
	var waypoint := start + away.normalized() * step; waypoint.x = clampf(waypoint.x, float(bounds[0]), float(bounds[2])); waypoint.y = clampf(waypoint.y, float(bounds[1]), float(bounds[3]))
	return {"squadron_id": squadron_id, "action": "move", "waypoints": [[waypoint.x, waypoint.y]], "facing_deg": fposmod(rad_to_deg(atan2(away.y, away.x)), 360.0)}

func _flow_zone_order(squadron_id: String, from: Array, zones: Array, zone_id: String, bounds: Array) -> Dictionary:
	for value in zones:
		if String(value.get("zone_id", "")) != zone_id: continue
		var shape: Dictionary = value.shape; var center := [float(shape.x) + float(shape.width) * 0.5, float(shape.y) + float(shape.height) * 0.5]
		return _pursuit_order(squadron_id, from, center, {"pursuit_step": 110, "confirmed_standoff": 0}, bounds)
	return {"squadron_id": squadron_id, "action": "hold"}

func _select_contact(values: Array) -> Dictionary:
	var contacts: Array = []
	for value in values:
		if value is Dictionary and String(value.get("disposition", "")) == "hostile" and ["confirmed", "estimated"].has(String(value.get("state", ""))): contacts.append(value)
	contacts.sort_custom(func(a, b):
		var ar := 0 if String(a.state) == "confirmed" else 1; var br := 0 if String(b.state) == "confirmed" else 1
		if ar != br: return ar < br
		if int(a.get("confidence_basis_points", 0)) != int(b.get("confidence_basis_points", 0)): return int(a.get("confidence_basis_points", 0)) > int(b.get("confidence_basis_points", 0))
		if int(a.get("staleness_turns", 0)) != int(b.get("staleness_turns", 0)): return int(a.get("staleness_turns", 0)) < int(b.get("staleness_turns", 0))
		return String(a.contact_id) < String(b.contact_id))
	return {} if contacts.is_empty() else contacts[0].duplicate(true)

func _estimated_allowed(contact: Dictionary, reserve: int, rule: Dictionary) -> bool:
	return bool(rule.enabled) and int(contact.get("staleness_turns", 99)) <= int(rule.max_staleness_turns) \
		and int(contact.get("confidence_basis_points", 0)) >= int(rule.minimum_confidence_basis_points) \
		and reserve >= int(rule.minimum_resource_reserve_basis_points)

func _pursuit_order(squadron_id: String, from: Array, target: Array, posture: Dictionary, bounds: Array) -> Dictionary:
	var start := Vector2(float(from[0]), float(from[1])); var end := Vector2(float(target[0]), float(target[1])); var delta := end - start
	var distance := delta.length(); var travel := minf(float(posture.pursuit_step), maxf(0.0, distance - float(posture.confirmed_standoff)))
	var waypoint := start if distance <= 0.0001 else start + delta.normalized() * travel
	waypoint.x = clampf(waypoint.x, float(bounds[0]), float(bounds[2])); waypoint.y = clampf(waypoint.y, float(bounds[1]), float(bounds[3]))
	var facing := 0.0 if distance <= 0.0001 else fposmod(rad_to_deg(atan2(delta.y, delta.x)), 360.0)
	return {"squadron_id": squadron_id, "action": "move", "waypoints": [[waypoint.x, waypoint.y]], "facing_deg": facing}

func _no_contact_order(squadron_id: String, from: Array, posture: Dictionary, bounds: Array) -> Dictionary:
	if String(posture.no_contact_action) == "hold": return {"squadron_id": squadron_id, "action": "hold"}
	var waypoint := [clampf(float(from[0]) + float(posture.patrol_offset[0]), float(bounds[0]), float(bounds[2])), clampf(float(from[1]) + float(posture.patrol_offset[1]), float(bounds[1]), float(bounds[3]))]
	var facing := fposmod(rad_to_deg(atan2(float(waypoint[1]) - float(from[1]), float(waypoint[0]) - float(from[0]))), 360.0)
	return {"squadron_id": squadron_id, "action": "move", "waypoints": [waypoint], "facing_deg": facing}

func _ok() -> Dictionary: return {"ok": true, "errors": []}
func _error(message: String) -> Dictionary: return {"ok": false, "errors": [message]}
