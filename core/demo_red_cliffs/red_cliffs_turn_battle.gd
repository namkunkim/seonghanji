class_name RedCliffsTurnBattle
extends RefCounted

## DEMO-RC-G4-01 — 유비 명령·손권 제어 선택·20턴 판정 루프.
## 명령 원장과 턴 경계만 소유하며 이동·사격·피해·탐지·승패는 후속 resolver에 맡긴다.
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const MovementResolver := preload("res://core/demo_red_cliffs/red_cliffs_movement_resolver.gd")
const InterceptionResolver := preload("res://core/demo_red_cliffs/red_cliffs_interception_resolver.gd")
const FormationResolver := preload("res://core/demo_red_cliffs/red_cliffs_formation_resolver.gd")
const WeaponAllocation := preload("res://core/demo_red_cliffs/red_cliffs_weapon_allocation.gd")
const CombatResources := preload("res://core/demo_red_cliffs/red_cliffs_combat_resources.gd")
const PhaseLedger := preload("res://core/demo_red_cliffs/red_cliffs_phase_ledger.gd")
const FogOfWar := preload("res://core/demo_red_cliffs/red_cliffs_fog_of_war.gd")
const TerrainResolver := preload("res://core/demo_red_cliffs/red_cliffs_terrain_resolver.gd")
const AiPlanner := preload("res://core/demo_red_cliffs/red_cliffs_ai_planner.gd")
const MAX_TURNS := 20
const RULES_PENDING := [
	"weapon_fire", "damage", "casualties", "victory"
]

var _state: Dictionary = {}
var _movement
var _interception
var _formation
var _weapon_control
var _combat_resources
var _phase_ledger
var _fog
var _terrain
var _ai_planner
var _viewer_receipts_by_turn: Dictionary = {}
var _viewer_phase_ledgers_by_turn: Dictionary = {}


func _init(applied_setup: Dictionary = {}) -> void:
	if not applied_setup.is_empty():
		initialize(applied_setup)


func initialize(applied_setup: Dictionary) -> Dictionary:
	var validation := Setup.validate_document(applied_setup)
	if not bool(validation.get("ok", false)):
		return _error("유효한 G3 적용 편성이 필요합니다.", validation.get("errors", []))
	var setup: Dictionary = validation.get("setup", {}).duplicate(true)
	var movement = MovementResolver.new()
	var movement_result: Dictionary = movement.initialize(setup)
	if not movement_result.ok: return movement_result
	var interception = InterceptionResolver.new()
	var interception_result: Dictionary = interception.initialize(setup)
	if not interception_result.ok: return interception_result
	var formation = FormationResolver.new()
	var formation_result: Dictionary = formation.initialize(setup)
	if not formation_result.ok: return formation_result
	var weapon_control = WeaponAllocation.new()
	var weapon_result: Dictionary = weapon_control.initialize(setup)
	if not weapon_result.ok: return weapon_result
	var combat_resources = CombatResources.new()
	var resource_result: Dictionary = combat_resources.initialize(setup)
	if not resource_result.ok: return resource_result
	var phase_ledger = PhaseLedger.new()
	var ledger_result: Dictionary = phase_ledger.initialize()
	if not ledger_result.ok: return ledger_result
	var fog = FogOfWar.new()
	var fog_result: Dictionary = fog.initialize(setup)
	if not fog_result.ok: return fog_result
	var terrain = TerrainResolver.new(); var terrain_result: Dictionary = terrain.initialize(setup)
	if not terrain_result.ok: return terrain_result
	var ai_planner = AiPlanner.new(); var ai_result: Dictionary = ai_planner.initialize()
	if not ai_result.ok: return ai_result
	var formation_ids: Array = formation.allowed_formations().map(func(row): return String(row.formation_id))
	var preset_ids: Array = weapon_control.presets().map(func(row): return String(row.preset_id))
	for posture in ai_planner.rules_snapshot().postures.values():
		if not formation_ids.has(String(posture.formation_id)) or not preset_ids.has(String(posture.weapon_preset_id)):
			return _error("AI 자세가 미지 진형 또는 무기 프리셋을 참조합니다.")
	_movement = movement
	_interception = interception
	_formation = formation
	_weapon_control = weapon_control
	_combat_resources = combat_resources
	_phase_ledger = phase_ledger
	_fog = fog
	_terrain = terrain
	_ai_planner = ai_planner
	_viewer_receipts_by_turn = {}
	_viewer_phase_ledgers_by_turn = {}
	_state = {
		"applied_setup": setup,
		"current_turn": 1,
		"max_turns": MAX_TURNS,
		"phase": "liu_command",
		"resolved": false,
		"sun_prompt_policy": {"enabled": true, "current_turn_enabled": true, "effective_turn": 1},
		"live_navigation": _movement.initial_navigation(),
		"detection_state": _interception.initial_detection_state(),
		"formation_state": _formation.initial_state(),
		"weapon_allocation_state": _weapon_control.initial_state(),
		"combat_resource_state": _combat_resources.initial_state(),
		"last_resource_recovery_events": [],
		"last_resource_recovery_turn": 0,
		"phase_ledgers": {},
		"command_draft": {},
		"turn_log": [_new_turn_log(1)],
	}
	_begin_command_draft("liu_bei")
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


func live_navigation() -> Dictionary:
	return _state.get("live_navigation", {}).duplicate(true)


func detection_state() -> Dictionary:
	return _state.get("detection_state", {}).duplicate(true)


func formation_state() -> Dictionary:
	return _state.get("formation_state", {}).duplicate(true)


func allowed_formations() -> Array:
	if _state.is_empty(): return []
	return _formation.allowed_formations()


func weapon_categories() -> Array:
	if _state.is_empty(): return []
	return _weapon_control.categories()


func weapon_presets() -> Array:
	if _state.is_empty(): return []
	return _weapon_control.presets()


func weapon_allocation_state() -> Dictionary:
	return _state.get("weapon_allocation_state", {}).duplicate(true)


