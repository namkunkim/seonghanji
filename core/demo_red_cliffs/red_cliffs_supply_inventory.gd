class_name RedCliffsSupplyInventory
extends RefCounted

## DEMO-RC-G6-06 — 보급함 재고·손상 처리량·거점 재적재.
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const RULES_PATH := "res://data/red-cliffs-fast-craft-rules.json"
const SUPPLY_SHIP_ID := "SHP-05"

var _setup: Dictionary = {}
var _rules: Dictionary = {}

func initialize(applied_setup: Dictionary) -> Dictionary:
	var checked := Setup.validate_document(applied_setup)
	if not checked.ok: return _error("유효한 적용 편성이 필요합니다.")
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null: return _error("보급함 재고 규칙을 열 수 없습니다.")
	var parsed = JSON.parse_string(file.get_as_text())
	var rules = parsed.get("supply_inventory_contract", {}) if parsed is Dictionary else {}
	if not rules is Dictionary or int(rules.get("throughput_scale", 0)) != 10000 or int(rules.get("required_base_reload_stationary_turns", 0)) != 1:
		return _error("normal-demo 보급함 재고 계약이 잘못되었습니다.")
	var maximum: Dictionary = rules.get("per_supply_ship_maximum", {})
	var throughput: Dictionary = rules.get("throughput_basis_points", {})
	if int(maximum.get("fuel_basis_points",0))!=10000 or int(maximum.get("ammo_units",0))!=12 or int(maximum.get("supply_material_units",0))!=4 or int(throughput.get("operational",0))!=10000 or int(throughput.get("moderate_damage",0))!=5000 or int(throughput.get("heavy_damage",0))!=2500:
		return _error("보급함 재고·손상 수치가 계약과 일치하지 않습니다.")
	_setup = checked.setup.duplicate(true); _rules = rules.duplicate(true)
	return _ok()

func initial_state() -> Dictionary:
	var sources := {}
	for squad in _setup.squadrons:
		if not bool(squad.get("operational", true)): continue
		var count := _ship_count(squad, SUPPLY_SHIP_ID)
		if count <= 0: continue
		var source_id := "SUPPLY_SHIP-%s" % String(squad.id)
		var maximum := {"fuel_basis_points":count * 10000, "ammo_units":count * 12, "supply_material_units":count * 4}
		sources[source_id] = {"source_id":source_id, "provider_squadron_id":String(squad.id), "faction_id":String(squad.faction_id),
			"initial_ship_count":count, "ship_status_counts":{"operational":count,"moderate_damage":0,"heavy_damage":0,"destroyed":0,"captured":0},
			"stock":maximum.duplicate(true), "maximum_stock":maximum, "throughput_credit_basis_points":0, "last_credit_turn":0,
			"reload":{"status":"idle","base_source_id":"","progress_turns":0,"required_turns":1}, "disabled":false,"disabled_reason":"","revision":0}
	return {"sources":sources,"events_by_turn":{},"next_event_serial":1}

func begin_turn(state: Dictionary, turn_number: int) -> Dictionary:
	var valid := _validate_state(state)
	if not valid.ok: return valid
	if turn_number < 1: return _error("재고 처리 턴이 잘못되었습니다.")
	var next := state.duplicate(true); var ids: Array = next.sources.keys(); ids.sort()
	for source_id in ids:
		var row: Dictionary = next.sources[source_id]
		if int(row.last_credit_turn) >= turn_number: continue
		row.last_credit_turn = turn_number
		if bool(row.disabled) or not _has_all_stock(row): continue
		row.throughput_credit_basis_points = int(row.throughput_credit_basis_points) % 10000 + _weighted_throughput(row)
	return {"ok":true,"errors":[],"state":next}

func capacity(source_id: String, state: Dictionary) -> int:
	var row: Dictionary = state.get("sources", {}).get(source_id, {})
	if row.is_empty() or bool(row.get("disabled", true)) or not _has_all_stock(row): return 0
	return int(row.get("throughput_credit_basis_points", 0)) / 10000

func automatic_supply_enabled(source_id:String,state:Dictionary)->bool:
	var row:Dictionary=state.get("sources",{}).get(source_id,{})
	return not row.is_empty() and not bool(row.get("disabled",true)) and _has_all_stock(row) and int(row.ship_status_counts.operational)+int(row.ship_status_counts.moderate_damage)+int(row.ship_status_counts.heavy_damage)>0

