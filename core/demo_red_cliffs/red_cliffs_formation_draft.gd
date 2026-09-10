class_name RedCliffsFormationDraft
extends RefCounted

## DEMO-RC-G3-01 — 비용 기반 전대·함대 편성 편집기 (Phase A core reducer).
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")

var _historical: Dictionary = {}
var _applied: Dictionary = {}
var _draft: Dictionary = {}


func _init(validated_setup: Dictionary = {}) -> void:
	if not validated_setup.is_empty(): configure(validated_setup)


func configure(historical_setup: Dictionary, applied_setup: Dictionary = {}) -> Dictionary:
	var historical_result := Setup.validate_document(historical_setup)
	if not historical_result.ok: return historical_result
	var current_input := historical_setup if applied_setup.is_empty() else applied_setup
	var applied_result := Setup.validate_document(current_input)
	if not applied_result.ok: return applied_result
	_draft = historical_result.setup.duplicate(true)
	_normalize_all_flagships()
	_historical = _draft.duplicate(true)
	_draft = applied_result.setup.duplicate(true)
	_normalize_all_flagships()
	_applied = _draft.duplicate(true)
	return _ok()


func historical_snapshot() -> Dictionary: return _historical.duplicate(true)
func applied_snapshot() -> Dictionary: return _applied.duplicate(true)
func draft_snapshot() -> Dictionary: return _draft.duplicate(true)
func applied_digest() -> String: return JSON.stringify(_applied)
func draft_digest() -> String: return JSON.stringify(_draft)


func can_edit_faction(faction_id: String) -> bool:
	if faction_id == "liu_bei": return true
	if faction_id == "sun_quan": return bool(_draft.get("formation_options", {}).get("sun_manual", false))
	return false


func set_sun_manual(enabled: bool) -> Dictionary:
	_draft["formation_options"]["sun_manual"] = enabled
	if not enabled: _restore_faction_from_applied("sun_quan")
	return _ok()


func set_ship_count(squadron_id: String, ship_type_id: String, count: int) -> Dictionary:
	var target := _editable_squad(squadron_id)
	if not target.ok: return target
	if count < 0: return _error("함종 수량은 0 이상이어야 합니다.")
	if not _ship_index().has(ship_type_id): return _error("미지 함종입니다: %s" % ship_type_id)
	var squad: Dictionary = target.squad
	var row := _composition_row(squad, ship_type_id)
	if row.is_empty():
		row = {"ship_type_id": ship_type_id, "count": count}
		if ship_type_id == Setup.FAST_CRAFT_ID: row["mission_equipment_id"] = Setup.REQUIRED_FAST_EQUIPMENT[0]
		squad.composition.append(row)
	else: row.count = count
	_recalculate_cost(squad)
	return _ok()


func set_fast_equipment(squadron_id: String, equipment_id: String) -> Dictionary:
	var target := _editable_squad(squadron_id)
	if not target.ok: return target
	if not _equipment_index().has(equipment_id): return _error("미지 고속정 임무장비입니다: %s" % equipment_id)
	var row := _composition_row(target.squad, Setup.FAST_CRAFT_ID)
	if row.is_empty(): return _error("고속정 구성 행이 없습니다.")
	row.mission_equipment_id = equipment_id; _recalculate_cost(target.squad)
	return _ok()


func set_commander(squadron_id: String, commander_id: String) -> Dictionary:
	var target := _editable_squad(squadron_id)
	if not target.ok: return target
	var roster := _roster_index(String(target.squad.faction_id))
	if not roster.has(commander_id): return _error("같은 세력의 가용 장수가 아닙니다.")
	for value in _draft.squadrons:
		var other: Dictionary = value
		if String(other.id) != squadron_id and String(other.faction_id) == String(target.squad.faction_id) and String(other.commander.id) == commander_id:
			return _error("지휘관은 두 전대에 중복 배치할 수 없습니다.")
	target.squad.commander = {"id": commander_id, "name": String(roster[commander_id].name)}
	_normalize_all_flagships()
	return _ok()


