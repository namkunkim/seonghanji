class_name RedCliffsFastCraftMission
extends RefCounted

## DEMO-RC-G6-02 — immutable 장비와 active/queued 전술 임무 상태 권위.
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const RULES_PATH := "res://data/red-cliffs-fast-craft-rules.json"

var _setup: Dictionary = {}
var _rules: Dictionary = {}


func initialize(applied_setup: Dictionary) -> Dictionary:
	var checked := Setup.validate_document(applied_setup)
	if not checked.ok: return _error("유효한 G3 적용 편성이 필요합니다.")
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null: return _error("고속정 전술 임무 규칙을 열 수 없습니다.")
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not parsed.get("mission_equipment") is Array or not parsed.get("tactical_missions") is Array:
		return _error("고속정 전술 임무 규칙이 잘못되었습니다.")
	var known := {}; for row in parsed.tactical_missions: known[String(row.get("mission_id", ""))] = true
	var equipment := {}
	for row in parsed.mission_equipment:
		var supported = row.get("supported_tactical_mission_ids", [])
		if not supported is Array or supported.is_empty(): return _error("장비별 전술 임무 allowlist가 필요합니다.")
		for mission_id in supported:
			if not known.has(String(mission_id)): return _error("장비 allowlist가 미지 임무를 참조합니다.")
		equipment[String(row.equipment_id)] = row.duplicate(true)
	_setup = checked.setup.duplicate(true); _rules = parsed.duplicate(true)
	return _ok()


func catalog() -> Dictionary:
	return {"ok": true, "errors": [], "tactical_missions": _rules.get("tactical_missions", []).duplicate(true),
		"equipment_allowlists": _equipment_allowlists(), "result_pending": ["non_rescue_mission_effect"]}


func initial_state() -> Dictionary:
	var active := {}
	for squad in _fast_craft_squadrons():
		var equipment_id := String(squad.composition[0].mission_equipment_id); var supported := supported_missions(equipment_id)
		active[String(squad.id)] = {"squadron_id": String(squad.id), "faction_id": String(squad.faction_id),
			"equipment_id": equipment_id, "supported_mission_ids": supported,
			"mission_id": String(_equipment_rule(equipment_id).mission_id), "effective_turn": 1, "source": "applied_equipment_default"}
	return {"active": active, "current_turn_draft": {}, "next_turn_queue": {}, "events_by_turn": {}, "next_event_serial": 1}


func supported_missions(equipment_id: String) -> Array:
	return _equipment_rule(equipment_id).get("supported_tactical_mission_ids", []).duplicate()


func ai_mission(state: Dictionary, squadron_id: String, turn_number: int) -> Dictionary:
	if turn_number < 1 or not state.get("active", {}).has(squadron_id): return _error("AI 전술 임무 입력이 잘못되었습니다.")
	var supported: Array = state.active[squadron_id].supported_mission_ids
	if supported.is_empty(): return _error("AI 전술 임무 allowlist가 비었습니다.")
	var mission_id := String(supported[(turn_number - 1) % supported.size()])
	var valid := validate_mission(state, squadron_id, mission_id)
	if not valid.ok: return valid
	return {"ok": true, "errors": [], "squadron_id": squadron_id, "mission_id": mission_id,
		"source": "equipment_allowlist_turn_cycle_v1"}


func validate_mission(state: Dictionary, squadron_id: String, mission_id: String) -> Dictionary:
	var active: Dictionary = state.get("active", {})
	if not active.has(squadron_id): return _error("미지 고속정 전대입니다: %s" % squadron_id)
	if not active[squadron_id].get("supported_mission_ids", []).has(mission_id): return _error("현재 장비가 지원하지 않는 전술 임무입니다: %s" % mission_id)
	return _ok()


