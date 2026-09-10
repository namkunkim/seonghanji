class_name RedCliffsCombatResources
extends RefCounted

## DEMO-RC-G4-06 — 제한 전투 자원 예약·소모·턴 경계 회복의 코어 권위.
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Weapon := preload("res://core/demo_red_cliffs/red_cliffs_weapon_allocation.gd")
const RULES_PATH := "res://data/red-cliffs-combat-resource-rules.json"

var _setup: Dictionary = {}
var _rules: Dictionary = {}
var _weapon


func initialize(applied_setup: Dictionary) -> Dictionary:
	var checked := Setup.validate_document(applied_setup)
	if not checked.ok: return _error("유효한 G3 적용 편성이 필요합니다.")
	var loaded := _load_rules()
	if not loaded.ok: return loaded
	var weapon = Weapon.new(); var weapon_result: Dictionary = weapon.initialize(checked.setup)
	if not weapon_result.ok: return weapon_result
	_setup = checked.setup.duplicate(true); _rules = loaded.rules.duplicate(true); _weapon = weapon
	return _ok()


func rules_snapshot() -> Dictionary: return _rules.duplicate(true)


func initial_state() -> Dictionary:
	var result := {}; var weapon_state: Dictionary = _weapon.initial_state()
	for squad in _operational_squadrons():
		var squadron_id := String(squad.id); var total_ships := 0
		for component in squad.composition: total_ships += int(component.count)
		var energy_capacity := int(_rules.shared_base.energy_capacity) + total_ships * int(_rules.shared_initial_per_ship.energy)
		var heat_capacity := int(_rules.shared_base.heat_capacity) + total_ships * int(_rules.shared_initial_per_ship.heat_capacity)
		var weapons := {}
		for weapon_id in _rules.weapon_initial_per_platform:
			var platform_count := _weapon_platform_count(squad, String(weapon_id)); var initial: Dictionary = _rules.weapon_initial_per_platform[weapon_id]
			var carrier_capacity := 0
			for key in _rules.platform_overrides:
				var parts := String(key).split("@")
				if parts[0] == weapon_id: carrier_capacity += _ship_count(squad, parts[1]) * int(_rules.platform_overrides[key].carrier_sorties_per_platform)
			weapons[weapon_id] = {"ammo": platform_count * int(initial.ammo), "ammo_capacity": platform_count * int(initial.ammo),
				"carrier_ready": carrier_capacity, "carrier_capacity": carrier_capacity,
				"special": platform_count * int(initial.special), "special_capacity": platform_count * int(initial.special)}
		result[squadron_id] = {"squadron_id": squadron_id, "faction_id": String(squad.faction_id),
			"shared": {"energy": energy_capacity, "energy_capacity": energy_capacity, "heat": 0, "heat_capacity": heat_capacity},
			"weapons": weapons, "effective_turn": 0, "last_consumed_event_ids": []}
		# Weapon state is evaluated here so zero-weapon auto-hold remains one authority.
		if weapon_state[squadron_id].available_categories.is_empty(): result[squadron_id]["auto_hold_fire"] = true
	return result


