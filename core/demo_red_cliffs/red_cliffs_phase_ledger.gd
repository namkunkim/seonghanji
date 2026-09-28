class_name RedCliffsPhaseLedger
extends RefCounted

## DEMO-RC-G4-07 — 기존 권위 이벤트를 5단계로 조직하는 결정론적 감사 원장.
const RULES_PATH := "res://data/red-cliffs-phase-ledger-rules.json"

var _rules: Dictionary = {}


func initialize() -> Dictionary:
	var loaded := _load_rules()
	if not loaded.ok: return loaded
	_rules = loaded.rules.duplicate(true)
	return _ok()


func rules_snapshot() -> Dictionary: return _rules.duplicate(true)


func build(turn_number: int, receipt: Dictionary) -> Dictionary:
	if _rules.is_empty(): return _error("5단계 원장이 초기화되지 않았습니다.")
	if turn_number < 1 or not receipt is Dictionary: return _error("유효한 턴 receipt가 필요합니다.")
	for forbidden in _rules.forbidden_outcomes:
		if _contains_key_recursive(receipt, String(forbidden)): return _error("원장 입력에 금지된 미완성 결과가 있습니다: %s" % forbidden)
	var phases: Array = []; var seen_input_ids := {}
	for phase_index in range(_rules.phase_order.size()):
		var phase_id := String(_rules.phase_order[phase_index]); var phase_rule: Dictionary = _rules.phases[phase_id]
		var events: Array = []
		for source_index in range(phase_rule.sources.size()):
			var source := String(phase_rule.sources[source_index]); var values = _source_values(source, receipt)
			if not values is Array: return _error("원장 event source는 배열이어야 합니다: %s" % source)
			for event_index in range(values.size()):
				if not values[event_index] is Dictionary: return _error("원장 이벤트는 객체여야 합니다: %s" % source)
				var payload: Dictionary = values[event_index].duplicate(true)
				var payload_check := _validate_payload(source, payload, turn_number)
				if not payload_check.ok: return payload_check
				var identity := "%s|%s" % [source, _input_identity(source, payload)]
				if seen_input_ids.has(identity): return _error("중복 원장 이벤트입니다: %s" % identity)
				seen_input_ids[identity] = true
				events.append({"ledger_event_id": _ledger_event_id(turn_number, phase_index, source_index, event_index, payload),
					"source": source, "event_type": _event_type(source, payload), "payload": payload})
		var pending: Array = phase_rule.pending.duplicate()
		phases.append({"phase_id": phase_id, "phase_name": String(phase_rule.name), "order": phase_index + 1,
			"status": _status(events, pending), "events": events, "pending": pending})
	var ledger := {"ok": true, "errors": [], "turn": turn_number, "profile_id": String(_rules.profile_id),
		"phase_order": _rules.phase_order.duplicate(), "phases": phases,
		"result_contract": {"hit": "resolved", "damage": "resolved", "ship_losses": "resolved", "morale": "resolved", "sensor_disruption": "resolved", "temporary_terrain": "resolved", "commander_casualties": "pending", "victory": "pending_G8_01"}}
	ledger["turn_digest"] = _digest(ledger)
	return ledger


func build_viewer(turn_number: int, safe_receipt: Dictionary) -> Dictionary:
	var ledger := build(turn_number, safe_receipt)
	if not ledger.ok: return ledger
	ledger["viewer_redacted"] = true
	for phase_row in ledger.phases:
		if phase_row.events.is_empty(): phase_row.status = "no_visible_events"
	ledger.turn_digest = _digest(ledger)
	return ledger


func summary(ledger: Dictionary) -> Dictionary:
	var checked := _validate_ledger(ledger)
	if not checked.ok: return checked
	var rows: Array = []; var total_events := 0
	for phase_row in ledger.phases:
		var count: int = phase_row.events.size(); total_events += count
		rows.append({"phase_id": String(phase_row.phase_id), "phase_name": String(phase_row.phase_name),
			"status": String(phase_row.status), "event_count": count, "pending_count": phase_row.pending.size()})
	return {"ok": true, "errors": [], "turn": int(ledger.turn), "turn_digest": String(ledger.turn_digest),
		"total_events": total_events, "phases": rows}


func phase(ledger: Dictionary, phase_id: String) -> Dictionary:
	var checked := _validate_ledger(ledger)
	if not checked.ok: return checked
	for row in ledger.phases:
		if String(row.phase_id) == phase_id: return {"ok": true, "errors": [], "turn": int(ledger.turn), "phase": row.duplicate(true)}
	return _error("미지 5단계 ID입니다: %s" % phase_id)


func _validate_ledger(ledger: Dictionary) -> Dictionary:
	if not ledger is Dictionary or ledger.get("phase_order") != _rules.phase_order or not ledger.get("phases") is Array or ledger.phases.size() != 5: return _error("5단계 원장 스키마가 잘못되었습니다.")
	var copy := ledger.duplicate(true); var claimed := String(copy.get("turn_digest", "")); copy.erase("turn_digest")
	if claimed.is_empty() or claimed != JSON.stringify(copy).sha256_text(): return _error("턴 원장 digest가 일치하지 않습니다.")
	return _ok()


func _ledger_event_id(turn_number: int, phase_index: int, source_index: int, event_index: int, payload: Dictionary) -> String:
	var hash := JSON.stringify(payload).sha256_text().substr(0, 12)
	return "LED-%02d-%d-%02d-%03d-%s" % [turn_number, phase_index + 1, source_index + 1, event_index + 1, hash]


