class_name RedCliffsWeaponAllocation
extends RefCounted

## DEMO-RC-G4-05 — 편성 기반 무기 가용성·비율·사격 보류의 코어 권위.
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const RULES_PATH := "res://data/red-cliffs-weapon-allocation-rules.json"

var _setup: Dictionary = {}
var _rules: Dictionary = {}


func initialize(applied_setup: Dictionary) -> Dictionary:
	var checked := Setup.validate_document(applied_setup)
	if not checked.ok: return _error("유효한 G3 적용 편성이 필요합니다.")
	var loaded := _load_rules()
	if not loaded.ok: return loaded
	_setup = checked.setup.duplicate(true); _rules = loaded.rules.duplicate(true)
	return _ok()


func rules_snapshot() -> Dictionary: return _rules.duplicate(true)


func categories() -> Array:
	var result: Array = []; var ids: Array = _rules.get("weapons", {}).keys(); ids.sort()
	for weapon_id in ids:
		result.append({"weapon_id": String(weapon_id), "name": String(_rules.weapons[weapon_id].name)})
	return result


func presets() -> Array:
	var result: Array = []; var ids: Array = _rules.get("presets", {}).keys(); ids.sort()
	for preset_id in ids:
		result.append({"preset_id": String(preset_id), "name": String(_rules.presets[preset_id].name)})
	return result


func available_categories(squadron_id: String) -> Array:
	var squad := _find_squad(squadron_id)
	if squad.is_empty(): return []
	var available := {}
	for component in squad.composition:
		if int(component.count) <= 0: continue
		var ship_id := String(component.ship_type_id); var equipment_id := String(component.get("mission_equipment_id", ""))
		for weapon_id in _rules.weapons:
			var row: Dictionary = _rules.weapons[weapon_id]
			if row.platforms.has(ship_id) or not equipment_id.is_empty() and row.fast_equipment.has(equipment_id):
				available[weapon_id] = true
	var result: Array = available.keys(); result.sort(); return result


func initial_state() -> Dictionary:
	var result := {}
	for squad in _operational_squadrons():
		var squadron_id := String(squad.id)
		result[squadron_id] = {"squadron_id": squadron_id, "faction_id": String(squad.faction_id),
			"available_categories": available_categories(squadron_id),
			"allocations": _preset_allocations(squadron_id, "balanced"), "hold_fire": available_categories(squadron_id).is_empty(),
			"effective_turn": 0, "source": "default_balanced"}
	return result


func set_basis_points(draft_state: Dictionary, squadron_id: String, weapon_id: String, basis_points) -> Dictionary:
	var checked := _validate_state_row(draft_state, squadron_id)
	if not checked.ok: return checked
	if not _rules.weapons.has(weapon_id): return _error("미지 무기 종류입니다: %s" % weapon_id)
	if not _integer_basis_points(basis_points): return _error("무기 비율은 0~10000 basis points 정수여야 합니다.")
	var next := draft_state.duplicate(true); var row: Dictionary = next[squadron_id]
	if not row.available_categories.has(weapon_id) and int(basis_points) != 0:
		return _error("사용 불가 무기 비율은 0이어야 합니다: %s" % weapon_id)
	if row.available_categories.is_empty():
		return {"ok": true, "errors": [], "state": next, "row": row.duplicate(true)}
	row.allocations = _normalize_after_change(row.allocations, row.available_categories, weapon_id, int(basis_points))
	return {"ok": true, "errors": [], "state": next, "row": row.duplicate(true)}


func apply_preset(draft_state: Dictionary, squadron_id: String, preset_id: String) -> Dictionary:
	var checked := _validate_state_row(draft_state, squadron_id)
	if not checked.ok: return checked
	if not _rules.presets.has(preset_id): return _error("미지 무기 프리셋입니다: %s" % preset_id)
	var next := draft_state.duplicate(true); next[squadron_id].allocations = _preset_allocations(squadron_id, preset_id)
	return {"ok": true, "errors": [], "state": next, "row": next[squadron_id].duplicate(true)}


func set_hold_fire(draft_state: Dictionary, squadron_id: String, enabled: bool) -> Dictionary:
	var checked := _validate_state_row(draft_state, squadron_id)
	if not checked.ok: return checked
	var next := draft_state.duplicate(true)
	if not enabled and next[squadron_id].available_categories.is_empty(): return _error("무장 0 전대는 사격을 재개할 수 없습니다.")
	next[squadron_id].hold_fire = enabled
	return {"ok": true, "errors": [], "state": next, "row": next[squadron_id].duplicate(true)}


