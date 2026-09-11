class_name RedCliffsFastCraftFormation
extends RefCounted

## DEMO-RC-G6-01 — 고속정 전대와 요격·뇌격·정찰·구조 임무 장비·코스트.
## apply()가 반환한 applied_setup이 전투 시작 뒤 불변 loadout의 권위 입력이다.
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Draft := preload("res://core/demo_red_cliffs/red_cliffs_formation_draft.gd")
const RULES_PATH := "res://data/red-cliffs-fast-craft-rules.json"
const MISSIONS := {"intercept": "FAST-EQ-INTERCEPT", "torpedo": "FAST-EQ-TORPEDO", "recon": "FAST-EQ-RECON", "rescue": "FAST-EQ-RESCUE"}
const BASING_MODES := ["independent", "carrier", "base"]
var _rules: Dictionary = {}; var _historical: Dictionary = {}; var _applied: Dictionary = {}; var _draft: Dictionary = {}

func initialize(applied_setup: Dictionary) -> Dictionary:
	if int(applied_setup.get("formation_revision", 0)) > 0:
		var baseline := Setup.load_default()
		if baseline.ok and String(baseline.setup.get("setup_id", "")) == String(applied_setup.get("setup_id", "")):
			return configure(baseline.setup, applied_setup)
	return configure(applied_setup)

func configure(historical_setup: Dictionary, applied_setup_value: Dictionary = {}) -> Dictionary:
	var historical_checked := Setup.validate_document(historical_setup); if not historical_checked.ok: return historical_checked
	var file := FileAccess.open(RULES_PATH, FileAccess.READ); if file == null: return _error("고속정 편성 규칙을 열 수 없습니다.")
	var parsed = JSON.parse_string(file.get_as_text()); var rules_check := _validate_rules(parsed, historical_checked.setup)
	if not rules_check.ok: return rules_check
	var current_input: Dictionary = historical_setup if applied_setup_value.is_empty() else applied_setup_value
	var current_checked := Setup.validate_document(current_input); if not current_checked.ok: return current_checked
	_rules = parsed.duplicate(true); var current_contract := _validate_contract(current_checked.setup, false)
	if not current_contract.ok:
		_rules = {}
		return current_contract
	if String(current_checked.setup.setup_id) != String(historical_checked.setup.setup_id) or String(current_checked.setup.battle_id) != String(historical_checked.setup.battle_id):
		_rules = {}
		return _error("역사 기준선과 적용 편성의 전투 ID가 일치해야 합니다.")
	_historical = historical_checked.setup.duplicate(true); _applied = current_checked.setup.duplicate(true); _draft = current_checked.setup.duplicate(true)
	return _ok()

func catalog() -> Dictionary:
	if _rules.is_empty(): return _error("고속정 편성기가 초기화되지 않았습니다.")
	var ship_costs: Array = []
	for value in _draft.ship_types: ship_costs.append({"ship_type_id": String(value.id), "name": String(value.name), "category": String(value.category), "unit_cost": int(value.unit_cost)})
	ship_costs.sort_custom(func(a, b): return String(a.ship_type_id) < String(b.ship_type_id))
	var missions: Array = []
	for rule in _rules.mission_equipment:
		var equipment := _equipment(_draft, String(rule.equipment_id)); var base := _base_cost(_draft)
		missions.append({"mission_id": String(rule.mission_id), "equipment_id": String(rule.equipment_id), "label": String(rule.label),
			"eligible_ship_type_ids": rule.eligible_ship_type_ids.duplicate(), "base_unit_cost": base,
			"equipment_unit_cost": int(equipment.unit_cost), "total_unit_cost": base + int(equipment.unit_cost)})
	return {"ok": true, "errors": [], "profile_id": String(_rules.profile_id), "fast_craft_ship_type_id": Setup.FAST_CRAFT_ID,
		"interceptor_ship_type_id": "SHP-07", "category_contract": _rules.category_contract.duplicate(true),
		"ship_costs": ship_costs, "missions": missions, "deployment_kinds": ["independent", "fleet"],
		"basing_modes": _rules.basing_modes.duplicate(true), "basing_contract": _rules.basing_contract.duplicate(true),
		"penalty_application": Draft.PENALTY_APPLICATION.duplicate(true),
		"out_of_scope": _rules.out_of_scope.duplicate()}