func combat_resource_state() -> Dictionary:
	return _state.get("combat_resource_state", {}).duplicate(true)


func visible_combat_resources(viewer_faction_id: String) -> Dictionary:
	if _state.is_empty(): return _error("턴 전투가 초기화되지 않았습니다.")
	return _combat_resources.visible_state(viewer_faction_id, _state.combat_resource_state)


func scheduled_resource_preview(viewer_faction_id: String) -> Dictionary:
	if _state.is_empty(): return _error("턴 전투가 초기화되지 않았습니다.")
	return _combat_resources.scheduled_preview(viewer_faction_id, _state.combat_resource_state,
		turn(), int(_state.last_resource_recovery_turn))


func visible_contacts(viewer_faction_id: String) -> Dictionary:
	if _state.is_empty(): return _error("턴 전투가 초기화되지 않았습니다.")
	var result: Dictionary = _interception.visible_contacts(viewer_faction_id, _state.detection_state, _state.live_navigation)
	if not result.ok: return result
	for contact in result.contacts:
		var target_id := _target_id_for_contact(viewer_faction_id, String(contact.contact_id))
		contact["disposition"] = _ai_planner.disposition(viewer_faction_id, _squadron_faction_id(target_id))
	return result


func terrain_zones() -> Array:
	return [] if _state.is_empty() else _terrain.visible_zones()


func own_terrain_membership(viewer_faction_id: String) -> Dictionary:
	if not _faction_ids().has(viewer_faction_id): return _error("미지 관측 세력입니다: %s" % viewer_faction_id)
	var result := {}
	for squadron_id in _operational_squadron_ids(viewer_faction_id): result[squadron_id] = _terrain.point_effects(_state.live_navigation[squadron_id].position)
	return {"ok": true, "errors": [], "viewer_faction_id": viewer_faction_id, "membership": result}


func visible_tactical_events(viewer_faction_id: String, turn_number: int = 0) -> Dictionary:
	if _state.is_empty(): return _error("턴 전투가 초기화되지 않았습니다.")
	var wanted_turn := turn() if turn_number <= 0 else turn_number
	if not _viewer_receipts_by_turn.has(wanted_turn) or not _viewer_receipts_by_turn[wanted_turn].has(viewer_faction_id):
		return {"ok": true, "errors": [], "viewer_faction_id": viewer_faction_id, "turn": wanted_turn, "events": []}
	return _viewer_receipts_by_turn[wanted_turn][viewer_faction_id].duplicate(true)


func phase_ledger(turn_number: int = 0) -> Dictionary:
	if _state.is_empty(): return _error("턴 전투가 초기화되지 않았습니다.")
	var wanted_turn := turn() if turn_number <= 0 else turn_number
	if not _state.phase_ledgers.has(wanted_turn): return _error("아직 확정된 5단계 원장이 없습니다: %d턴" % wanted_turn)
	return _state.phase_ledgers[wanted_turn].duplicate(true)


func viewer_phase_ledger(viewer_faction_id: String, turn_number: int = 0) -> Dictionary:
	if not _faction_ids().has(viewer_faction_id): return _error("미지 관측 세력입니다: %s" % viewer_faction_id)
	var wanted_turn := turn() if turn_number <= 0 else turn_number
	if not _viewer_phase_ledgers_by_turn.has(wanted_turn) or not _viewer_phase_ledgers_by_turn[wanted_turn].has(viewer_faction_id):
		return _error("아직 확정된 viewer 5단계 원장이 없습니다: %d턴" % wanted_turn)
	return _viewer_phase_ledgers_by_turn[wanted_turn][viewer_faction_id].duplicate(true)


func viewer_phase_summary(viewer_faction_id: String, turn_number: int = 0) -> Dictionary:
	var ledger := viewer_phase_ledger(viewer_faction_id, turn_number)
	if not ledger.ok: return ledger
	return _phase_ledger.summary(ledger)


func viewer_phase(viewer_faction_id: String, phase_id: String, turn_number: int = 0) -> Dictionary:
	var ledger := viewer_phase_ledger(viewer_faction_id, turn_number)
	if not ledger.ok: return ledger
	return _phase_ledger.phase(ledger, phase_id)


func viewer_turn_log(viewer_faction_id: String) -> Dictionary:
	var contacts := visible_contacts(viewer_faction_id)
	if not contacts.ok: return contacts
	var logs: Array = []
	for value in _state.turn_log:
		var row: Dictionary = value; var visible := {"turn": int(row.turn), "resolved": not row.resolution_receipt.is_empty()}
		if viewer_faction_id == "liu_bei":
			visible["own_orders"] = row.liu_orders.duplicate(true)
			visible["own_formation_orders"] = row.liu_formation_orders.duplicate(true)
			visible["own_weapon_allocation_orders"] = row.liu_weapon_allocation_orders.duplicate(true)
			visible["own_estimated_fire_orders"] = row.liu_estimated_fire_orders.duplicate(true)
		elif viewer_faction_id == "sun_quan":
			visible["own_orders"] = row.sun_orders.duplicate(true)
			visible["own_formation_orders"] = row.sun_formation_orders.duplicate(true)
			visible["own_weapon_allocation_orders"] = row.sun_weapon_allocation_orders.duplicate(true)
			visible["own_estimated_fire_orders"] = row.sun_estimated_fire_orders.duplicate(true)
			visible["own_control_decision"] = row.sun_control_decision.duplicate(true)
			visible["own_ai_decision"] = row.sun_ai_decision.duplicate(true)
		elif viewer_faction_id == "cao_cao":
			visible["own_orders"] = row.cao_orders.duplicate(true)
			visible["own_formation_orders"] = row.cao_formation_orders.duplicate(true)
			visible["own_weapon_allocation_orders"] = row.cao_weapon_allocation_orders.duplicate(true)
			visible["own_estimated_fire_orders"] = row.cao_estimated_fire_orders.duplicate(true)
			visible["own_ai_decision"] = row.cao_ai_decision.duplicate(true)
		else: return _error("미지 관측 세력입니다: %s" % viewer_faction_id)
		visible["tactical_events"] = visible_tactical_events(viewer_faction_id, int(row.turn)).events
		logs.append(visible)
	return {"ok": true, "errors": [], "viewer_faction_id": viewer_faction_id, "turn_log": logs}