func _event_type(source: String, payload: Dictionary) -> String:
	if not String(payload.get("event_type", "")).is_empty(): return String(payload.event_type)
	if source == "movement_events": return "movement_%s" % String(payload.get("action", "unknown"))
	if source == "opportunity_fire_events": return "shot_authorized"
	if source == "estimated_fire_events": return "estimated_fire_authorized"
	if source == "estimated_fire_suppressed_events": return "estimated_fire_suppressed"
	if source == "path_intersection_events": return "path_intersection"
	if source == "terrain_events": return String(payload.get("event_type", "terrain_transition"))
	if source == "detection_events": return "detection"
	if source == "resolution_boundary": return "resolution_boundary"
	return source.trim_suffix("_events")


func _source_values(source: String, receipt: Dictionary):
	if source == "resolution_boundary":
		if receipt.get("victory_check_required") != true or not receipt.get("rules_pending") is Array: return []
		return [{"event_type": "resolution_boundary", "turn": int(receipt.get("turn", 0)),
			"victory_check_required": true, "rules_pending": receipt.rules_pending.duplicate()}]
	var values = receipt.get(source, [])
	return values if values is Array else values


func _validate_payload(source: String, payload: Dictionary, turn_number: int) -> Dictionary:
	var event_turn := int(payload.get("turn", payload.get("resolution_turn", turn_number)))
	if event_turn != turn_number: return _error("원장 이벤트 턴이 다릅니다: %s" % source)
	var event_type := _event_type(source, payload)
	var allowed := {
		"formation_events": ["formation_applied"], "weapon_allocation_events": ["weapon_allocation_applied"],
		"resource_recovery_events": ["resource_recovered"], "movement_events": ["movement_hold", "movement_move"],
		"terrain_events": ["terrain_transition", "terrain_membership", "terrain_stay"],
		"path_intersection_events": ["path_intersection"], "detection_events": ["detection"],
		"chain_explosion_events": ["chain_explosion_disrupted", "chain_explosion_triggered"],
		"combat_effect_events": ["shot_effect_resolved", "chain_effects_applied", "squadron_effect_applied", "temporary_terrain_created"],
		"opportunity_fire_events": ["shot_authorized"], "estimated_fire_events": ["estimated_fire_authorized"],
		"estimated_fire_suppressed_events": ["estimated_fire_suppressed"], "resource_consumption_events": ["resource_consumed"],
		"suppressed_fire_events": ["fire_suppressed"], "resolution_boundary": ["resolution_boundary"]}
	if not allowed.has(source) or not allowed[source].has(event_type): return _error("미지 원장 이벤트 유형입니다: %s/%s" % [source, event_type])
	return _ok()


func _input_identity(source: String, payload: Dictionary) -> String:
	if not String(payload.get("event_id", "")).is_empty(): return String(payload.event_id)
	if source == "resolution_boundary": return "resolution"
	if not String(payload.get("squadron_id", "")).is_empty(): return String(payload.squadron_id)
	return JSON.stringify(payload).sha256_text()


func _status(events: Array, pending: Array) -> String:
	if not events.is_empty() and not pending.is_empty(): return "partial"
	if not events.is_empty(): return "recorded"
	if not pending.is_empty(): return "pending"
	return "empty"


func _digest(ledger: Dictionary) -> String:
	var copy := ledger.duplicate(true); copy.erase("turn_digest"); return JSON.stringify(copy).sha256_text()


func _contains_key_recursive(value, key: String) -> bool:
	if value is Dictionary:
		if value.has(key): return true
		for child in value.values():
			if _contains_key_recursive(child, key): return true
	elif value is Array:
		for child in value:
			if _contains_key_recursive(child, key): return true
	return false


func _load_rules() -> Dictionary:
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null: return _error("5단계 원장 규칙 파일을 열 수 없습니다.")
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1 or String(parsed.get("profile_id", "")) != "normal-demo-five-phase-ledger-v1": return _error("지원하지 않는 5단계 원장 프로필입니다.")
	if parsed.get("phase_order") != ["contact", "barrage", "engagement", "assault", "resolution"] or not parsed.get("phases") is Dictionary: return _error("5단계 순서가 잘못되었습니다.")
	var names := ["접적", "포화", "교전", "강습", "결착"]
	for index in range(parsed.phase_order.size()):
		var phase_id := String(parsed.phase_order[index]); var row = parsed.phases.get(phase_id)
		if not row is Dictionary or String(row.get("name", "")) != names[index] or not row.get("sources") is Array or not row.get("pending") is Array: return _error("5단계 정의가 잘못되었습니다: %s" % phase_id)
	if String(parsed.get("event_id_policy", "")) != "LED-turn-phase_order-source_order-event_order-sha256_payload" or String(parsed.get("digest_policy", "")) != "sha256_canonical_json_without_turn_digest": return _error("원장 ID/digest 정책이 잘못되었습니다.")
	if parsed.get("forbidden_outcomes") != ["winner"]: return _error("금지 결과 계약이 잘못되었습니다.")
	return {"ok": true, "errors": [], "rules": parsed.duplicate(true)}


func _ok() -> Dictionary: return {"ok": true, "errors": []}
func _error(message: String) -> Dictionary: return {"ok": false, "errors": [message]}
