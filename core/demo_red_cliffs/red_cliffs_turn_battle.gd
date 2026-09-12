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
const ChainExplosion := preload("res://core/demo_red_cliffs/red_cliffs_chain_explosion.gd")
const FastCraftMission := preload("res://core/demo_red_cliffs/red_cliffs_fast_craft_mission.gd")
const FastCraftSupply := preload("res://core/demo_red_cliffs/red_cliffs_fast_craft_supply.gd")
const FastCraftReturn := preload("res://core/demo_red_cliffs/red_cliffs_fast_craft_return.gd")
const FastCraftRecovery := preload("res://core/demo_red_cliffs/red_cliffs_fast_craft_recovery.gd")
const SupplyInventory := preload("res://core/demo_red_cliffs/red_cliffs_supply_inventory.gd")
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
var _chain_explosion
var _fast_craft_mission
var _fast_craft_supply
var _fast_craft_return
var _fast_craft_recovery
var _supply_inventory
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
	var chain_explosion = ChainExplosion.new(); var chain_result: Dictionary = chain_explosion.initialize(setup)
	if not chain_result.ok: return chain_result
	var fast_craft_mission = FastCraftMission.new(); var mission_result: Dictionary = fast_craft_mission.initialize(setup)
	if not mission_result.ok: return mission_result
	var fast_craft_supply = FastCraftSupply.new(); var supply_result: Dictionary = fast_craft_supply.initialize(setup)
	if not supply_result.ok: return supply_result
	var fast_craft_return = FastCraftReturn.new(); var return_result: Dictionary = fast_craft_return.initialize(setup)
	if not return_result.ok: return return_result
	var fast_craft_recovery = FastCraftRecovery.new(); var recovery_result: Dictionary = fast_craft_recovery.initialize(setup)
	if not recovery_result.ok: return recovery_result
	var supply_inventory=SupplyInventory.new();var inventory_result:Dictionary=supply_inventory.initialize(setup)
	if not inventory_result.ok:return inventory_result
	_movement = movement
	_interception = interception
	_formation = formation
	_weapon_control = weapon_control
	_combat_resources = combat_resources
	_phase_ledger = phase_ledger
	_fog = fog
	_terrain = terrain
	_ai_planner = ai_planner
	_chain_explosion = chain_explosion
	_fast_craft_mission = fast_craft_mission
	_fast_craft_supply = fast_craft_supply
	_fast_craft_return = fast_craft_return
	_fast_craft_recovery = fast_craft_recovery
	_supply_inventory=supply_inventory
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
		"chain_explosion_state": _chain_explosion.initial_state(),
		"fast_craft_mission_state": _fast_craft_mission.initial_state(),
		"supply_inventory_state":_supply_inventory.initial_state(),
		"fast_craft_supply_state": {},
		"fast_craft_return_state": _fast_craft_return.initial_state(),
		"fast_craft_recovery_state": _fast_craft_recovery.initial_state(),
		"phase_ledgers": {},
		"command_draft": {},
		"turn_log": [_new_turn_log(1)],
	}
	var begun_inventory: Dictionary = _supply_inventory.begin_turn(_state.supply_inventory_state, 1)
	if not begun_inventory.ok: return begun_inventory
	_state.supply_inventory_state = begun_inventory.state.duplicate(true)
	_state.fast_craft_supply_state=_fast_craft_supply.initial_state(_state.live_navigation,_state.supply_inventory_state)
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


func viewer_command_penalty_metrics(viewer_faction_id: String, squadron_id: String) -> Dictionary:
	if _state.is_empty() or not ["liu_bei", "sun_quan", "cao_cao"].has(viewer_faction_id):
		return {"ok": false, "errors": ["명령 불이익 조회 입력이 잘못되었습니다."]}
	if _squadron_faction_id(squadron_id) != viewer_faction_id:
		return {"ok": false, "errors": ["자기 전대의 명령 불이익만 조회할 수 있습니다."]}
	return _formation.command_penalty_metrics(squadron_id).duplicate(true)


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


func chain_explosion_readiness(contact_id_value: String = "") -> Dictionary:
	if _state.is_empty(): return _error("턴 전투가 초기화되지 않았습니다.")
	var receipt: Dictionary = _chain_explosion_readiness_internal(contact_id_value)
	if receipt.ok:
		receipt.erase("target_squadron_id")
		receipt.conditions = _public_chain_conditions(receipt.conditions)
	return receipt


func _chain_explosion_readiness_internal(contact_id_value: String = "") -> Dictionary:
	var rules: Dictionary = _chain_explosion.rules_snapshot(); var source_id := String(rules.allied_operation_detachment.host_squadron_id)
	var contacts: Array = visible_contacts("liu_bei").contacts; var selected := {}
	for value in contacts:
		if value is Dictionary and String(value.get("state", "")) == "confirmed" and String(value.get("disposition", "")) == "hostile":
			if contact_id_value.is_empty() or String(value.contact_id) == contact_id_value: selected = value.duplicate(true); break
	if selected.is_empty(): selected = {"contact_id": contact_id_value, "state": "undetected"}
	else: selected["target_squadron_id"] = _target_id_for_contact("liu_bei", String(selected.contact_id))
	var receipt: Dictionary = _chain_explosion.readiness("liu_bei", _state.chain_explosion_state, source_id,
		selected, _state.live_navigation, _state.formation_state)
	if receipt.ok: receipt["detachment_id"] = String(rules.allied_operation_detachment.id)
	return receipt


func stage_chain_explosion(detachment_id: String, contact_id_value: String) -> Dictionary:
	if phase() != "liu_command": return _error("연쇄 폭발 작전은 유비 명령 단계에서만 준비할 수 있습니다.")
	var rules: Dictionary = _chain_explosion.rules_snapshot()
	if detachment_id != String(rules.allied_operation_detachment.id): return _error("미지 연합 특수작전 분견대입니다.")
	var readiness: Dictionary = _chain_explosion_readiness_internal(contact_id_value)
	if not readiness.ok: return readiness
	var staged: Dictionary = _chain_explosion.stage(_state.chain_explosion_state, readiness, turn())
	if not staged.ok: return staged
	_state.chain_explosion_state = staged.state.duplicate(true)
	return {"ok": true, "errors": [], "state": viewer_chain_explosion_state("liu_bei"), "idempotent": bool(staged.get("idempotent", false))}


