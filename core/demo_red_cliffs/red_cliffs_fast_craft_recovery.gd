class_name RedCliffsFastCraftRecovery
extends RefCounted

## DEMO-RC-G6-05 — 표류·구조·나포와 G6-06 재고 원자 커밋 전 보급함 무력화.
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const RULES_PATH := "res://data/red-cliffs-fast-craft-rules.json"
var _setup: Dictionary = {}
var _rules: Dictionary = {}
var _alliances: Array = []
var _bounds: Array = []

func initialize(applied_setup: Dictionary) -> Dictionary:
	var checked := Setup.validate_document(applied_setup)
	if not checked.ok: return _error("유효한 적용 편성이 필요합니다.")
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null: return _error("고속정 구조 규칙을 열 수 없습니다.")
	var parsed = JSON.parse_string(file.get_as_text())
	var rules = parsed.get("recovery_contract", {}) if parsed is Dictionary else {}
	if not rules is Dictionary or int(rules.get("passive_drift_distance", 0)) != 40 or int(rules.get("contact_radius", 0)) != 40:
		return _error("normal-demo 구조 계약이 잘못되었습니다.")
	_setup = checked.setup.duplicate(true)
	_bounds = checked.setup.battlefield_bounds.duplicate()
	_rules = rules.duplicate(true)
	_alliances = parsed.supply_contract.mutual_supply_alliances.duplicate(true)
	return _ok()

func initial_state() -> Dictionary:
	var rows := {}
	for squad in _pure_fast_craft():
		rows[String(squad.id)] = {"squadron_id": String(squad.id), "faction_id": String(squad.faction_id),
			"status": "active", "drift_started_turn": 0, "drift_vector": [], "resolved_turn": 0,
			"responder_squadron_id": "", "responder_faction_id": ""}
	return {"squadrons": rows, "disabled_supply_sources": {}, "events_by_turn": {}, "next_event_serial": 1}

func prepare_orders(state: Dictionary, supply_state: Dictionary, orders: Array, navigation: Dictionary) -> Dictionary:
	var next_orders: Array = []
	var seen := {}
	for value in orders:
		if not value is Dictionary: return _error("이동 명령이 객체가 아닙니다.")
		var order: Dictionary = value.duplicate(true)
		var sid := String(order.get("squadron_id", ""))
		if seen.has(sid): return _error("중복 이동 명령입니다.")
		seen[sid] = true
		var row: Dictionary = state.get("squadrons", {}).get(sid, {})
		if ["rescued", "captured", "depleted_docked"].has(String(row.get("status", ""))):
			order = {"squadron_id": sid, "action": "hold"}
		elif String(row.get("status", "")) == "drifting":
			var vector: Array = row.get("drift_vector", [])
			if vector.size() != 2: return _error("표류 방향이 누락되었습니다.")
			var from := _point(navigation[sid].position)
			var to := from + Vector2(float(vector[0]), float(vector[1])) * float(_rules.passive_drift_distance)
			to.x = clampf(to.x, float(_bounds[0]), float(_bounds[0] + _bounds[2]))
			to.y = clampf(to.y, float(_bounds[1]), float(_bounds[1] + _bounds[3]))
			order = {"squadron_id": sid, "action": "hold"} if from.is_equal_approx(to) else {"squadron_id": sid,
				"action": "move", "waypoints": [[to.x, to.y]], "facing_deg": float(navigation[sid].facing_deg)}
		elif supply_state.get("resources", {}).has(sid) and String(order.get("action", "")) == "move":
			var maximum := float(supply_state.resources[sid].fuel_basis_points) / 10.0
			order["waypoints"] = _clamp_waypoints(navigation[sid].position, order.waypoints, maximum)
			if order.waypoints.is_empty(): order = {"squadron_id": sid, "action": "hold"}
		next_orders.append(order)
	return {"ok": true, "errors": [], "orders": next_orders}

