class_name RedCliffsCombatEffects
extends RefCounted

## DEMO-RC-G8-00 — 승인 사격과 연쇄 폭발의 실제 전투 효과 권위.
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const RULES_PATH := "res://data/red-cliffs-combat-effects-rules.json"
const CHAIN_RULES_PATH := "res://data/red-cliffs-chain-explosion-rules.json"
var _setup: Dictionary = {}
var _rules: Dictionary = {}
var _chain_rules: Dictionary = {}
var _ship_costs: Dictionary = {}

func initialize(applied_setup: Dictionary) -> Dictionary:
	var checked := Setup.validate_document(applied_setup)
	if not checked.ok: return _error("유효한 G3 적용 편성이 필요합니다.")
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null: return _error("전투 효과 규칙을 열 수 없습니다.")
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1 or String(parsed.get("profile_id", "")) != "normal-demo-combat-effects-v1": return _error("지원하지 않는 전투 효과 프로필입니다.")
	var accuracy: Dictionary = parsed.get("hit", {}).get("base_accuracy_basis_points", {})
	var damage: Dictionary = parsed.get("damage_points", {})
	var expected := ["artillery", "intercept", "line_fire", "torpedo"]
	var accuracy_ids: Array = accuracy.keys(); accuracy_ids.sort(); var damage_ids: Array = damage.keys(); damage_ids.sort()
	if accuracy_ids != expected or damage_ids != expected: return _error("무기별 명중·피해 표가 잘못되었습니다.")
	var hull_bands: Dictionary = parsed.get("hull_bands_basis_points", {})
	if int(parsed.get("hull_points_per_ship_unit_cost_point", 0)) != 10 or int(hull_bands.get("operational_min", 0)) != 7500 or int(hull_bands.get("moderate_damage_min", 0)) != 4000 or int(hull_bands.get("heavy_damage_min", 0)) != 1 or int(hull_bands.get("destroyed", -1)) != 0: return _error("hull 수치 계약이 잘못되었습니다.")
	var morale: Dictionary = parsed.get("morale", {})
	var morale_bands: Dictionary = morale.get("bands_basis_points", {})
	if int(morale.get("maximum_basis_points", 0)) != 10000 or int(morale.get("chain_shock_basis_points", 0)) != 3500 or int(morale_bands.get("steady_min", 0)) != 6000 or int(morale_bands.get("shaken_min", 0)) != 3000 or int(morale_bands.get("retreating_min", 0)) != 1 or int(morale_bands.get("surrendered", -1)) != 0: return _error("사기 수치 계약이 잘못되었습니다.")
	var chain: Dictionary = parsed.get("chain_explosion", {})
	if int(chain.get("reactor_damage_percent_of_pre_damage_maximum_hull", 0)) != 40 or int(chain.get("sensor_modifier_percent", 0)) != -40 or int(chain.get("sensor_duration_turns", 0)) != 2: return _error("연쇄 폭발 효과 계약이 잘못되었습니다.")
	var chain_file := FileAccess.open(CHAIN_RULES_PATH, FileAccess.READ)
	if chain_file == null: return _error("G5-06 연쇄 폭발 규칙을 열 수 없습니다.")
	var chain_parsed = JSON.parse_string(chain_file.get_as_text())
	if not chain_parsed is Dictionary or String(chain_parsed.get("profile_id", "")) != "normal-demo-chain-explosion-v1": return _error("G5-06 연쇄 폭발 규칙이 잘못되었습니다.")
	_setup = checked.setup.duplicate(true); _rules = parsed.duplicate(true); _chain_rules = chain_parsed.duplicate(true); _ship_costs = {}
	for ship in _setup.ship_types: _ship_costs[String(ship.id)] = int(ship.unit_cost)
	return _ok()

func rules_snapshot() -> Dictionary: return _rules.duplicate(true)