func cancel_chain_explosion() -> Dictionary:
	if phase() != "liu_command": return _error("연쇄 폭발 작전은 유비 명령 단계에서만 취소할 수 있습니다.")
	var cancelled: Dictionary = _chain_explosion.cancel(_state.chain_explosion_state)
	if not cancelled.ok: return cancelled
	_state.chain_explosion_state = cancelled.state.duplicate(true)
	return {"ok": true, "errors": [], "state": viewer_chain_explosion_state("liu_bei")}


func viewer_chain_explosion_state(viewer_faction_id: String) -> Dictionary:
	if not _faction_ids().has(viewer_faction_id): return _error("미지 관측 세력입니다: %s" % viewer_faction_id)
	var state: Dictionary = _state.chain_explosion_state; var status := String(state.status)
	if viewer_faction_id == "cao_cao" and status != "triggered":
		return {"ok": true, "errors": [], "viewer_faction_id": viewer_faction_id, "status": "unknown", "revealed": false, "can_stage": false, "can_cancel": false}
	var result := {"ok": true, "errors": [], "viewer_faction_id": viewer_faction_id, "status": status, "revealed": true,
		"can_stage": viewer_faction_id == "liu_bei" and phase() == "liu_command" and ["idle", "disrupted"].has(status),
		"can_cancel": viewer_faction_id == "liu_bei" and phase() == "liu_command" and status == "staged",
		"irreversible": status == "triggered"}
	if viewer_faction_id == "liu_bei":
		var visible_order: Dictionary = state.staged_order.duplicate(true); visible_order.erase("target_squadron_id")
		result["staged_order"] = visible_order
		var visible_evaluation: Dictionary = state.last_evaluation.duplicate(true); visible_evaluation.erase("target_squadron_id")
		visible_evaluation["conditions"] = _public_chain_conditions(visible_evaluation.get("conditions", []))
		result["last_evaluation"] = visible_evaluation
	if viewer_faction_id == "sun_quan": result["allied_operation_label"] = "연합 폭발정 분견대"
	if status == "triggered":
		result["triggered_turn"] = int(state.triggered_turn)
		result["effect_intents"] = state.trigger_event.get("effect_intents", []).duplicate()
		result["effects_pending"] = state.trigger_event.get("effects_pending", []).duplicate()
	return result


func visible_contacts(viewer_faction_id: String) -> Dictionary:
	if _state.is_empty(): return _error("턴 전투가 초기화되지 않았습니다.")
	return _visible_contacts_from(viewer_faction_id, _state.detection_state, _state.live_navigation)


func _visible_contacts_from(viewer_faction_id: String, detection: Dictionary, navigation: Dictionary) -> Dictionary:
	var result: Dictionary = _interception.visible_contacts(viewer_faction_id, detection, navigation)
	if not result.ok: return result
	var terminal_ids:Array=_fast_craft_recovery.terminal_ids(_state.fast_craft_recovery_state) if _fast_craft_recovery != null else []
	result.contacts=result.contacts.filter(func(contact):return not terminal_ids.has(_target_id_for_contact(viewer_faction_id,String(contact.contact_id))))
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
		if String(squad.faction_id) == viewer_faction_id and not _recovery_locked(String(squad.id)):
			var own_squad: Dictionary = squad.duplicate(true)
			own_squad.formation_id = String(_state.formation_state[String(squad.id)].formation_id)
			own_squadrons.append(own_squad); own_navigation[String(squad.id)] = _state.live_navigation[String(squad.id)].duplicate(true)
	var own_formation:Dictionary=_own_formation_state(viewer_faction_id);var own_weapon:Dictionary=_own_weapon_allocation_state(viewer_faction_id);var own_resources:Dictionary=visible_combat_resources(viewer_faction_id).resource_state;var own_terrain:Dictionary=own_terrain_membership(viewer_faction_id).membership
	for locked_id in _fast_craft_recovery.combat_locked_ids(_state.fast_craft_recovery_state):own_formation.erase(locked_id);own_weapon.erase(locked_id);own_resources.erase(locked_id);own_terrain.erase(locked_id)
	return {"ok": true, "errors": [], "viewer_faction_id": viewer_faction_id, "turn": turn(), "phase": phase(),
		"battlefield_bounds": _state.applied_setup.battlefield_bounds.duplicate(),
		"own_squadrons": own_squadrons, "own_navigation": own_navigation, "contacts": contacts.contacts,
		"own_formation_state": own_formation, "allowed_formations": allowed_formations(),
		"own_weapon_allocation_state": own_weapon,
		"weapon_categories": weapon_categories(), "weapon_presets": weapon_presets(),
		"own_combat_resources": own_resources,
		"terrain_zones": terrain_zones(), "own_terrain_membership": own_terrain,
		"resource_recovery_events": _combat_resources.visible_events(viewer_faction_id,
			{"recovery_events": _state.last_resource_recovery_events}).events,
		"tactical_events": visible_tactical_events(viewer_faction_id).events,
		"chain_explosion": viewer_chain_explosion_state(viewer_faction_id),
		"prompt_policy": prompt_policy() if viewer_faction_id == "sun_quan" else {}}