func historical_snapshot() -> Dictionary: return _historical.duplicate(true)
func applied_snapshot() -> Dictionary: return _applied.duplicate(true)
func applied_setup() -> Dictionary: return _applied.duplicate(true)
func draft_snapshot() -> Dictionary: return _draft.duplicate(true)
func applied_digest() -> String: return JSON.stringify(_applied)
func draft_digest() -> String: return JSON.stringify(_draft)
func can_edit_faction(faction_id: String) -> bool: return faction_id == "liu_bei" or faction_id == "sun_quan" and bool(_draft.formation_options.sun_manual)

func set_sun_manual(enabled: bool) -> Dictionary:
	var candidate := _draft.duplicate(true); candidate.formation_options.sun_manual = enabled
	if not enabled: _restore_faction(candidate, _applied, "sun_quan")
	return _accept_candidate(candidate, {"enabled": enabled})

func set_count(squadron_id: String, count: int) -> Dictionary:
	var editable := _editable(squadron_id); if not editable.ok: return editable
	if count < 1: return _error("고속정 전대는 1척 이상이어야 합니다.")
	var candidate := _draft.duplicate(true); var squad := _find_squad(candidate, squadron_id)
	squad.composition[0].count = count; squad.declared_total_cost = _cost(candidate, squad)
	return _accept_candidate(candidate, {"squadron_id": squadron_id, "faction_id": String(squad.faction_id)})

func set_equipment(squadron_id: String, equipment_id: String) -> Dictionary:
	var editable := _editable(squadron_id); if not editable.ok: return editable
	if not MISSIONS.values().has(equipment_id): return _error("요격·뇌격·정찰·구조 임무장비만 선택할 수 있습니다.")
	var candidate := _draft.duplicate(true); var squad := _find_squad(candidate, squadron_id)
	squad.composition[0].mission_equipment_id = equipment_id; squad.declared_total_cost = _cost(candidate, squad)
	return _accept_candidate(candidate, {"squadron_id": squadron_id, "faction_id": String(squad.faction_id)})

func create_squadron(faction_id: String, name: String, commander_id: String, count: int, equipment_id: String, formation_id: String, position: Vector2, deployment_kind: String = "independent", fleet_id: String = "", basing_mode: String = "independent") -> Dictionary:
	if not can_edit_faction(faction_id): return _permission(faction_id)
	var candidate := _draft.duplicate(true)
	var created := _append_squadron_candidate(candidate, faction_id, name, commander_id, count, equipment_id, formation_id, position, deployment_kind, fleet_id, basing_mode)
	if not created.ok: return created
	return _accept_candidate(candidate, {"squadron_id": String(created.squadron_id), "faction_id": faction_id, "created": true})

func set_deployment(squadron_id: String, deployment_kind: String, fleet_id: String = "") -> Dictionary:
	var editable := _editable(squadron_id); if not editable.ok: return editable
	var candidate := _draft.duplicate(true); var changed := _set_deployment_candidate(candidate, squadron_id, deployment_kind, fleet_id)
	if not changed.ok: return changed
	return _accept_candidate(candidate, {"squadron_id": squadron_id, "faction_id": String(editable.squad.faction_id), "deployment_changed": true})

func set_basing_mode(squadron_id: String, basing_mode: String) -> Dictionary:
	var editable := _editable(squadron_id); if not editable.ok: return editable
	if not BASING_MODES.has(basing_mode): return _error("고속정 운용 기반은 독립·강습모함 탑재·거점 배치 중 하나여야 합니다.")
	var candidate := _draft.duplicate(true); _find_squad(candidate, squadron_id)["fast_craft_basing"] = basing_mode
	return _accept_candidate(candidate, {"squadron_id": squadron_id, "faction_id": String(editable.squad.faction_id), "basing_changed": true})