func resolve_orders(orders: Array, prior_state: Dictionary, turn_number: int) -> Dictionary:
	if turn_number < 1: return _error("턴 번호는 1 이상이어야 합니다.")
	var ids := _operational_ids()
	if orders.size() != ids.size() or prior_state.size() != ids.size(): return _error("모든 operational 전대의 무기 명령과 상태가 필요합니다.")
	var seen := {}; var normalized: Array = []
	for value in orders:
		if not value is Dictionary: return _error("무기 명령은 객체여야 합니다.")
		var squadron_id := String(value.get("squadron_id", ""))
		if value.size() != 3 or seen.has(squadron_id) or not ids.has(squadron_id): return _error("미지·중복 또는 잘못된 무기 명령입니다: %s" % squadron_id)
		var row := {"squadron_id": squadron_id, "allocations": value.get("allocations", {}).duplicate(true), "hold_fire": value.get("hold_fire")}
		var valid := _validate_allocations(squadron_id, row.allocations, row.hold_fire)
		if not valid.ok: return valid
		seen[squadron_id] = true; normalized.append(row)
	if seen.size() != ids.size(): return _error("모든 operational 전대의 무기 명령이 필요합니다.")
	normalized.sort_custom(func(a, b): return String(a.squadron_id) < String(b.squadron_id))
	var next := prior_state.duplicate(true); var events: Array = []
	for order in normalized:
		var squadron_id := String(order.squadron_id)
		next[squadron_id] = {"squadron_id": squadron_id, "faction_id": String(_find_squad(squadron_id).faction_id),
			"available_categories": available_categories(squadron_id), "allocations": order.allocations.duplicate(true),
			"hold_fire": bool(order.hold_fire), "effective_turn": turn_number, "source": "resolution_start"}
		events.append({"event_type": "weapon_allocation_applied", "turn": turn_number, "squadron_id": squadron_id,
			"allocations": order.allocations.duplicate(true), "hold_fire": bool(order.hold_fire),
			"application_timing": String(_rules.application_timing)})
	return {"ok": true, "errors": [], "weapon_allocation_state": next, "weapon_allocation_events": events}


func interception_policy(state: Dictionary) -> Dictionary:
	var result := {}
	for squadron_id in state:
		var row: Dictionary = state[squadron_id]
		result[squadron_id] = {"hold_fire": bool(row.hold_fire), "allocations": row.allocations.duplicate(true),
			"capabilities": _capabilities_for_squadron(String(squadron_id))}
	return result


func _normalize_after_change(previous: Dictionary, available: Array, changed: String, value: int) -> Dictionary:
	var result := _zero_allocations(); result[changed] = value
	var remainder := 10000 - value; var others: Array = []
	for category_id in available:
		if category_id != changed: others.append(category_id)
	others.sort()
	if others.is_empty(): result[changed] = 10000; return result
	var weights := {}; var weight_sum := 0
	for category_id in others:
		var weight := maxi(0, int(previous.get(category_id, 0))); weights[category_id] = weight; weight_sum += weight
	if weight_sum == 0:
		for category_id in others: weights[category_id] = 1
		weight_sum = others.size()
	_distribute(result, others, weights, weight_sum, remainder)
	return result


func _preset_allocations(squadron_id: String, preset_id: String) -> Dictionary:
	var result := _zero_allocations(); var available := available_categories(squadron_id)
	if available.is_empty(): return result
	var weights: Dictionary = _rules.presets[preset_id].weights; var weight_sum := 0
	for category_id in available: weight_sum += int(weights[category_id])
	_distribute(result, available, weights, weight_sum, 10000); return result


func _distribute(result: Dictionary, ids: Array, weights: Dictionary, weight_sum: int, total: int) -> void:
	var fractions: Array = []; var assigned := 0
	for category_id in ids:
		var exact := float(total * int(weights[category_id])) / float(weight_sum)
		var base := int(floor(exact)); result[category_id] = base; assigned += base
		fractions.append({"category_id": category_id, "fraction": exact - base})
	fractions.sort_custom(func(a, b):
		if not is_equal_approx(float(a.fraction), float(b.fraction)): return float(a.fraction) > float(b.fraction)
		return String(a.category_id) < String(b.category_id))
	for index in range(total - assigned): result[fractions[index % fractions.size()].category_id] += 1


func _validate_state_row(state: Dictionary, squadron_id: String) -> Dictionary:
	if not state.has(squadron_id) or not state[squadron_id] is Dictionary: return _error("무기 배분 전대가 없습니다: %s" % squadron_id)
	return _validate_allocations(squadron_id, state[squadron_id].get("allocations", {}), state[squadron_id].get("hold_fire"))


func _validate_allocations(squadron_id: String, allocations, hold_fire) -> Dictionary:
	if not allocations is Dictionary or not hold_fire is bool: return _error("무기 배분 스키마가 잘못되었습니다.")
	var category_ids: Array = _rules.weapons.keys(); category_ids.sort()
	var keys: Array = allocations.keys(); keys.sort()
	if keys != category_ids: return _error("모든 무기 종류 비율이 정확히 필요합니다.")
	var available := available_categories(squadron_id); var total := 0
	for category_id in category_ids:
		var value = allocations[category_id]
		if not _integer_basis_points(value): return _error("무기 비율은 0~10000 basis points 정수여야 합니다: %s" % category_id)
		if not available.has(category_id) and int(value) != 0: return _error("사용 불가 무기는 0%여야 합니다: %s" % category_id)
		total += int(value)
	var expected_total := 0 if available.is_empty() else 10000
	if total != expected_total: return _error("무기 비율 합계는 정확히 10000 basis points여야 합니다.")
	if available.is_empty() and not bool(hold_fire): return _error("무장 0 전대는 자동 사격 보류여야 합니다.")
	return _ok()