func viewer_ai_decision(viewer_faction_id: String, turn_number: int = 0) -> Dictionary:
	if not ["sun_quan", "cao_cao"].has(viewer_faction_id): return _error("AI 자기 관점 세력만 결정을 조회할 수 있습니다.")
	var wanted := turn() if turn_number <= 0 else turn_number
	for row in _state.get("turn_log", []):
		if int(row.turn) != wanted: continue
		var decision: Dictionary = row.sun_ai_decision if viewer_faction_id == "sun_quan" else row.cao_ai_decision
		if decision.is_empty(): return {"ok": true, "errors": [], "viewer_faction_id": viewer_faction_id, "turn": wanted, "available": false}
		var result: Dictionary = decision.duplicate(true); result["ok"] = true; result["errors"] = []
		result["viewer_faction_id"] = viewer_faction_id; result["turn"] = wanted; result["available"] = true
		return result
	return _error("요청한 턴이 없습니다: %d" % wanted)


func viewer_snapshot(viewer_faction_id: String) -> Dictionary:
	var contacts := visible_contacts(viewer_faction_id)
	if not contacts.ok: return contacts
	var own_squadrons: Array = []; var own_navigation := {}
	for squad in _state.applied_setup.squadrons:
		if String(squad.faction_id) == viewer_faction_id:
			var own_squad: Dictionary = squad.duplicate(true)
			own_squad.formation_id = String(_state.formation_state[String(squad.id)].formation_id)
			own_squadrons.append(own_squad); own_navigation[String(squad.id)] = _state.live_navigation[String(squad.id)].duplicate(true)
	return {"ok": true, "errors": [], "viewer_faction_id": viewer_faction_id, "turn": turn(), "phase": phase(),
		"battlefield_bounds": _state.applied_setup.battlefield_bounds.duplicate(),
		"own_squadrons": own_squadrons, "own_navigation": own_navigation, "contacts": contacts.contacts,
		"own_formation_state": _own_formation_state(viewer_faction_id), "allowed_formations": allowed_formations(),
		"own_weapon_allocation_state": _own_weapon_allocation_state(viewer_faction_id),
		"weapon_categories": weapon_categories(), "weapon_presets": weapon_presets(),
		"own_combat_resources": visible_combat_resources(viewer_faction_id).resource_state,
		"terrain_zones": terrain_zones(), "own_terrain_membership": own_terrain_membership(viewer_faction_id).membership,
		"resource_recovery_events": _combat_resources.visible_events(viewer_faction_id,
			{"recovery_events": _state.last_resource_recovery_events}).events,
		"tactical_events": visible_tactical_events(viewer_faction_id).events,
		"prompt_policy": prompt_policy() if viewer_faction_id == "sun_quan" else {}}


func movement_preview(squadron_id: String, waypoints: Array, facing_deg) -> Dictionary:
	if _state.is_empty(): return _error("턴 전투가 초기화되지 않았습니다.")
	return _movement.movement_preview(squadron_id, waypoints, facing_deg, _state.live_navigation)


func command_draft() -> Dictionary:
	return _state.get("command_draft", {}).duplicate(true)


func current_direct_faction_id() -> String:
	if phase() == "liu_command": return "liu_bei"
	if phase() == "sun_command": return "sun_quan"
	return ""


func command_order(squadron_id: String) -> Dictionary:
	var draft: Dictionary = _state.get("command_draft", {})
	var orders: Dictionary = draft.get("orders", {})
	if not orders.has(squadron_id): return _error("현재 명령 초안에 전대가 없습니다: %s" % squadron_id)
	return {"ok": true, "errors": [], "order": orders[squadron_id].duplicate(true)}


func formation_order(squadron_id: String) -> Dictionary:
	var draft: Dictionary = _state.get("command_draft", {})
	var orders: Dictionary = draft.get("formation_orders", {})
	if not orders.has(squadron_id): return _error("현재 명령 초안에 전대 진형이 없습니다: %s" % squadron_id)
	return {"ok": true, "errors": [], "order": orders[squadron_id].duplicate(true)}


func weapon_allocation_order(squadron_id: String) -> Dictionary:
	var draft: Dictionary = _state.get("command_draft", {})
	var orders: Dictionary = draft.get("weapon_allocation_orders", {})
	if not orders.has(squadron_id): return _error("현재 명령 초안에 전대 무기 배분이 없습니다: %s" % squadron_id)
	return {"ok": true, "errors": [], "order": orders[squadron_id].duplicate(true),
		"total_basis_points": _allocation_total(orders[squadron_id].allocations)}


func estimated_fire_order(squadron_id: String) -> Dictionary:
	var draft: Dictionary = _state.get("command_draft", {})
	var orders: Dictionary = draft.get("estimated_fire_orders", {})
	return {"ok": true, "errors": [], "order": orders.get(squadron_id, {}).duplicate(true)}


func set_estimated_fire(squadron_id: String, contact_id_value: String) -> Dictionary:
	var access := _command_draft_access(squadron_id)
	if not access.ok: return access
	var faction_id := String(_state.command_draft.faction_id)
	var contacts := visible_contacts(faction_id)
	if not contacts.ok: return contacts
	for value in contacts.contacts:
		if value is Dictionary and String(value.get("contact_id", "")) == contact_id_value:
			var made: Dictionary = _fog.make_order(faction_id, squadron_id, value, turn())
			if not made.ok: return made
			_state.command_draft.estimated_fire_orders[squadron_id] = made.order.duplicate(true)
			return {"ok": true, "errors": [], "order": made.order.duplicate(true)}
	return _error("현재 관측 정보에 없는 추정 contact입니다: %s" % contact_id_value)


