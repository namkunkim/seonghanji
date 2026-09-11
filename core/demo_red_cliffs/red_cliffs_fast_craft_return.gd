class_name RedCliffsFastCraftReturn
extends RefCounted

## DEMO-RC-G6-04 — 비상·조기 귀환 판단과 actual-distance 연료 소비.
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const RULES_PATH := "res://data/red-cliffs-fast-craft-rules.json"
var _setup: Dictionary = {}
var _rules: Dictionary = {}
var _alliances: Array = []

func initialize(applied_setup: Dictionary) -> Dictionary:
	var checked := Setup.validate_document(applied_setup); if not checked.ok: return _error("유효한 G3 적용 편성이 필요합니다.")
	var file := FileAccess.open(RULES_PATH, FileAccess.READ); if file == null: return _error("고속정 귀환 규칙을 열 수 없습니다.")
	var parsed = JSON.parse_string(file.get_as_text()); var rules = parsed.get("return_contract", {}) if parsed is Dictionary else {}
	if not rules is Dictionary or int(rules.get("fuel_basis_points_per_distance", 0)) <= 0 or int(rules.get("reserve_turns", 0)) != 1: return _error("normal-demo 귀환 계약이 잘못되었습니다.")
	_setup = checked.setup.duplicate(true); _rules = rules.duplicate(true); _alliances = parsed.supply_contract.get("mutual_supply_alliances", []).duplicate(true); return _ok()

func initial_state() -> Dictionary: return {"early_return_intents":{}, "destinations":{}, "events_by_turn":{}, "next_event_serial":1}

func status(squadron_id: String, return_state: Dictionary, supply_state: Dictionary, sources: Array, navigation: Dictionary, speed: int) -> Dictionary:
	if not supply_state.get("resources", {}).has(squadron_id) or not navigation.has(squadron_id) or speed <= 0: return _error("고속정 귀환 상태 입력이 잘못되었습니다.")
	var resource: Dictionary = supply_state.resources[squadron_id]; var fuel := int(resource.fuel_basis_points); var reserve := speed * int(_rules.fuel_basis_points_per_distance)
	var candidates: Array = []
	for source in sources:
		if not _friendly(String(resource.faction_id), String(source.faction_id)): continue
		var current := Vector2(float(navigation[squadron_id].position[0]), float(navigation[squadron_id].position[1]))
		var center := Vector2(float(source.position[0]), float(source.position[1]))
		var center_distance := current.distance_to(center)
		var distance := maxf(0.0, center_distance - float(source.get("radius", 0)))
		var required := int(ceil(distance * float(_rules.fuel_basis_points_per_distance)))
		if required <= fuel:
			var arrival := current if distance <= 0.001 else current + current.direction_to(center) * distance
			var row: Dictionary = source.duplicate(true); row["distance"] = distance; row["required_fuel_basis_points"] = required; row["arrival_position"] = [arrival.x, arrival.y]; candidates.append(row)
	candidates.sort_custom(func(a,b):
		if int(a.required_fuel_basis_points) != int(b.required_fuel_basis_points): return int(a.required_fuel_basis_points) < int(b.required_fuel_basis_points)
		if not is_equal_approx(float(a.distance), float(b.distance)): return float(a.distance) < float(b.distance)
		return String(a.source_id) < String(b.source_id))
	var chosen: Dictionary = {} if candidates.is_empty() else candidates[0]; var required := -1 if chosen.is_empty() else int(chosen.required_fuel_basis_points)
	var forced: bool = required < 0 or fuel <= required + reserve; var early: bool = return_state.get("early_return_intents", {}).has(squadron_id)
	var state_label: String = "stranded_risk" if forced and chosen.is_empty() else ("forced_return" if forced else ("early_return" if early else "normal"))
	return {"ok":true,"errors":[],"squadron_id":squadron_id,"faction_id":String(resource.faction_id),"fuel_basis_points":fuel,
		"required_fuel_basis_points":required,"reserve_fuel_basis_points":reserve,"threshold_basis_points":required + reserve if required >= 0 else -1,
		"nearest_source_id":String(chosen.get("source_id","")),"distance":float(chosen.get("distance",-1.0)),"eta_turns":int(ceil(float(chosen.get("distance",0.0))/float(speed))) if not chosen.is_empty() else -1,
		"route":[chosen.arrival_position.duplicate()] if not chosen.is_empty() else [],"status":state_label,"forced":forced,"can_request_early":not forced and not early,"can_cancel":not forced and early}

func request_early(return_state: Dictionary, status_row: Dictionary, turn_number: int) -> Dictionary:
	if not status_row.get("can_request_early", false): return _error("조기 귀환을 요청할 수 없습니다.")
	var next := return_state.duplicate(true); var sid := String(status_row.squadron_id); next.early_return_intents[sid] = {"squadron_id":sid,"faction_id":String(status_row.faction_id),"requested_turn":turn_number}
	var event := _event(next,"early_requested",status_row,turn_number); _append(next,turn_number,event); return {"ok":true,"errors":[],"state":next,"event":event}

func cancel_early(return_state: Dictionary, status_row: Dictionary, turn_number: int) -> Dictionary:
	if not status_row.get("can_cancel", false): return _error("조기 귀환을 취소할 수 없습니다.")
	var next := return_state.duplicate(true); next.early_return_intents.erase(String(status_row.squadron_id)); next.destinations.erase(String(status_row.squadron_id))
	var event := _event(next,"early_cancelled",status_row,turn_number); _append(next,turn_number,event); return {"ok":true,"errors":[],"state":next,"event":event}

