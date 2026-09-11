class_name RedCliffsChainExplosion
extends RefCounted

## DEMO-RC-G5-06 — 연쇄 폭발 작전의 조건·방해·불가역 발동 권위.
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Terrain := preload("res://core/demo_red_cliffs/red_cliffs_terrain_resolver.gd")
const RULES_PATH := "res://data/red-cliffs-chain-explosion-rules.json"
var _setup: Dictionary = {}; var _rules: Dictionary = {}; var _terrain

func initialize(applied_setup: Dictionary) -> Dictionary:
	var checked := Setup.validate_document(applied_setup); if not checked.ok: return _error("유효한 G3 적용 편성이 필요합니다.")
	var file := FileAccess.open(RULES_PATH, FileAccess.READ); if file == null: return _error("연쇄 폭발 규칙을 열 수 없습니다.")
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1 or String(parsed.get("profile_id", "")) != "normal-demo-chain-explosion-v1": return _error("지원하지 않는 연쇄 폭발 규칙입니다.")
	if String(parsed.get("operator_faction_id", "")) != "liu_bei" or String(parsed.get("allied_asset_faction_id", "")) != "sun_quan" or String(parsed.get("target_faction_id", "")) != "cao_cao": return _error("연쇄 폭발 세력 계약이 잘못되었습니다.")
	if not parsed.get("dense_formation_ids") is Array or not parsed.get("dispersed_formation_ids") is Array or float(parsed.get("maximum_range", 0)) <= 0 or not parsed.get("flow") is Dictionary: return _error("연쇄 폭발 조건 스키마가 잘못되었습니다.")
	if parsed.dense_formation_ids != ["FRM-02", "FRM-03", "FRM-04"] or parsed.dispersed_formation_ids != ["FRM-05", "FRM-06", "FRM-07"]: return _error("밀집·분산 진형 집합이 잘못되었습니다.")
	if parsed.get("effect_intents") != ["reactor_chain_blast", "morale_shock", "sensor_disruption", "temporary_terrain_hazard"] \
			or parsed.get("effects_pending") != ["damage", "morale", "sensor_disruption", "terrain_effect", "casualties", "victory"]: return _error("연쇄 폭발 효과 intent·pending 경계가 잘못되었습니다.")
	var detachment: Dictionary = parsed.get("allied_operation_detachment", {}); var asset := _find_squad(checked.setup, String(detachment.get("host_squadron_id", "")))
	if String(detachment.get("id", "")) != "CHAIN-DET-01" or int(detachment.get("minimum_available_payloads", 0)) < 1 or String(detachment.get("modeling_boundary", "")) != "allied_special_operation_payload_not_a_new_ship_type_or_squadron": return _error("연합 특수작전 payload 경계가 잘못되었습니다.")
	if asset.is_empty() or String(asset.faction_id) != "sun_quan" or _component_count(asset, String(detachment.payload_platform_id), String(detachment.payload_equipment_id)) < int(detachment.minimum_available_payloads): return _error("연합 폭발정 분견대 payload가 역사 데모 편성과 일치하지 않습니다.")
	var terrain = Terrain.new(); var terrain_result: Dictionary = terrain.initialize(checked.setup); if not terrain_result.ok: return terrain_result
	var zone_ids: Array = terrain.visible_zones().map(func(row): return String(row.zone_id))
	var direction = parsed.flow.get("direction", [])
	if not zone_ids.has(String(parsed.flow.terrain_zone_id)) or not direction is Array or direction.size() != 2 \
			or float(direction[0]) != 1.0 or float(direction[1]) != 0.0 or float(parsed.flow.maximum_deviation_deg) <= 0 or float(parsed.flow.maximum_deviation_deg) > 180: return _error("태양풍·성운 흐름 규칙이 잘못되었습니다.")
	_setup = checked.setup.duplicate(true); _rules = parsed.duplicate(true); _terrain = terrain; return _ok()

func initial_state() -> Dictionary:
	return {"status": "idle", "staged_order": {}, "last_evaluation": {}, "trigger_event": {}, "triggered_turn": 0}

func rules_snapshot() -> Dictionary: return _rules.duplicate(true)