func clear_estimated_fire(squadron_id: String) -> Dictionary:
	var access := _command_draft_access(squadron_id)
	if not access.ok: return access
	_state.command_draft.estimated_fire_orders.erase(squadron_id)
	return _ok()


func command_draft_summary() -> Dictionary:
	var draft: Dictionary = _state.get("command_draft", {})
	var orders: Dictionary = draft.get("orders", {})
	var hold_count := 0
	var move_count := 0
	for order in orders.values():
		if String(order.get("action", "")) == "hold": hold_count += 1
		if String(order.get("action", "")) == "move": move_count += 1
	return {"faction_id": String(draft.get("faction_id", "")), "total": orders.size(),
		"hold_count": hold_count, "move_count": move_count,
		"estimated_fire_count": draft.get("estimated_fire_orders", {}).size(),
		"all_orders_ready": not orders.is_empty() and orders.size() == _operational_squadron_ids(String(draft.get("faction_id", ""))).size()}


func set_order_hold(squadron_id: String) -> Dictionary:
	var access := _command_draft_access(squadron_id)
	if not access.ok: return access
	_state.command_draft.orders[squadron_id] = {"squadron_id": squadron_id, "action": "hold"}
	return _ok()


func set_order_move(squadron_id: String, waypoints: Array, facing_deg) -> Dictionary:
	var access := _command_draft_access(squadron_id)
	if not access.ok: return access
	var preview := movement_preview(squadron_id, waypoints, facing_deg)
	if not preview.ok: return preview
	_state.command_draft.orders[squadron_id] = {"squadron_id": squadron_id, "action": "move",
		"waypoints": waypoints.duplicate(true), "facing_deg": float(facing_deg)}
	return preview


func set_formation_order(squadron_id: String, formation_id: String) -> Dictionary:
	var access := _command_draft_access(squadron_id)
	if not access.ok: return access
	var checked: Dictionary = _formation.validate_order(squadron_id, formation_id)
	if not checked.ok: return checked
	_state.command_draft.formation_orders[squadron_id] = {"squadron_id": squadron_id, "formation_id": formation_id}
	return _ok()


func set_weapon_basis_points(squadron_id: String, weapon_id: String, basis_points) -> Dictionary:
	var access := _command_draft_access(squadron_id)
	if not access.ok: return access
	var draft_state := _weapon_draft_state()
	var changed: Dictionary = _weapon_control.set_basis_points(draft_state, squadron_id, weapon_id, basis_points)
	if not changed.ok: return changed
	_set_weapon_draft_row(squadron_id, changed.row)
	return {"ok": true, "errors": [], "order": _state.command_draft.weapon_allocation_orders[squadron_id].duplicate(true),
		"total_basis_points": _allocation_total(changed.row.allocations)}


func apply_weapon_preset(squadron_id: String, preset_id: String) -> Dictionary:
	var access := _command_draft_access(squadron_id)
	if not access.ok: return access
	var changed: Dictionary = _weapon_control.apply_preset(_weapon_draft_state(), squadron_id, preset_id)
	if not changed.ok: return changed
	_set_weapon_draft_row(squadron_id, changed.row)
	return {"ok": true, "errors": [], "order": _state.command_draft.weapon_allocation_orders[squadron_id].duplicate(true),
		"total_basis_points": _allocation_total(changed.row.allocations)}


func set_hold_fire(squadron_id: String, enabled: bool) -> Dictionary:
	var access := _command_draft_access(squadron_id)
	if not access.ok: return access
	var changed: Dictionary = _weapon_control.set_hold_fire(_weapon_draft_state(), squadron_id, enabled)
	if not changed.ok: return changed
	_set_weapon_draft_row(squadron_id, changed.row)
	return {"ok": true, "errors": [], "order": _state.command_draft.weapon_allocation_orders[squadron_id].duplicate(true)}


func submit_command_draft() -> Dictionary:
	var draft: Dictionary = _state.get("command_draft", {})
	var faction_id := String(draft.get("faction_id", ""))
	var orders: Array = draft.get("orders", {}).values()
	orders.sort_custom(func(a, b): return String(a.squadron_id) < String(b.squadron_id))
	if phase() == "liu_command" and faction_id == "liu_bei": return submit_liu_orders(orders)
	if phase() == "sun_command" and faction_id == "sun_quan": return submit_sun_orders(orders)
	return _error("현재 단계의 직접 지휘 명령 초안을 제출할 수 없습니다.")


func submit_liu_orders(orders: Array) -> Dictionary:
	if phase() != "liu_command":
		return _error("현재 단계에서는 유비군 명령을 제출할 수 없습니다.")
	var checked := _validate_orders("liu_bei", orders)
	if not bool(checked.get("ok", false)): return checked
	var before_ai_state := _state.duplicate(true)
	_current_log()["liu_orders"] = checked.orders.duplicate(true)
	_current_log()["liu_formation_orders"] = _submitted_formation_orders("liu_bei")
	_current_log()["liu_weapon_allocation_orders"] = _submitted_weapon_orders("liu_bei")
	_current_log()["liu_estimated_fire_orders"] = _submitted_estimated_fire_orders("liu_bei")
	_state.command_draft = {}
	if bool(_state.sun_prompt_policy.current_turn_enabled):
		_state.phase = "sun_control_prompt"
	else:
		_current_log()["sun_control_decision"] = {
			"control": "ai", "dont_ask_again": true, "source": "saved_policy"
		}
		var prepared := _prepare_ai_resolution(true)
		if not prepared.ok: _state = before_ai_state; return prepared
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
	var before_ai_state := _state.duplicate(true)
	_current_log()["sun_control_decision"] = {
		"control": "manual" if manual else "ai",
		"dont_ask_again": dont_ask_again,
		"source": "turn_prompt",
	}
	if manual:
		_state.phase = "sun_command"
		_begin_command_draft("sun_quan")
	else:
		if dont_ask_again: _state.sun_prompt_policy.enabled = false
		var prepared := _prepare_ai_resolution(true)
		if not prepared.ok: _state = before_ai_state; return prepared
	return _ok()