func movement_preview(squadron_id: String, waypoints: Array, facing_deg) -> Dictionary:
	if _state.is_empty(): return _error("턴 전투가 초기화되지 않았습니다.")
	if _recovery_locked(squadron_id): return _error("표류·구조·나포 상태 전대는 이동을 미리 볼 수 없습니다.")
	var requested: Dictionary = _movement.movement_preview(squadron_id, waypoints, facing_deg, _state.live_navigation)
	if not requested.ok: return requested
	var resources: Dictionary = _state.get("fast_craft_supply_state", {}).get("resources", {})
	if not resources.has(squadron_id): return requested
	var fuel_basis_points: int = int(resources[squadron_id].get("fuel_basis_points", 0))
	var maximum_fuel_distance: float = float(fuel_basis_points) / 10.0
	var prepared: Dictionary = _fast_craft_recovery.prepare_orders(_state.fast_craft_recovery_state,
		_state.fast_craft_supply_state, [{"squadron_id": squadron_id, "action": "move",
			"waypoints": waypoints.duplicate(true), "facing_deg": float(facing_deg)}], _state.live_navigation)
	if not prepared.ok: return prepared
	var effective_waypoints: Array = []
	if not prepared.orders.is_empty() and String(prepared.orders[0].get("action", "")) == "move":
		effective_waypoints = prepared.orders[0].waypoints.duplicate(true)
	var predicted: Dictionary
	if effective_waypoints.is_empty():
		var current_position: Array = _state.live_navigation[squadron_id].position.duplicate()
		predicted = requested.duplicate(true)
		predicted["predicted_position"] = current_position
		predicted["terrain_segments"] = []
		predicted["terrain_events"] = []
	else:
		predicted = _movement.movement_preview(squadron_id, effective_waypoints, facing_deg, _state.live_navigation)
		if not predicted.ok: return predicted
	var predicted_actual_distance: float = 0.0
	for segment in predicted.get("terrain_segments", []): predicted_actual_distance += float(segment.get("length", 0.0))
	var requested_total_distance: float = float(requested.total_distance)
	var fuel_limited: bool = requested_total_distance > maximum_fuel_distance + 0.000001
	predicted["waypoints"] = waypoints.duplicate(true)
	predicted["effective_waypoints"] = effective_waypoints
	predicted["requested_total_distance"] = requested_total_distance
	predicted["total_distance"] = requested_total_distance
	predicted["predicted_actual_distance"] = predicted_actual_distance
	predicted["available_fuel_basis_points"] = fuel_basis_points
	predicted["maximum_fuel_distance"] = maximum_fuel_distance
	predicted["fuel_limited"] = fuel_limited
	predicted["path_complete"] = not fuel_limited and bool(predicted.path_complete)
	predicted["remaining_distance"] = maxf(0.0, requested_total_distance - predicted_actual_distance)
	if fuel_limited: predicted["eta_turns"] = -1
	return predicted


func command_draft() -> Dictionary:
	return _state.get("command_draft", {}).duplicate(true)


func viewer_fast_craft_missions(viewer_faction_id: String) -> Dictionary:
	if _state.is_empty() or not ["liu_bei", "sun_quan", "cao_cao"].has(viewer_faction_id): return _error("미지 관측 세력입니다.")
	var visible: Dictionary = _fast_craft_mission.visible(viewer_faction_id, _state.fast_craft_mission_state)
	var immediate := current_direct_faction_id() == viewer_faction_id
	var late_phase := ["sun_control_prompt", "resolution", "victory_check"].has(phase()) and _late_fast_craft_mission_editable(viewer_faction_id)
	var queued_mode := late_phase and turn() < MAX_TURNS
	for status in visible.statuses:
		var squadron_id := String(status.squadron_id)
		var recovery_status := String(_state.fast_craft_recovery_state.get("squadrons", {}).get(squadron_id, {}).get("status", "active"))
		var has_queue: bool = _state.fast_craft_mission_state.next_turn_queue.has(squadron_id)
		status["application"] = "immediate" if immediate else ("next_turn_queue" if queued_mode else "read_only")
		status["can_change"] = immediate or queued_mode and not has_queue
		status["can_cancel"] = queued_mode and has_queue
		status["change_reason"] = "turn_limit_no_next_turn" if late_phase and turn() >= MAX_TURNS else ("queue_already_exists" if queued_mode and has_queue else "")
		if recovery_status != "active": status["can_change"] = false; status["can_cancel"] = false; status["application"] = "read_only"; status["change_reason"] = "recovery_command_locked"
	visible["turn"] = turn(); visible["phase"] = phase()
	return visible


func viewer_fast_craft_supply(viewer_faction_id: String) -> Dictionary:
	if _state.is_empty() or not ["liu_bei", "sun_quan", "cao_cao"].has(viewer_faction_id): return _error("미지 관측 세력입니다.")
	var visible: Dictionary = _fast_craft_supply.visible(viewer_faction_id, _state.fast_craft_supply_state, _state.live_navigation,
		_fast_craft_recovery.disabled_source_ids(_state.fast_craft_recovery_state),_state.supply_inventory_state)
	visible["turn"] = turn(); visible["phase"] = phase(); return visible

func viewer_supply_inventory(viewer_faction_id:String)->Dictionary:
	if _state.is_empty() or not ["liu_bei","sun_quan","cao_cao"].has(viewer_faction_id):return _error("미지 관측 세력입니다.")
	var visible:Dictionary=_supply_inventory.visible(viewer_faction_id,_state.supply_inventory_state);visible["turn"]=turn();visible["phase"]=phase();return visible


func viewer_fast_craft_returns(viewer_faction_id: String) -> Dictionary:
	if _state.is_empty() or not ["liu_bei", "sun_quan", "cao_cao"].has(viewer_faction_id): return _error("미지 관측 세력입니다.")
	var statuses: Array = []; var sources: Array = _fast_craft_supply.source_zones(_state.live_navigation,
		_fast_craft_recovery.disabled_source_ids(_state.fast_craft_recovery_state),_state.supply_inventory_state)
	for squadron_id in _state.fast_craft_supply_state.resources.keys():
		if _recovery_locked(String(squadron_id)): continue
		var speed: Dictionary = _movement.effective_speed(String(squadron_id)); if not speed.ok: return speed
		var row: Dictionary = _fast_craft_return.status(String(squadron_id),_state.fast_craft_return_state,_state.fast_craft_supply_state,sources,_state.live_navigation,int(speed.effective_speed)); if not row.ok:return row
		statuses.append(row)
	var visible: Dictionary = _fast_craft_return.visible(viewer_faction_id,_state.fast_craft_return_state,statuses); visible["turn"]=turn();visible["phase"]=phase();return visible