func initial_state() -> Dictionary:
	var squadrons := {}
	for squad in _setup.squadrons:
		if not bool(squad.get("operational", true)): continue
		var original := _normalized_composition(squad.composition); var maximum := 0
		for row in original: maximum += int(row.count) * int(_ship_costs[row.ship_type_id]) * int(_rules.hull_points_per_ship_unit_cost_point)
		squadrons[String(squad.id)] = {"squadron_id":String(squad.id),"faction_id":String(squad.faction_id),
			"original_composition":original.duplicate(true),"current_composition":original.duplicate(true),"maximum_hull_points":maximum,"hull_points":maximum,
			"casualties_total":0,"damage_state":"operational","morale_basis_points":10000,"morale_status":"steady","sensor_disruptions":[],
			"capabilities":{"operational":true,"can_command":true,"can_attack":true,"can_change_mission":true,"forced_retreat":false,"surrendered":false}}
	return {"squadrons":squadrons,"processed_event_ids":[],"temporary_terrain_zones":{},"events_by_turn":{},"next_event_serial":1}

func resolve(prior_state: Dictionary, shot_events: Array, chain_events: Array, navigation: Dictionary,
		sealed_contact_targets: Dictionary, turn_number: int) -> Dictionary:
	var valid := _validate_state(prior_state)
	if not valid.ok: return valid
	if turn_number < 1: return _error("전투 효과 턴이 잘못되었습니다.")
	var shots := shot_events.duplicate(true); var chains := chain_events.duplicate(true)
	var seen := {}; var processed: Array = prior_state.processed_event_ids
	for value in shots + chains:
		if not value is Dictionary: return _error("전투 효과 입력은 객체여야 합니다.")
		if not value.get("event_id") is String or not _integer(value.get("turn")): return _error("전투 효과 event ID·turn 타입이 잘못되었습니다.")
		var event_id := String(value.event_id)
		if event_id.is_empty() or seen.has(event_id) or processed.has(event_id) or int(value.turn) != turn_number: return _error("전투 효과 event ID·turn·replay 경계가 잘못되었습니다.")
		seen[event_id] = true
	shots.sort_custom(func(a,b): return String(a.event_id) < String(b.event_id))
	chains.sort_custom(func(a,b): return String(a.event_id) < String(b.event_id))
	var aggregates := {}; var source_events: Array = []
	for event in shots:
		var payload_valid := _validate_shot_payload(event)
		if not payload_valid.ok: return payload_valid
		var outcome := String(event.get("outcome", "")); var shooter_id := String(event.get("shooter_squadron_id", "")); var target_id := String(event.get("target_squadron_id", ""))
		if not ["shot_authorized","estimated_fire_authorized"].has(outcome) or not prior_state.squadrons.has(shooter_id): return _error("승인 사격 효과 입력이 잘못되었습니다.")
		if outcome == "estimated_fire_authorized": target_id = String(sealed_contact_targets.get(String(event.get("contact_id", "")), ""))
		if not prior_state.squadrons.has(target_id) or String(prior_state.squadrons[shooter_id].faction_id) == String(prior_state.squadrons[target_id].faction_id): return _error("승인 사격의 봉인 target 매핑이 잘못되었습니다.")
		var weapon_id := String(event.get("selected_weapon_id", "")); if not _rules.damage_points.has(weapon_id): return _error("미지 무기 피해 입력입니다.")
		var target_navigation = navigation.get(target_id, {})
		if outcome == "estimated_fire_authorized" and (not target_navigation is Dictionary or not _valid_point(target_navigation.get("position"))): return _error("추정 사격 actual target navigation이 잘못되었습니다.")
		var chance := _accuracy(event, outcome); var impact_gate := _estimated_impact(event, target_navigation.get("position", []), weapon_id) if outcome == "estimated_fire_authorized" else true
		var roll := _roll(String(event.event_id), turn_number); var hit := impact_gate and roll < chance; var damage := int(_rules.damage_points[weapon_id]) if hit else 0
		var aggregate := _aggregate(aggregates, target_id); aggregate.damage += damage; aggregate.normal_damage += damage
		if hit:
			var target_maximum := int(prior_state.squadrons[target_id].maximum_hull_points)
			aggregate.normal_morale += maxi(int(_rules.morale.normal_hit_minimum_loss_basis_points), int(ceil(float(damage * 10000) / float(target_maximum * int(_rules.morale.normal_hit_damage_ratio_divisor)))))
		aggregate.source_event_ids.append(String(event.event_id))
		source_events.append({"event_id":"FX-%s"%String(event.event_id),"event_type":"shot_effect_resolved","turn":turn_number,"source_event_id":String(event.event_id),
			"shooter_squadron_id":shooter_id,"target_squadron_id":target_id,"weapon_id":weapon_id,"authorization_type":outcome,"hit":hit,
			"accuracy_basis_points":chance,"roll_basis_points":roll,"estimated_impact_gate":impact_gate,"damage_points":damage})
	for event in chains:
		var chain_valid := _validate_chain_payload(event, prior_state, turn_number)
		if not chain_valid.ok: return chain_valid
		var target_id := String(event.get("target_squadron_id", "")); if not prior_state.squadrons.has(target_id): return _error("연쇄 폭발 target이 잘못되었습니다.")
		var target_navigation = navigation.get(target_id, {})
		if not target_navigation is Dictionary or not _valid_point(target_navigation.get("position")): return _error("연쇄 폭발 target navigation이 잘못되었습니다.")
		var target: Dictionary = prior_state.squadrons[target_id]; var damage := maxi(1, int(floor(float(target.maximum_hull_points) * 0.4)))
		var aggregate := _aggregate(aggregates, target_id); aggregate.damage += damage; aggregate.chain_morale += int(_rules.morale.chain_shock_basis_points); aggregate.chain_trigger_ids.append(String(event.event_id)); aggregate.source_event_ids.append(String(event.event_id))
		var disruption := {"source_event_id":String(event.event_id),"modifier_percent":int(_rules.chain_explosion.sensor_modifier_percent),"active_from_turn":turn_number+1,"expires_after_turn":turn_number+int(_rules.chain_explosion.sensor_duration_turns)}
		aggregate.sensor_disruptions.append(disruption)
		var hazard := _hazard(event, target_navigation.position, turn_number)
		if hazard.is_empty(): return _error("연쇄 폭발 임시 지형 위치가 누락되었습니다.")
		aggregate.hazards.append(hazard)
		source_events.append({"event_id":"FX-%s"%String(event.event_id),"event_type":"chain_effects_applied","turn":turn_number,"source_event_id":String(event.event_id),"target_squadron_id":target_id,
			"damage_points":damage,"morale_loss_basis_points":int(_rules.morale.chain_shock_basis_points),"sensor_disruption":disruption.duplicate(true),"temporary_terrain_zone_id":String(hazard.zone_id)})
		source_events.append({"event_id":"FX-HAZARD-%s"%String(event.event_id),"event_type":"temporary_terrain_created","turn":turn_number,"source_event_id":String(event.event_id),"temporary_terrain_zone_id":String(hazard.zone_id)})
	var next := prior_state.duplicate(true); var effect_events: Array = source_events; var supply_statuses: Array = []; var target_ids: Array = aggregates.keys(); target_ids.sort()
	for target_id in target_ids:
		var before: Dictionary = prior_state.squadrons[target_id]; var row: Dictionary = next.squadrons[target_id]; var aggregate: Dictionary = aggregates[target_id]
		var applied_damage := mini(int(row.hull_points), int(aggregate.damage)); row.hull_points -= applied_damage
		var target_losses := int(floor(float(_ship_total(row.original_composition) * (int(row.maximum_hull_points) - int(row.hull_points))) / float(row.maximum_hull_points)))
		if int(row.hull_points) == 0: target_losses = _ship_total(row.original_composition)
		var casualty_delta := maxi(0, target_losses - int(row.casualties_total)); row.casualties_total = target_losses; row.current_composition = _composition_after_losses(row.original_composition, target_losses)
		var normal_morale := int(aggregate.normal_morale)
		var morale_loss := normal_morale + int(aggregate.chain_morale) + casualty_delta * int(_rules.morale.ship_loss_penalty_each_basis_points)
		row.morale_basis_points = maxi(0, int(row.morale_basis_points) - morale_loss)
		if int(row.hull_points) == 0: row.morale_basis_points = 0
		row.damage_state = _damage_state(row); row.morale_status = _morale_status(int(row.morale_basis_points)); row.sensor_disruptions.append_array(aggregate.sensor_disruptions); row.capabilities = _capabilities(row)
		for hazard in aggregate.hazards: next.temporary_terrain_zones[String(hazard.zone_id)] = hazard.duplicate(true)
		var applied_event := _event(next,"squadron_effect_applied",turn_number,{"target_squadron_id":String(target_id),"source_event_ids":aggregate.source_event_ids.duplicate(),
			"before":_snapshot(before,turn_number),"after":_snapshot(row,turn_number),"damage_applied":applied_damage,"casualties_delta":casualty_delta,"morale_loss_basis_points":morale_loss})
		effect_events.append(applied_event)
		var original_supply_count := _supply_ship_count(row.original_composition)
		if original_supply_count > 0:
			supply_statuses.append({"provider_squadron_id":String(target_id),"damage_state":String(row.damage_state),
				"original_ship_count":original_supply_count,"surviving_ship_count":_supply_ship_count(row.current_composition)})
	for event_id in seen.keys(): next.processed_event_ids.append(String(event_id))
	next.processed_event_ids.sort(); effect_events.sort_custom(func(a,b): return String(a.get("event_id","")) < String(b.get("event_id","")))
	for event in effect_events: _append(next,turn_number,event)
	return {"ok":true,"errors":[],"state":next,"events":effect_events,"supply_ship_statuses":supply_statuses,"victory_inputs":victory_inputs(next,turn_number)}