func set_formation(squadron_id: String, formation_id: String) -> Dictionary:
	var target := _editable_squad(squadron_id)
	if not target.ok: return target
	if not Setup.ALLOWED_FORMATION_IDS.has(formation_id): return _error("FRM-01~07 진형만 선택할 수 있습니다.")
	target.squad.formation_id = formation_id; return _ok()


func set_position(squadron_id: String, position: Vector2) -> Dictionary:
	var target := _editable_squad(squadron_id)
	if not target.ok: return target
	var bounds: Array = _draft.battlefield_bounds
	if position.x < bounds[0] or position.y < bounds[1] or position.x > bounds[0] + bounds[2] or position.y > bounds[1] + bounds[3]: return _error("초기 좌표가 1600×900 전장 유효 경계 밖입니다.")
	target.squad.initial_position = [position.x, position.y]; return _ok()


func create_fleet(faction_id: String, name: String, squadron_ids: Array) -> Dictionary:
	if not can_edit_faction(faction_id): return _error(_permission_reason(faction_id))
	if name.strip_edges().is_empty() or squadron_ids.is_empty(): return _error("함대 이름과 최소 1개 전대가 필요합니다.")
	var unique_ids := {}
	for sid_value in squadron_ids:
		var sid := String(sid_value)
		if unique_ids.has(sid): return _error("같은 전대를 함대에 두 번 편입할 수 없습니다.")
		unique_ids[sid] = true
		var squad := _find_squad(sid)
		if squad.is_empty() or String(squad.faction_id) != faction_id: return _error("함대에는 같은 세력 전대만 편입할 수 있습니다.")
	var serial := 1; var fleet_id := ""
	while fleet_id.is_empty() or not _find_fleet(fleet_id).is_empty():
		fleet_id = "RC-USER-%s-FLT-%02d" % [faction_id.to_upper(), serial]; serial += 1
	for sid_value in squadron_ids:
		_remove_from_all_fleets(String(sid_value))
	_draft.fleet_groups.append({"id": fleet_id, "faction_id": faction_id, "name": name.strip_edges(), "squadron_ids": squadron_ids.duplicate(), "flagship_squadron_id": ""})
	for sid_value in squadron_ids:
		_find_squad(String(sid_value)).deployment = {"kind": "fleet", "fleet_id": fleet_id}
	_normalize_all_flagships()
	return {"ok": true, "errors": [], "fleet_id": fleet_id}


func rename_fleet(fleet_id: String, name: String) -> Dictionary:
	var fleet := _find_fleet(fleet_id)
	if fleet.is_empty(): return _error("미지 함대입니다.")
	if not can_edit_faction(String(fleet.faction_id)): return _error(_permission_reason(String(fleet.faction_id)))
	if name.strip_edges().is_empty(): return _error("함대 이름은 비울 수 없습니다.")
	fleet.name = name.strip_edges(); return _ok()


func assign_to_fleet(squadron_id: String, fleet_id: String) -> Dictionary:
	var target := _editable_squad(squadron_id)
	if not target.ok: return target
	var fleet := _find_fleet(fleet_id)
	if fleet.is_empty(): return _error("미지 함대입니다.")
	if String(fleet.faction_id) != String(target.squad.faction_id): return _error("세력 간 전대 이동은 금지됩니다.")
	_remove_from_all_fleets(squadron_id)
	fleet.squadron_ids.append(squadron_id)
	target.squad.deployment = {"kind": "fleet", "fleet_id": fleet_id}
	_normalize_all_flagships()
	return _ok()


func unassign_to_independent(squadron_id: String) -> Dictionary:
	var target := _editable_squad(squadron_id)
	if not target.ok: return target
	_remove_from_all_fleets(squadron_id)
	target.squad.deployment = {"kind": "independent"}; target.squad.flagship = false
	_normalize_all_flagships(); return _ok()


func restore_historical() -> Dictionary:
	_draft = _historical.duplicate(true); return _ok()


func cancel() -> Dictionary:
	_draft = _applied.duplicate(true); return _ok()


func apply() -> Dictionary:
	var candidate := _draft.duplicate(true)
	_normalize_candidate(candidate)
	var validation := Setup.validate_document(candidate)
	if not validation.ok: return {"ok": false, "errors": validation.errors.duplicate(), "digest": applied_digest()}
	var next: Dictionary = validation.setup.duplicate(true)
	next.formation_revision = int(_applied.get("formation_revision", 0)) + 1
	_applied = next; _draft = next.duplicate(true)
	return {"ok": true, "errors": [], "setup": next.duplicate(true), "summary": summary(), "digest": applied_digest()}


