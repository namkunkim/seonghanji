class_name RedCliffsFastCraftSupply
extends RefCounted

## DEMO-RC-G6-03 — 자동 보급 영역·정박·처리량의 결정론적 reducer.
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const SupplyInventory := preload("res://core/demo_red_cliffs/red_cliffs_supply_inventory.gd")
const RULES_PATH := "res://data/red-cliffs-fast-craft-rules.json"

var _setup: Dictionary = {}
var _rules: Dictionary = {}
var _inventory

func initialize(applied_setup: Dictionary) -> Dictionary:
	var checked := Setup.validate_document(applied_setup)
	if not checked.ok: return _error("유효한 G3 적용 편성이 필요합니다.")
	var file := FileAccess.open(RULES_PATH, FileAccess.READ); if file == null: return _error("고속정 보급 규칙을 열 수 없습니다.")
	var parsed = JSON.parse_string(file.get_as_text()); var supply = parsed.get("supply_contract", {}) if parsed is Dictionary else {}
	if not supply is Dictionary or int(supply.get("maximum_basis_points", 0)) != 10000 or int(supply.get("required_stationary_turns", 0)) != 1: return _error("normal-demo 보급 계약이 잘못되었습니다.")
	if supply.get("priority") != ["remaining_fuel_ascending", "entry_turn_ascending", "squadron_id_ascending"]: return _error("보급 우선순위 계약이 잘못되었습니다.")
	var inventory = SupplyInventory.new(); var inventory_result: Dictionary = inventory.initialize(checked.setup)
	if not inventory_result.ok: return inventory_result
	_setup = checked.setup.duplicate(true); _rules = supply.duplicate(true); _inventory = inventory; return _ok()

func initial_state(navigation: Dictionary, inventory_state: Dictionary = {}) -> Dictionary:
	var resources := {}; var queue := {}; var sources := source_zones(navigation, [], inventory_state)
	for squad in _fast_craft_squadrons():
		var sid := String(squad.id); resources[sid] = {"squadron_id": sid, "faction_id": String(squad.faction_id),
			"fuel_basis_points": int(_rules.initial_fuel_basis_points), "maximum_basis_points": 10000}
		var source := _source_at(String(squad.faction_id), navigation.get(sid, {}).get("position", []), sources)
		if not source.is_empty(): queue[sid] = _queue_row(sid, String(squad.faction_id), String(source.source_id), 1, 0)
	return {"resources": resources, "queue": queue, "events_by_turn": {}, "next_event_serial": 1}

func source_zones(navigation: Dictionary, disabled_source_ids: Array = [], inventory_state: Dictionary = {}) -> Array:
	var sources: Array = []
	for base in _rules.friendly_bases:
		if disabled_source_ids.has(String(base.source_id)): continue
		sources.append({"source_id": String(base.source_id), "source_type": "friendly_base", "faction_id": String(base.faction_id),
			"position": base.position.duplicate(), "radius": int(_rules.source_types.friendly_base.radius), "capacity_squadrons_per_turn": int(_rules.source_types.friendly_base.capacity_squadrons_per_turn)})
	for squad in _setup.squadrons:
		if not bool(squad.get("operational", true)) or not navigation.has(String(squad.id)): continue
		for source_type in ["supply_ship", "carrier"]:
			var rule: Dictionary = _rules.source_types[source_type]; var count := 0
			for row in squad.composition:
				if String(row.ship_type_id) == String(rule.ship_type_id): count += int(row.count)
			var source_id := "%s-%s" % [source_type.to_upper(), String(squad.id)]
			if count > 0 and not disabled_source_ids.has(source_id) and (inventory_state.is_empty() or source_type!="supply_ship" or _inventory.automatic_supply_enabled(source_id,inventory_state)): sources.append({"source_id": source_id, "source_type": source_type,
				"faction_id": String(squad.faction_id), "provider_squadron_id": String(squad.id), "position": navigation[String(squad.id)].position.duplicate(), "radius": int(rule.radius),
				"capacity_squadrons_per_turn": _inventory.capacity(source_id,inventory_state) if source_type=="supply_ship" and not inventory_state.is_empty() else count * int(rule.capacity_per_ship)})
	sources.sort_custom(func(a, b): return String(a.source_id) < String(b.source_id)); return sources