func readiness(viewer_faction_id: String, state: Dictionary, source_squadron_id: String,
		contact: Dictionary, navigation: Dictionary, formation_state: Dictionary,
		interception_events: Array = [], _disruption_evidence: Array = []) -> Dictionary:
	if viewer_faction_id != String(_rules.operator_faction_id): return _error("유비 플레이어 관점에서만 작전을 준비할 수 있습니다.")
	var validated := _validate_state(state); if not validated.ok: return validated
	var source := _find_squad(_setup, source_squadron_id); var target_id := String(contact.get("target_squadron_id", "")); var target := _find_squad(_setup, target_id)
	var detachment: Dictionary = _rules.allied_operation_detachment
	var source_alive: bool = not source.is_empty() and bool(source.get("operational", true)) and source_squadron_id == String(detachment.host_squadron_id)
	var detected: bool = String(contact.get("state", "")) == "confirmed" and not target.is_empty() and String(target.faction_id) == String(_rules.target_faction_id)
	var source_pos: Array = navigation.get(source_squadron_id, {}).get("position", [])
	var target_pos: Array = navigation.get(target_id, {}).get("position", []) if detected else []
	var distance: float = INF; var in_range: bool = false; var flow: Dictionary = {"met": false, "zone_ids": [], "deviation_deg": 180.0}
	if source_pos.size() == 2 and target_pos.size() == 2:
		distance = Vector2(float(source_pos[0]), float(source_pos[1])).distance_to(Vector2(float(target_pos[0]), float(target_pos[1])))
		in_range = distance <= float(_rules.maximum_range) + 0.001; flow = _flow_condition(source_pos, target_pos)
	var formation_id := String(formation_state.get(target_id, {}).get("formation_id", "")); var dense: bool = detected and _rules.dense_formation_ids.has(formation_id)
	var blocking_event_ids: Array = []
	for event in interception_events:
		if event is Dictionary and String(event.get("target_squadron_id", "")) == source_squadron_id \
				and String(event.get("selected_weapon_id", "")) == "intercept": blocking_event_ids.append(String(event.get("event_id", "")))
	blocking_event_ids.sort(); var screen_clear: bool = blocking_event_ids.is_empty()
	var conditions := [
		{"id": "detachment_available", "met": source_alive, "label": "연합 폭발정 분견대 운용 가능"},
		{"id": "cao_dense_formation", "met": dense, "label": "조조군 밀집 진형", "formation_id": formation_id if detected else ""},
		{"id": "legal_detection", "met": detected, "label": "조조군 목표 확인 탐지"},
		{"id": "designated_range", "met": in_range, "label": "지정 사거리 진입", "distance": distance if is_finite(distance) else null, "maximum_range": float(_rules.maximum_range)},
		{"id": "solar_nebula_flow", "met": bool(flow.met), "label": "태양풍·성운 흐름 확보", "zone_ids": flow.zone_ids.duplicate(), "deviation_deg": float(flow.deviation_deg)},
		{"id": "interception_screen_clear", "met": screen_clear, "label": "조조군 요격 차단선 돌파", "blocking_event_ids": blocking_event_ids}]
	var ready: bool = true; for row in conditions: ready = ready and bool(row.met)
	return {"ok": true, "errors": [], "ready": ready, "source_squadron_id": source_squadron_id,
		"contact_id": String(contact.get("contact_id", "")), "target_squadron_id": target_id if detected else "",
		"conditions": conditions, "evaluation_timing": String(_rules.evaluation_timing)}

func stage(state: Dictionary, readiness_receipt: Dictionary, turn_number: int) -> Dictionary:
	var valid := _validate_state(state); if not valid.ok: return valid
	if String(state.status) == "triggered": return _error("이미 발동한 연쇄 폭발 작전은 다시 준비할 수 없습니다.")
	if not bool(readiness_receipt.get("ok", false)) or not bool(readiness_receipt.get("ready", false)): return _error("연쇄 폭발 작전의 모든 선행 조건이 충족되어야 준비할 수 있습니다.")
	var order := {"source_squadron_id": String(readiness_receipt.source_squadron_id), "contact_id": String(readiness_receipt.contact_id), "target_squadron_id": String(readiness_receipt.target_squadron_id), "staged_turn": turn_number}
	if String(state.status) == "staged":
		if state.staged_order == order: return {"ok": true, "errors": [], "state": state.duplicate(true), "idempotent": true}
		return _error("이미 다른 연쇄 폭발 작전이 준비되어 있습니다.")
	if String(state.status) == "disrupted" and turn_number <= int(state.last_evaluation.get("turn", 0)): return _error("방해된 작전은 다음 명령 턴부터 재시도할 수 있습니다.")
	var next := state.duplicate(true); next.status = "staged"; next.staged_order = order; next.last_evaluation = readiness_receipt.duplicate(true)
	return {"ok": true, "errors": [], "state": next, "idempotent": false}