func authorize_refill(state: Dictionary, source_id: String, squadron_id: String, quote: Dictionary, turn_number: int) -> Dictionary:
	var valid := _validate_state(state)
	if not valid.ok: return valid
	if not state.sources.has(source_id): return _error("보급함 재고 source가 없습니다.")
	var fuel := int(quote.get("fuel_basis_points", -1)); var ammo := int(quote.get("ammo_units", -1)); var materials := int(quote.get("supply_material_units", -1))
	if fuel < 0 or ammo < 0 or materials != 1: return _error("보급 소모 quote가 잘못되었습니다.")
	var next := state.duplicate(true); var row: Dictionary = next.sources[source_id]
	if int(row.stock.fuel_basis_points) < fuel or int(row.stock.ammo_units) < ammo or int(row.stock.supply_material_units) < materials:
		return {"ok":true,"errors":[],"authorized":false,"reason":"inventory","state":next}
	if capacity(source_id, next) <= 0: return {"ok":true,"errors":[],"authorized":false,"reason":"throughput","state":next}
	var before:Dictionary = row.stock.duplicate(true)
	row.stock.fuel_basis_points -= fuel; row.stock.ammo_units -= ammo; row.stock.supply_material_units -= materials
	row.throughput_credit_basis_points -= 10000
	var event := _event(next,"inventory_consumed",source_id,turn_number,{"squadron_id":squadron_id,"before":before,"after":row.stock.duplicate(true),"debit":quote.duplicate(true)})
	_append(next,turn_number,event)
	return {"ok":true,"errors":[],"authorized":true,"reason":"","state":next,"event":event}

func finish_base_reload(state: Dictionary, prior_navigation: Dictionary, live_navigation: Dictionary, movement_events: Array, bases: Array, turn_number: int) -> Dictionary:
	var valid := _validate_state(state)
	if not valid.ok: return valid
	var next := state.duplicate(true); var events: Array = []; var ids: Array = next.sources.keys(); ids.sort()
	for source_id in ids:
		var row: Dictionary = next.sources[source_id]
		if bool(row.disabled): continue
		var provider := String(row.provider_squadron_id); var base := _same_faction_base(row, live_navigation.get(provider, {}).get("position", []), bases)
		var prior_base := _same_faction_base(row, prior_navigation.get(provider, {}).get("position", []), bases)
		var stationary := not _actual_moved(provider, movement_events)
		if base.is_empty() or prior_base.is_empty() or String(base.source_id) != String(prior_base.source_id) or not stationary:
			row.reload = {"status":"idle" if base.is_empty() else "queued","base_source_id":"" if base.is_empty() else String(base.source_id),"progress_turns":0,"required_turns":1}
			continue
		row.reload = {"status":"reloaded","base_source_id":String(base.source_id),"progress_turns":1,"required_turns":1}
		if row.stock == row.maximum_stock: continue
		var before:Dictionary = row.stock.duplicate(true); row.stock = row.maximum_stock.duplicate(true)
		var event := _event(next,"base_reloaded",String(source_id),turn_number,{"base_source_id":String(base.source_id),"before":before,"after":row.stock.duplicate(true)})
		events.append(event); _append(next,turn_number,event)
	return {"ok":true,"errors":[],"state":next,"events":events}