func resolve(state: Dictionary, prior_navigation: Dictionary, live_navigation: Dictionary, movement_events: Array, turn_number: int, disabled_source_ids: Array = [], ineligible_squadron_ids: Array = [], inventory_state: Dictionary = {}, refill_quotes: Dictionary = {}) -> Dictionary:
	if turn_number < 1: return _error("보급 판정 턴이 잘못되었습니다.")
	var movement_seen := {}
	for value in movement_events:
		if not value is Dictionary: return _error("실제 이동 결과는 객체여야 합니다.")
		var movement_id := String(value.get("squadron_id", "")); var actual = value.get("actual_distance")
		if movement_id.is_empty() or movement_seen.has(movement_id) or not (actual is int or actual is float) or not is_finite(float(actual)) or float(actual) < 0.0: return _error("실제 이동 거리 원장이 잘못되었습니다.")
		movement_seen[movement_id] = true
	var next_inventory := inventory_state.duplicate(true)
	if not next_inventory.is_empty():
		var begun: Dictionary = _inventory.begin_turn(next_inventory,turn_number)
		if not begun.ok:return begun
		next_inventory=begun.state.duplicate(true)
	var next := state.duplicate(true); next.resources = _sorted_dictionary(next.get("resources", {})); next.queue = _sorted_dictionary(next.get("queue", {}))
	var events: Array = []; var inventory_events: Array = []; var sources := source_zones(live_navigation, disabled_source_ids,next_inventory); var ids: Array = next.resources.keys(); ids.sort()
	for sid_value in ids:
		var sid := String(sid_value); var resource: Dictionary = next.resources[sid]
		if not prior_navigation.has(sid) or not live_navigation.has(sid): return _error("고속정 이동 결과가 누락되었습니다: %s" % sid)
		if ineligible_squadron_ids.has(sid):
			var unavailable: Dictionary = next.queue.get(sid, {})
			if not unavailable.is_empty(): events.append(_event(next, "interrupted", sid, String(resource.faction_id), String(unavailable.source_id), turn_number, "recovery_locked")); next.queue.erase(sid)
			continue
		var current: Array = live_navigation[sid].position
		var moved := _actual_moved(sid, movement_events)
		var old: Dictionary = next.queue.get(sid, {})
		if not old.is_empty() and disabled_source_ids.has(String(old.source_id)):
			events.append(_event(next, "interrupted", sid, String(resource.faction_id), String(old.source_id), turn_number, "source_captured")); next.queue.erase(sid); old = {}
		if not old.is_empty() and not inventory_state.is_empty() and inventory_state.get("sources",{}).has(String(old.source_id)) and not _inventory.automatic_supply_enabled(String(old.source_id),next_inventory):
			var inactive_reason:String=String(next_inventory.sources[String(old.source_id)].get("disabled_reason","inventory_depleted"));if inactive_reason.is_empty():inactive_reason="inventory_depleted"
			events.append(_event(next,"interrupted",sid,String(resource.faction_id),String(old.source_id),turn_number,inactive_reason));next.queue.erase(sid);old={}
		var source := _source_at(String(resource.faction_id), current, sources)
		if source.is_empty():
			if not old.is_empty(): events.append(_event(next, "interrupted", sid, String(resource.faction_id), String(old.source_id), turn_number, "left_zone")); next.queue.erase(sid)
			continue
		var source_id := String(source.source_id); var provider_moved := _provider_moved(source, movement_events)
		if moved or provider_moved:
			if not old.is_empty(): events.append(_event(next, "interrupted", sid, String(resource.faction_id), String(old.source_id), turn_number, "moved"))
			next.queue[sid] = _queue_row(sid, String(resource.faction_id), source_id, turn_number, 0)
			events.append(_event(next, "queued", sid, String(resource.faction_id), source_id, turn_number, "provider_moved" if provider_moved and not moved else "movement_entry")); continue
		if old.is_empty() or String(old.source_id) != source_id:
			next.queue[sid] = _queue_row(sid, String(resource.faction_id), source_id, turn_number, 1)
			events.append(_event(next, "queued", sid, String(resource.faction_id), source_id, turn_number, "stationary_entry"))
		else: next.queue[sid].docked_turns = int(old.docked_turns) + 1
	var by_source := {}
	for queued in next.queue.values():
		if int(queued.docked_turns) < int(_rules.required_stationary_turns): continue
		if not by_source.has(String(queued.source_id)): by_source[String(queued.source_id)] = []
		by_source[String(queued.source_id)].append(queued)
	var source_ids: Array = by_source.keys(); source_ids.sort()
	var completed_squadron_ids: Array = []
	for source_id in source_ids:
		var candidates: Array = by_source[source_id]; candidates.sort_custom(func(a, b):
			var af := int(next.resources[a.squadron_id].fuel_basis_points); var bf := int(next.resources[b.squadron_id].fuel_basis_points)
			if af != bf: return af < bf
			if int(a.entry_turn) != int(b.entry_turn): return int(a.entry_turn) < int(b.entry_turn)
			return String(a.squadron_id) < String(b.squadron_id))
		var source := _source_by_id(String(source_id), sources); var capacity := int(source.capacity_squadrons_per_turn); var served:=0
		for index in range(candidates.size()):
			var queued: Dictionary = candidates[index]; var sid := String(queued.squadron_id)
			if served >= capacity: events.append(_event(next, "waiting_capacity", sid, String(queued.faction_id), String(source_id), turn_number, "capacity")); continue
			var resource: Dictionary = next.resources[sid]; var fuel_before := int(resource.fuel_basis_points)
			if String(source.get("source_type",""))=="supply_ship":
				var quote:Dictionary=refill_quotes.get(sid,{}).duplicate(true);quote["fuel_basis_points"]=mini(10000,int(resource.maximum_basis_points))-fuel_before;quote["supply_material_units"]=1
				var authorized:Dictionary=_inventory.authorize_refill(next_inventory,String(source_id),sid,quote,turn_number)
				if not authorized.ok:return authorized
				if not authorized.authorized:
					events.append(_event(next,"waiting_inventory" if String(authorized.reason)=="inventory" else "waiting_capacity",sid,String(queued.faction_id),String(source_id),turn_number,String(authorized.reason)));continue
				next_inventory=authorized.state.duplicate(true);inventory_events.append(authorized.event.duplicate(true));served+=1
			else:served+=1
			resource.fuel_basis_points = mini(10000, int(resource.maximum_basis_points))
			var event := _event(next, "completed", sid, String(queued.faction_id), String(source_id), turn_number, "normal_demo_capacity")
			event["fuel_granted_basis_points"] = int(resource.fuel_basis_points) - fuel_before
			events.append(event); completed_squadron_ids.append(sid); next.queue.erase(sid)
	for event in events: _append_event(next, turn_number, event)
	if not next_inventory.is_empty():
		var reloaded:Dictionary=_inventory.finish_base_reload(next_inventory,prior_navigation,live_navigation,movement_events,_base_zones(),turn_number)
		if not reloaded.ok:return reloaded
		next_inventory=reloaded.state.duplicate(true);inventory_events.append_array(reloaded.events)
	return {"ok": true, "errors": [], "state": next, "events": events, "sources": sources, "completed_squadron_ids":completed_squadron_ids,"inventory_state":next_inventory,"inventory_events":inventory_events}