func split_from_mixed_squadron(source_squadron_id: String, name: String, commander_id: String, count: int, equipment_id: String, formation_id: String, position: Vector2, deployment_kind: String = "independent", fleet_id: String = "", basing_mode: String = "independent") -> Dictionary:
	var source := _find_squad(_draft, source_squadron_id)
	if source.is_empty() or _pure(source) or not can_edit_faction(String(source.get("faction_id", ""))): return _error("편집 가능한 혼성 전대가 아닙니다.")
	var source_row := _component(source, Setup.FAST_CRAFT_ID)
	if source_row.is_empty() or count < 1 or count > int(source_row.count): return _error("혼성 전대의 고속정 수량 범위를 벗어났습니다.")
	var candidate := _draft.duplicate(true); var candidate_source := _find_squad(candidate, source_squadron_id); var row := _component(candidate_source, Setup.FAST_CRAFT_ID)
	row.count = int(row.count) - count
	if int(row.count) == 0: candidate_source.composition.erase(row)
	_recalculate_declared(candidate, candidate_source)
	var created := _append_squadron_candidate(candidate, String(source.faction_id), name, commander_id, count, equipment_id, formation_id, position, deployment_kind, fleet_id, basing_mode)
	if not created.ok: return created
	return _accept_candidate(candidate, {"squadron_id": String(created.squadron_id), "faction_id": String(source.faction_id), "created": true,
		"split_from_squadron_id": source_squadron_id, "transferred_count": count})

func transfer_from_mixed_squadron(source_squadron_id: String, target_squadron_id: String, count: int) -> Dictionary:
	var source := _find_squad(_draft, source_squadron_id); var target_editable := _editable(target_squadron_id)
	if source.is_empty() or _pure(source) or not target_editable.ok: return _error("편집 가능한 혼성 원본과 고속정 대상 전대가 필요합니다.")
	if String(source.get("faction_id", "")) != String(target_editable.squad.get("faction_id", "")) or not can_edit_faction(String(source.get("faction_id", ""))): return _error("같은 편집 가능 세력 안에서만 고속정을 이관할 수 있습니다.")
	var source_row := _component(source, Setup.FAST_CRAFT_ID)
	if source_row.is_empty() or count < 1 or count > int(source_row.get("count", 0)): return _error("혼성 전대의 고속정 수량 범위를 벗어났습니다.")
	var candidate := _draft.duplicate(true); var candidate_source := _find_squad(candidate, source_squadron_id); var candidate_target := _find_squad(candidate, target_squadron_id)
	var candidate_row := _component(candidate_source, Setup.FAST_CRAFT_ID); candidate_row.count = int(candidate_row.count) - count
	if int(candidate_row.count) == 0: candidate_source.composition.erase(candidate_row)
	candidate_target.composition[0].count = int(candidate_target.composition[0].count) + count
	_recalculate_declared(candidate, candidate_source); _recalculate_declared(candidate, candidate_target)
	return _accept_candidate(candidate, {"squadron_id": target_squadron_id, "faction_id": String(source.faction_id),
		"transferred_from_squadron_id": source_squadron_id, "transferred_count": count})

func delete_squadron(squadron_id: String, recovery_squadron_id: String = "") -> Dictionary:
	var editable := _editable(squadron_id); if not editable.ok: return editable
	var faction_id := String(editable.squad.faction_id); var candidate := _draft.duplicate(true)
	var removed_count := int(_find_squad(candidate, squadron_id).composition[0].count)
	if not recovery_squadron_id.is_empty():
		var recovery := _find_squad(candidate, recovery_squadron_id)
		if recovery.is_empty() or String(recovery.get("faction_id", "")) != faction_id or recovery_squadron_id == squadron_id: return _error("해체 고속정을 회수할 같은 세력 전대가 필요합니다.")
		var recovery_row := _component(recovery, Setup.FAST_CRAFT_ID)
		if recovery_row.is_empty(): recovery.composition.append({"ship_type_id": Setup.FAST_CRAFT_ID, "count": removed_count, "mission_equipment_id": String(editable.squad.composition[0].mission_equipment_id)})
		else: recovery_row.count = int(recovery_row.count) + removed_count
		_recalculate_declared(candidate, recovery)
	_remove_from_fleets(candidate, squadron_id)
	for index in range(candidate.squadrons.size() - 1, -1, -1):
		if String(candidate.squadrons[index].id) == squadron_id: candidate.squadrons.remove_at(index)
	return _accept_candidate(candidate, {"deleted_squadron_id": squadron_id, "faction_id": faction_id,
		"released_to_inventory": removed_count if recovery_squadron_id.is_empty() else 0, "recovered_to_squadron_id": recovery_squadron_id,
		"recovered_count": removed_count if not recovery_squadron_id.is_empty() else 0})

