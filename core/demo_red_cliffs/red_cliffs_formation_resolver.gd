class_name RedCliffsFormationResolver
extends RefCounted

## DEMO-RC-G4-04 — 진형 명령, 방향 sector와 결과 전 보정 snapshot의 코어 권위.
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Draft := preload("res://core/demo_red_cliffs/red_cliffs_formation_draft.gd")
const RULES_PATH := "res://data/red-cliffs-formation-rules.json"

var _setup: Dictionary = {}
var _rules: Dictionary = {}
var _draft


func initialize(applied_setup: Dictionary) -> Dictionary:
	var checked := Setup.validate_document(applied_setup)
	if not checked.ok: return _error("유효한 G3 적용 편성이 필요합니다.")
	var loaded := _load_rules()
	if not loaded.ok: return loaded
	_setup = checked.setup.duplicate(true)
	_rules = loaded.rules.duplicate(true)
	_draft = Draft.new(_setup)
	return _ok()


func rules_snapshot() -> Dictionary: return _rules.duplicate(true)


func allowed_formations() -> Array:
	var result: Array = []
	var ids: Array = _rules.get("formations", {}).keys(); ids.sort()
	for formation_id in ids:
		var row: Dictionary = _rules.formations[formation_id]
		result.append({"formation_id": String(formation_id), "name": String(row.name),
			"role": String(row.role), "modifiers": _modifier_values(row)})
	return result


func initial_state() -> Dictionary:
	var result := {}
	for squad in _operational_squadrons():
		result[String(squad.id)] = {"squadron_id": String(squad.id),
			"faction_id": String(squad.faction_id), "formation_id": String(squad.formation_id),
			"modifier_effectiveness_basis_points": 10000, "effective_turn": 0, "source": "applied_g3_setup"}
	return result


func validate_order(squadron_id: String, formation_id: String) -> Dictionary:
	if _setup.is_empty(): return _error("진형 판정기가 초기화되지 않았습니다.")
	if not _operational_ids().has(squadron_id): return _error("미지 또는 비가동 전대입니다: %s" % squadron_id)
	if not _rules.formations.has(formation_id): return _error("허용되지 않은 진형입니다: %s" % formation_id)
	return _ok()


func command_penalty_metrics(squadron_id: String) -> Dictionary:
	if _draft == null: return _error("진형 판정기가 초기화되지 않았습니다.")
	var metrics: Dictionary = _draft.squadron_metrics(squadron_id)
	if metrics.is_empty(): return _error("미지 전대입니다: %s" % squadron_id)
	return {"ok": true, "errors": [], "squadron_id": squadron_id,
		"total_cost": int(metrics.total_cost), "recommended_cost": int(metrics.recommended_cost),
		"penalty_tier": int(metrics.penalty_tier), "mobility_percent": int(metrics.mobility_percent),
		"accuracy_percent": int(metrics.accuracy_percent), "formation_change_percent": int(metrics.formation_change_percent),
		"penalty_application": metrics.penalty_application.duplicate(true), "pending_penalties": metrics.pending_penalties.duplicate()}