func cancel(state: Dictionary) -> Dictionary:
	var valid := _validate_state(state); if not valid.ok: return valid
	if String(state.status) == "triggered": return _error("발동 성공한 연쇄 폭발 작전은 취소할 수 없습니다.")
	if String(state.status) != "staged": return _error("취소할 준비 작전이 없습니다.")
	var next := initial_state(); return {"ok": true, "errors": [], "state": next}

func resolve_staged(state: Dictionary, final_readiness: Dictionary, turn_number: int) -> Dictionary:
	var valid := _validate_state(state); if not valid.ok: return valid
	if String(state.status) != "staged": return {"ok": true, "errors": [], "state": state.duplicate(true), "events": []}
	if String(state.staged_order.contact_id) != String(final_readiness.get("contact_id", "")) or String(state.staged_order.source_squadron_id) != String(final_readiness.get("source_squadron_id", "")): return _error("준비 명령과 최종 조건 대상이 일치하지 않습니다.")
	var next := state.duplicate(true); next.last_evaluation = final_readiness.duplicate(true); next.last_evaluation["turn"] = turn_number
	if not bool(final_readiness.get("ready", false)):
		next.status = "disrupted"
		var blocked := {"event_id": "CHAIN-DISRUPT-%02d" % turn_number, "event_type": "chain_explosion_disrupted", "turn": turn_number,
			"source_squadron_id": String(state.staged_order.source_squadron_id), "target_squadron_id": String(state.staged_order.target_squadron_id),
			"conditions": final_readiness.conditions.duplicate(true), "status": "disrupted", "retry_allowed_from_turn": turn_number + 1}
		return {"ok": true, "errors": [], "state": next, "events": [blocked]}
	next.status = "triggered"; next.triggered_turn = turn_number
	var event := {"event_id": "CHAIN-TRIGGER-%02d" % turn_number, "event_type": "chain_explosion_triggered", "turn": turn_number,
		"source_squadron_id": String(state.staged_order.source_squadron_id), "target_squadron_id": String(state.staged_order.target_squadron_id),
		"conditions": final_readiness.conditions.duplicate(true), "probability_roll_used": false, "irreversible": true,
		"effect_intents": _rules.effect_intents.duplicate(), "effects_pending": _rules.effects_pending.duplicate()}
	next.trigger_event = event.duplicate(true); return {"ok": true, "errors": [], "state": next, "events": [event]}

func _flow_condition(source: Array, target: Array) -> Dictionary:
	var delta := Vector2(float(target[0]) - float(source[0]), float(target[1]) - float(source[1])); var deviation := 180.0
	if delta.length() > 0.0001: deviation = absf(rad_to_deg(Vector2(float(_rules.flow.direction[0]), float(_rules.flow.direction[1])).normalized().angle_to(delta.normalized())))
	var zones: Array = _terrain.weapon_effect(source, target, "chain_explosion_route").zone_ids
	return {"met": zones.has(String(_rules.flow.terrain_zone_id)) and deviation <= float(_rules.flow.maximum_deviation_deg) + 0.001,
		"zone_ids": zones, "deviation_deg": deviation}

func _validate_state(state: Dictionary) -> Dictionary:
	if not state is Dictionary or not ["idle", "staged", "disrupted", "triggered"].has(String(state.get("status", ""))) or not state.get("staged_order") is Dictionary or not state.get("last_evaluation") is Dictionary or not state.get("trigger_event") is Dictionary or int(state.get("triggered_turn", -1)) < 0: return _error("연쇄 폭발 상태 스키마가 잘못되었습니다.")
	if String(state.status) == "triggered" and (state.trigger_event.is_empty() or int(state.triggered_turn) < 1): return _error("발동 상태에 확정 이벤트가 필요합니다.")
	return _ok()

func _find_squad(setup: Dictionary, squadron_id: String) -> Dictionary:
	for squad in setup.get("squadrons", []):
		if String(squad.get("id", "")) == squadron_id: return squad
	return {}
func _component_count(squad: Dictionary, ship_type_id: String, equipment_id: String) -> int:
	var total := 0
	for row in squad.get("composition", []):
		if String(row.get("ship_type_id", "")) == ship_type_id and String(row.get("mission_equipment_id", "")) == equipment_id: total += int(row.get("count", 0))
	return total
func _ok() -> Dictionary: return {"ok": true, "errors": []}
func _error(message: String) -> Dictionary: return {"ok": false, "errors": [message]}