func squadron_summary(squadron_id: String) -> Dictionary:
	var squad := _find_squad(_draft, squadron_id)
	if squad.is_empty() or not _pure(squad): return _error("미지 고속정 전대입니다: %s" % squadron_id)
	var row: Dictionary = squad.composition[0]; var equipment := _equipment(_draft, String(row.mission_equipment_id)); var commander := _commander(_draft, String(squad.faction_id), String(squad.commander.id))
	var base := _base_cost(_draft); var total := int(row.count) * (base + int(equipment.unit_cost)); var metric := _metrics(squadron_id); var historical := _historical_loadout(squadron_id)
	return {"ok": true, "errors": [], "squadron_id": squadron_id, "faction_id": String(squad.faction_id), "name": String(squad.name), "commander": commander.duplicate(true),
		"ship_type_id": Setup.FAST_CRAFT_ID, "equipment_id": String(row.mission_equipment_id), "mission_id": _mission_id(String(row.mission_equipment_id)), "count": int(row.count),
		"base_unit_cost": base, "equipment_unit_cost": int(equipment.unit_cost), "total_unit_cost": base + int(equipment.unit_cost), "subtotal_cost": total,
		"historical": not historical.is_empty(), "historical_count": int(historical.get("count", 0)), "historical_total_cost": int(historical.get("declared_historical_cost", 0)),
		"deployment": squad.deployment.duplicate(true), "basing_mode": String(squad.get("fast_craft_basing", "independent")), "recommended_cost": metric.recommended_cost, "over_ratio_basis_points": metric.over_ratio_basis_points,
		"penalty_tier": metric.penalty_tier, "penalties": metric.penalties.duplicate(true), "penalty_application": Draft.PENALTY_APPLICATION.duplicate(true),
		"pending_penalties": [], "over_cap_warning": metric.over_cap_warning}

func faction_summary(faction_id: String) -> Dictionary:
	var faction := _faction(_draft, faction_id); if faction.is_empty(): return _error("미지 세력입니다: %s" % faction_id)
	var committed := 0; var reserved := 0; var fast_cost := 0; var rows: Array = []
	for squad in _draft.squadrons:
		if String(squad.faction_id) != faction_id: continue
		for component in squad.composition:
			if String(component.ship_type_id) == Setup.FAST_CRAFT_ID:
				if _pure(squad): reserved += int(component.count)
				else: committed += int(component.count)
		if _pure(squad): var summary := squadron_summary(String(squad.id)); fast_cost += int(summary.subtotal_cost); rows.append(summary)
	rows.sort_custom(func(a, b): return String(a.squadron_id) < String(b.squadron_id)); var total := int(faction.inventory[Setup.FAST_CRAFT_ID])
	return {"ok": true, "errors": [], "faction_id": faction_id, "inventory": {"total": total, "committed_other_squadrons": committed,
		"reserved_fast_craft_squadrons": reserved, "used": committed + reserved, "remaining": total - committed - reserved},
		"fast_craft_squadron_cost": fast_cost, "within_inventory": committed + reserved <= total, "squadrons": rows}

func validate_draft() -> Dictionary: return _validate_candidate(_draft)
func restore_historical() -> Dictionary: _draft = _historical.duplicate(true); return {"ok": true, "errors": [], "draft": draft_snapshot()}
func cancel() -> Dictionary: _draft = _applied.duplicate(true); return {"ok": true, "errors": [], "draft": draft_snapshot()}
func apply() -> Dictionary:
	var checked := _validate_candidate(_draft)
	if not checked.ok: return {"ok": false, "errors": checked.errors.duplicate(), "digest": applied_digest()}
	var next: Dictionary = checked.setup.duplicate(true); next.formation_revision = int(_applied.formation_revision) + 1; checked = _validate_candidate(next)
	if not checked.ok: return {"ok": false, "errors": checked.errors.duplicate(), "digest": applied_digest()}
	_applied = checked.setup.duplicate(true); _draft = _applied.duplicate(true)
	return {"ok": true, "errors": [], "applied_setup": applied_setup(), "formation_revision": int(_applied.formation_revision), "digest": applied_digest()}