func transition_after_fuel(state: Dictionary, supply_state: Dictionary, sources: Array, navigation: Dictionary,
		movement_events: Array, turn_number: int) -> Dictionary:
	var next := state.duplicate(true)
	var events: Array = []
	var ids: Array = next.squadrons.keys(); ids.sort()
	for sid_value in ids:
		var sid := String(sid_value)
		var row: Dictionary = next.squadrons[sid]
		if String(row.status) != "active": continue
		var fuel := int(supply_state.resources.get(sid, {}).get("fuel_basis_points", -1))
		if fuel != 0: continue
		if _friendly_source_at(String(row.faction_id), navigation[sid].position, sources):
			row.status = "depleted_docked"
			events.append(_event(next, "depleted_docked", row, turn_number, {"position": navigation[sid].position.duplicate()}))
			continue
		var movement := _movement(sid, movement_events)
		var direction := Vector2.ZERO
		if float(movement.get("actual_distance", 0.0)) > 0.001:
			direction = (_point(movement.to) - _point(movement.from)).normalized()
		else:
			direction = Vector2.RIGHT.rotated(deg_to_rad(float(navigation[sid].facing_deg)))
		row.status = "drifting"; row.drift_started_turn = turn_number; row.drift_vector = [direction.x, direction.y]
		events.append(_event(next, "drifting", row, turn_number, {"position": navigation[sid].position.duplicate()}))
	for event in events: _append(next, turn_number, event)
	return {"ok": true, "errors": [], "state": next, "events": events}

func resolve_contacts(state: Dictionary, mission_state: Dictionary, navigation: Dictionary,
		movement_events: Array, turn_number: int) -> Dictionary:
	var next := state.duplicate(true)
	var events: Array = []
	var used := {}
	var targets: Array = []
	for sid in next.squadrons:
		var row: Dictionary = next.squadrons[sid]
		if String(row.status) == "drifting" and int(row.drift_started_turn) < turn_number: targets.append(String(sid))
	targets.sort_custom(func(a, b):
		var at := int(next.squadrons[a].drift_started_turn); var bt := int(next.squadrons[b].drift_started_turn)
		return String(a) < String(b) if at == bt else at < bt)
	for target_id in targets:
		var target: Dictionary = next.squadrons[target_id]
		var candidates: Array = []
		for squad in _setup.squadrons:
			var responder_id := String(squad.id)
			if responder_id == target_id or used.has(responder_id) or not bool(squad.get("operational", true)): continue
			if next.squadrons.has(responder_id) and ["drifting", "rescued", "captured"].has(String(next.squadrons[responder_id].status)): continue
			var action := "capture"
			if _friendly(String(target.faction_id), String(squad.faction_id)):
				if not _rescue_capable(responder_id, mission_state): continue
				action = "rescue"
			var movement := _movement(responder_id, movement_events); var target_movement := _movement(target_id, movement_events)
			var progress := _swept_contact_progress(movement, target_movement, navigation[responder_id].position,
				navigation[target_id].position, float(_rules.contact_radius))
			if progress < 0.0: continue
			candidates.append({"responder_id": responder_id, "responder_faction_id": String(squad.faction_id),
				"action": action, "progress": progress, "actual_distance": float(movement.get("actual_distance", 0.0))})
		candidates.sort_custom(func(a, b):
			if not is_equal_approx(float(a.progress), float(b.progress)): return float(a.progress) < float(b.progress)
			if not is_equal_approx(float(a.actual_distance), float(b.actual_distance)): return float(a.actual_distance) < float(b.actual_distance)
			if String(a.action) != String(b.action): return String(a.action) == "rescue"
			return String(a.responder_id) < String(b.responder_id))
		if candidates.is_empty(): continue
		var chosen: Dictionary = candidates[0]
		used[chosen.responder_id] = true
		target.status = "rescued" if String(chosen.action) == "rescue" else "captured"
		target.resolved_turn = turn_number; target.responder_squadron_id = String(chosen.responder_id); target.responder_faction_id = String(chosen.responder_faction_id)
		var responder_move := _movement(String(chosen.responder_id), movement_events); var target_move := _movement(target_id, movement_events)
		events.append(_event(next, String(target.status), target, turn_number, {"contact_progress": float(chosen.progress),
			"actual_distance": float(chosen.actual_distance), "position": navigation[target_id].position.duplicate(),
			"responder_route": _event_route(responder_move, navigation[String(chosen.responder_id)].position), "target_route": _event_route(target_move, navigation[target_id].position)}))
	for event in events: _append(next, turn_number, event)
	return {"ok": true, "errors": [], "state": next, "events": events}