func plan(return_state: Dictionary, supply_state: Dictionary, sources: Array, navigation: Dictionary, speeds: Dictionary, turn_number: int) -> Dictionary:
	var next := return_state.duplicate(true); var overrides := {}; var statuses: Array = []; var events: Array = []; var ids: Array = supply_state.resources.keys(); ids.sort()
	for sid_value in ids:
		var sid := String(sid_value); var row: Dictionary = status(sid,next,supply_state,sources,navigation,int(speeds.get(sid,0))); if not row.ok: return row
		statuses.append(row.duplicate(true)); if not ["forced_return","early_return","stranded_risk"].has(String(row.status)): continue
		if String(row.status) == "stranded_risk": events.append(_event(next,"stranded_risk",row,turn_number)); continue
		var previous := String(next.destinations.get(sid,{}).get("source_id","")); next.destinations[sid] = {"source_id":String(row.nearest_source_id),"selected_turn":turn_number}
		var status_name := "retargeted" if not previous.is_empty() and previous != String(row.nearest_source_id) else String(row.status)
		events.append(_event(next,status_name,row,turn_number)); overrides[sid] = {"squadron_id":sid,"action":"hold"} if float(row.distance) <= 0.001 else {"squadron_id":sid,"action":"move","waypoints":row.route.duplicate(true),"facing_deg":float(navigation[sid].facing_deg)}
	for event in events: _append(next,turn_number,event)
	return {"ok":true,"errors":[],"state":next,"overrides":overrides,"statuses":statuses,"events":events}

func consume_fuel(supply_state: Dictionary, movement_events: Array, turn_number: int) -> Dictionary:
	var next := supply_state.duplicate(true); var events: Array = []; var seen := {}
	for value in movement_events:
		if not value is Dictionary: return _error("실제 이동 결과가 잘못되었습니다.")
		var sid := String(value.get("squadron_id","")); if seen.has(sid): return _error("중복 실제 이동 결과입니다."); seen[sid]=true
		if not next.resources.has(sid): continue
		var distance := float(value.get("actual_distance",-1.0)); if distance < 0.0 or not is_finite(distance): return _error("실제 이동 거리가 잘못되었습니다.")
		var before := int(next.resources[sid].fuel_basis_points); var used := mini(before,int(ceil(distance*float(_rules.fuel_basis_points_per_distance))))
		next.resources[sid].fuel_basis_points = before-used
		events.append({"event_id":"FC-FUEL-%02d-%s"%[turn_number,sid],"event_type":"fast_craft_fuel_consumed","turn":turn_number,"squadron_id":sid,"faction_id":String(next.resources[sid].faction_id),"actual_distance":distance,"fuel_before_basis_points":before,"fuel_used_basis_points":used,"fuel_after_basis_points":before-used})
	return {"ok":true,"errors":[],"state":next,"events":events}

func record_fuel_events(return_state:Dictionary, fuel_events:Array, turn_number:int)->Dictionary:
	var next:=return_state.duplicate(true);var recorded:Array=[]
	for value in fuel_events:
		if not value is Dictionary:return _error("연료 이벤트가 잘못되었습니다.")
		var event:Dictionary=value.duplicate(true);var serial:=int(next.next_event_serial);next.next_event_serial=serial+1
		event.event_id="FC-RETURN-%06d"%serial;event.serial=serial;recorded.append(event);_append(next,turn_number,event)
	return {"ok":true,"errors":[],"state":next,"events":recorded}

func clear_completed(return_state:Dictionary, completed_squadron_ids:Array)->Dictionary:
	var next:=return_state.duplicate(true)
	for value in completed_squadron_ids:
		var sid:=String(value);next.early_return_intents.erase(sid);next.destinations.erase(sid)
	return {"ok":true,"errors":[],"state":next}

func visible(viewer_faction_id:String, return_state:Dictionary, statuses:Array) -> Dictionary:
	var own_statuses:Array=[]; var events:Array=[]
	for row in statuses:
		if String(row.faction_id)==viewer_faction_id: own_statuses.append(row.duplicate(true))
	var turns:Array=return_state.events_by_turn.keys(); turns.sort()
	for t in turns:
		for row in return_state.events_by_turn[t]:
			if String(row.faction_id)==viewer_faction_id: events.append(row.duplicate(true))
	events.sort_custom(func(a,b):return int(a.serial)<int(b.serial)); return {"ok":true,"errors":[],"viewer_faction_id":viewer_faction_id,"statuses":own_statuses,"events":events,"unreachable_contract":String(_rules.unreachable_contract)}

func _event(state:Dictionary,status_name:String,row:Dictionary,turn_number:int)->Dictionary:
	var serial:=int(state.next_event_serial);state.next_event_serial=serial+1
	return {"event_id":"FC-RETURN-%06d"%serial,"serial":serial,"event_type":"fast_craft_return","status":status_name,"turn":turn_number,"squadron_id":String(row.squadron_id),"faction_id":String(row.faction_id),"forced":bool(row.forced),"fuel_basis_points":int(row.fuel_basis_points),"required_fuel_basis_points":int(row.required_fuel_basis_points),"reserve_fuel_basis_points":int(row.reserve_fuel_basis_points),"threshold_basis_points":int(row.threshold_basis_points),"source_id":String(row.nearest_source_id),"distance":float(row.distance),"eta_turns":int(row.eta_turns),"route":row.route.duplicate(true)}
func _append(state:Dictionary,turn_number:int,event:Dictionary)->void:
	if not state.events_by_turn.has(turn_number):state.events_by_turn[turn_number]=[]
	state.events_by_turn[turn_number].append(event.duplicate(true))
func _friendly(a:String,b:String)->bool:
	if a==b:return true
	for pair in _alliances:
		if pair is Array and pair.has(a) and pair.has(b):return true
	return false
func _ok()->Dictionary:return {"ok":true,"errors":[]}
func _error(message:String)->Dictionary:return {"ok":false,"errors":[message]}