func apply_authoritative_status(state: Dictionary, intent: Dictionary, turn_number: int) -> Dictionary:
	var expected := ["authority","effective_turn","ship_status_counts","source_id","source_revision","status"]; var keys: Array = intent.keys(); keys.sort(); expected.sort()
	if keys != expected or intent.get("authority") != "G8-00" or intent.get("status") != "authorized_supply_ship_status" or int(intent.get("effective_turn",0)) != turn_number:
		return _error("현재 턴 G8-00 권위 보급함 상태 intent가 필요합니다.")
	var valid := _validate_state(state)
	if not valid.ok: return valid
	var source_id := String(intent.source_id)
	if not state.sources.has(source_id): return _error("보급함 재고 source가 없습니다.")
	var old: Dictionary = state.sources[source_id]; var counts = intent.ship_status_counts
	if not counts is Dictionary or counts.keys().size() != 5: return _error("보급함 상태 count schema가 잘못되었습니다.")
	for key in ["operational","moderate_damage","heavy_damage","destroyed","captured"]:
		if not counts.has(key) or not _nonnegative_int(counts[key]): return _error("보급함 상태 count가 잘못되었습니다.")
	if int(counts.captured) != int(old.ship_status_counts.captured) or int(intent.source_revision) != int(old.revision): return _error("보급함 상태 revision 또는 capture 경계가 잘못되었습니다.")
	var total := 0; for key in counts: total += int(counts[key])
	if total != int(old.initial_ship_count) or not _monotonic(old.ship_status_counts, counts): return _error("보급함 손상 상태는 역행할 수 없습니다.")
	var newly_destroyed := int(counts.destroyed) - int(old.ship_status_counts.destroyed); var before_alive := int(old.initial_ship_count) - int(old.ship_status_counts.destroyed) - int(old.ship_status_counts.captured); var old_rate := _weighted_throughput(old)
	var next := state.duplicate(true); var row: Dictionary = next.sources[source_id]; var stock_before:Dictionary = row.stock.duplicate(true)
	row.ship_status_counts = counts.duplicate(true); row.revision += 1
	row.throughput_credit_basis_points = maxi(0, int(row.throughput_credit_basis_points) - old_rate) + _weighted_throughput(row) if int(row.last_credit_turn) == turn_number else 0
	if newly_destroyed > 0:
		for key in row.stock:
			row.stock[key] = int(floor(float(row.stock[key]) * float(before_alive - newly_destroyed) / float(before_alive)))
			row.maximum_stock[key] = int(floor(float(row.maximum_stock[key]) * float(before_alive - newly_destroyed) / float(before_alive)))
	if int(counts.operational)+int(counts.moderate_damage)+int(counts.heavy_damage) == 0: row.disabled=true;row.disabled_reason="destroyed";row.throughput_credit_basis_points=0
	var event := _event(next,"status_applied",source_id,turn_number,{"ship_status_counts":counts.duplicate(true),"stock_before":stock_before,"stock_after":row.stock.duplicate(true)})
	_append(next,turn_number,event)
	return {"ok":true,"errors":[],"state":next,"event":event}

func capture_source(state: Dictionary, source_id: String, turn_number: int) -> Dictionary:
	var valid := _validate_state(state)
	if not valid.ok: return valid
	if not state.sources.has(source_id) or bool(state.sources[source_id].disabled): return _error("나포 가능한 보급함 재고 source가 아닙니다.")
	var next := state.duplicate(true); var row: Dictionary = next.sources[source_id]; var before:Dictionary = row.stock.duplicate(true)
	row.stock={"fuel_basis_points":0,"ammo_units":0,"supply_material_units":0};row.throughput_credit_basis_points=0;row.disabled=true;row.disabled_reason="captured";row.revision+=1
	row.ship_status_counts.captured = int(row.initial_ship_count)-int(row.ship_status_counts.destroyed);row.ship_status_counts.operational=0;row.ship_status_counts.moderate_damage=0;row.ship_status_counts.heavy_damage=0
	var event:=_event(next,"captured_discarded",source_id,turn_number,{"before":before,"after":row.stock.duplicate(true),"captor_gain":0});_append(next,turn_number,event)
	return {"ok":true,"errors":[],"state":next,"event":event}

func visible(viewer_faction_id: String, state: Dictionary) -> Dictionary:
	var providers: Array = [];var events:Array=[]; var ids: Array = state.get("sources",{}).keys(); ids.sort()
	for source_id in ids:
		var row: Dictionary = state.sources[source_id]
		if String(row.faction_id) != viewer_faction_id: continue
		providers.append({"source_id":String(source_id),"provider_squadron_id":String(row.provider_squadron_id),"faction_id":String(row.faction_id),
			"inventory":{"fuel":{"current":int(row.stock.fuel_basis_points),"maximum":int(row.maximum_stock.fuel_basis_points),"unit":"bp"},"ammo":{"current":int(row.stock.ammo_units),"maximum":int(row.maximum_stock.ammo_units),"unit":"units"},"supply_materials":{"current":int(row.stock.supply_material_units),"maximum":int(row.maximum_stock.supply_material_units),"unit":"units"}},
			"ship_status_counts":row.ship_status_counts.duplicate(true),"base_capacity_squadrons_per_turn":int(row.ship_status_counts.operational)+int(row.ship_status_counts.moderate_damage)+int(row.ship_status_counts.heavy_damage),"effective_throughput_basis_points_per_turn":_weighted_throughput(row),"available_capacity_squadrons_this_turn":capacity(String(source_id),state),
			"automatic_supply_enabled":not bool(row.disabled) and _has_all_stock(row),"disabled_reason":String(row.disabled_reason) if bool(row.disabled) else ("inventory_depleted" if not _has_all_stock(row) else ""),"reload":row.reload.duplicate(true)})
	var turns:Array=state.get("events_by_turn",{}).keys();turns.sort()
	for event_turn in turns:
		for event in state.events_by_turn[event_turn]:
			var source:Dictionary=state.sources.get(String(event.get("source_id","")),{})
			if String(source.get("faction_id",""))==viewer_faction_id:events.append(event.duplicate(true))
	events.sort_custom(func(a,b):return int(a.serial)<int(b.serial))
	return {"ok":true,"errors":[],"viewer_faction_id":viewer_faction_id,"providers":providers,"events":events,"contract":_rules.duplicate(true)}