func resolve_shots(shot_events: Array, prior_state: Dictionary, turn_number: int) -> Dictionary:
	var valid := _validate_state(prior_state)
	if not valid.ok: return valid
	if turn_number < 1: return _error("턴 번호는 1 이상이어야 합니다.")
	var rows := shot_events.duplicate(true)
	for row in rows:
		if not row is Dictionary or not ["shot_authorized", "estimated_fire_authorized"].has(String(row.get("outcome", ""))) or String(row.get("event_id", "")).is_empty(): return _error("유효한 사격 승인 이벤트만 자원을 예약할 수 있습니다.")
		if int(row.get("turn", 0)) != turn_number: return _error("사격 이벤트 턴이 자원 판정 턴과 일치해야 합니다.")
	rows.sort_custom(func(a, b): return String(a.event_id) < String(b.event_id))
	var next := prior_state.duplicate(true); var authorized: Array = []; var consumed: Array = []; var suppressed: Array = []; var seen := {}
	for event in rows:
		var event_id := String(event.event_id); var squadron_id := String(event.get("shooter_squadron_id", "")); var weapon_id := String(event.get("selected_weapon_id", ""))
		if seen.has(event_id): return _error("중복 사격 이벤트 ID입니다: %s" % event_id)
		seen[event_id] = true
		if not next.has(squadron_id) or not next[squadron_id].weapons.has(weapon_id): return _error("사격 자원 전대·무기가 잘못되었습니다: %s/%s" % [squadron_id, weapon_id])
		if next[squadron_id].last_consumed_event_ids.has(event_id):
			suppressed.append(_suppressed(event, "duplicate_event", "이미 처리된 사격 이벤트")); continue
		var platform_id := String(event.get("fire_control_snapshot", {}).get("selected_platform_id", ""))
		var cost := _shot_cost(weapon_id, platform_id); var reason := _shortage_reason(next[squadron_id], weapon_id, cost)
		if not reason.is_empty(): suppressed.append(_suppressed(event, reason, String(_rules.suppression_reasons[reason]))); continue
		var before: Dictionary = _public_row(next[squadron_id]); _consume(next[squadron_id], weapon_id, cost); next[squadron_id].last_consumed_event_ids.append(event_id)
		var after: Dictionary = _public_row(next[squadron_id]); var decorated: Dictionary = event.duplicate(true)
		decorated["resource_reservation"] = {"status": "consumed", "weapon_id": weapon_id, "cost": cost.duplicate(true),
			"before": before, "after": after, "result_pending": _rules.result_pending.duplicate()}
		authorized.append(decorated)
		consumed.append({"event_type": "resource_consumed", "event_id": "RES-%s" % event_id, "turn": turn_number,
			"shot_event_id": event_id, "squadron_id": squadron_id, "weapon_id": weapon_id,
			"cost": cost.duplicate(true), "before": before, "after": after})
	return {"ok": true, "errors": [], "authorized_events": authorized, "consumption_events": consumed,
		"suppressed_fire_events": suppressed, "resource_state": next}


func recover_at_resolution_start(prior_state: Dictionary, resolution_turn: int) -> Dictionary:
	var valid := _validate_state(prior_state)
	if not valid.ok: return valid
	if resolution_turn < 2: return _error("회복은 2턴 판정 시작부터 적용합니다.")
	var next := prior_state.duplicate(true); var events: Array = []; var ids: Array = next.keys(); ids.sort()
	for squadron_id in ids:
		var row: Dictionary = next[squadron_id]; var before := _public_row(row)
		var energy_gain := int(floor(float(row.shared.energy_capacity) * float(_rules.resolution_start_recovery.energy_percent_of_capacity) / 100.0))
		row.shared.energy = mini(int(row.shared.energy_capacity), int(row.shared.energy) + energy_gain)
		row.shared.heat = maxi(0, int(row.shared.heat) - int(_rules.resolution_start_recovery.heat_dissipation))
		for weapon_id in row.weapons:
			var weapon_row: Dictionary = row.weapons[weapon_id]
			var carrier_gain := int(ceil(float(weapon_row.carrier_capacity) * float(_rules.resolution_start_recovery.carrier_percent_of_capacity) / 100.0))
			weapon_row.carrier_ready = mini(int(weapon_row.carrier_capacity), int(weapon_row.carrier_ready) + carrier_gain)
		events.append({"event_type": "resource_recovered", "event_id": "REC-%02d-%s" % [resolution_turn, squadron_id],
			"resolution_turn": resolution_turn, "squadron_id": squadron_id, "before": before, "after": _public_row(row)})
	return {"ok": true, "errors": [], "resource_state": next, "recovery_events": events}


func visible_events(viewer_faction_id: String, receipt: Dictionary) -> Dictionary:
	if not _faction_ids().has(viewer_faction_id): return _error("미지 관측 세력입니다: %s" % viewer_faction_id)
	var events: Array = []
	for key in ["consumption_events", "suppressed_fire_events", "recovery_events"]:
		for value in receipt.get(key, []):
			if not value is Dictionary: continue
			var squadron_id := String(value.get("squadron_id", value.get("shooter_squadron_id", "")))
			if String(_find_squad(squadron_id).get("faction_id", "")) == viewer_faction_id: events.append(value.duplicate(true))
	events.sort_custom(func(a, b): return String(a.get("event_id", "")) < String(b.get("event_id", "")))
	return {"ok": true, "errors": [], "viewer_faction_id": viewer_faction_id, "events": events}