func set_sun_prompt_enabled(enabled: bool) -> Dictionary:
	if _state.is_empty(): return _error("턴 전투가 초기화되지 않았습니다.")
	if phase() == "sun_control_prompt":
		return _error("진행 중인 손권 선택에 먼저 답해야 합니다.")
	# Settings changes are visible immediately but become effective only when the
	# next turn begins. They never discard or redirect the current direct draft.
	_state.sun_prompt_policy.enabled = enabled
	return _ok()


func submit_sun_orders(orders: Array) -> Dictionary:
	if phase() != "sun_command":
		return _error("현재 단계에서는 손권군 명령을 제출할 수 없습니다.")
	var checked := _validate_orders("sun_quan", orders)
	if not bool(checked.get("ok", false)): return checked
	var before_ai_state := _state.duplicate(true)
	_current_log()["sun_orders"] = checked.orders.duplicate(true)
	_current_log()["sun_formation_orders"] = _submitted_formation_orders("sun_quan")
	_current_log()["sun_weapon_allocation_orders"] = _submitted_weapon_orders("sun_quan")
	_current_log()["sun_estimated_fire_orders"] = _submitted_estimated_fire_orders("sun_quan")
	_state.command_draft = {}
	var prepared := _prepare_ai_faction("cao_cao")
	if not prepared.ok: _state = before_ai_state; return prepared
	_state.phase = "resolution"
	return _ok()


func resolve_turn() -> Dictionary:
	if phase() != "resolution":
		return _error("현재 단계에서는 턴 판정을 확정할 수 없습니다.")
	var resource_base_state: Dictionary = _state.combat_resource_state.duplicate(true)
	var recovery_events: Array = []
	if turn() >= 2 and int(_state.last_resource_recovery_turn) < turn():
		var recovered: Dictionary = _combat_resources.recover_at_resolution_start(resource_base_state, turn())
		if not recovered.ok: return recovered
		resource_base_state = recovered.resource_state.duplicate(true)
		recovery_events = recovered.recovery_events.duplicate(true)
	var orders: Array = []
	orders.append_array(_current_log().liu_orders)
	orders.append_array(_current_log().sun_orders)
	orders.append_array(_current_log().cao_orders)
	var formation_orders: Array = []
	formation_orders.append_array(_current_log().liu_formation_orders)
	formation_orders.append_array(_current_log().sun_formation_orders)
	formation_orders.append_array(_current_log().cao_formation_orders)
	var formation_result: Dictionary = _formation.resolve_orders(formation_orders, _state.formation_state, turn())
	if not formation_result.ok: return formation_result
	var weapon_orders: Array = []
	weapon_orders.append_array(_current_log().liu_weapon_allocation_orders)
	weapon_orders.append_array(_current_log().sun_weapon_allocation_orders)
	weapon_orders.append_array(_current_log().cao_weapon_allocation_orders)
	var weapon_result: Dictionary = _weapon_control.resolve_orders(weapon_orders, _state.weapon_allocation_state, turn())
	if not weapon_result.ok: return weapon_result
	var movement_result: Dictionary = _movement.resolve_orders(orders, _state.live_navigation)
	if not movement_result.ok: return movement_result
	var interception_result: Dictionary = _interception.resolve(movement_result.events,
		movement_result.live_navigation, _state.detection_state, turn(),
		_weapon_control.interception_policy(weapon_result.weapon_allocation_state), formation_result.formation_state)
	if not interception_result.ok: return interception_result
	var decorated: Dictionary = _formation.decorate_shot_events(interception_result.opportunity_fire_events,
		formation_result.formation_state, movement_result.live_navigation)
	if not decorated.ok: return decorated
	var estimated_events: Array = []; var estimated_suppressed: Array = []
	for faction_id in ["liu_bei", "sun_quan", "cao_cao"]:
		var estimated_result: Dictionary = _fog.authorize_orders(_estimated_orders_from_log(faction_id), faction_id,
			movement_result.live_navigation, _weapon_control.interception_policy(weapon_result.weapon_allocation_state), turn())
		if not estimated_result.ok: return estimated_result
		estimated_events.append_array(estimated_result.estimated_fire_events)
		estimated_suppressed.append_array(estimated_result.suppressed_events)
	var all_authorized: Array = decorated.events.duplicate(true)
	all_authorized.append_array(estimated_events)
	var resource_result: Dictionary = _combat_resources.resolve_shots(all_authorized,
		resource_base_state, turn())
	if not resource_result.ok: return resource_result
	var receipt := {
		"ok": true,
		"turn": turn(),
		"status": "orders_committed",
		"rules_pending": RULES_PENDING.duplicate(),
		"movement_events": movement_result.events.duplicate(true),
		"terrain_events": _decorate_terrain_events(movement_result.terrain_events),
		"formation_events": formation_result.formation_events.duplicate(true),
		"formation_modifier_snapshots": formation_result.modifier_snapshots.duplicate(true),
		"weapon_allocation_events": weapon_result.weapon_allocation_events.duplicate(true),
		"path_intersection_events": interception_result.path_intersection_events.duplicate(true),
		"detection_events": interception_result.detection_events.duplicate(true),
		"opportunity_fire_events": _events_with_outcome(resource_result.authorized_events, "shot_authorized"),
		"estimated_fire_events": _events_with_outcome(resource_result.authorized_events, "estimated_fire_authorized"),
		"estimated_fire_suppressed_events": estimated_suppressed.duplicate(true),
		"resource_consumption_events": resource_result.consumption_events.duplicate(true),
		"suppressed_fire_events": resource_result.suppressed_fire_events.duplicate(true),
		"resource_recovery_events": recovery_events.duplicate(true),
		"victory_check_required": true,
	}
	var ledger: Dictionary = _phase_ledger.build(turn(), receipt)
	if not ledger.ok: return ledger
	receipt["phase_ledger"] = ledger.duplicate(true)
	var next_viewer_receipts := {}; var next_viewer_ledgers := {}
	for faction in _state.applied_setup.factions:
		var faction_id := String(faction.id)
		var visible: Dictionary = _interception.visible_tactical_events(faction_id, receipt, interception_result.detection_state)
		if not visible.ok: return visible
		for terrain_event in receipt.terrain_events:
			if _squadron_faction_id(String(terrain_event.squadron_id)) == faction_id: visible.events.append(terrain_event.duplicate(true))
		var resource_visible: Dictionary = _combat_resources.visible_events(faction_id,
			{"consumption_events": receipt.resource_consumption_events,
			"suppressed_fire_events": receipt.suppressed_fire_events,
			"recovery_events": receipt.resource_recovery_events})
		if not resource_visible.ok: return resource_visible
		visible.events.append_array(resource_visible.events)
		var fog_visible: Dictionary = _fog.visible_events(faction_id, receipt)
		visible.events.append_array(fog_visible.events)
		visible.events.sort_custom(func(a, b): return String(a.get("event_id", "")) < String(b.get("event_id", "")))
		visible["turn"] = turn()
		var viewer_ledger: Dictionary = _phase_ledger.build_viewer(turn(),
			_viewer_ledger_receipt(faction_id, receipt, visible.events))
		if not viewer_ledger.ok: return viewer_ledger
		next_viewer_receipts[faction_id] = visible.duplicate(true)
		next_viewer_ledgers[faction_id] = viewer_ledger.duplicate(true)
	_state.live_navigation = movement_result.live_navigation.duplicate(true)
	_state.detection_state = interception_result.detection_state.duplicate(true)
	_state.formation_state = formation_result.formation_state.duplicate(true)
	_state.weapon_allocation_state = weapon_result.weapon_allocation_state.duplicate(true)
	_state.combat_resource_state = resource_result.resource_state.duplicate(true)
	_state.last_resource_recovery_events = recovery_events.duplicate(true)
	if turn() >= 2: _state.last_resource_recovery_turn = turn()
	_state.phase_ledgers[turn()] = ledger.duplicate(true)
	_viewer_receipts_by_turn[turn()] = next_viewer_receipts.duplicate(true)
	_viewer_phase_ledgers_by_turn[turn()] = next_viewer_ledgers.duplicate(true)
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
	_state.sun_prompt_policy.current_turn_enabled = bool(_state.sun_prompt_policy.enabled)
	_state.sun_prompt_policy.effective_turn = turn()
	_state.last_resource_recovery_events = []
	_state.phase = "liu_command"
	_state.resolved = false
	_state.turn_log.append(_new_turn_log(turn()))
	_begin_command_draft("liu_bei")
	return _ok()