func request(state: Dictionary, squadron_id: String, mission_id: String, turn_number: int, application: String) -> Dictionary:
	if not ["immediate", "next_turn_queue"].has(application) or turn_number < 1: return _error("전술 임무 적용 시점이 잘못되었습니다.")
	var valid := validate_mission(state, squadron_id, mission_id); if not valid.ok: return valid
	var active: Dictionary = state.get("active", {})
	var row: Dictionary = active[squadron_id]
	var next := state.duplicate(true); var event: Dictionary
	if application == "immediate":
		var previous_draft: Dictionary = next.get("current_turn_draft", {}).get(squadron_id, {})
		if String(previous_draft.get("mission_id", "")) == mission_id: return _error("현재 명령 초안과 같은 전술 임무 요청입니다.")
		var previous := String(previous_draft.get("mission_id", row.mission_id))
		if String(row.mission_id) == mission_id: next.current_turn_draft.erase(squadron_id)
		else: next.current_turn_draft[squadron_id] = {"squadron_id": squadron_id, "faction_id": String(row.faction_id),
			"mission_id": mission_id, "requested_turn": turn_number}
		event = _event("immediate", squadron_id, String(row.faction_id), previous, mission_id, turn_number, turn_number, _claim_serial(next))
	else:
		if next.next_turn_queue.has(squadron_id): return _error("다음 턴 전술 임무 요청이 이미 있습니다.")
		if String(row.mission_id) == mission_id: return _error("활성 임무와 같은 다음 턴 요청은 중복입니다.")
		next.next_turn_queue[squadron_id] = {"squadron_id": squadron_id, "faction_id": String(row.faction_id),
			"mission_id": mission_id, "requested_turn": turn_number, "effective_turn": turn_number + 1}
		event = _event("queued", squadron_id, String(row.faction_id), String(row.mission_id), mission_id, turn_number, turn_number + 1, _claim_serial(next))
	_append_event(next, turn_number, event)
	return {"ok": true, "errors": [], "state": next, "application": application, "event": event.duplicate(true)}


func commit_draft(state: Dictionary, faction_id: String, orders: Array, turn_number: int) -> Dictionary:
	var next := state.duplicate(true); var seen := {}; var normalized: Array = []
	for value in orders:
		if not value is Dictionary: return _error("전술 임무 초안은 객체여야 합니다.")
		var squadron_id := String(value.get("squadron_id", "")); var mission_id := String(value.get("mission_id", ""))
		if seen.has(squadron_id) or not next.current_turn_draft.has(squadron_id): return _error("전술 임무 초안이 중복되었거나 일치하지 않습니다.")
		if String(next.active.get(squadron_id, {}).get("faction_id", "")) != faction_id: return _error("다른 세력의 전술 임무를 제출할 수 없습니다.")
		var valid := validate_mission(next, squadron_id, mission_id); if not valid.ok: return valid
		if String(next.current_turn_draft[squadron_id].mission_id) != mission_id: return _error("전술 임무 초안과 제출값이 일치하지 않습니다.")
		seen[squadron_id] = true; normalized.append({"squadron_id": squadron_id, "mission_id": mission_id})
	if seen.size() != next.current_turn_draft.values().filter(func(row): return String(row.faction_id) == faction_id).size(): return _error("세력의 전술 임무 초안이 누락되었습니다.")
	normalized.sort_custom(func(a, b): return String(a.squadron_id) < String(b.squadron_id)); var events: Array = []
	for order in normalized:
		var active: Dictionary = next.active[order.squadron_id]; var previous := String(active.mission_id)
		active.mission_id = String(order.mission_id); active.effective_turn = turn_number; active.source = "command_submit"
		var event := _event("applied", String(order.squadron_id), String(active.faction_id), previous, String(order.mission_id), turn_number, turn_number, _claim_serial(next))
		events.append(event); _append_event(next, turn_number, event); next.current_turn_draft.erase(order.squadron_id)
	return {"ok": true, "errors": [], "state": next, "events": events}


func cancel_queue(state: Dictionary, squadron_id: String, turn_number: int) -> Dictionary:
	if not state.get("next_turn_queue", {}).has(squadron_id): return _error("취소할 다음 턴 전술 임무 요청이 없습니다.")
	var next := state.duplicate(true); var queued: Dictionary = next.next_turn_queue[squadron_id]; next.next_turn_queue.erase(squadron_id)
	var active: Dictionary = next.active[squadron_id]
	var event := _event("cancelled", squadron_id, String(active.faction_id), String(active.mission_id), String(queued.mission_id), turn_number, int(queued.effective_turn), _claim_serial(next))
	_append_event(next, turn_number, event)
	return {"ok": true, "errors": [], "state": next, "event": event.duplicate(true)}