func resolve_orders(formation_orders: Array, prior_state: Dictionary, turn_number: int) -> Dictionary:
	if turn_number < 1: return _error("턴 번호는 1 이상이어야 합니다.")
	var expected := _operational_ids()
	if formation_orders.size() != expected.size() or prior_state.size() != expected.size():
		return _error("모든 operational 전대의 진형 명령과 상태가 필요합니다.")
	var seen := {}; var normalized: Array = []
	for value in formation_orders:
		if not value is Dictionary: return _error("진형 명령은 객체여야 합니다.")
		var squadron_id := String(value.get("squadron_id", "")); var formation_id := String(value.get("formation_id", ""))
		if value.size() != 2 or seen.has(squadron_id): return _error("진형 명령 스키마 또는 중복이 잘못되었습니다: %s" % squadron_id)
		var valid := validate_order(squadron_id, formation_id)
		if not valid.ok: return valid
		if not prior_state.has(squadron_id) or not prior_state[squadron_id] is Dictionary:
			return _error("전대 진형 상태가 누락되었습니다: %s" % squadron_id)
		seen[squadron_id] = true
		normalized.append({"squadron_id": squadron_id, "formation_id": formation_id})
	if seen.size() != expected.size(): return _error("모든 operational 전대의 진형 명령이 필요합니다.")
	normalized.sort_custom(func(a, b): return String(a.squadron_id) < String(b.squadron_id))
	var next := prior_state.duplicate(true); var events: Array = []
	for order in normalized:
		var squadron_id := String(order.squadron_id); var previous := String(next[squadron_id].formation_id)
		var requested := String(order.formation_id); var metrics := command_penalty_metrics(squadron_id)
		if not metrics.ok: return metrics
		var change_requested := previous != requested
		var effectiveness := clampi(10000 + int(metrics.formation_change_percent) * 100, 0, 10000) if change_requested else 10000
		next[squadron_id] = {"squadron_id": squadron_id, "faction_id": String(_find_squad(squadron_id).faction_id),
			"formation_id": requested, "modifier_effectiveness_basis_points": effectiveness, "effective_turn": turn_number,
			"source": "resolution_start"}
		events.append({"event_id": "CMD-FORM-%02d-%s" % [turn_number, squadron_id],
			"event_type": "formation_applied", "turn": turn_number,
			"squadron_id": squadron_id, "previous_formation_id": previous,
			"requested_formation_id": requested, "formation_id": requested, "changed": change_requested,
			"command_penalty": {"penalty_tier": int(metrics.penalty_tier), "formation_change_percent": int(metrics.formation_change_percent),
				"modifier_effectiveness_basis_points": effectiveness, "change_turn_only": change_requested},
			"application_timing": String(_rules.application_timing)})
	return {"ok": true, "errors": [], "formation_state": next, "formation_events": events,
		"modifier_snapshots": modifier_snapshots(next)}


func apply_accuracy_penalty(events: Array, turn_number: int) -> Dictionary:
	if _draft == null or turn_number < 1: return _error("명중 불이익 판정 입력이 잘못되었습니다.")
	for value in events:
		if not value is Dictionary: return _error("사격 이벤트는 객체여야 합니다.")
	var ordered: Array = events.duplicate(true)
	ordered.sort_custom(func(a, b): return String(a.get("event_id", "")) < String(b.get("event_id", "")))
	var eligible: Array = []; var seen := {}
	for value in ordered:
		var event: Dictionary = value.duplicate(true); var event_id := String(event.get("event_id", "")); var shooter_id := String(event.get("shooter_squadron_id", ""))
		if event_id.is_empty() or seen.has(event_id) or int(event.get("turn", 0)) != turn_number or not ["shot_authorized", "estimated_fire_authorized"].has(String(event.get("outcome", ""))): return _error("명중 불이익 사격 이벤트가 잘못되었습니다.")
		seen[event_id] = true
		var metrics := command_penalty_metrics(shooter_id); if not metrics.ok: return metrics
		var effectiveness := clampi(10000 + int(metrics.accuracy_percent) * 100, 0, 10000)
		var penalty := {"penalty_tier": int(metrics.penalty_tier), "accuracy_percent": int(metrics.accuracy_percent),
			"accuracy_basis_points": effectiveness, "applied": true,
			"result_contract": "authorized_fire_accuracy_input_only; hit_and_damage_pending"}
		event["command_penalty"] = penalty
		eligible.append(event)
	return {"ok": true, "errors": [], "eligible_events": eligible, "suppressed_events": [],
		"result_pending": ["hit", "damage", "casualties", "victory"]}


func modifier_snapshots(formation_state: Dictionary) -> Dictionary:
	var result := {}
	var ids: Array = formation_state.keys(); ids.sort()
	for squadron_id in ids:
		var formation_id := String(formation_state[squadron_id].get("formation_id", ""))
		if not _rules.formations.has(formation_id): continue
		var row: Dictionary = _rules.formations[formation_id]
		var effectiveness := int(formation_state[squadron_id].get("modifier_effectiveness_basis_points", 10000))
		result[squadron_id] = {"squadron_id": String(squadron_id), "formation_id": formation_id,
			"name": String(row.name), "role": String(row.role), "modifier_effectiveness_basis_points": effectiveness,
			"base_modifiers": _modifier_values(row), "modifiers": _scaled_modifiers(_modifier_values(row), effectiveness)}
	return result