func viewer_fast_craft_recovery(viewer_faction_id: String) -> Dictionary:
	if _state.is_empty() or not ["liu_bei", "sun_quan", "cao_cao"].has(viewer_faction_id): return _error("미지 관측 세력입니다.")
	var contact_result:Dictionary=_interception.visible_contacts(viewer_faction_id,_state.detection_state,_state.live_navigation);if not contact_result.ok:return contact_result
	for contact in contact_result.contacts:contact["recovery_target_id"]=_target_id_for_contact(viewer_faction_id,String(contact.contact_id))
	var visible: Dictionary = _fast_craft_recovery.visible(viewer_faction_id, _state.fast_craft_recovery_state, _state.fast_craft_supply_state,contact_result.contacts,_state.live_navigation)
	visible["turn"] = turn(); visible["phase"] = phase(); return visible


func _apply_authoritative_supply_capture(intent: Dictionary) -> Dictionary:
	if _state.is_empty(): return _error("전투가 초기화되지 않았습니다.")
	if not _supply_authoritative_pre_resolution(): return _error("보급함 권위 상태는 턴 판정 전 phase에서만 적용할 수 있습니다.")
	var sources: Array = _fast_craft_supply.source_zones(_state.live_navigation,
		_fast_craft_recovery.disabled_source_ids(_state.fast_craft_recovery_state),_state.supply_inventory_state)
	var applied: Dictionary = _fast_craft_recovery.apply_authoritative_supply_capture(_state.fast_craft_recovery_state, intent, sources, turn())
	if not applied.ok: return applied
	var inventory_applied:Dictionary=_supply_inventory.capture_source(_state.supply_inventory_state,String(intent.get("source_id","")),turn())
	if not inventory_applied.ok:return inventory_applied
	_state.fast_craft_recovery_state = applied.state.duplicate(true)
	_state.supply_inventory_state=inventory_applied.state.duplicate(true)
	applied.event["inventory_disposition"]="discarded";applied.event["inventory_event_id"]=String(inventory_applied.event.event_id)
	for stored in _state.fast_craft_recovery_state.events_by_turn.get(turn(),[]):
		if String(stored.get("event_id",""))==String(applied.event.event_id):stored["inventory_disposition"]="discarded";stored["inventory_event_id"]=String(inventory_applied.event.event_id)
	return {"ok": true, "errors": [], "event": applied.event.duplicate(true),"inventory_event":inventory_applied.event.duplicate(true)}

func _apply_authoritative_supply_ship_status(intent:Dictionary)->Dictionary:
	if _state.is_empty():return _error("전투가 초기화되지 않았습니다.")
	if not _supply_authoritative_pre_resolution():return _error("보급함 권위 상태는 턴 판정 전 phase에서만 적용할 수 있습니다.")
	var applied:Dictionary=_supply_inventory.apply_authoritative_status(_state.supply_inventory_state,intent,turn())
	if not applied.ok:return applied
	_state.supply_inventory_state=applied.state.duplicate(true)
	return {"ok":true,"errors":[],"event":applied.event.duplicate(true)}


func _supply_authoritative_pre_resolution() -> bool:
	return not bool(_state.get("resolved", false)) and ["liu_command", "sun_control_prompt", "sun_command", "resolution"].has(phase())


func request_fast_craft_return(requesting_faction_id:String,squadron_id:String)->Dictionary:
	if current_direct_faction_id()!=requesting_faction_id or _squadron_faction_id(squadron_id)!=requesting_faction_id:return _error("현재 직접 지휘 세력의 고속정만 조기 귀환할 수 있습니다.")
	if _recovery_locked(squadron_id):return _error("표류·구조·나포 상태에서는 귀환 명령을 변경할 수 없습니다.")
	var status_row:Dictionary=_return_status(squadron_id);if not status_row.ok:return status_row
	var changed:Dictionary=_fast_craft_return.request_early(_state.fast_craft_return_state,status_row,turn());if not changed.ok:return changed
	_state.fast_craft_return_state=changed.state.duplicate(true);return {"ok":true,"errors":[],"event":changed.event.duplicate(true)}


func cancel_fast_craft_return(requesting_faction_id:String,squadron_id:String)->Dictionary:
	if current_direct_faction_id()!=requesting_faction_id or _squadron_faction_id(squadron_id)!=requesting_faction_id:return _error("현재 직접 지휘 세력의 고속정 조기 귀환만 취소할 수 있습니다.")
	if _recovery_locked(squadron_id):return _error("표류·구조·나포 상태에서는 귀환 명령을 변경할 수 없습니다.")
	var status_row:Dictionary=_return_status(squadron_id);if not status_row.ok:return status_row
	var changed:Dictionary=_fast_craft_return.cancel_early(_state.fast_craft_return_state,status_row,turn());if not changed.ok:return changed
	_state.fast_craft_return_state=changed.state.duplicate(true);return {"ok":true,"errors":[],"event":changed.event.duplicate(true)}