func visible(viewer_faction_id: String, state: Dictionary, navigation: Dictionary, disabled_source_ids: Array = [], inventory_state: Dictionary = {}) -> Dictionary:
	var resources: Array = []; var queue: Array = []; var events: Array = []; var sources: Array = []
	for row in state.resources.values():
		if String(row.faction_id) == viewer_faction_id: resources.append(row.duplicate(true))
	for row in state.queue.values():
		if String(row.faction_id) == viewer_faction_id: queue.append(row.duplicate(true))
	for source in source_zones(navigation, disabled_source_ids,inventory_state):
		if _friendly(viewer_faction_id, String(source.faction_id)): sources.append(source.duplicate(true))
	var turns: Array = state.events_by_turn.keys(); turns.sort()
	for event_turn in turns:
		for row in state.events_by_turn[event_turn]:
			if String(row.faction_id) == viewer_faction_id: events.append(row.duplicate(true))
	resources.sort_custom(func(a,b): return String(a.squadron_id) < String(b.squadron_id)); events.sort_custom(func(a,b): return int(a.serial) < int(b.serial))
	var visible_sources := {}; for source in sources: visible_sources[String(source.source_id)] = source
	var by_source := {}
	for row in queue:
		if not by_source.has(String(row.source_id)): by_source[String(row.source_id)] = []
		by_source[String(row.source_id)].append(row)
	for source_id in by_source:
		var candidates: Array = by_source[source_id]; candidates.sort_custom(func(a,b):
			var af := int(state.resources[a.squadron_id].fuel_basis_points); var bf := int(state.resources[b.squadron_id].fuel_basis_points)
			if af != bf: return af < bf
			if int(a.entry_turn) != int(b.entry_turn): return int(a.entry_turn) < int(b.entry_turn)
			return String(a.squadron_id) < String(b.squadron_id))
		for index in range(candidates.size()): candidates[index]["priority_rank"] = index + 1; candidates[index]["capacity_squadrons_per_turn"] = int(visible_sources.get(source_id, {}).get("capacity_squadrons_per_turn", 0))
	queue.sort_custom(func(a,b): return String(a.squadron_id) < String(b.squadron_id))
	return {"ok": true, "errors": [], "viewer_faction_id": viewer_faction_id, "sources": sources, "resources": resources, "queue": queue, "events": events,
		"priority": _rules.priority.duplicate(), "required_stationary_turns": int(_rules.required_stationary_turns), "inventory_contract": String(_rules.inventory_contract)}