func classify_sector(shooter_position: Array, target_position: Array, target_facing_deg) -> Dictionary:
	if not _valid_point(shooter_position) or not _valid_point(target_position) or not _valid_facing(target_facing_deg):
		return _error("sector 판정 좌표 또는 target facing이 잘못되었습니다.")
	var vector := Vector2(float(shooter_position[0]) - float(target_position[0]),
		float(shooter_position[1]) - float(target_position[1]))
	var epsilon := float(_rules.sector_rule.epsilon)
	if vector.length_squared() <= epsilon * epsilon:
		return {"ok": true, "errors": [], "sector": "indeterminate", "origin_bearing_deg": null,
			"relative_angle_deg": null, "sector_defense_percent": int(_rules.sector_defense_percent.indeterminate)}
	var origin_bearing := fposmod(rad_to_deg(atan2(vector.y, vector.x)), 360.0)
	var delta := absf(wrapf(origin_bearing - float(target_facing_deg), -180.0, 180.0))
	# Keep only a machine-noise tolerance at trigonometric boundaries. The rules
	# epsilon is reserved for coincident-position detection, not a wider sector.
	var boundary_tolerance := epsilon * 0.1
	var sector := "front"
	if delta >= float(_rules.sector_rule.rear_limit_deg) - boundary_tolerance: sector = "rear"
	elif delta > float(_rules.sector_rule.front_limit_deg) + boundary_tolerance: sector = "flank"
	return {"ok": true, "errors": [], "sector": sector, "origin_bearing_deg": origin_bearing,
		"relative_angle_deg": delta, "sector_defense_percent": int(_rules.sector_defense_percent[sector])}


func decorate_shot_events(events: Array, formation_state: Dictionary, live_navigation: Dictionary) -> Dictionary:
	var snapshots := modifier_snapshots(formation_state); var decorated: Array = []
	for value in events:
		if not value is Dictionary: return _error("사격 이벤트는 객체여야 합니다.")
		var event: Dictionary = value.duplicate(true)
		if String(event.get("outcome", "")) != "shot_authorized": return _error("shot_authorized 이벤트만 진형 평가할 수 있습니다.")
		var shooter_id := String(event.get("shooter_squadron_id", "")); var target_id := String(event.get("target_squadron_id", ""))
		if not snapshots.has(shooter_id) or not snapshots.has(target_id) or not live_navigation.has(shooter_id) or not live_navigation.has(target_id):
			return _error("사격 진형 평가 입력이 누락되었습니다.")
		var sector := classify_sector(live_navigation[shooter_id].position, live_navigation[target_id].position,
			live_navigation[target_id].facing_deg)
		if not sector.ok: return sector
		var shooter: Dictionary = snapshots[shooter_id]; var target: Dictionary = snapshots[target_id]
		event["formation_modifier"] = {"application_timing": String(_rules.application_timing),
			"shooter": {"formation_id": String(shooter.formation_id), "fire_percent": int(shooter.modifiers.fire_percent)},
			"target": {"formation_id": String(target.formation_id), "defense_percent": int(target.modifiers.defense_percent),
				"sector": String(sector.sector), "sector_defense_percent": int(sector.sector_defense_percent),
				"total_defense_percent": int(target.modifiers.defense_percent) + int(sector.sector_defense_percent)},
			"result_pending": _rules.result_contract.pending.duplicate()}
		decorated.append(event)
	return {"ok": true, "errors": [], "events": decorated}


func _modifier_values(row: Dictionary) -> Dictionary:
	return {"mobility_percent": int(row.mobility_percent), "detection_percent": int(row.detection_percent),
		"fire_percent": int(row.fire_percent), "defense_percent": int(row.defense_percent)}