func active_temporary_zones(state: Dictionary, turn_number: int) -> Array:
	var result: Array = []; var ids: Array = state.get("temporary_terrain_zones",{}).keys(); ids.sort()
	for id in ids:
		var row: Dictionary = state.temporary_terrain_zones[id]
		if turn_number >= int(row.active_from_turn) and turn_number <= int(row.expires_after_turn):
			var active: Dictionary = row.duplicate(true); active["status"] = "active"; active.erase("source_event_id"); result.append(active)
	return result

func sensor_modifier_percent(state: Dictionary, squadron_id: String, turn_number: int) -> int:
	var total := 0
	for row in state.get("squadrons",{}).get(squadron_id,{}).get("sensor_disruptions",[]):
		if turn_number >= int(row.active_from_turn) and turn_number <= int(row.expires_after_turn): total += int(row.modifier_percent)
	return clampi(total,-80,0)

func attack_locked_ids(state: Dictionary) -> Array:
	var result: Array = []
	for id in state.get("squadrons",{}):
		if not bool(state.squadrons[id].capabilities.can_attack): result.append(String(id))
	result.sort(); return result

func terminal_ids(state: Dictionary) -> Array:
	var result: Array = []
	for id in state.get("squadrons",{}):
		if not bool(state.squadrons[id].capabilities.operational): result.append(String(id))
	result.sort(); return result