func visible_state(viewer_faction_id: String, state: Dictionary) -> Dictionary:
	if not _faction_ids().has(viewer_faction_id): return _error("미지 관측 세력입니다: %s" % viewer_faction_id)
	var result := {}
	for squadron_id in state:
		if String(_find_squad(String(squadron_id)).get("faction_id", "")) == viewer_faction_id: result[squadron_id] = _public_row(state[squadron_id])
	return {"ok": true, "errors": [], "viewer_faction_id": viewer_faction_id, "resource_state": result}


func _shot_cost(weapon_id: String, platform_id: String) -> Dictionary:
	var result: Dictionary = _rules.shot_cost[weapon_id].duplicate(true)
	result.carrier_sorties = int(_rules.carrier_platform_shot_cost.get("%s@%s" % [weapon_id, platform_id], result.carrier_sorties))
	return result


func _shortage_reason(row: Dictionary, weapon_id: String, cost: Dictionary) -> String:
	var weapon: Dictionary = row.weapons[weapon_id]
	if int(weapon.ammo) < int(cost.ammo): return "ammo"
	if int(row.shared.energy) < int(cost.energy): return "energy"
	if int(row.shared.heat) + int(cost.heat) > int(row.shared.heat_capacity): return "overheat"
	if int(weapon.carrier_ready) < int(cost.carrier_sorties): return "carrier_not_returned"
	if int(weapon.special) < int(cost.special): return "special"
	return ""


func _consume(row: Dictionary, weapon_id: String, cost: Dictionary) -> void:
	row.weapons[weapon_id].ammo -= int(cost.ammo); row.shared.energy -= int(cost.energy); row.shared.heat += int(cost.heat)
	row.weapons[weapon_id].carrier_ready -= int(cost.carrier_sorties); row.weapons[weapon_id].special -= int(cost.special)


func _suppressed(event: Dictionary, reason: String, label: String) -> Dictionary:
	var result := {"event_type": "fire_suppressed", "event_id": "SUP-%s" % String(event.event_id), "turn": int(event.get("turn", 0)),
		"shot_event_id": String(event.event_id), "squadron_id": String(event.get("shooter_squadron_id", "")),
		"weapon_id": String(event.get("selected_weapon_id", "")), "reason": reason, "reason_label": label,
		"authorization_type": String(event.get("outcome", ""))}
	if event.has("contact_id"): result["contact_id"] = String(event.contact_id)
	return result


func _public_row(row: Dictionary) -> Dictionary:
	return {"shared": row.shared.duplicate(true), "weapons": row.weapons.duplicate(true)}


func _weapon_platform_count(squad: Dictionary, weapon_id: String) -> int:
	var count := 0; var weapon_rule: Dictionary = _weapon.rules_snapshot().weapons[weapon_id]
	for component in squad.composition:
		if weapon_rule.platforms.has(String(component.ship_type_id)) or weapon_rule.fast_equipment.has(String(component.get("mission_equipment_id", ""))): count += int(component.count)
	return count


func _ship_count(squad: Dictionary, ship_id: String) -> int:
	var count := 0
	for component in squad.composition:
		if String(component.ship_type_id) == ship_id: count += int(component.count)
	return count


