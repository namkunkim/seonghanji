class_name RedCliffsTurnBattle
extends RefCounted

## DEMO-RC-G4-01 — 유비 명령·손권 제어 선택·20턴 판정 루프.
## 명령 원장과 턴 경계만 소유하며 이동·사격·피해·탐지·승패는 후속 resolver에 맡긴다.
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const MAX_TURNS := 20
const RULES_PENDING := [
	"movement", "weapon_fire", "formation_change", "detection", "damage", "casualties", "victory"
]

var _state: Dictionary = {}


func _init(applied_setup: Dictionary = {}) -> void:
	if not applied_setup.is_empty():
		initialize(applied_setup)


func initialize(applied_setup: Dictionary) -> Dictionary:
	var validation := Setup.validate_document(applied_setup)
	if not bool(validation.get("ok", false)):
		return _error("유효한 G3 적용 편성이 필요합니다.", validation.get("errors", []))
	var setup: Dictionary = validation.get("setup", {}).duplicate(true)
	_state = {
		"applied_setup": setup,
		"current_turn": 1,
		"max_turns": MAX_TURNS,
		"phase": "liu_command",
		"resolved": false,
		"sun_prompt_policy": {"enabled": true},
		"turn_log": [_new_turn_log(1)],
	}
	return _ok()


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func digest() -> String:
	return JSON.stringify(_state)


func phase() -> String:
	return String(_state.get("phase", "uninitialized"))


func turn() -> int:
	return int(_state.get("current_turn", 0))


func prompt_policy() -> Dictionary:
	return _state.get("sun_prompt_policy", {}).duplicate(true)


func turn_log() -> Array:
	return _state.get("turn_log", []).duplicate(true)


func submit_liu_orders(orders: Array) -> Dictionary:
	if phase() != "liu_command":
		return _error("현재 단계에서는 유비군 명령을 제출할 수 없습니다.")
	var checked := _validate_orders("liu_bei", orders)
	if not bool(checked.get("ok", false)): return checked
	_current_log()["liu_orders"] = checked.orders.duplicate(true)
	if bool(_state.sun_prompt_policy.enabled):
		_state.phase = "sun_control_prompt"
	else:
		_current_log()["sun_control_decision"] = {
			"control": "ai", "dont_ask_again": true, "source": "saved_policy"
		}
		_prepare_ai_resolution()
	return _ok()


func submit_sun_control_choice(answer: String, dont_ask_again: bool = false) -> Dictionary:
	if phase() != "sun_control_prompt":
		return _error("현재 단계에서는 손권군 제어 방식을 선택할 수 없습니다.")
	var normalized := answer.strip_edges().to_lower()
	if not ["yes", "manual", "no", "ai"].has(normalized):
		return _error("손권군 제어 선택은 yes/manual 또는 no/ai여야 합니다.")
	var manual := ["yes", "manual"].has(normalized)
	if manual and dont_ask_again:
		return _error("수동 제어와 다시 묻지 않음을 함께 선택할 수 없습니다.")
	_current_log()["sun_control_decision"] = {
		"control": "manual" if manual else "ai",
		"dont_ask_again": dont_ask_again,
		"source": "turn_prompt",
	}
	if manual:
		_state.phase = "sun_command"
	else:
		if dont_ask_again: _state.sun_prompt_policy.enabled = false
		_prepare_ai_resolution()
	return _ok()


func set_sun_prompt_enabled(enabled: bool) -> Dictionary:
	if _state.is_empty(): return _error("턴 전투가 초기화되지 않았습니다.")
	if phase() == "sun_control_prompt":
		return _error("진행 중인 손권 선택에 먼저 답해야 합니다.")
	_state.sun_prompt_policy.enabled = enabled
	return _ok()


func submit_sun_orders(orders: Array) -> Dictionary:
	if phase() != "sun_command":
		return _error("현재 단계에서는 손권군 명령을 제출할 수 없습니다.")
	var checked := _validate_orders("sun_quan", orders)
	if not bool(checked.get("ok", false)): return checked
	_current_log()["sun_orders"] = checked.orders.duplicate(true)
	_current_log()["cao_orders"] = _ai_hold_orders("cao_cao")
	_state.phase = "resolution"
	return _ok()