func set_fast_craft_mission(requesting_faction_id: String, squadron_id: String, mission_id: String) -> Dictionary:
	if _state.is_empty() or phase() == "turn_limit_reached": return _error("현재 단계에서는 전술 임무를 변경할 수 없습니다.")
	if _recovery_locked(squadron_id): return _error("표류·구조·나포 상태에서는 전술 임무를 변경할 수 없습니다.")
	var faction_id := _squadron_faction_id(squadron_id); var application := ""
	if requesting_faction_id != faction_id: return _error("다른 세력의 고속정 전술 임무를 변경할 수 없습니다.")
	if current_direct_faction_id() == faction_id and requesting_faction_id == current_direct_faction_id():
		application = "immediate"
	elif ["sun_control_prompt", "resolution", "victory_check"].has(phase()) and _late_fast_craft_mission_editable(requesting_faction_id) and turn() < MAX_TURNS:
		application = "next_turn_queue"
	else: return _error("현재 직접 지휘하거나 다음 턴 예약할 수 있는 세력이 아닙니다.")
	var changed: Dictionary = _fast_craft_mission.request(_state.fast_craft_mission_state, squadron_id, mission_id, turn(), application)
	if not changed.ok: return changed
	_state.fast_craft_mission_state = changed.state.duplicate(true)
	if application == "immediate":
		if _state.fast_craft_mission_state.current_turn_draft.has(squadron_id): _state.command_draft.fast_craft_mission_orders[squadron_id] = {"squadron_id": squadron_id, "mission_id": mission_id}
		else: _state.command_draft.fast_craft_mission_orders.erase(squadron_id)
	return {"ok": true, "errors": [], "application": application, "event": changed.event.duplicate(true)}