func promote(state: Dictionary, turn_number: int) -> Dictionary:
	var next := state.duplicate(true); var events: Array = []; var ids: Array = next.next_turn_queue.keys(); ids.sort()
	for squadron_id in ids:
		var queued: Dictionary = next.next_turn_queue[squadron_id]
		if int(queued.effective_turn) != turn_number: continue
		var active: Dictionary = next.active[squadron_id]; var previous := String(active.mission_id)
		active.mission_id = String(queued.mission_id); active.effective_turn = turn_number; active.source = "next_turn_promotion"
		var event := _event("promoted", String(squadron_id), String(active.faction_id), previous, String(active.mission_id), int(queued.requested_turn), turn_number, _claim_serial(next))
		events.append(event); _append_event(next, turn_number, event); next.next_turn_queue.erase(squadron_id)
	return {"ok": true, "errors": [], "state": next, "events": events}


func visible(viewer_faction_id: String, state: Dictionary) -> Dictionary:
	var statuses: Array = []; var queued: Array = []; var events: Array = []
	var ids: Array = state.get("active", {}).keys(); ids.sort()
	for squadron_id in ids:
		var row: Dictionary = state.active[squadron_id]
		if String(row.faction_id) == viewer_faction_id:
			var status: Dictionary = row.duplicate(true); var draft: Dictionary = state.get("current_turn_draft", {}).get(squadron_id, {})
			status["draft_mission_id"] = String(draft.get("mission_id", "")); status["display_mission_id"] = String(draft.get("mission_id", row.mission_id))
			statuses.append(status)
	for value in state.get("next_turn_queue", {}).values():
		if String(value.get("faction_id", "")) == viewer_faction_id: queued.append(value.duplicate(true))
	var turns: Array = state.get("events_by_turn", {}).keys(); turns.sort()
	for event_turn in turns:
		var rows: Array = state.events_by_turn[event_turn]
		for value in rows:
			if String(value.get("faction_id", "")) == viewer_faction_id: events.append(value.duplicate(true))
	queued.sort_custom(func(a, b): return String(a.squadron_id) < String(b.squadron_id)); events.sort_custom(func(a, b): return int(a.serial) < int(b.serial))
	var result := catalog(); result.merge({"viewer_faction_id": viewer_faction_id, "statuses": statuses, "queued": queued, "events": events})
	return result


func _event(status: String, squadron_id: String, faction_id: String, previous: String, requested: String, requested_turn: int, effective_turn: int, serial: int) -> Dictionary:
	return {"event_id": "FC-MISSION-%06d" % serial, "serial": serial, "event_type": "fast_craft_mission_change",
		"status": status, "squadron_id": squadron_id, "faction_id": faction_id, "previous_mission_id": previous,
		"mission_id": requested, "requested_turn": requested_turn, "effective_turn": effective_turn,
		"result_pending": ["non_rescue_mission_effect"]}


func _append_event(state: Dictionary, turn_number: int, event: Dictionary) -> void:
	if not state.events_by_turn.has(turn_number): state.events_by_turn[turn_number] = []
	state.events_by_turn[turn_number].append(event.duplicate(true))


func _claim_serial(state: Dictionary) -> int:
	var serial := int(state.get("next_event_serial", 1)); state["next_event_serial"] = serial + 1; return serial


func _equipment_allowlists() -> Dictionary:
	var out := {}; for row in _rules.get("mission_equipment", []): out[String(row.equipment_id)] = row.supported_tactical_mission_ids.duplicate()
	return out


func _equipment_rule(equipment_id: String) -> Dictionary:
	for row in _rules.get("mission_equipment", []):
		if String(row.get("equipment_id", "")) == equipment_id: return row
	return {}


func _fast_craft_squadrons() -> Array:
	var rows: Array = []
	for squad in _setup.get("squadrons", []):
		if bool(squad.get("operational", true)) and squad.get("composition") is Array and squad.composition.size() == 1 and String(squad.composition[0].get("ship_type_id", "")) == Setup.FAST_CRAFT_ID: rows.append(squad)
	rows.sort_custom(func(a, b): return String(a.id) < String(b.id)); return rows


func _ok() -> Dictionary: return {"ok": true, "errors": []}
func _error(message: String) -> Dictionary: return {"ok": false, "errors": [message]}