func _accept_candidate(candidate: Dictionary, receipt: Dictionary) -> Dictionary:
	var checked := _validate_candidate(candidate); if not checked.ok: return checked
	_draft = checked.setup.duplicate(true); receipt["ok"] = true; receipt["errors"] = []
	if receipt.has("squadron_id"): receipt["squadron"] = squadron_summary(String(receipt.squadron_id))
	if receipt.has("faction_id"): receipt["faction"] = faction_summary(String(receipt.faction_id))
	return receipt

func _validate_rules(raw, setup: Dictionary) -> Dictionary:
	if not raw is Dictionary or int(raw.get("schema_version", 0)) != 1 or String(raw.get("profile_id", "")) != "normal-demo-fast-craft-v1": return _error("지원하지 않는 고속정 편성 규칙입니다.")
	if String(raw.get("fast_craft_ship_type_id", "")) != Setup.FAST_CRAFT_ID or String(raw.get("interceptor_ship_type_id", "")) != "SHP-07": return _error("고속정과 요격함 ID 경계가 잘못되었습니다.")
	var fast := _ship(setup, Setup.FAST_CRAFT_ID); var interceptor := _ship(setup, "SHP-07")
	if String(fast.get("category", "")) != "small_craft" or String(interceptor.get("category", "")) != "interceptor" or String(interceptor.get("name", "")) != "요격함": return _error("고속정과 요격함 범주가 분리되어야 합니다.")
	if not raw.get("mission_equipment") is Array or raw.mission_equipment.size() != 4: return _error("고속정 임무장비 4종이 필요합니다.")
	var seen := {}
	for value in raw.mission_equipment:
		var mission_id := String(value.get("mission_id", "")); var equipment_id := String(value.get("equipment_id", ""))
		if not MISSIONS.has(mission_id) or equipment_id != String(MISSIONS[mission_id]) or seen.has(equipment_id) or value.get("eligible_ship_type_ids") != [Setup.FAST_CRAFT_ID]: return _error("고속정 임무장비 적격성 집합이 잘못되었습니다.")
		seen[equipment_id] = true
	if seen.size() != 4 or raw.get("historical_squadron_ids") != ["RC-LIU-FC-01"] or not raw.get("historical_loadouts") is Array or raw.historical_loadouts.size() != 1: return _error("역사 기본 고속정 전대 계약이 잘못되었습니다.")
	if not raw.get("basing_modes") is Array or raw.basing_modes != BASING_MODES: return _error("고속정 운용 기반 3종 계약이 잘못되었습니다.")
	if not raw.get("basing_contract") is Dictionary or not BASING_MODES.all(func(id): return not String(raw.basing_contract.get(id, "")).is_empty()): return _error("고속정 운용 기반 설명이 누락되었습니다.")
	var expected_out_of_scope := ["in_battle_equipment_change", "tactical_mission_change", "fuel", "ammo_resupply", "automatic_return", "drift", "rescue_result", "capture_result"]
	if not raw.get("out_of_scope") is Array or raw.out_of_scope != expected_out_of_scope: return _error("후속 G6 범위 경계가 누락되었습니다.")
	_rules = raw.duplicate(true); var result := _validate_contract(setup, true); _rules = {}
	return result

func _validate_candidate(candidate: Dictionary) -> Dictionary:
	var checked := Setup.validate_document(candidate); if not checked.ok: return checked
	var contract := _validate_contract(checked.setup, false); if not contract.ok: return contract
	return checked

func _validate_contract(setup: Dictionary, require_historical_loadout: bool) -> Dictionary:
	for loadout in _rules.historical_loadouts:
		var squad := _find_squad(setup, String(loadout.squadron_id))
		if not require_historical_loadout and squad.is_empty(): continue
		if squad.is_empty() or not _pure(squad): return _error("역사 기준선에는 기본 고속정 전대가 필요합니다.")
		var row: Dictionary = squad.composition[0]
		if String(squad.faction_id) != String(loadout.faction_id) or require_historical_loadout and String(squad.deployment.kind) != "independent" or not bool(squad.get("operational", false)) \
			or require_historical_loadout and (int(row.count) != int(loadout.count) or String(row.mission_equipment_id) != String(loadout.equipment_id)) \
			or int(loadout.declared_historical_cost) != int(loadout.count) * (_base_cost(setup) + int(_equipment(setup, String(loadout.equipment_id)).unit_cost)):
			return _error("역사 기본 고속정 전대의 세력·가동·장비·비용 계약이 잘못되었습니다.")
	for squad in setup.squadrons:
		if _pure(squad) and not BASING_MODES.has(String(squad.get("fast_craft_basing", "independent"))): return _error("고속정 운용 기반 metadata가 잘못되었습니다.")
	return _ok()