func _prepare_ai_resolution(include_sun: bool) -> Dictionary:
	var factions := ["cao_cao"]
	if include_sun: factions.push_front("sun_quan")
	for faction_id in factions:
		var prepared := _prepare_ai_faction(faction_id)
		if not prepared.ok: return prepared
	_state.command_draft = {}
	_state.phase = "resolution"
	return _ok()


func _prepare_ai_faction(faction_id: String) -> Dictionary:
	var viewer: Dictionary = viewer_snapshot(faction_id)
	if not viewer.ok: return viewer
	var resources: Dictionary = scheduled_resource_preview(faction_id)
	if not resources.ok: return resources
	var plan: Dictionary = _ai_planner.plan(viewer.duplicate(true), resources.duplicate(true), turn())
	if not plan.ok: return plan
	var weapon_state: Dictionary = _state.weapon_allocation_state.duplicate(true)
	var weapon_orders: Array = []
	for preset_order in plan.weapon_preset_orders:
		var squadron_id := String(preset_order.squadron_id); var changed: Dictionary
		if String(preset_order.preset_id).is_empty():
			changed = {"ok": true, "state": weapon_state.duplicate(true), "row": weapon_state[squadron_id].duplicate(true)}
		else:
			changed = _weapon_control.apply_preset(weapon_state, squadron_id, String(preset_order.preset_id))
			if not changed.ok: return changed
		weapon_state = changed.state.duplicate(true)
		var fire_policy: Dictionary = _weapon_control.set_hold_fire(weapon_state, squadron_id, bool(preset_order.hold_fire))
		if not fire_policy.ok: return fire_policy
		weapon_state = fire_policy.state.duplicate(true)
		weapon_orders.append({"squadron_id": squadron_id, "allocations": fire_policy.row.allocations.duplicate(true), "hold_fire": bool(fire_policy.row.hold_fire)})
	var estimated_orders: Array = []
	for intent in plan.estimated_fire_intents:
		var contact := _contact_by_id(viewer.contacts, String(intent.contact_id))
		if contact.is_empty(): return _error("AI 추정 contact가 viewer snapshot에 없습니다.")
		var made: Dictionary = _fog.make_order(faction_id, String(intent.squadron_id), contact, turn())
		if not made.ok: return made
		estimated_orders.append(made.order.duplicate(true))
	var prefix := "sun" if faction_id == "sun_quan" else "cao"
	_current_log()["%s_orders" % prefix] = plan.orders.duplicate(true)
	_current_log()["%s_formation_orders" % prefix] = plan.formation_orders.duplicate(true)
	_current_log()["%s_weapon_allocation_orders" % prefix] = weapon_orders
	_current_log()["%s_estimated_fire_orders" % prefix] = estimated_orders
	_current_log()["%s_ai_decision" % prefix] = {"source": String(plan.source), "posture": String(plan.posture),
		"intents": plan.intents.duplicate(true), "orders": plan.orders.duplicate(true),
		"formation_orders": plan.formation_orders.duplicate(true), "weapon_allocation_orders": weapon_orders.duplicate(true),
		"estimated_fire_orders": estimated_orders.duplicate(true)}
	return _ok()


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
		if not order.has("squadron_id") or not order.has("action"):
			return _error("명령에는 squadron_id와 action이 필요합니다.")
		var squadron_id := String(order.get("squadron_id", ""))
		if not expected_set.has(squadron_id):
			return _error("미지 전대이거나 해당 세력의 operational 전대가 아닙니다: %s" % squadron_id)
		if seen.has(squadron_id): return _error("전대 명령이 중복되었습니다: %s" % squadron_id)
		var action := String(order.get("action", ""))
		if action == "hold":
			if order.size() != 2: return _error("hold 명령에는 이동 필드를 지정할 수 없습니다.")
		elif action == "move":
			if order.size() != 4 or not order.has("waypoints") or not order.has("facing_deg") or not order.waypoints is Array:
				return _error("move 명령 스키마는 squadron_id, action, waypoints, facing_deg입니다.")
			var preview := movement_preview(squadron_id, order.waypoints, order.facing_deg)
			if not preview.ok: return preview
		else:
			return _error("hold 또는 move 명령만 허용합니다.")
		seen[squadron_id] = true
		var normalized_order := {"squadron_id": squadron_id, "action": action}
		if action == "move":
			normalized_order.waypoints = order.waypoints.duplicate(true)
			normalized_order.facing_deg = float(order.facing_deg)
		normalized.append(normalized_order)
	if seen.size() != expected.size():
		return _error("세력의 모든 operational 전대 명령을 제출해야 합니다.")
	normalized.sort_custom(func(a, b): return String(a.squadron_id) < String(b.squadron_id))
	return {"ok": true, "errors": [], "orders": normalized}