func _validate_state(state: Dictionary) -> Dictionary:
	if state.size() != _operational_squadrons().size(): return _error("모든 operational 전대 자원 상태가 필요합니다.")
	for squad in _operational_squadrons():
		var squadron_id := String(squad.id)
		if not state.has(squadron_id) or not state[squadron_id] is Dictionary: return _error("전대 자원 상태가 누락되었습니다: %s" % squadron_id)
		var row: Dictionary = state[squadron_id]
		if not row.get("shared") is Dictionary or not row.get("weapons") is Dictionary or not row.get("last_consumed_event_ids") is Array: return _error("전대 자원 스키마가 잘못되었습니다: %s" % squadron_id)
		var shared: Dictionary = row.shared
		for key in ["energy", "energy_capacity", "heat", "heat_capacity"]:
			if not _nonnegative_integer(shared.get(key)): return _error("공용 자원은 음이 아닌 정수여야 합니다: %s/%s" % [squadron_id, key])
		if int(shared.energy) > int(shared.energy_capacity) or int(shared.heat) > int(shared.heat_capacity): return _error("공용 자원이 용량 범위를 벗어났습니다: %s" % squadron_id)
		var weapon_ids: Array = row.weapons.keys(); weapon_ids.sort()
		if weapon_ids != ["artillery", "intercept", "line_fire", "torpedo"]: return _error("무기별 자원 상태가 누락되었습니다: %s" % squadron_id)
		for weapon_id in weapon_ids:
			var weapon: Dictionary = row.weapons[weapon_id]
			for key in ["ammo", "ammo_capacity", "carrier_ready", "carrier_capacity", "special", "special_capacity"]:
				if not _nonnegative_integer(weapon.get(key)): return _error("무기 자원은 음이 아닌 정수여야 합니다: %s/%s/%s" % [squadron_id, weapon_id, key])
			if int(weapon.ammo) > int(weapon.ammo_capacity) or int(weapon.carrier_ready) > int(weapon.carrier_capacity) or int(weapon.special) > int(weapon.special_capacity): return _error("무기 자원이 용량 범위를 벗어났습니다: %s/%s" % [squadron_id, weapon_id])
		var consumed_seen := {}
		for event_id in row.last_consumed_event_ids:
			if String(event_id).is_empty() or consumed_seen.has(String(event_id)): return _error("소모 이벤트 원장이 잘못되었습니다: %s" % squadron_id)
			consumed_seen[String(event_id)] = true
	return _ok()


func _load_rules() -> Dictionary:
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null: return _error("전투 자원 규칙 파일을 열 수 없습니다.")
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1 or String(parsed.get("profile_id", "")) != "normal-demo-resource-v1": return _error("지원하지 않는 전투 자원 프로필입니다.")
	var ids: Array = parsed.get("shot_cost", {}).keys(); ids.sort()
	if ids != ["artillery", "intercept", "line_fire", "torpedo"] or parsed.get("weapon_initial_per_platform", {}).keys().size() != 4: return _error("무기별 자원 규칙이 잘못되었습니다.")
	if String(parsed.get("resolution_policy", "")) != "shot_authorized_event_id_asc; reserve_and_consume_atomically; selected_weapon_shortage_suppresses_without_fallback": return _error("자원 소모 순서 계약이 잘못되었습니다.")
	var semantics = parsed.get("resource_semantics", {})
	if not semantics is Dictionary or semantics.get("ammo") != "finite_consumable" or semantics.get("energy") != "recoverable_gauge" or semantics.get("heat") != "accumulates_and_cools" or semantics.get("carrier_sorties") != "readiness_and_concurrent_operation_limit_no_permanent_loss" or semantics.get("special") != "finite_charge_in_normal-demo-resource-v1_only": return _error("전투 자원 의미 계약이 잘못되었습니다.")
	var recovery = parsed.get("resolution_start_recovery", {})
	if not recovery is Dictionary or int(recovery.get("starts_at_turn", 0)) != 2 or recovery.get("once_per_turn") != true: return _error("회복 적용 시점 계약이 잘못되었습니다.")
	for table_key in ["weapon_initial_per_platform", "shot_cost"]:
		for row in parsed[table_key].values():
			if not row is Dictionary: return _error("자원 규칙은 객체여야 합니다.")
			for value in row.values():
				if float(value) < 0 or not is_equal_approx(float(value), floor(float(value))): return _error("자원 수치는 음이 아닌 정수여야 합니다.")
	if parsed.get("result_pending") != ["hit", "damage", "casualties", "victory"]: return _error("전투 결과 pending 계약이 잘못되었습니다.")
	return {"ok": true, "errors": [], "rules": parsed.duplicate(true)}


func _operational_squadrons() -> Array:
	var rows: Array = []
	for squad in _setup.get("squadrons", []):
		if bool(squad.get("operational", true)): rows.append(squad)
	rows.sort_custom(func(a, b): return String(a.id) < String(b.id)); return rows


func _find_squad(squadron_id: String) -> Dictionary:
	for squad in _setup.get("squadrons", []):
		if String(squad.id) == squadron_id: return squad
	return {}


func _faction_ids() -> Array:
	var result: Array = []; for faction in _setup.get("factions", []): result.append(String(faction.id))
	return result


func _nonnegative_integer(value) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 and is_equal_approx(float(value), floor(float(value)))


func _ok() -> Dictionary: return {"ok": true, "errors": []}
func _error(message: String) -> Dictionary: return {"ok": false, "errors": [message]}