func apply_authoritative_supply_capture(state: Dictionary, intent: Dictionary, sources: Array, turn_number: int) -> Dictionary:
	if turn_number < 1 or intent.keys().size() != 6 or intent.get("authority") != "G8-00" or intent.get("status") != "authorized_capture" or int(intent.get("effective_turn", 0)) != turn_number:
		return _error("현재 턴 G8-00 권위 나포 intent가 필요합니다.")
	var source_id := String(intent.get("source_id", ""))
	var source: Dictionary = {}
	for value in sources:
		if String(value.get("source_id", "")) == source_id: source = value
	if source.is_empty() or String(source.get("source_type", "")) != "supply_ship" or state.disabled_supply_sources.has(source_id):
		return _error("나포 가능한 활성 보급함 source가 아닙니다.")
	var responder_id := String(intent.get("responder_squadron_id", "")); var responder_faction := String(intent.get("responder_faction_id", "")); var responder := _squad(responder_id)
	if responder.is_empty() or not bool(responder.get("operational", true)) or String(responder.faction_id) != responder_faction or _friendly(responder_faction, String(source.faction_id)):
		return _error("적대 operational 나포 수행 전대 권위가 일치하지 않습니다.")
	var next := state.duplicate(true)
	var disabled := {"source_id": source_id, "provider_squadron_id": String(source.provider_squadron_id),
		"target_faction_id": String(source.faction_id), "position": source.position.duplicate(), "captured_turn": turn_number,
		"status": "captured_disabled", "capacity_squadrons_per_turn": 0, "captor_gain": 0}
	next.disabled_supply_sources[source_id] = disabled
	var row := disabled.duplicate(true); row["target_squadron_id"] = String(source.provider_squadron_id); row["responder_squadron_id"] = String(intent.get("responder_squadron_id", "")); row["responder_faction_id"] = String(intent.get("responder_faction_id", "")); row["inventory_disposition"] = "pending_atomic_inventory_commit"
	var event := _event(next, "supply_source_captured", row, turn_number, {"position": source.position.duplicate()})
	_append(next, turn_number, event)
	return {"ok": true, "errors": [], "state": next, "event": event}

func disabled_source_ids(state: Dictionary) -> Array:
	var ids: Array = state.get("disabled_supply_sources", {}).keys(); ids.sort(); return ids

func combat_locked_ids(state: Dictionary) -> Array:
	var ids: Array = []
	for sid in state.get("squadrons", {}):
		if String(state.squadrons[sid].status) != "active": ids.append(String(sid))
	ids.sort(); return ids

func supply_locked_ids(state: Dictionary) -> Array:
	var ids: Array = []
	for sid in state.get("squadrons", {}):
		if ["drifting", "rescued", "captured"].has(String(state.squadrons[sid].status)): ids.append(String(sid))
	ids.sort(); return ids

func terminal_ids(state: Dictionary) -> Array:
	var ids: Array = []
	for sid in state.get("squadrons", {}):
		if ["rescued", "captured"].has(String(state.squadrons[sid].status)): ids.append(String(sid))
	ids.sort(); return ids

func complete_supply(state: Dictionary, completed_squadron_ids: Array) -> Dictionary:
	var next := state.duplicate(true)
	for value in completed_squadron_ids:
		var sid := String(value)
		if next.squadrons.has(sid) and String(next.squadrons[sid].status) == "depleted_docked": next.squadrons[sid].status = "active"
	return {"ok": true, "errors": [], "state": next}