func _ai_hold_orders(faction_id: String) -> Array:
	var result: Array = []
	for squadron_id in _operational_squadron_ids(faction_id):
		result.append({"squadron_id": squadron_id, "action": "hold"})
	return result


func _current_formation_orders(faction_id: String) -> Array:
	var result: Array = []
	for squadron_id in _operational_squadron_ids(faction_id):
		result.append({"squadron_id": squadron_id,
			"formation_id": String(_state.formation_state[squadron_id].formation_id)})
	return result


func _submitted_formation_orders(faction_id: String) -> Array:
	var draft: Dictionary = _state.get("command_draft", {})
	if String(draft.get("faction_id", "")) != faction_id:
		return _current_formation_orders(faction_id)
	var result: Array = draft.get("formation_orders", {}).values()
	result.sort_custom(func(a, b): return String(a.squadron_id) < String(b.squadron_id))
	return result.duplicate(true)


func _current_weapon_orders(faction_id: String) -> Array:
	var result: Array = []
	for squadron_id in _operational_squadron_ids(faction_id):
		var row: Dictionary = _state.weapon_allocation_state[squadron_id]
		result.append({"squadron_id": squadron_id, "allocations": row.allocations.duplicate(true),
			"hold_fire": bool(row.hold_fire)})
	return result


func _submitted_weapon_orders(faction_id: String) -> Array:
	var draft: Dictionary = _state.get("command_draft", {})
	if String(draft.get("faction_id", "")) != faction_id: return _current_weapon_orders(faction_id)
	var result: Array = draft.get("weapon_allocation_orders", {}).values()
	result.sort_custom(func(a, b): return String(a.squadron_id) < String(b.squadron_id))
	return result.duplicate(true)


func _submitted_estimated_fire_orders(faction_id: String) -> Array:
	var draft: Dictionary = _state.get("command_draft", {})
	if String(draft.get("faction_id", "")) != faction_id: return []
	var result: Array = draft.get("estimated_fire_orders", {}).values()
	result.sort_custom(func(a, b): return String(a.squadron_id) < String(b.squadron_id))
	return result.duplicate(true)


func _estimated_orders_from_log(faction_id: String) -> Array:
	if faction_id == "liu_bei": return _current_log().liu_estimated_fire_orders.duplicate(true)
	if faction_id == "sun_quan": return _current_log().sun_estimated_fire_orders.duplicate(true)
	if faction_id == "cao_cao": return _current_log().cao_estimated_fire_orders.duplicate(true)
	return []


func _events_with_outcome(events: Array, outcome: String) -> Array:
	var result: Array = []
	for value in events:
		if value is Dictionary and String(value.get("outcome", "")) == outcome: result.append(value.duplicate(true))
	return result


func _weapon_draft_state() -> Dictionary:
	var result := {}
	for squadron_id in _state.get("command_draft", {}).get("weapon_allocation_orders", {}):
		var order: Dictionary = _state.command_draft.weapon_allocation_orders[squadron_id]
		var live: Dictionary = _state.weapon_allocation_state[squadron_id]
		result[squadron_id] = {"squadron_id": squadron_id, "faction_id": String(live.faction_id),
			"available_categories": live.available_categories.duplicate(), "allocations": order.allocations.duplicate(true),
			"hold_fire": bool(order.hold_fire)}
	return result


func _set_weapon_draft_row(squadron_id: String, row: Dictionary) -> void:
	_state.command_draft.weapon_allocation_orders[squadron_id] = {"squadron_id": squadron_id,
		"allocations": row.allocations.duplicate(true), "hold_fire": bool(row.hold_fire)}


func _allocation_total(allocations: Dictionary) -> int:
	var total := 0
	for value in allocations.values(): total += int(value)
	return total


func _own_formation_state(faction_id: String) -> Dictionary:
	var result := {}
	for squadron_id in _operational_squadron_ids(faction_id):
		result[squadron_id] = _state.formation_state[squadron_id].duplicate(true)
	return result


func _own_weapon_allocation_state(faction_id: String) -> Dictionary:
	var result := {}
	for squadron_id in _operational_squadron_ids(faction_id):
		result[squadron_id] = _state.weapon_allocation_state[squadron_id].duplicate(true)
	return result