func resolve_turn() -> Dictionary:
	if phase() != "resolution":
		return _error("현재 단계에서는 턴 판정을 확정할 수 없습니다.")
	var receipt := {
		"ok": true,
		"turn": turn(),
		"status": "orders_committed",
		"rules_pending": RULES_PENDING.duplicate(),
		"victory_check_required": true,
	}
	var log := _current_log()
	log.resolution_receipt = receipt.duplicate(true)
	log.victory_check_required = true
	_state.resolved = true
	_state.phase = "turn_limit_reached" if turn() >= MAX_TURNS else "victory_check"
	return receipt.duplicate(true)


func continue_turn() -> Dictionary:
	if phase() == "turn_limit_reached":
		return _error("20턴 제한에 도달했습니다. 후속 승패 비교가 필요하며 다음 턴은 시작할 수 없습니다.")
	if phase() != "victory_check":
		return _error("턴 판정 뒤 외부 승리 확인 경계에서만 다음 턴으로 진행할 수 있습니다.")
	_state.current_turn = turn() + 1
	_state.phase = "liu_command"
	_state.resolved = false
	_state.turn_log.append(_new_turn_log(turn()))
	return _ok()


func _prepare_ai_resolution() -> void:
	_current_log()["sun_orders"] = _ai_hold_orders("sun_quan")
	_current_log()["cao_orders"] = _ai_hold_orders("cao_cao")
	_state.phase = "resolution"


func _validate_orders(faction_id: String, orders: Array) -> Dictionary:
	var expected := _operational_squadron_ids(faction_id)
	var expected_set := {}
	for squadron_id in expected: expected_set[squadron_id] = true
	var seen := {}
	var normalized: Array = []
	for value in orders:
		if not value is Dictionary:
			return _error("명령은 squadron_id와 action을 가진 객체여야 합니다.")
		var order: Dictionary = value
		if order.size() != 2 or not order.has("squadron_id") or not order.has("action"):
			return _error("명령 스키마는 {squadron_id, action}만 허용합니다.")
		var squadron_id := String(order.get("squadron_id", ""))
		if not expected_set.has(squadron_id):
			return _error("미지 전대이거나 해당 세력의 operational 전대가 아닙니다: %s" % squadron_id)
		if seen.has(squadron_id): return _error("전대 명령이 중복되었습니다: %s" % squadron_id)
		if String(order.get("action", "")) != "hold":
			return _error("이번 단계에서는 hold 명령만 허용합니다.")
		seen[squadron_id] = true
		normalized.append({"squadron_id": squadron_id, "action": "hold"})
	if seen.size() != expected.size():
		return _error("세력의 모든 operational 전대 명령을 제출해야 합니다.")
	normalized.sort_custom(func(a, b): return String(a.squadron_id) < String(b.squadron_id))
	return {"ok": true, "errors": [], "orders": normalized}


func _ai_hold_orders(faction_id: String) -> Array:
	var result: Array = []
	for squadron_id in _operational_squadron_ids(faction_id):
		result.append({"squadron_id": squadron_id, "action": "hold"})
	return result


func _operational_squadron_ids(faction_id: String) -> Array:
	var result: Array = []
	for value in _state.get("applied_setup", {}).get("squadrons", []):
		if value is Dictionary and String(value.get("faction_id", "")) == faction_id \
				and bool(value.get("operational", true)):
			result.append(String(value.get("id", "")))
	result.sort()
	return result


func _current_log() -> Dictionary:
	return _state.turn_log[_state.turn_log.size() - 1]


func _new_turn_log(turn_number: int) -> Dictionary:
	return {
		"turn": turn_number,
		"liu_orders": [],
		"sun_control_decision": {},
		"sun_orders": [],
		"cao_orders": [],
		"resolution_receipt": {},
		"victory_check_required": false,
	}


func _ok() -> Dictionary:
	return {"ok": true, "errors": []}


func _error(message: String, details: Array = []) -> Dictionary:
	var errors: Array = [message]
	for detail in details: errors.append(String(detail))
	return {"ok": false, "errors": errors}