func visible(viewer: String, state: Dictionary, supply_state: Dictionary, contacts: Array = [], navigation: Dictionary = {}) -> Dictionary:
	var statuses: Array = []; var events: Array = []; var disabled: Array = []
	var contacts_by_target := {}
	for contact in contacts:
		var target_id := String(contact.get("recovery_target_id", contact.get("target_squadron_id", "")))
		if not target_id.is_empty(): contacts_by_target[target_id] = contact
	for sid in state.squadrons:
		var row: Dictionary = state.squadrons[sid]
		if String(row.faction_id) != viewer: continue
		var status: Dictionary = row.duplicate(true); status["fuel_basis_points"] = int(supply_state.resources.get(sid, {}).get("fuel_basis_points", 0)); status["terminal"] = ["rescued", "captured"].has(String(row.status)); status["command_locked"] = String(row.status) != "active"; status["can_move"] = String(row.status) == "active"; status["can_attack"] = String(row.status) == "active"; status["can_change_mission"] = String(row.status) == "active"; status["viewer_state"] = "own"; status["display_position"] = navigation.get(sid, {}).get("position", []).duplicate(); status["rescue_route"] = []; status["responder_type"] = "rescue_fast_craft" if String(row.status) == "rescued" else ("capture_unit" if String(row.status) == "captured" else "")
		statuses.append(status)
	for target_id in contacts_by_target:
		if not state.squadrons.has(target_id) or String(state.squadrons[target_id].faction_id) == viewer or String(state.squadrons[target_id].status) == "active": continue
		var contact: Dictionary = contacts_by_target[target_id]; var viewer_state := "confirmed" if String(contact.state) == "confirmed" else "estimated"
		statuses.append({"squadron_id": target_id if viewer_state == "confirmed" else "", "contact_id": String(contact.contact_id),
			"faction_id": "", "status": String(state.squadrons[target_id].status), "viewer_state": viewer_state,
			"display_position": contact.get("display_position"), "uncertainty": {"error_radius": int(contact.get("error_radius", 0)),
			"confidence_basis_points": int(contact.get("confidence_basis_points", 0)), "staleness_turns": int(contact.get("staleness_turns", 0))},
			"terminal": ["rescued", "captured"].has(String(state.squadrons[target_id].status)), "command_locked": true,
			"can_move": false, "can_attack": false, "can_change_mission": false, "rescue_route": [], "responder_type": ""})
	var turns: Array = state.events_by_turn.keys(); turns.sort()
	for event_turn in turns:
		for value in state.events_by_turn[event_turn]:
			var event: Dictionary = value.duplicate(true); var own_target := String(event.get("target_faction_id", "")) == viewer; var own_responder := String(event.get("responder_faction_id", "")) == viewer
			if not own_target and not own_responder: continue
			event["viewer_state"] = "own"
			if not own_target:
				var contact:Dictionary=contacts_by_target.get(String(value.get("target_squadron_id","")),{});var confirmed:=String(contact.get("state",""))=="confirmed"
				event["viewer_state"]="confirmed" if confirmed else ("estimated" if not contact.is_empty() else "own");event["contact_id"]=String(contact.get("contact_id",""));event["display_position"]=contact.get("display_position");event["uncertainty"]={"error_radius":int(contact.get("error_radius",0)),"confidence_basis_points":int(contact.get("confidence_basis_points",0)),"staleness_turns":int(contact.get("staleness_turns",0))}
				if not confirmed:event["target_squadron_id"]="";event["target_route"]=[];event["position"]=contact.get("display_position")
			if not own_responder: event["responder_squadron_id"] = ""; event["responder_route"] = []
			events.append(event)
	for source_id in state.disabled_supply_sources:
		var disabled_row: Dictionary = state.disabled_supply_sources[source_id]
		if String(disabled_row.target_faction_id) == viewer: disabled.append(disabled_row.duplicate(true))
	statuses.sort_custom(func(a, b): return String(a.squadron_id) < String(b.squadron_id)); events.sort_custom(func(a, b): return int(a.serial) < int(b.serial)); disabled.sort_custom(func(a, b): return String(a.source_id) < String(b.source_id))
	return {"ok": true, "errors": [], "viewer_faction_id": viewer, "statuses": statuses, "events": events,
		"disabled_supply_sources": disabled, "contract": _rules.duplicate(true)}

func _clamp_waypoints(from_value: Array, waypoints: Array, maximum: float) -> Array:
	var out: Array = []; var cursor := _point(from_value); var remaining := maximum
	for value in waypoints:
		var target := _point(value); var distance := cursor.distance_to(target)
		if distance <= remaining + 0.000001: out.append([target.x, target.y]); remaining -= distance; cursor = target
		elif remaining > 0.0 and distance > 0.0:
			var stop := cursor + cursor.direction_to(target) * remaining; out.append([stop.x, stop.y]); break
		else: break
	return out