func _source_at(faction_id: String, position: Array, sources: Array) -> Dictionary:
	if position.size() != 2: return {}
	for source in sources:
		if _friendly(faction_id, String(source.faction_id)) and Vector2(float(position[0]), float(position[1])).distance_to(Vector2(float(source.position[0]), float(source.position[1]))) <= float(source.radius): return source
	return {}
func _base_zones()->Array:
	var bases:Array=[]
	for base in _rules.friendly_bases:bases.append({"source_id":String(base.source_id),"source_type":"friendly_base","faction_id":String(base.faction_id),"position":base.position.duplicate(),"radius":int(_rules.source_types.friendly_base.radius),"capacity_squadrons_per_turn":int(_rules.source_types.friendly_base.capacity_squadrons_per_turn)})
	return bases
func _friendly(a: String, b: String) -> bool:
	if a == b: return true
	for pair in _rules.get("mutual_supply_alliances", []):
		if pair is Array and pair.has(a) and pair.has(b): return true
	return false
func _provider_moved(source: Dictionary, movement_events: Array) -> bool:
	var provider := String(source.get("provider_squadron_id", "")); if provider.is_empty(): return false
	return _actual_moved(provider, movement_events)
func _actual_moved(squadron_id: String, movement_events: Array) -> bool:
	for event in movement_events:
		if event is Dictionary and String(event.get("squadron_id", "")) == squadron_id: return float(event.get("actual_distance", -1.0)) > float(_rules.movement_epsilon)
	return true
func _source_by_id(id: String, sources: Array) -> Dictionary:
	for source in sources:
		if String(source.source_id) == id: return source
	return {}
func _queue_row(sid: String, faction_id: String, source_id: String, entry_turn: int, docked: int) -> Dictionary:
	return {"squadron_id": sid, "faction_id": faction_id, "source_id": source_id, "entry_turn": entry_turn, "docked_turns": docked}
func _event(state: Dictionary, status: String, sid: String, faction_id: String, source_id: String, turn_number: int, reason: String) -> Dictionary:
	var serial := int(state.next_event_serial); state.next_event_serial = serial + 1
	return {"event_id": "FC-SUPPLY-%06d" % serial, "serial": serial, "event_type": "fast_craft_supply", "status": status, "turn": turn_number,
		"squadron_id": sid, "faction_id": faction_id, "source_id": source_id, "reason": reason}
func _append_event(state: Dictionary, turn_number: int, event: Dictionary) -> void:
	if not state.events_by_turn.has(turn_number): state.events_by_turn[turn_number] = []
	state.events_by_turn[turn_number].append(event.duplicate(true))
func _sorted_dictionary(input: Dictionary) -> Dictionary:
	var result := {}; var keys: Array = input.keys(); keys.sort()
	for key in keys: result[key] = input[key].duplicate(true) if input[key] is Dictionary or input[key] is Array else input[key]
	return result
func _fast_craft_squadrons() -> Array:
	var out: Array = []
	for squad in _setup.squadrons:
		if bool(squad.get("operational", true)) and squad.composition.size() == 1 and String(squad.composition[0].ship_type_id) == Setup.FAST_CRAFT_ID: out.append(squad)
	return out
func _ok() -> Dictionary: return {"ok": true, "errors": []}
func _error(message: String) -> Dictionary: return {"ok": false, "errors": [message]}
