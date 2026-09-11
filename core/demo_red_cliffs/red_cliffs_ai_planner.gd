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
		var current_weapon: Dictionary = viewer.get("own_weapon_allocation_state", {}).get(squadron_id, {})
		formations.append({"squadron_id": squadron_id, "formation_id": formation_id})
		presets.append({"squadron_id": squadron_id, "preset_id": "" if preserve else String(posture.weapon_preset_id),
			"hold_fire": bool(current_weapon.get("hold_fire", false)) if preserve else not ready})
		if confirmed:
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