func cancel_queued_fast_craft_mission(requesting_faction_id: String, squadron_id: String) -> Dictionary:
	var faction_id := _squadron_faction_id(squadron_id)
	if requesting_faction_id != faction_id: return _error("다른 세력의 다음 턴 전술 임무 요청을 취소할 수 없습니다.")
	if not ["sun_control_prompt", "resolution", "victory_check"].has(phase()) or not _late_fast_craft_mission_editable(requesting_faction_id): return _error("현재 단계에서는 다음 턴 요청을 취소할 수 없습니다.")
	var changed: Dictionary = _fast_craft_mission.cancel_queue(_state.fast_craft_mission_state, squadron_id, turn())
	if not changed.ok: return changed
	_state.fast_craft_mission_state = changed.state.duplicate(true)
	return {"ok": true, "errors": [], "event": changed.event.duplicate(true)}


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
	var mission_orders := _submitted_fast_craft_mission_orders("liu_bei")
	var mission_commit: Dictionary = _fast_craft_mission.commit_draft(_state.fast_craft_mission_state, "liu_bei", mission_orders, turn())
	if not mission_commit.ok: return mission_commit
	_state.fast_craft_mission_state = mission_commit.state.duplicate(true)
	_current_log()["liu_orders"] = checked.orders.duplicate(true)
	_current_log()["liu_formation_orders"] = _submitted_formation_orders("liu_bei")
	_current_log()["liu_weapon_allocation_orders"] = _submitted_weapon_orders("liu_bei")
	_current_log()["liu_estimated_fire_orders"] = _submitted_estimated_fire_orders("liu_bei")
	_current_log()["liu_fast_craft_mission_orders"] = mission_orders
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
	var mission_orders := _submitted_fast_craft_mission_orders("sun_quan")
	var mission_commit: Dictionary = _fast_craft_mission.commit_draft(_state.fast_craft_mission_state, "sun_quan", mission_orders, turn())
	if not mission_commit.ok: return mission_commit
	_state.fast_craft_mission_state = mission_commit.state.duplicate(true)
	_current_log()["sun_orders"] = checked.orders.duplicate(true)
	_current_log()["sun_formation_orders"] = _submitted_formation_orders("sun_quan")
	_current_log()["sun_weapon_allocation_orders"] = _submitted_weapon_orders("sun_quan")
	_current_log()["sun_estimated_fire_orders"] = _submitted_estimated_fire_orders("sun_quan")
	_current_log()["sun_fast_craft_mission_orders"] = mission_orders
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
	var return_speeds := {}; for squadron_id in _state.fast_craft_supply_state.resources.keys():
		var speed:Dictionary=_movement.effective_speed(String(squadron_id));if not speed.ok:return speed
		return_speeds[squadron_id]=int(speed.effective_speed)
	var disabled_supply_sources:Array=_fast_craft_recovery.disabled_source_ids(_state.fast_craft_recovery_state)
	var return_result:Dictionary=_fast_craft_return.plan(_state.fast_craft_return_state,_state.fast_craft_supply_state,_fast_craft_supply.source_zones(_state.live_navigation,disabled_supply_sources,_state.supply_inventory_state),_state.live_navigation,return_speeds,turn(),_fast_craft_recovery.combat_locked_ids(_state.fast_craft_recovery_state))
	if not return_result.ok:return return_result
	var weapon_orders: Array = []
	weapon_orders.append_array(_current_log().liu_weapon_allocation_orders)
	weapon_orders.append_array(_current_log().sun_weapon_allocation_orders)
	weapon_orders.append_array(_current_log().cao_weapon_allocation_orders)
	for index in range(weapon_orders.size()):
		var weapon_sid:=String(weapon_orders[index].squadron_id)
		if return_result.overrides.has(weapon_sid) or _fast_craft_recovery.combat_locked_ids(_state.fast_craft_recovery_state).has(weapon_sid):
			weapon_orders[index]=weapon_orders[index].duplicate(true);weapon_orders[index]["hold_fire"]=true
	var weapon_result: Dictionary = _weapon_control.resolve_orders(weapon_orders, _state.weapon_allocation_state, turn())
	if not weapon_result.ok: return weapon_result
	for index in range(orders.size()):
		var sid:String=String(orders[index].squadron_id)
		if return_result.overrides.has(sid):orders[index]=return_result.overrides[sid].duplicate(true)
	var prepared_recovery_orders:Dictionary=_fast_craft_recovery.prepare_orders(_state.fast_craft_recovery_state,_state.fast_craft_supply_state,orders,_state.live_navigation)
	if not prepared_recovery_orders.ok:return prepared_recovery_orders
	var movement_result: Dictionary = _movement.resolve_orders(prepared_recovery_orders.orders, _state.live_navigation)
	if not movement_result.ok: return movement_result
	var fuel_result:Dictionary=_fast_craft_return.consume_fuel(_state.fast_craft_supply_state,movement_result.events,turn())
	if not fuel_result.ok:return fuel_result
	var recorded_fuel:Dictionary=_fast_craft_return.record_fuel_events(return_result.state,fuel_result.events,turn())
	if not recorded_fuel.ok:return recorded_fuel
	return_result.state=recorded_fuel.state.duplicate(true);fuel_result.events=recorded_fuel.events.duplicate(true)
	var drift_result:Dictionary=_fast_craft_recovery.transition_after_fuel(_state.fast_craft_recovery_state,fuel_result.state,
		_fast_craft_supply.source_zones(movement_result.live_navigation,disabled_supply_sources,_state.supply_inventory_state),movement_result.live_navigation,movement_result.events,turn())
	if not drift_result.ok:return drift_result
	var contact_result:Dictionary=_fast_craft_recovery.resolve_contacts(drift_result.state,_state.fast_craft_mission_state,
		movement_result.live_navigation,movement_result.events,turn())
	if not contact_result.ok:return contact_result
	var combat_locked:Array=_fast_craft_recovery.combat_locked_ids(contact_result.state)
	var terminal_ids:Array=_fast_craft_recovery.terminal_ids(contact_result.state)
	var interception_result: Dictionary = _interception.resolve(movement_result.events,
		movement_result.live_navigation, _state.detection_state, turn(),
		_weapon_control.interception_policy(weapon_result.weapon_allocation_state), formation_result.formation_state)
	if not interception_result.ok: return interception_result
	interception_result.path_intersection_events=interception_result.path_intersection_events.filter(func(event):return not terminal_ids.has(String(event.get("squadron_a_id",""))) and not terminal_ids.has(String(event.get("squadron_b_id",""))))
	interception_result.detection_events=interception_result.detection_events.filter(func(event):return not terminal_ids.has(String(event.get("observer_squadron_id",""))) and not terminal_ids.has(String(event.get("target_squadron_id",""))))
	interception_result.opportunity_fire_events=interception_result.opportunity_fire_events.filter(func(event):return not terminal_ids.has(String(event.get("shooter_squadron_id",""))) and not terminal_ids.has(String(event.get("target_squadron_id",""))))
	for key in interception_result.detection_state.keys():
		var detection_row:Dictionary=interception_result.detection_state[key]
		if terminal_ids.has(String(detection_row.get("observer_squadron_id",""))) or terminal_ids.has(String(detection_row.get("target_squadron_id",""))):interception_result.detection_state.erase(key)
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
	all_authorized=all_authorized.filter(func(event):return not combat_locked.has(String(event.get("shooter_squadron_id",event.get("source_squadron_id","")))) and not terminal_ids.has(String(event.get("target_squadron_id",""))))
	var accuracy_result: Dictionary = _formation.apply_accuracy_penalty(all_authorized, turn())
	if not accuracy_result.ok: return accuracy_result
	var resource_result: Dictionary = _combat_resources.resolve_shots(accuracy_result.eligible_events,
		resource_base_state, turn())
	if not resource_result.ok: return resource_result
	# G6-03 replenishment is an end-of-turn consumer: movement, fire authorization,
	# and combat resource consumption have already completed.
	var refill_quotes:={}
	for candidate_id in fuel_result.state.resources.keys():
		var quote_result:Dictionary=_combat_resources.refill_fast_craft_finite([String(candidate_id)],resource_result.resource_state,turn())
		if not quote_result.ok:return quote_result
		var ammo_units:=0
		for weapon_quote in quote_result.events[0].combat_resource_refill.values():ammo_units+=int(weapon_quote.ammo_granted)+int(weapon_quote.special_granted)
		refill_quotes[String(candidate_id)]={"ammo_units":ammo_units}
	var supply_result: Dictionary = _fast_craft_supply.resolve(fuel_result.state, _state.live_navigation, movement_result.live_navigation,
		movement_result.events, turn(), disabled_supply_sources, _fast_craft_recovery.supply_locked_ids(contact_result.state),_state.supply_inventory_state,refill_quotes)
	if not supply_result.ok: return supply_result
	var finite_refill: Dictionary = _combat_resources.refill_fast_craft_finite(supply_result.completed_squadron_ids, resource_result.resource_state, turn())
	if not finite_refill.ok: return finite_refill
	var cleared_returns:Dictionary=_fast_craft_return.clear_completed(return_result.state,supply_result.completed_squadron_ids)
	if not cleared_returns.ok:return cleared_returns
	return_result.state=cleared_returns.state.duplicate(true)
	var recovered_docked:Dictionary=_fast_craft_recovery.complete_supply(contact_result.state,supply_result.completed_squadron_ids)
	if not recovered_docked.ok:return recovered_docked
	contact_result.state=recovered_docked.state.duplicate(true)
	resource_result.resource_state = finite_refill.resource_state.duplicate(true)
	var refill_by_squad := {}; for event in finite_refill.events: refill_by_squad[String(event.squadron_id)] = event
	for event in supply_result.events:
		if String(event.status) == "completed" and refill_by_squad.has(String(event.squadron_id)):
			var refill: Dictionary = refill_by_squad[String(event.squadron_id)]
			event["combat_resource_before"] = refill.combat_resource_before.duplicate(true)
			event["combat_resource_after"] = refill.combat_resource_after.duplicate(true)
			event["combat_resource_refill"] = refill.combat_resource_refill.duplicate(true)
			for stored in supply_result.state.events_by_turn.get(turn(), []):
				if int(stored.serial) == int(event.serial):
					stored["combat_resource_before"] = refill.combat_resource_before.duplicate(true)
					stored["combat_resource_after"] = refill.combat_resource_after.duplicate(true)
					stored["combat_resource_refill"] = refill.combat_resource_refill.duplicate(true)
	var chain_result := {"ok": true, "state": _state.chain_explosion_state.duplicate(true), "events": []}
	if String(_state.chain_explosion_state.status) == "staged":
		var final_contacts: Dictionary = _visible_contacts_from("liu_bei", interception_result.detection_state, movement_result.live_navigation)
		if not final_contacts.ok: return final_contacts
		var staged_contact_id := String(_state.chain_explosion_state.staged_order.contact_id)
		var final_contact := _contact_by_id(final_contacts.contacts, staged_contact_id)
		if final_contact.is_empty(): final_contact = {"contact_id": staged_contact_id, "state": "undetected"}
		elif String(final_contact.get("state", "")) == "confirmed":
			final_contact["target_squadron_id"] = String(_state.chain_explosion_state.staged_order.target_squadron_id)
		var source_id := String(_state.chain_explosion_state.staged_order.source_squadron_id)
		var authorized_interceptions := _events_with_outcome(resource_result.authorized_events, "shot_authorized")
		var final_readiness: Dictionary = _chain_explosion.readiness("liu_bei", _state.chain_explosion_state,
			source_id, final_contact, movement_result.live_navigation, formation_result.formation_state,
			authorized_interceptions)
		if not final_readiness.ok: return final_readiness
		chain_result = _chain_explosion.resolve_staged(_state.chain_explosion_state, final_readiness, turn())
		if not chain_result.ok: return chain_result
	var receipt := {
		"ok": true,
		"turn": turn(),
		"status": "orders_committed",
		"rules_pending": RULES_PENDING.duplicate(),
		"movement_events": movement_result.events.duplicate(true),
		"terrain_events": _decorate_terrain_events(movement_result.terrain_events),
		"formation_events": formation_result.formation_events.duplicate(true),
		"formation_modifier_snapshots": formation_result.modifier_snapshots.duplicate(true),
		"fast_craft_mission_events": _state.fast_craft_mission_state.events_by_turn.get(turn(), []).duplicate(true),
		"fast_craft_supply_events": supply_result.events.duplicate(true),
		"supply_inventory_events":supply_result.inventory_events.duplicate(true),
		"fast_craft_return_events": return_result.events.duplicate(true),
		"fast_craft_fuel_events": fuel_result.events.duplicate(true),
		"fast_craft_recovery_events": drift_result.events.duplicate(true) + contact_result.events.duplicate(true),
		"weapon_allocation_events": weapon_result.weapon_allocation_events.duplicate(true),
		"chain_explosion_events": chain_result.events.duplicate(true),
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
		visible.events.append_array(_visible_chain_explosion_events(faction_id, receipt.chain_explosion_events))
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
	_state.chain_explosion_state = chain_result.state.duplicate(true)
	_state.fast_craft_supply_state = supply_result.state.duplicate(true)
	_state.supply_inventory_state=supply_result.inventory_state.duplicate(true)
	_state.fast_craft_return_state = return_result.state.duplicate(true)
	_state.fast_craft_recovery_state = contact_result.state.duplicate(true)
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
	var begun_inventory: Dictionary = _supply_inventory.begin_turn(_state.supply_inventory_state, turn())
	if not begun_inventory.ok: return begun_inventory
	_state.supply_inventory_state = begun_inventory.state.duplicate(true)
	var promoted: Dictionary = _fast_craft_mission.promote(_state.fast_craft_mission_state, turn())
	if not promoted.ok: return promoted
	_state.fast_craft_mission_state = promoted.state.duplicate(true)
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
	var resolved_orders:Array=plan.orders.duplicate(true);var resolved_formations:Array=plan.formation_orders.duplicate(true)
	for expected_id in _operational_squadron_ids(faction_id):
		if not resolved_orders.any(func(row):return String(row.squadron_id)==String(expected_id)):resolved_orders.append({"squadron_id":String(expected_id),"action":"hold"})
		if not resolved_formations.any(func(row):return String(row.squadron_id)==String(expected_id)):resolved_formations.append({"squadron_id":String(expected_id),"formation_id":String(_state.formation_state[expected_id].formation_id)})
		if not weapon_orders.any(func(row):return String(row.squadron_id)==String(expected_id)):
			var current_weapon:Dictionary=_state.weapon_allocation_state[expected_id];weapon_orders.append({"squadron_id":String(expected_id),"allocations":current_weapon.allocations.duplicate(true),"hold_fire":true})
	_current_log()["%s_orders" % prefix] = resolved_orders
	_current_log()["%s_formation_orders" % prefix] = resolved_formations
	_current_log()["%s_weapon_allocation_orders" % prefix] = weapon_orders
	_current_log()["%s_estimated_fire_orders" % prefix] = estimated_orders
	var mission_orders: Array = []; var changed_mission_orders: Array = []; var mission_working_state: Dictionary = _state.fast_craft_mission_state.duplicate(true)
	for squadron_id in _state.fast_craft_mission_state.active.keys():
		var mission_row: Dictionary = _state.fast_craft_mission_state.active[squadron_id]
		if String(mission_row.faction_id) != faction_id or _recovery_locked(String(squadron_id)): continue
		var selected: Dictionary = _fast_craft_mission.ai_mission(mission_working_state, String(squadron_id), turn())
		if not selected.ok: return selected
		mission_orders.append({"squadron_id": String(squadron_id), "mission_id": String(selected.mission_id), "source": String(selected.source)})
		if String(mission_row.mission_id) != String(selected.mission_id):
			var requested: Dictionary = _fast_craft_mission.request(mission_working_state, String(squadron_id), String(selected.mission_id), turn(), "immediate")
			if not requested.ok: return requested
			mission_working_state = requested.state.duplicate(true); changed_mission_orders.append({"squadron_id": String(squadron_id), "mission_id": String(selected.mission_id)})
	var committed_missions: Dictionary = _fast_craft_mission.commit_draft(mission_working_state, faction_id, changed_mission_orders, turn())
	if not committed_missions.ok: return committed_missions
	_state.fast_craft_mission_state = committed_missions.state.duplicate(true)
	mission_orders.sort_custom(func(a, b): return String(a.squadron_id) < String(b.squadron_id))
	_current_log()["%s_fast_craft_mission_orders" % prefix] = mission_orders
	var ai_weapon_orders:Array=weapon_orders.filter(func(row):return not _recovery_locked(String(row.squadron_id)))
	_current_log()["%s_ai_decision" % prefix] = {"source": String(plan.source), "posture": String(plan.posture),
		"intents": plan.intents.duplicate(true), "orders": plan.orders.duplicate(true),
		"formation_orders": plan.formation_orders.duplicate(true), "weapon_allocation_orders": ai_weapon_orders.duplicate(true),
		"estimated_fire_orders": estimated_orders.duplicate(true)}
	_current_log()["%s_ai_decision" % prefix]["fast_craft_mission_orders"] = mission_orders.duplicate(true)
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


func _submitted_fast_craft_mission_orders(faction_id: String) -> Array:
	var draft: Dictionary = _state.get("command_draft", {})
	if String(draft.get("faction_id", "")) != faction_id: return []
	var result: Array = draft.get("fast_craft_mission_orders", {}).values()
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
		"chain_explosion_events": [], "opportunity_fire_events": [], "estimated_fire_events": [], "estimated_fire_suppressed_events": [],
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
		elif ["chain_explosion_disrupted", "chain_explosion_triggered"].has(event_type): source = "chain_explosion_events"
		if not source.is_empty(): safe[source].append(value.duplicate(true))
	return safe


func _visible_chain_explosion_events(viewer_faction_id: String, events: Array) -> Array:
	var result: Array = []
	for value in events:
		if not value is Dictionary: continue
		var event: Dictionary = value; var event_type := String(event.event_type)
		if viewer_faction_id == "cao_cao" and event_type != "chain_explosion_triggered": continue
		if viewer_faction_id == "liu_bei":
			result.append({"event_id": String(event.event_id), "event_type": event_type, "turn": int(event.turn),
				"contact_id": String(_state.chain_explosion_state.staged_order.get("contact_id", "")),
				"conditions": _public_chain_conditions(event.conditions), "retry_allowed_from_turn": int(event.get("retry_allowed_from_turn", 0)),
				"irreversible": bool(event.get("irreversible", false)), "effect_intents": event.get("effect_intents", []).duplicate(),
				"effects_pending": event.get("effects_pending", []).duplicate()})
		elif viewer_faction_id == "sun_quan":
			result.append({"event_id": String(event.event_id), "event_type": event_type, "turn": int(event.turn),
				"own_detachment_involved": true, "irreversible": bool(event.get("irreversible", false)),
				"effect_intents": event.get("effect_intents", []).duplicate(), "effects_pending": event.get("effects_pending", []).duplicate()})
		elif viewer_faction_id == "cao_cao":
			result.append({"event_id": String(event.event_id), "event_type": event_type, "turn": int(event.turn),
				"own_target_squadron_id": String(event.target_squadron_id), "irreversible": true,
				"effect_intents": event.effect_intents.duplicate(), "effects_pending": event.effects_pending.duplicate()})
	return result


func _public_chain_conditions(values: Array) -> Array:
	var result: Array = []
	for value in values:
		if not value is Dictionary: continue
		var condition: Dictionary = value.duplicate(true)
		condition.erase("formation_id")
		var blocking_ids: Array = condition.get("blocking_event_ids", [])
		if not blocking_ids.is_empty(): condition["blocking_evidence_count"] = blocking_ids.size()
		condition.erase("blocking_event_ids")
		result.append(condition)
	return result


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
		"weapon_allocation_orders": weapon_orders, "estimated_fire_orders": estimated_fire_orders, "fast_craft_mission_orders": {}}