func victory_inputs(state: Dictionary, turn_number: int) -> Dictionary:
	var factions := {}; var ids: Array = state.squadrons.keys(); ids.sort()
	for id in ids:
		var row: Dictionary = state.squadrons[id]; var faction_id := String(row.faction_id)
		if not factions.has(faction_id): factions[faction_id] = {"maximum_hull_points":0,"remaining_hull_points":0,"original_ship_count":0,"remaining_ship_count":0,"morale_basis_points_total":0,"operational_squadron_count":0}
		var total: Dictionary = factions[faction_id]; total.maximum_hull_points += int(row.maximum_hull_points); total.remaining_hull_points += int(row.hull_points); total.original_ship_count += _ship_total(row.original_composition); total.remaining_ship_count += _ship_total(row.current_composition); total.morale_basis_points_total += int(row.morale_basis_points)
		if bool(row.capabilities.operational): total.operational_squadron_count += 1
	return {"turn":turn_number,"factions":factions,"commander_casualties_pending":true,"victory_status":"pending_G8_01","winner_present":false}

func visible(viewer_faction_id: String, state: Dictionary, contacts: Array, turn_number: int) -> Dictionary:
	var own: Array = []; var public_contacts: Array = []; var target_to_contact := {}; var contact_states := {}
	var ids: Array = state.get("squadrons",{}).keys(); ids.sort()
	for id in ids:
		var row: Dictionary = state.squadrons[id]
		if String(row.faction_id) == viewer_faction_id: own.append(_public_own(row,turn_number))
	for value in contacts:
		if not value is Dictionary: continue
		var visible_state := String(value.get("state", "undetected"))
		if not ["confirmed", "estimated"].has(visible_state): continue
		var target_id := String(value.get("target_squadron_id","")); if target_id.is_empty() or not state.squadrons.has(target_id): continue
		var contact_id := String(value.get("contact_id","")); target_to_contact[target_id] = contact_id; contact_states[contact_id] = visible_state; var row: Dictionary = state.squadrons[target_id]
		public_contacts.append({"contact_id":contact_id,"state":visible_state,"display_position":value.get("display_position"),"effect_band":_effect_band(row),
			"damage_label":_damage_label(String(row.damage_state)),"morale_label":_morale_public_label(String(row.morale_status)),"sensor_label":"교란 징후" if sensor_modifier_percent(state,target_id,turn_number)<0 else "교란 미확인"})
	var visible_events: Array = []; var turns: Array = state.get("events_by_turn",{}).keys(); turns.sort()
	for event_turn in turns:
		for raw in state.events_by_turn[event_turn]:
			if String(raw.get("event_type",""))=="temporary_terrain_created":visible_events.append(_visible_event(raw,"","","public_hazard"));continue
			var target_id := String(raw.get("target_squadron_id","")); var shooter_id := String(raw.get("shooter_squadron_id","")); var own_id := target_id if state.squadrons.has(target_id) and String(state.squadrons[target_id].faction_id)==viewer_faction_id else ""
			var contact_id := String(target_to_contact.get(target_id,target_to_contact.get(shooter_id,""))); if own_id.is_empty() and contact_id.is_empty(): continue
			visible_events.append(_visible_event(raw,own_id,contact_id,"own" if not own_id.is_empty() else ("estimated_contact" if String(contact_states.get(contact_id,""))=="estimated" else "confirmed_contact")))
	return {"ok":true,"errors":[],"viewer_faction_id":viewer_faction_id,"turn":turn_number,"own_squadrons":own,"contacts":public_contacts,"events":visible_events,
		"temporary_terrain_zones":active_temporary_zones(state,turn_number),"victory_boundary":{"status":"pending_G8_01","input_ready":true,"winner_present":false}}