func _append_squadron_candidate(candidate: Dictionary, faction_id: String, name: String, commander_id: String, count: int, equipment_id: String, formation_id: String, position: Vector2, deployment_kind: String, fleet_id: String, basing_mode: String) -> Dictionary:
	if name.strip_edges().is_empty() or count < 1: return _error("고속정 전대 이름과 1척 이상의 수량이 필요합니다.")
	if not MISSIONS.values().has(equipment_id): return _error("요격·뇌격·정찰·구조 임무장비만 선택할 수 있습니다.")
	if not Setup.ALLOWED_FORMATION_IDS.has(formation_id): return _error("FRM-01~07 진형만 선택할 수 있습니다.")
	if not BASING_MODES.has(basing_mode): return _error("고속정 운용 기반은 독립·강습모함 탑재·거점 배치 중 하나여야 합니다.")
	var commander := _commander(candidate, faction_id, commander_id); if commander.is_empty(): return _error("같은 세력의 가용 장수가 아닙니다.")
	var squadron_id := _next_id(candidate, faction_id)
	var squad := {"id": squadron_id, "faction_id": faction_id, "name": name.strip_edges(), "commander": {"id": commander_id, "name": String(commander.name)},
		"flagship": false, "operational": true, "initial_position": [position.x, position.y], "formation_id": formation_id, "deployment": {"kind":"independent"}, "fast_craft_basing": basing_mode,
		"historical_basis": "사용자 preparation 고속정 전대; 역사 사실이 아닌 normal-demo 편성",
		"composition": [{"ship_type_id":Setup.FAST_CRAFT_ID, "count":count, "mission_equipment_id":equipment_id}]}
	squad.declared_total_cost = _cost(candidate, squad); candidate.squadrons.append(squad)
	var deployed := _set_deployment_candidate(candidate, squadron_id, deployment_kind, fleet_id)
	if not deployed.ok: return deployed
	return {"ok":true, "errors":[], "squadron_id":squadron_id}

func _set_deployment_candidate(candidate: Dictionary, squadron_id: String, kind: String, fleet_id: String) -> Dictionary:
	if not ["independent", "fleet"].has(kind): return _error("고속정 전대 배치는 독립 또는 함대 편입이어야 합니다.")
	var squad := _find_squad(candidate, squadron_id); if squad.is_empty(): return _error("미지 고속정 전대입니다: %s" % squadron_id)
	_remove_from_fleets(candidate, squadron_id)
	if kind == "independent": squad.deployment = {"kind":"independent"}; squad.flagship = false; return _ok()
	var fleet := _fleet(candidate, fleet_id)
	if fleet.is_empty() or String(fleet.faction_id) != String(squad.faction_id): return _error("같은 세력의 유효한 함대가 필요합니다.")
	fleet.squadron_ids.append(squadron_id); squad.deployment = {"kind":"fleet", "fleet_id":fleet_id}; squad.flagship = false
	return _ok()

func _remove_from_fleets(setup: Dictionary, squadron_id: String) -> void:
	for fleet in setup.get("fleet_groups", []):
		if fleet is Dictionary: fleet.get("squadron_ids", []).erase(squadron_id)

func _recalculate_declared(setup: Dictionary, squad: Dictionary) -> void:
	var cost := 0
	for row in squad.get("composition", []):
		var ship := _ship(setup, String(row.get("ship_type_id", ""))); var unit := int(ship.get("unit_cost", 0))
		if String(row.get("ship_type_id", "")) == Setup.FAST_CRAFT_ID: unit += int(_equipment(setup, String(row.get("mission_equipment_id", ""))).get("unit_cost", 0))
		cost += int(row.get("count", 0)) * unit
	squad.declared_total_cost = cost