func _validate_state(state: Dictionary) -> Dictionary:
	if not state.get("sources") is Dictionary or not state.get("events_by_turn") is Dictionary or not _nonnegative_int(state.get("next_event_serial")): return _error("보급함 재고 상태 schema가 잘못되었습니다.")
	for source_id in state.sources:
		var row: Dictionary = state.sources[source_id]
		if not row.get("stock") is Dictionary or not row.get("maximum_stock") is Dictionary or not row.get("ship_status_counts") is Dictionary: return _error("보급함 재고 source 상태가 잘못되었습니다.")
		for key in ["fuel_basis_points","ammo_units","supply_material_units"]:
			if not _nonnegative_int(row.stock.get(key)) or int(row.stock[key]) > int(row.maximum_stock.get(key,-1)): return _error("보급함 재고 범위가 잘못되었습니다.")
	return _ok()

func _monotonic(old: Dictionary, next: Dictionary) -> bool:
	return int(next.destroyed) >= int(old.destroyed) and int(next.heavy_damage)+int(next.destroyed) >= int(old.heavy_damage)+int(old.destroyed) and int(next.moderate_damage)+int(next.heavy_damage)+int(next.destroyed) >= int(old.moderate_damage)+int(old.heavy_damage)+int(old.destroyed)
func _has_all_stock(row: Dictionary) -> bool: return int(row.stock.fuel_basis_points)>0 and int(row.stock.ammo_units)>0 and int(row.stock.supply_material_units)>0
func _weighted_throughput(row: Dictionary) -> int:
	var counts: Dictionary = row.ship_status_counts
	return int(counts.operational) * 10000 + int(counts.moderate_damage) * 5000 + int(counts.heavy_damage) * 2500
func _same_faction_base(row: Dictionary, position: Array, bases: Array) -> Dictionary:
	if position.size()!=2:return {}
	for base in bases:
		if String(base.get("source_type",""))=="friendly_base" and String(base.faction_id)==String(row.faction_id) and Vector2(float(position[0]),float(position[1])).distance_to(Vector2(float(base.position[0]),float(base.position[1])))<=float(base.radius):return base
	return {}
func _actual_moved(squadron_id:String,events:Array)->bool:
	for event in events:
		if event is Dictionary and String(event.get("squadron_id",""))==squadron_id:return float(event.get("actual_distance",-1.0))>0.001
	return true
func _ship_count(squad:Dictionary,ship_id:String)->int:
	var count:=0;for component in squad.composition:
		if String(component.ship_type_id)==ship_id:count+=int(component.count)
	return count
func _event(state:Dictionary,status:String,source_id:String,turn_number:int,extra:Dictionary)->Dictionary:
	var serial:=int(state.next_event_serial);state.next_event_serial=serial+1;var event:={"event_id":"SUP-INV-%06d"%serial,"serial":serial,"event_type":"supply_inventory","status":status,"turn":turn_number,"source_id":source_id};event.merge(extra,true);return event
func _append(state:Dictionary,turn_number:int,event:Dictionary)->void:
	if not state.events_by_turn.has(turn_number):state.events_by_turn[turn_number]=[]
	state.events_by_turn[turn_number].append(event.duplicate(true))
func _nonnegative_int(value)->bool:return (value is int or value is float) and is_finite(float(value)) and float(value)>=0.0 and is_equal_approx(float(value),floor(float(value)))
func _ok()->Dictionary:return {"ok":true,"errors":[]}
func _error(message:String)->Dictionary:return {"ok":false,"errors":[message]}