func _viewer_ledger_receipt(faction_id: String, receipt: Dictionary, visible_events: Array) -> Dictionary:
	var safe := {"turn": int(receipt.turn), "rules_pending": receipt.rules_pending.duplicate(),
		"victory_check_required": bool(receipt.victory_check_required),
		"formation_events": [], "weapon_allocation_events": [], "resource_recovery_events": [],
		"movement_events": [], "terrain_events": [], "path_intersection_events": [], "detection_events": [],
		"opportunity_fire_events": [], "estimated_fire_events": [], "estimated_fire_suppressed_events": [],
		"resource_consumption_events": [], "suppressed_fire_events": []}
	for source in ["formation_events", "weapon_allocation_events", "resource_recovery_events",
			"movement_events", "terrain_events", "resource_consumption_events", "suppressed_fire_events"]:
		for value in receipt.get(source, []):
			if value is Dictionary:
				var squadron_id := String(value.get("squadron_id", ""))
				if _squadron_faction_id(squadron_id) == faction_id: safe[source].append(value.duplicate(true))
	for value in visible_events:
		if not value is Dictionary: continue
		var event_type := String(value.get("event_type", "")); var source := ""
		if event_type == "path_intersection": source = "path_intersection_events"
		elif event_type == "detection": source = "detection_events"
		elif event_type == "shot_authorized": source = "opportunity_fire_events"
		elif event_type == "estimated_fire_authorized": source = "estimated_fire_events"
		elif event_type == "estimated_fire_suppressed": source = "estimated_fire_suppressed_events"
		if not source.is_empty(): safe[source].append(value.duplicate(true))
	return safe


func _decorate_terrain_events(events: Array) -> Array:
	var result: Array = []
	for index in range(events.size()):
		var row: Dictionary = events[index].duplicate(true); row["turn"] = turn()
		row["event_id"] = "TRN-%02d-%03d-%s" % [turn(), index + 1, JSON.stringify(row).sha256_text().substr(0, 10)]
		result.append(row)
	return result


func _squadron_faction_id(squadron_id: String) -> String:
	for squad in _state.get("applied_setup", {}).get("squadrons", []):
		if String(squad.get("id", "")) == squadron_id: return String(squad.get("faction_id", ""))
	return ""


func _faction_ids() -> Array:
	var result: Array = []
	for faction in _state.get("applied_setup", {}).get("factions", []): result.append(String(faction.get("id", "")))
	return result


func _operational_squadron_ids(faction_id: String) -> Array:
	var result: Array = []
	for value in _state.get("applied_setup", {}).get("squadrons", []):
		if value is Dictionary and String(value.get("faction_id", "")) == faction_id \
				and bool(value.get("operational", true)):
			result.append(String(value.get("id", "")))
	result.sort()
	return result


func _target_id_for_contact(viewer_faction_id: String, contact_id_value: String) -> String:
	for squadron_id in _state.get("live_navigation", {}).keys():
		if _squadron_faction_id(String(squadron_id)) == viewer_faction_id: continue
		if _fog.contact_id(viewer_faction_id, String(squadron_id)) == contact_id_value: return String(squadron_id)
	return ""


func _contact_by_id(contacts: Array, contact_id_value: String) -> Dictionary:
	for value in contacts:
		if value is Dictionary and String(value.get("contact_id", "")) == contact_id_value: return value.duplicate(true)
	return {}


func _begin_command_draft(faction_id: String) -> void:
	var orders := {}
	var formation_orders := {}
	var weapon_orders := {}
	var estimated_fire_orders := {}
	for squadron_id in _operational_squadron_ids(faction_id):
		orders[squadron_id] = {"squadron_id": squadron_id, "action": "hold"}
		formation_orders[squadron_id] = {"squadron_id": squadron_id,
			"formation_id": String(_state.formation_state[squadron_id].formation_id)}
		var weapon_row: Dictionary = _state.weapon_allocation_state[squadron_id]
		weapon_orders[squadron_id] = {"squadron_id": squadron_id,
			"allocations": weapon_row.allocations.duplicate(true), "hold_fire": bool(weapon_row.hold_fire)}
	_state.command_draft = {"faction_id": faction_id, "orders": orders, "formation_orders": formation_orders,
		"weapon_allocation_orders": weapon_orders, "estimated_fire_orders": estimated_fire_orders}


func _command_draft_access(squadron_id: String) -> Dictionary:
	var faction_id := ""
	if phase() == "liu_command": faction_id = "liu_bei"
	elif phase() == "sun_command": faction_id = "sun_quan"
	if faction_id.is_empty() or String(_state.get("command_draft", {}).get("faction_id", "")) != faction_id:
		return _error("현재 단계에는 편집 가능한 명령 초안이 없습니다.")
	if not _operational_squadron_ids(faction_id).has(squadron_id):
		return _error("현재 직접 지휘 세력의 operational 전대가 아닙니다: %s" % squadron_id)
	return _ok()


func _current_log() -> Dictionary:
	return _state.turn_log[_state.turn_log.size() - 1]


func _new_turn_log(turn_number: int) -> Dictionary:
	return {
		"turn": turn_number,
		"liu_orders": [],
		"liu_formation_orders": [],
		"liu_weapon_allocation_orders": [],
		"liu_estimated_fire_orders": [],
		"sun_control_decision": {},
		"sun_orders": [],
		"sun_formation_orders": [],
		"sun_weapon_allocation_orders": [],
		"sun_estimated_fire_orders": [],
		"sun_ai_decision": {},
		"cao_orders": [],
		"cao_formation_orders": [],
		"cao_weapon_allocation_orders": [],
		"cao_estimated_fire_orders": [],
		"cao_ai_decision": {},
		"resolution_receipt": {},
		"victory_check_required": false,
	}


func _ok() -> Dictionary:
	return {"ok": true, "errors": []}


func _error(message: String, details: Array = []) -> Dictionary:
	var errors: Array = [message]
	for detail in details: errors.append(String(detail))
	return {"ok": false, "errors": errors}