func _swept_contact_progress(responder: Dictionary, target: Dictionary, responder_fallback: Array, target_fallback: Array, radius: float) -> float:
	var responder_from := _point(responder.get("from", responder_fallback)); var responder_to := _point(responder.get("to", responder_fallback)); var target_from := _point(target.get("from", target_fallback)); var target_to := _point(target.get("to", target_fallback))
	var total := float(responder.get("actual_distance", responder_from.distance_to(responder_to))); var segments:Array=responder.get("terrain_segments",[])
	if segments.is_empty():segments=[{"from":[responder_from.x,responder_from.y],"to":[responder_to.x,responder_to.y],"length":total}]
	var traversed:=0.0
	for segment in segments:
		var start:=_point(segment.from);var finish:=_point(segment.to);var length:=float(segment.get("length",start.distance_to(finish)));var t0:=0.0 if total<=0.000001 else traversed/total;var t1:=1.0 if total<=0.000001 else (traversed+length)/total
		var relative_start:=start-target_from.lerp(target_to,t0);var relative_delta:=(finish-start)-(target_from.lerp(target_to,t1)-target_from.lerp(target_to,t0))
		if relative_start.length()<=radius:return traversed
		var a:=relative_delta.length_squared();var b:=2.0*relative_start.dot(relative_delta);var c:=relative_start.length_squared()-radius*radius
		if a>0.0000001:
			var discriminant:=b*b-4.0*a*c
			if discriminant>=0.0:
				var entry:=(-b-sqrt(discriminant))/(2.0*a)
				if entry>=-0.000001 and entry<=1.000001:return traversed+clampf(entry,0.0,1.0)*length
		traversed+=length
	return -1.0

func _event_route(movement: Dictionary, fallback: Array) -> Array:
	return [movement.get("from", fallback).duplicate(), movement.get("to", fallback).duplicate()]

func _movement(sid: String, events: Array) -> Dictionary:
	for value in events:
		if value is Dictionary and String(value.get("squadron_id", "")) == sid: return value
	return {}
func _rescue_capable(sid: String, mission_state: Dictionary) -> bool:
	var row: Dictionary = mission_state.get("active", {}).get(sid, {})
	return _is_pure_fast_craft(sid) and String(row.get("equipment_id", "")) == "FAST-EQ-RESCUE" and String(row.get("mission_id", "")) == "rescue"
func _friendly_source_at(faction: String, position: Array, sources: Array) -> bool:
	for source in sources:
		if _friendly(faction, String(source.faction_id)) and _point(position).distance_to(_point(source.position)) <= float(source.radius): return true
	return false
func _friendly(a: String, b: String) -> bool:
	if a == b: return true
	for pair in _alliances:
		if pair is Array and pair.has(a) and pair.has(b): return true
	return false
func _pure_fast_craft() -> Array:
	var out: Array = []
	for squad in _setup.squadrons:
		if bool(squad.get("operational", true)) and squad.composition.size() == 1 and String(squad.composition[0].ship_type_id) == Setup.FAST_CRAFT_ID: out.append(squad)
	return out
func _squad(sid: String) -> Dictionary:
	for squad in _setup.squadrons:
		if String(squad.id) == sid: return squad
	return {}
func _is_pure_fast_craft(sid: String) -> bool:
	var squad:=_squad(sid);return not squad.is_empty() and squad.composition.size()==1 and String(squad.composition[0].ship_type_id)==Setup.FAST_CRAFT_ID
func _point(value: Array) -> Vector2: return Vector2(float(value[0]), float(value[1]))
func _event(state: Dictionary, status: String, row: Dictionary, turn_number: int, extra: Dictionary) -> Dictionary:
	var serial := int(state.next_event_serial); state.next_event_serial = serial + 1
	var event := {"event_id": "FC-RECOVERY-%06d" % serial, "serial": serial, "event_type": "fast_craft_recovery", "status": status, "turn": turn_number,
		"target_squadron_id": String(row.get("squadron_id", row.get("target_squadron_id", ""))), "target_faction_id": String(row.get("faction_id", row.get("target_faction_id", ""))),
		"responder_squadron_id": String(row.get("responder_squadron_id", "")), "responder_faction_id": String(row.get("responder_faction_id", "")), "contact_progress": -1.0, "actual_distance": 0.0, "position": []}
	event.merge(extra, true)
	for key in ["source_id", "inventory_disposition", "captor_gain"]:
		if row.has(key): event[key] = row[key]
	return event
func _append(state: Dictionary, turn_number: int, event: Dictionary) -> void:
	if not state.events_by_turn.has(turn_number): state.events_by_turn[turn_number] = []
	state.events_by_turn[turn_number].append(event.duplicate(true))
func _ok() -> Dictionary: return {"ok": true, "errors": []}
func _error(message: String) -> Dictionary: return {"ok": false, "errors": [message]}