func _validate_chain_payload(event: Dictionary, state: Dictionary, turn_number: int) -> Dictionary:
	if not event.get("event_type") is String or String(event.event_type) != "chain_explosion_triggered": return _error("연쇄 폭발 event type이 잘못되었습니다.")
	if String(event.event_id) != "CHAIN-TRIGGER-%02d" % turn_number: return _error("연쇄 폭발 trigger ID가 G5-06 정본과 다릅니다.")
	for key in ["source_squadron_id", "target_squadron_id"]:
		if not event.get(key) is String or String(event[key]).is_empty(): return _error("연쇄 폭발 source/target 타입이 잘못되었습니다.")
	var source_id := String(event.source_squadron_id); var target_id := String(event.target_squadron_id)
	var expected_source := String(_chain_rules.get("allied_operation_detachment", {}).get("host_squadron_id", ""))
	if source_id != expected_source or not state.squadrons.has(source_id) or String(state.squadrons[source_id].faction_id) != String(_chain_rules.allied_asset_faction_id): return _error("연쇄 폭발 source/faction이 G5-06 정본과 다릅니다.")
	if not state.squadrons.has(target_id) or String(state.squadrons[target_id].faction_id) != String(_chain_rules.target_faction_id) or source_id == target_id: return _error("연쇄 폭발 target faction이 G5-06 정본과 다릅니다.")
	if event.get("effect_intents") != _chain_rules.effect_intents or event.get("effects_pending") != _chain_rules.effects_pending: return _error("연쇄 폭발 effect intent/pending 경계가 잘못되었습니다.")
	if not event.get("irreversible") is bool or not bool(event.irreversible) or not event.get("probability_roll_used") is bool or bool(event.probability_roll_used): return _error("연쇄 폭발 irreversible/probability 경계가 잘못되었습니다.")
	if not event.get("conditions") is Array: return _error("연쇄 폭발 conditions payload가 잘못되었습니다.")
	for condition in event.conditions:
		if not condition is Dictionary: return _error("연쇄 폭발 condition row가 잘못되었습니다.")
	return _ok()