func _zero_allocations() -> Dictionary:
	var result := {}; for category_id in _rules.weapons: result[category_id] = 0
	return result


func _capabilities_for_squadron(squadron_id: String) -> Array:
	var squad := _find_squad(squadron_id); var best := {}
	for component in squad.get("composition", []):
		if int(component.count) <= 0: continue
		var ship_id := String(component.ship_type_id); var equipment_id := String(component.get("mission_equipment_id", ""))
		for weapon_id in _rules.weapons:
			var weapon: Dictionary = _rules.weapons[weapon_id]; var capability: Dictionary = {}
			if weapon.platforms.has(ship_id): capability = weapon.platforms[ship_id]
			elif not equipment_id.is_empty() and weapon.fast_equipment.has(equipment_id): capability = weapon.fast_equipment[equipment_id]
			if capability.is_empty(): continue
			if not best.has(weapon_id) or int(capability.range) > int(best[weapon_id].range) \
					or int(capability.range) == int(best[weapon_id].range) and ship_id < String(best[weapon_id].platform_id):
				best[weapon_id] = {"weapon_id": String(weapon_id), "platform_id": ship_id,
					"mission_equipment_id": equipment_id, "range": int(capability.range), "arc_deg": float(capability.arc_deg)}
	var ids: Array = best.keys(); ids.sort(); var result: Array = []
	for weapon_id in ids: result.append(best[weapon_id])
	return result


func _load_rules() -> Dictionary:
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null: return _error("무기 배분 규칙 파일을 열 수 없습니다.")
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1 or String(parsed.get("profile_id", "")) != "normal-demo-weapon-allocation-v1": return _error("지원하지 않는 무기 배분 프로필입니다.")
	if int(parsed.get("total_basis_points", 0)) != 10000 or not parsed.get("weapons") is Dictionary or not parsed.get("presets") is Dictionary or parsed.presets.size() < 3: return _error("무기 종류·프리셋 규칙이 잘못되었습니다.")
	var expected := ["artillery", "intercept", "line_fire", "torpedo"]; var ids: Array = parsed.weapons.keys(); ids.sort()
	if ids != expected: return _error("무기 종류 집합이 지원 계약과 다릅니다.")
	for category_id in ids:
		var row = parsed.weapons[category_id]
		if not row is Dictionary or String(row.get("name", "")).is_empty() or not row.get("platforms") is Dictionary or not row.get("fast_equipment") is Dictionary: return _error("무기 종류 규칙이 잘못되었습니다: %s" % category_id)
		for table in [row.platforms, row.fast_equipment]:
			for capability in table.values():
				if not capability is Dictionary or float(capability.get("range", 0)) <= 0 or float(capability.get("arc_deg", 0)) <= 0 or float(capability.arc_deg) > 360: return _error("무기 range/arc 규칙이 잘못되었습니다: %s" % category_id)
	for preset in parsed.presets.values():
		if not preset is Dictionary or String(preset.get("name", "")).is_empty() or not preset.get("weights") is Dictionary: return _error("무기 프리셋이 잘못되었습니다.")
		var weight_keys: Array = preset.weights.keys(); weight_keys.sort()
		if weight_keys != expected: return _error("프리셋은 모든 무기 종류 weight를 가져야 합니다.")
		for weight in preset.weights.values():
			if int(weight) <= 0: return _error("프리셋 weight는 양수여야 합니다.")
	if String(parsed.get("normalization", "")) != "changed_weapon_fixed_basis_points; remainder_proportional_to_previous_available_positive; equal_fallback; floor_then_fraction_desc_weapon_id_asc": return _error("결정론적 정규화 계약이 잘못되었습니다.")
	if parsed.get("result_pending") != ["ammo", "energy", "heat", "hit", "damage", "casualties", "victory"]: return _error("G4-06 pending 계약이 잘못되었습니다.")
	return {"ok": true, "errors": [], "rules": parsed.duplicate(true)}


func _operational_squadrons() -> Array:
	var rows: Array = []
	for squad in _setup.get("squadrons", []):
		if bool(squad.get("operational", true)): rows.append(squad)
	rows.sort_custom(func(a, b): return String(a.id) < String(b.id)); return rows


func _operational_ids() -> Array:
	var result: Array = []; for squad in _operational_squadrons(): result.append(String(squad.id))
	return result


func _find_squad(squadron_id: String) -> Dictionary:
	for squad in _setup.get("squadrons", []):
		if String(squad.id) == squadron_id: return squad
	return {}


func _integer_basis_points(value) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and is_equal_approx(float(value), floor(float(value))) and int(value) >= 0 and int(value) <= 10000


func _ok() -> Dictionary: return {"ok": true, "errors": []}
func _error(message: String) -> Dictionary: return {"ok": false, "errors": [message]}