func validate_draft() -> Dictionary:
	var candidate := _draft.duplicate(true); _normalize_candidate(candidate)
	return Setup.validate_document(candidate)


func squadron_metrics(squadron_id: String) -> Dictionary:
	var squad := _find_squad(squadron_id)
	if squad.is_empty(): return {}
	var roster := _roster_index(String(squad.faction_id)); var commander: Dictionary = roster.get(String(squad.commander.id), {})
	var rules: Dictionary = _draft.command_limit_rules
	var recommended := int(rules.recommended_base_cost) + int(commander.get("command", 0)) * int(rules.recommended_cost_per_command)
	var total := int(squad.get("declared_total_cost", 0)); var ratio := maxf(0.0, float(total - recommended) / float(maxi(1, recommended)))
	var tier := mini(int(ceil(ratio / float(rules.over_tier_ratio))), int(rules.max_penalty_tier)) if ratio > 0.0 else 0
	var penalty: Dictionary = rules.penalty_per_tier
	return {"total_cost": total, "recommended_cost": recommended, "over_ratio": ratio, "penalty_tier": tier,
		"mobility_percent": -tier * int(penalty.mobility_percent), "accuracy_percent": -tier * int(penalty.accuracy_percent),
		"formation_change_percent": -tier * int(penalty.formation_change_percent), "warning": tier > 0}


func summary() -> Dictionary:
	var faction_costs := {}; var overcap := []
	for value in _draft.squadrons:
		var squad: Dictionary = value; var fid := String(squad.faction_id)
		faction_costs[fid] = int(faction_costs.get(fid, 0)) + int(squad.declared_total_cost)
		if squadron_metrics(String(squad.id)).get("warning", false): overcap.append(String(squad.id))
	return {"formation_revision": int(_draft.get("formation_revision", 0)), "faction_costs": faction_costs, "over_cap_squadrons": overcap}


func faction_inventory_summary(faction_id: String) -> Dictionary:
	var faction: Dictionary = {}
	for value in _draft.get("factions", []):
		if value is Dictionary and String(value.get("id", "")) == faction_id:
			faction = value
			break
	if faction.is_empty():
		return {"ok": false, "errors": ["미지 세력입니다: %s" % faction_id], "faction_id": faction_id, "inventory": {}}
	var used := {}
	for value in _draft.get("squadrons", []):
		if not value is Dictionary or String(value.get("faction_id", "")) != faction_id: continue
		for component in value.get("composition", []):
			if not component is Dictionary: continue
			var ship_type_id := String(component.get("ship_type_id", ""))
			used[ship_type_id] = int(used.get(ship_type_id, 0)) + int(component.get("count", 0))
	var inventory := {}
	for ship in _draft.get("ship_types", []):
		var ship_type_id := String(ship.get("id", ""))
		var total := int(faction.get("inventory", {}).get(ship_type_id, 0))
		var assigned := int(used.get(ship_type_id, 0))
		inventory[ship_type_id] = {"total": total, "used": assigned, "available": total - assigned}
	return {"ok": true, "errors": [], "faction_id": faction_id, "inventory": inventory}


func _editable_squad(squadron_id: String) -> Dictionary:
	var squad := _find_squad(squadron_id)
	if squad.is_empty(): return _error("미지 전대입니다: %s" % squadron_id)
	if not can_edit_faction(String(squad.faction_id)): return _error(_permission_reason(String(squad.faction_id)))
	return {"ok": true, "errors": [], "squad": squad}


func _permission_reason(faction_id: String) -> String:
	if faction_id == "sun_quan": return "손권군은 연합 편성 수동 설정을 켜야 편집할 수 있습니다."
	if faction_id == "cao_cao": return "조조군은 AI 역사 편성 읽기 전용입니다."
	return "편집할 수 없는 세력입니다."