func _validate_shot_payload(event: Dictionary) -> Dictionary:
	for key in ["outcome", "shooter_squadron_id", "selected_weapon_id"]:
		if not event.get(key) is String or String(event[key]).is_empty(): return _error("승인 사격 문자열 payload가 잘못되었습니다: %s" % key)
	if String(event.outcome) == "shot_authorized" and (not event.get("target_squadron_id") is String or String(event.target_squadron_id).is_empty()): return _error("확정 사격 target payload가 잘못되었습니다.")
	var formation = event.get("formation_modifier")
	if not formation is Dictionary: return _error("승인 사격 formation_modifier는 객체여야 합니다.")
	var shooter = formation.get("shooter"); var target = formation.get("target")
	if not shooter is Dictionary or not target is Dictionary: return _error("승인 사격 formation shooter/target은 객체여야 합니다.")
	if not _integer(shooter.get("fire_percent")) or not _integer(target.get("total_defense_percent")): return _error("승인 사격 formation percent 타입이 잘못되었습니다.")
	var command = event.get("command_penalty")
	if not command is Dictionary or not _bounded_basis_points(command.get("accuracy_basis_points")): return _error("승인 사격 command accuracy payload가 잘못되었습니다.")
	if event.has("terrain_weapon_modifier"):
		var terrain = event.terrain_weapon_modifier
		if not terrain is Dictionary or not terrain.get("zone_ids") is Array or not _integer(terrain.get("range_basis_points")) or int(terrain.range_basis_points) < 0 or not _finite_number(terrain.get("arc_delta_deg")) or not terrain.get("target_source") is String or not terrain.get("rounding") is String: return _error("승인 사격 terrain payload가 잘못되었습니다.")
		for zone_id in terrain.zone_ids:
			if not zone_id is String: return _error("승인 사격 terrain zone ID 타입이 잘못되었습니다.")
	if String(event.outcome) == "estimated_fire_authorized":
		if not event.get("contact_id") is String or String(event.contact_id).is_empty() or not _valid_point(event.get("aim_position")) or not _bounded_basis_points(event.get("confidence_basis_points")): return _error("추정 사격 contact·aim·confidence payload가 잘못되었습니다.")
		for point_key in ["last_known_position", "error_offset"]:
			if event.has(point_key) and not _valid_point(event[point_key]): return _error("추정 사격 %s payload가 잘못되었습니다." % point_key)
		for integer_key in ["last_seen_turn", "staleness_turns", "error_radius"]:
			if event.has(integer_key) and (not _integer(event[integer_key]) or int(event[integer_key]) < 0): return _error("추정 사격 %s payload가 잘못되었습니다." % integer_key)
	return _ok()

func _valid_point(value) -> bool:
	return value is Array and value.size() == 2 and _finite_number(value[0]) and _finite_number(value[1])
func _finite_number(value) -> bool: return (value is int or value is float) and is_finite(float(value))
func _integer(value) -> bool: return _finite_number(value) and is_equal_approx(float(value), floor(float(value)))
func _bounded_basis_points(value) -> bool: return _integer(value) and int(value) >= 0 and int(value) <= 10000

func _accuracy(event: Dictionary, outcome: String) -> int:
	var weapon_id := String(event.selected_weapon_id); var base := int(_rules.hit.base_accuracy_basis_points[weapon_id]); var formation: Dictionary = event.get("formation_modifier",{})
	var fire_percent := int(formation.get("shooter",{}).get("fire_percent",0)); var defense_percent := int(formation.get("target",{}).get("total_defense_percent",0))
	var chance := clampi(base+(fire_percent-defense_percent)*100,int(_rules.hit.minimum_basis_points),int(_rules.hit.maximum_basis_points))
	chance = _half_up(chance,int(event.get("command_penalty",{}).get("accuracy_basis_points",10000)))
	if outcome == "estimated_fire_authorized": chance = _half_up(chance,int(event.get("confidence_basis_points",0)))
	return clampi(chance,0,10000)

func _estimated_impact(event: Dictionary, target_position, weapon_id: String) -> bool:
	var aim = event.get("aim_position",[]); if not aim is Array or aim.size()!=2 or not target_position is Array or target_position.size()!=2:return false
	return Vector2(float(aim[0]),float(aim[1])).distance_to(Vector2(float(target_position[0]),float(target_position[1]))) <= float(_rules.hit.impact_radius[weapon_id])+0.001