func _scaled_modifiers(base: Dictionary, effectiveness_basis_points: int) -> Dictionary:
	var result := {}
	for key in ["mobility_percent", "detection_percent", "fire_percent", "defense_percent"]:
		var value := int(base.get(key, 0)); var scaled := float(value * effectiveness_basis_points) / 10000.0
		# Round toward zero so a partial change never reverses or amplifies either a
		# positive bonus or a negative trade-off.
		result[key] = int(floor(scaled)) if scaled >= 0.0 else int(ceil(scaled))
	return result


func _load_rules() -> Dictionary:
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null: return _error("진형 규칙 파일을 열 수 없습니다.")
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1 or String(parsed.get("profile_id", "")) != "normal-demo-formation-v1": return _error("지원하지 않는 진형 규칙 프로필입니다.")
	if String(parsed.get("application_timing", "")) != "submitted_with_command_draft; applied_atomically_at_resolution_start_before_movement_detection_and_fire; persists_until_changed": return _error("진형 적용 시점 계약이 잘못되었습니다.")
	if not parsed.get("formations") is Dictionary: return _error("진형 보정 표가 누락되었습니다.")
	var ids: Array = parsed.formations.keys(); ids.sort()
	if ids != Setup.ALLOWED_FORMATION_IDS: return _error("FRM-01~07 진형 보정이 정확히 필요합니다.")
	for formation_id in ids:
		var row = parsed.formations[formation_id]
		if not row is Dictionary or String(row.get("name", "")).is_empty() or String(row.get("role", "")).is_empty(): return _error("진형 설명이 누락되었습니다: %s" % formation_id)
		for key in ["mobility_percent", "detection_percent", "fire_percent", "defense_percent"]:
			if not _integer_number(row.get(key)): return _error("진형 보정은 정수 percent여야 합니다: %s/%s" % [formation_id, key])
	var sector = parsed.get("sector_rule", {}); var sector_mod = parsed.get("sector_defense_percent", {})
	if not sector is Dictionary or float(sector.get("front_limit_deg", 0)) <= 0.0 or float(sector.get("rear_limit_deg", 0)) <= float(sector.front_limit_deg) or float(sector.rear_limit_deg) > 180.0 or float(sector.get("epsilon", 0)) <= 0.0: return _error("sector 임계각 규칙이 잘못되었습니다.")
	if String(sector.get("boundary_policy", "")) != "front_if_abs_delta_lte_front_limit; rear_if_abs_delta_gte_rear_limit; otherwise_flank; coincident_indeterminate": return _error("sector 경계 정책이 잘못되었습니다.")
	if not sector_mod is Dictionary or sector_mod.keys().size() != 4:
		return _error("sector 방어 보정 표가 잘못되었습니다.")
	for key in ["front", "flank", "rear", "indeterminate"]:
		if not _integer_number(sector_mod.get(key)): return _error("sector 방어 보정이 누락되었습니다: %s" % key)
	var contract = parsed.get("result_contract", {})
	if not contract is Dictionary or contract.get("shot_authorized_only") != true or contract.get("pending") != ["hit", "damage", "ammo", "heat", "casualties", "victory"]: return _error("결과 pending 계약이 잘못되었습니다.")
	return {"ok": true, "errors": [], "rules": parsed.duplicate(true)}


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


func _find_squad(squadron_id: String) -> Dictionary:
	for squad in _setup.get("squadrons", []):
		if String(squad.id) == squadron_id: return squad
	return {}


func _valid_point(value) -> bool:
	return value is Array and value.size() == 2 and _finite_number(value[0]) and _finite_number(value[1])


func _valid_facing(value) -> bool:
	return _finite_number(value) and float(value) >= 0.0 and float(value) < 360.0


func _finite_number(value) -> bool: return (value is int or value is float) and is_finite(float(value))
func _integer_number(value) -> bool: return _finite_number(value) and is_equal_approx(float(value), floor(float(value)))
func _ok() -> Dictionary: return {"ok": true, "errors": []}
func _error(message: String) -> Dictionary: return {"ok": false, "errors": [message]}