func _restore_faction_from_applied(faction_id: String) -> void:
	for i in range(_draft.squadrons.size() - 1, -1, -1):
		if String(_draft.squadrons[i].faction_id) == faction_id: _draft.squadrons.remove_at(i)
	for squad in _applied.squadrons:
		if String(squad.faction_id) == faction_id: _draft.squadrons.append(squad.duplicate(true))
	for i in range(_draft.fleet_groups.size() - 1, -1, -1):
		if String(_draft.fleet_groups[i].faction_id) == faction_id: _draft.fleet_groups.remove_at(i)
	for fleet in _applied.fleet_groups:
		if String(fleet.faction_id) == faction_id: _draft.fleet_groups.append(fleet.duplicate(true))


func _remove_from_all_fleets(squadron_id: String) -> void:
	for i in range(_draft.fleet_groups.size() - 1, -1, -1):
		var fleet: Dictionary = _draft.fleet_groups[i]
		fleet.squadron_ids.erase(squadron_id)
		if fleet.squadron_ids.is_empty(): _draft.fleet_groups.remove_at(i)


func _normalize_all_flagships() -> void:
	for squad in _draft.squadrons: squad.flagship = false
	for fleet in _draft.fleet_groups:
		if fleet.squadron_ids.is_empty(): continue
		var candidates: Array = fleet.squadron_ids.duplicate()
		candidates.sort_custom(func(a, b): return _flagship_precedes(String(a), String(b)))
		var selected := String(candidates[0]); fleet.flagship_squadron_id = selected
		var squad := _find_squad(selected)
		if not squad.is_empty(): squad.flagship = true


func _flagship_precedes(a: String, b: String) -> bool:
	var sa := _find_squad(a); var sb := _find_squad(b)
	var ra: Dictionary = _roster_index(String(sa.faction_id)).get(String(sa.commander.id), {})
	var rb: Dictionary = _roster_index(String(sb.faction_id)).get(String(sb.commander.id), {})
	if int(ra.get("command", 0)) != int(rb.get("command", 0)): return int(ra.get("command", 0)) > int(rb.get("command", 0))
	if int(ra.get("level", 0)) != int(rb.get("level", 0)): return int(ra.get("level", 0)) > int(rb.get("level", 0))
	return a < b


func _recalculate_all_costs() -> void:
	for squad in _draft.squadrons: _recalculate_cost(squad)


func _recalculate_cost(squad: Dictionary) -> void:
	var result := Setup.calculate_squadron_cost(squad, _ship_index(), _equipment_by_ship())
	squad.declared_total_cost = int(result.cost); squad.calculated_total_cost = int(result.cost)


func _normalize_candidate(candidate: Dictionary) -> void:
	var temp := _draft; _draft = candidate; _normalize_all_flagships(); _recalculate_all_costs(); candidate = _draft; _draft = temp


func _ship_index() -> Dictionary:
	var out := {}; for row in _draft.get("ship_types", []): out[String(row.id)] = row
	return out


func _equipment_by_ship() -> Dictionary:
	var out := {}
	for row in _draft.get("ship_types", []):
		out[String(row.id)] = {}
		for eq in row.get("mission_equipment", []): out[String(row.id)][String(eq.id)] = eq
	return out


func _equipment_index() -> Dictionary: return _equipment_by_ship().get(Setup.FAST_CRAFT_ID, {})


func _roster_index(faction_id: String) -> Dictionary:
	var out := {}
	for faction in _draft.get("factions", []):
		if String(faction.id) == faction_id:
			for commander in faction.demo_roster: out[String(commander.id)] = commander
	return out


func _find_squad(squadron_id: String) -> Dictionary:
	for squad in _draft.get("squadrons", []):
		if String(squad.id) == squadron_id: return squad
	return {}


func _find_fleet(fleet_id: String) -> Dictionary:
	for fleet in _draft.get("fleet_groups", []):
		if String(fleet.id) == fleet_id: return fleet
	return {}


func _composition_row(squad: Dictionary, ship_type_id: String) -> Dictionary:
	for row in squad.composition:
		if String(row.ship_type_id) == ship_type_id: return row
	return {}


func _ok() -> Dictionary: return {"ok": true, "errors": []}
func _error(message: String) -> Dictionary: return {"ok": false, "errors": [message]}