func _roll(event_id: String, turn_number: int) -> int: return int(("%s|%d|%s"%[_rules.profile_id,turn_number,event_id]).sha256_text().substr(0,8).hex_to_int()%10000)
func _half_up(value: int, basis_points: int) -> int: return int(floor(float(value*basis_points+5000)/10000.0))
func _aggregate(values: Dictionary, target_id: String) -> Dictionary:
	if not values.has(target_id): values[target_id]={"damage":0,"normal_damage":0,"normal_morale":0,"chain_morale":0,"sensor_disruptions":[],"hazards":[],"source_event_ids":[],"chain_trigger_ids":[]}
	return values[target_id]

func _hazard(event: Dictionary, position, turn_number: int) -> Dictionary:
	if not position is Array or position.size()!=2:return {}
	var rule: Dictionary = _rules.chain_explosion.temporary_terrain; var bounds: Array = _setup.battlefield_bounds; var width:=float(rule.width);var height:=float(rule.height)
	var x:=clampf(float(position[0])-width*0.5,float(bounds[0]),float(bounds[0]+bounds[2])-width);var y:=clampf(float(position[1])-height*0.5,float(bounds[1]),float(bounds[1]+bounds[3])-height)
	return {"zone_id":"TMP-CHAIN-%02d-%s"%[turn_number,String(event.event_id).sha256_text().substr(0,8)],"terrain_type":"temporary_chain_hazard","name":String(rule.name),
		"shape":{"kind":"rect","x":x,"y":y,"width":width,"height":height},"effects":rule.effects.duplicate(true),"source_event_id":String(event.event_id),
		"active_from_turn":turn_number+int(rule.active_from_turn_offset),"expires_after_turn":turn_number+int(rule.duration_turns),"status":"scheduled"}

func _normalized_composition(values: Array) -> Array:
	var totals := {}; for value in values: totals[String(value.ship_type_id)] = int(totals.get(String(value.ship_type_id),0))+int(value.count)
	var ids: Array = totals.keys(); ids.sort(); var result: Array=[]; for id in ids: result.append({"ship_type_id":String(id),"count":int(totals[id])})
	return result
func _composition_after_losses(original: Array, losses: int) -> Array:
	var remaining:=losses;var result:Array=[]
	for value in original:
		var lost:=mini(remaining,int(value.count));remaining-=lost;var count:=int(value.count)-lost
		if count>0:result.append({"ship_type_id":String(value.ship_type_id),"count":count})
	return result
func _ship_total(values: Array)->int:
	var total:=0;for value in values:total+=int(value.count)
	return total
func _supply_ship_count(values:Array)->int:
	for value in values:
		if String(value.ship_type_id)=="SHP-05":return int(value.count)
	return 0
func _damage_state(row:Dictionary)->String:
	if int(row.hull_points)<=0:return "destroyed"
	var ratio:=int(floor(float(row.hull_points*10000)/float(row.maximum_hull_points)))
	if ratio>=7500:return "operational"
	if ratio>=4000:return "moderate_damage"
	return "heavy_damage"
func _morale_status(value:int)->String:
	if value>=6000:return "steady"
	if value>=3000:return "shaken"
	if value>=1:return "retreating"
	return "surrendered"
func _capabilities(row:Dictionary)->Dictionary:
	var operational:=int(row.hull_points)>0 and String(row.morale_status)!="surrendered";var retreating:=String(row.morale_status)=="retreating"
	return {"operational":operational,"can_command":operational,"can_attack":operational and not retreating,"can_change_mission":operational and not retreating,"forced_retreat":operational and retreating,"surrendered":String(row.morale_status)=="surrendered"}
func _snapshot(row:Dictionary,turn_number:int)->Dictionary:return {"hull_points":int(row.hull_points),"maximum_hull_points":int(row.maximum_hull_points),"current_composition":row.current_composition.duplicate(true),"casualties_total":int(row.casualties_total),"damage_state":String(row.damage_state),"morale_basis_points":int(row.morale_basis_points),"morale_status":String(row.morale_status),"sensor_modifier_percent":sensor_modifier_percent({"squadrons":{String(row.squadron_id):row}},String(row.squadron_id),turn_number),"capabilities":row.capabilities.duplicate(true)}
func _public_own(row:Dictionary,turn_number:int)->Dictionary:
	var snap:=_snapshot(row,turn_number);return {"squadron_id":String(row.squadron_id),"faction_id":String(row.faction_id),"hull":{"current":snap.hull_points,"maximum":snap.maximum_hull_points,"damage_taken":snap.maximum_hull_points-snap.hull_points},"composition_current":snap.current_composition,"casualties_total":snap.casualties_total,"damage_state":snap.damage_state,"morale":{"current":snap.morale_basis_points,"maximum":10000,"status":snap.morale_status,"next_risk_threshold":_next_morale_threshold(snap.morale_status)},"sensor":{"modifier_percent":snap.sensor_modifier_percent,"status":"disrupted" if snap.sensor_modifier_percent<0 else "normal","effective_from_turn":_sensor_from(row),"expires_after_turn":_sensor_expiry(row)},"capabilities":snap.capabilities}