func _late_fast_craft_mission_editable(faction_id: String) -> bool:
	if faction_id == "liu_bei": return true
	if faction_id != "sun_quan": return false
	return String(_current_log().get("sun_control_decision", {}).get("control", "")) == "manual"


func _return_status(squadron_id:String)->Dictionary:
	var speed:Dictionary=_movement.effective_speed(squadron_id);if not speed.ok:return speed
	return _fast_craft_return.status(squadron_id,_state.fast_craft_return_state,_state.fast_craft_supply_state,
		_fast_craft_supply.source_zones(_state.live_navigation,_fast_craft_recovery.disabled_source_ids(_state.fast_craft_recovery_state),_state.supply_inventory_state),_state.live_navigation,int(speed.effective_speed))


func _command_draft_access(squadron_id: String) -> Dictionary:
	var faction_id := ""
	if phase() == "liu_command": faction_id = "liu_bei"
	elif phase() == "sun_command": faction_id = "sun_quan"
	if faction_id.is_empty() or String(_state.get("command_draft", {}).get("faction_id", "")) != faction_id:
		return _error("현재 단계에는 편집 가능한 명령 초안이 없습니다.")
	if not _operational_squadron_ids(faction_id).has(squadron_id):
		return _error("현재 직접 지휘 세력의 operational 전대가 아닙니다: %s" % squadron_id)
	if _recovery_locked(squadron_id): return _error("표류·구조·나포 상태 전대는 명령할 수 없습니다.")
	return _ok()


func _recovery_locked(squadron_id: String) -> bool:
	return String(_state.get("fast_craft_recovery_state", {}).get("squadrons", {}).get(squadron_id, {}).get("status", "active")) != "active"


func _current_log() -> Dictionary:
	return _state.turn_log[_state.turn_log.size() - 1]


func _new_turn_log(turn_number: int) -> Dictionary:
	return {
		"turn": turn_number,
		"liu_orders": [],
		"liu_formation_orders": [],
		"liu_weapon_allocation_orders": [],
		"liu_estimated_fire_orders": [],
		"liu_fast_craft_mission_orders": [],
		"sun_control_decision": {},
		"sun_orders": [],
		"sun_formation_orders": [],
		"sun_weapon_allocation_orders": [],
		"sun_estimated_fire_orders": [],
		"sun_fast_craft_mission_orders": [],
		"sun_ai_decision": {},
		"cao_orders": [],
		"cao_formation_orders": [],
		"cao_weapon_allocation_orders": [],
		"cao_estimated_fire_orders": [],
		"cao_fast_craft_mission_orders": [],
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