func _metrics(squadron_id: String) -> Dictionary:
	var authority: Dictionary = Draft.new(_draft).squadron_metrics(squadron_id)
	var ratio := int(floor(float(authority.over_ratio) * 10000.0 + 0.5))
	return {"recommended_cost": int(authority.recommended_cost), "over_ratio_basis_points": ratio,
		"penalty_tier": int(authority.penalty_tier), "over_cap_warning": bool(authority.warning),
		"penalties": {"mobility_percent": int(authority.mobility_percent), "accuracy_percent": int(authority.accuracy_percent),
			"formation_change_percent": int(authority.formation_change_percent)}}

func _editable(id: String) -> Dictionary:
	var squad := _find_squad(_draft, id); if squad.is_empty() or not _pure(squad): return _error("미지 고속정 전대입니다: %s" % id)
	if not can_edit_faction(String(squad.faction_id)): return _permission(String(squad.faction_id))
	return {"ok": true, "errors": [], "squad": squad}
func _permission(faction_id: String) -> Dictionary:
	if faction_id == "sun_quan": return _error("손권군은 연합 편성 수동 설정을 켜야 편집할 수 있습니다.")
	return _error("조조군 고속정 전대는 AI 역사 편성 읽기 전용입니다.")
func _restore_faction(target: Dictionary, source: Dictionary, faction_id: String) -> void:
	for i in range(target.squadrons.size() - 1, -1, -1):
		if String(target.squadrons[i].faction_id) == faction_id: target.squadrons.remove_at(i)
	for squad in source.squadrons:
		if String(squad.faction_id) == faction_id: target.squadrons.append(squad.duplicate(true))
func _next_id(setup: Dictionary, faction_id: String) -> String:
	var n := 1; var id := ""
	while id.is_empty() or not _find_squad(setup, id).is_empty(): id = "RC-USER-%s-FC-%02d" % [faction_id.to_upper(), n]; n += 1
	return id
func _pure(squad: Dictionary) -> bool: return squad.get("composition") is Array and squad.composition.size() == 1 and String(squad.composition[0].get("ship_type_id", "")) == Setup.FAST_CRAFT_ID
func _cost(setup: Dictionary, squad: Dictionary) -> int: return int(squad.composition[0].count) * (_base_cost(setup) + int(_equipment(setup, String(squad.composition[0].mission_equipment_id)).get("unit_cost", 0)))
func _historical_loadout(id: String) -> Dictionary:
	for value in _rules.historical_loadouts:
		if String(value.squadron_id) == id: return value
	return {}
func _find_squad(setup: Dictionary, id: String) -> Dictionary:
	for value in setup.get("squadrons", []):
		if String(value.get("id", "")) == id: return value
	return {}
func _component(squad: Dictionary, ship_type_id: String) -> Dictionary:
	for value in squad.get("composition", []):
		if String(value.get("ship_type_id", "")) == ship_type_id: return value
	return {}
func _fleet(setup: Dictionary, id: String) -> Dictionary:
	for value in setup.get("fleet_groups", []):
		if String(value.get("id", "")) == id: return value
	return {}
func _ship(setup: Dictionary, id: String) -> Dictionary:
	for value in setup.get("ship_types", []):
		if String(value.get("id", "")) == id: return value
	return {}
func _equipment(setup: Dictionary, id: String) -> Dictionary:
	for value in _ship(setup, Setup.FAST_CRAFT_ID).get("mission_equipment", []):
		if String(value.get("id", "")) == id: return value
	return {}
func _base_cost(setup: Dictionary) -> int: return int(_ship(setup, Setup.FAST_CRAFT_ID).get("unit_cost", 0))
func _faction(setup: Dictionary, id: String) -> Dictionary:
	for value in setup.get("factions", []):
		if String(value.get("id", "")) == id: return value
	return {}
func _commander(setup: Dictionary, faction_id: String, id: String) -> Dictionary:
	for value in _faction(setup, faction_id).get("demo_roster", []):
		if String(value.get("id", "")) == id: return value
	return {}
func _mission_id(equipment_id: String) -> String:
	for id in MISSIONS:
		if String(MISSIONS[id]) == equipment_id: return String(id)
	return ""
func _ok() -> Dictionary: return {"ok": true, "errors": []}
func _error(message: String) -> Dictionary: return {"ok": false, "errors": [message], "setup": {}}