func _next_morale_threshold(status:String)->int:return 5999 if status=="steady" else (2999 if status=="shaken" else (0 if status=="retreating" else 0))
func _sensor_from(row:Dictionary)->int:return int(row.sensor_disruptions.back().active_from_turn) if not row.sensor_disruptions.is_empty() else 0
func _sensor_expiry(row:Dictionary)->int:return int(row.sensor_disruptions.back().expires_after_turn) if not row.sensor_disruptions.is_empty() else 0
func _effect_band(row:Dictionary)->String:return "neutralized" if not bool(row.capabilities.operational) else ("intact" if row.damage_state=="operational" else ("damaged" if row.damage_state=="moderate_damage" else "critical"))
func _damage_label(status:String)->String:return {"operational":"외관상 전투 가능","moderate_damage":"손상 관측","heavy_damage":"심각한 손상","destroyed":"전투 불능"}.get(status,"상태 미확인")
func _morale_public_label(status:String)->String:return {"steady":"대형 유지","shaken":"동요 징후","retreating":"붕괴·퇴각 징후","surrendered":"항복 확인"}.get(status,"사기 미확인")
func _visible_event(raw:Dictionary,own_id:String,contact_id:String,viewer_state:String)->Dictionary:
	var event_type:=String(raw.event_type);var headline:="전투 효과 적용";var details:Array[String]=[]
	if event_type=="shot_effect_resolved":headline="사격 명중" if bool(raw.hit) else "사격 빗나감";details.append("피해 %d"%int(raw.damage_points) if bool(raw.hit) else "피해 없음")
	elif event_type=="chain_effects_applied":headline="연쇄 폭발 효과 적용";details=["대규모 피해","사기 충격","센서 교란","임시 위험 지대 생성"]
	elif event_type=="squadron_effect_applied":headline="전대 상태 갱신";details=["피해 %d"%int(raw.damage_applied),"함선 손실 %d"%int(raw.casualties_delta),"사기 -%d bp"%int(raw.morale_loss_basis_points)]
	elif event_type=="temporary_terrain_created":headline="임시 위험 지대 생성";details=["다음 턴부터 2턴간 적용"]
	if ["confirmed_contact","estimated_contact"].has(viewer_state):
		if event_type=="shot_effect_resolved": details=["관측 가능한 명중 징후" if bool(raw.hit) else "명중 징후 없음"]
		elif event_type=="squadron_effect_applied": details=["관측 band 갱신"]
	return {"event_id":String(raw.event_id),"turn":int(raw.turn),"event_type":event_type,"viewer_state":viewer_state,"own_squadron_id":own_id,"contact_id":contact_id,"headline":headline,"details":details}
func _event(state:Dictionary,event_type:String,turn_number:int,extra:Dictionary)->Dictionary:
	var serial:=int(state.next_event_serial);state.next_event_serial=serial+1;var event:={"event_id":"CFX-%02d-%06d"%[turn_number,serial],"event_type":event_type,"turn":turn_number};event.merge(extra,true);return event
func _append(state:Dictionary,turn_number:int,event:Dictionary)->void:
	if not state.events_by_turn.has(turn_number):state.events_by_turn[turn_number]=[]
	state.events_by_turn[turn_number].append(event.duplicate(true))
func _validate_state(state:Dictionary)->Dictionary:
	if not state.get("squadrons") is Dictionary or not state.get("processed_event_ids") is Array or not state.get("temporary_terrain_zones") is Dictionary or not state.get("events_by_turn") is Dictionary:return _error("전투 효과 상태 schema가 잘못되었습니다.")
	return _ok()
func _ok()->Dictionary:return {"ok":true,"errors":[]}
func _error(message:String)->Dictionary:return {"ok":false,"errors":[message]}
