class_name RedCliffsDemoSetup
extends RefCounted

## DEMO-RC-G2-01 / DEMO-RC-G3-01 data boundary.
const DEFAULT_PATH := "res://data/red-cliffs-demo-setup.json"
const REQUIRED_FACTIONS := ["cao_cao", "sun_quan", "liu_bei"]
const REQUIRED_CONTROL := {"liu_bei": "player", "sun_quan": "turn_prompt_ai", "cao_cao": "ai"}
const FAST_CRAFT_ID := "SHP-08"
const REQUIRED_FAST_EQUIPMENT := ["FAST-EQ-INTERCEPT", "FAST-EQ-TORPEDO", "FAST-EQ-RECON", "FAST-EQ-RESCUE"]
const ALLOWED_FORMATION_IDS := ["FRM-01", "FRM-02", "FRM-03", "FRM-04", "FRM-05", "FRM-06", "FRM-07"]


static func load_default() -> Dictionary:
	return load_path(DEFAULT_PATH)


static func load_path(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _failure(["초기 전투 준비 데이터를 열 수 없습니다: %s" % path])
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK: return _failure(["초기 전투 준비 JSON이 올바르지 않습니다: %s" % json.get_error_message()])
	if not json.data is Dictionary: return _failure(["초기 전투 준비 데이터의 최상위 값은 객체여야 합니다."])
	return validate_document(json.data)


static func validate_document(raw: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	for key in ["schema_version", "setup_id", "battle_id", "title", "player_faction_id", "formation_revision", "formation_options", "battlefield_bounds", "command_limit_rules", "historical_context", "balance_profile", "ship_types", "factions", "squadrons", "fleet_groups"]:
		if not raw.has(key): errors.append("필수 항목 누락: %s" % key)
	if not errors.is_empty(): return _failure(errors)
	if int(raw.get("schema_version", 0)) != 1: errors.append("지원하지 않는 schema_version입니다.")
	if String(raw.get("player_faction_id", "")) != "liu_bei": errors.append("플레이어 세력은 liu_bei여야 합니다.")
	if not _nonnegative_int(raw.get("formation_revision")): errors.append("편성 버전은 0 이상의 정수여야 합니다.")
	var options = raw.get("formation_options")
	if not options is Dictionary or not options.get("sun_manual") is bool: errors.append("손권 수동 편성 옵션은 bool이어야 합니다.")
	var bounds = raw.get("battlefield_bounds")
	if not _valid_bounds(bounds): errors.append("전장 유효 경계는 [x, y, width, height] 양수 영역이어야 합니다.")
	var historical = raw.get("historical_context")
	if not historical is Dictionary or String(historical.get("statement", "")).is_empty(): errors.append("역사적 맥락과 한계 설명이 필요합니다.")
	_validate_balance(raw.get("balance_profile"), errors)
	_validate_command_limit_rules(raw.get("command_limit_rules"), errors)
	if not raw.get("ship_types") is Array or not raw.get("factions") is Array or not raw.get("squadrons") is Array or not raw.get("fleet_groups") is Array:
		errors.append("ship_types, factions, squadrons, fleet_groups는 배열이어야 합니다."); return _failure(errors)

	var ships := {}; var equipment := {}
	for value in raw["ship_types"]:
		if not value is Dictionary: errors.append("함종 행은 객체여야 합니다."); continue
		var row: Dictionary = value; var ship_id := String(row.get("id", ""))
		if ship_id.is_empty() or ships.has(ship_id) or String(row.get("name", "")).is_empty() or not _nonnegative_int(row.get("unit_cost")):
			errors.append("누락·중복되거나 잘못된 함종: %s" % ship_id); continue
		ships[ship_id] = row.duplicate(true); equipment[ship_id] = {}
		if row.has("mission_equipment"):
			if not row["mission_equipment"] is Array: errors.append("임무장비 목록은 배열이어야 합니다: %s" % ship_id)
			else:
				for eq_value in row["mission_equipment"]:
					if not eq_value is Dictionary: errors.append("임무장비 행은 객체여야 합니다."); continue
					var eq: Dictionary = eq_value; var eq_id := String(eq.get("id", ""))
					if eq_id.is_empty() or equipment[ship_id].has(eq_id) or not _nonnegative_int(eq.get("unit_cost")): errors.append("중복되거나 잘못된 임무장비: %s" % eq_id)
					else: equipment[ship_id][eq_id] = eq.duplicate(true)
	if not ships.has("SHP-07") or String(ships["SHP-07"].get("name", "")) != "요격함": errors.append("SHP-07 요격함 경계가 필요합니다.")
	if not ships.has(FAST_CRAFT_ID): errors.append("고속정 기본 선체가 필요합니다.")
	else:
		var actual: Array = equipment[FAST_CRAFT_ID].keys(); actual.sort()
		var expected: Array = REQUIRED_FAST_EQUIPMENT.duplicate(); expected.sort()
		if actual != expected: errors.append("고속정 임무장비는 요격·뇌격·정찰·구조 4종만 허용합니다.")

	var factions := {}; var rosters := {}
	for value in raw["factions"]:
		if not value is Dictionary: errors.append("세력 행은 객체여야 합니다."); continue
		var faction: Dictionary = value; var fid := String(faction.get("id", ""))
		if fid.is_empty() or factions.has(fid): errors.append("누락되거나 중복된 세력 ID: %s" % fid); continue
		factions[fid] = faction.duplicate(true)
		if String(faction.get("control", "")) != String(REQUIRED_CONTROL.get(fid, "")): errors.append("세력 제어 방식 불일치: %s" % fid)
		var inventory = faction.get("inventory")
		if not inventory is Dictionary: errors.append("세력 재고가 필요합니다: %s" % fid)
		else:
			for ship_id in inventory:
				if not ships.has(ship_id) or not _nonnegative_int(inventory[ship_id]): errors.append("미지 함종 또는 잘못된 재고: %s/%s" % [fid, ship_id])
			for ship_id in ships:
				if not inventory.has(ship_id): errors.append("세력 재고 함종 누락: %s/%s" % [fid, ship_id])
		var roster = faction.get("demo_roster"); var roster_index := {}
		if not roster is Array or roster.is_empty(): errors.append("데모 가용 장수 명단이 필요합니다: %s" % fid)
		else:
			for commander_value in roster:
				if not commander_value is Dictionary: errors.append("장수 행은 객체여야 합니다."); continue
				var commander: Dictionary = commander_value; var cid := String(commander.get("id", ""))
				if cid.is_empty() or roster_index.has(cid) or String(commander.get("name", "")).is_empty() or not _nonnegative_int(commander.get("command")) or int(commander.get("command", 101)) > 100 or not _nonnegative_int(commander.get("level")): errors.append("누락·중복되거나 잘못된 가용 장수: %s/%s" % [fid, cid])
				else: roster_index[cid] = commander.duplicate(true)
		rosters[fid] = roster_index
	for fid in REQUIRED_FACTIONS:
		if not factions.has(fid): errors.append("필수 참가 세력 누락: %s" % fid)

	var squad_index := {}; var normalized := []; var usage := {}; var assigned_commanders := {}; var faction_squadron_counts := {}
	for value in raw["squadrons"]:
		if not value is Dictionary: errors.append("전대 행은 객체여야 합니다."); continue
		var squad: Dictionary = value; var sid := String(squad.get("id", "")); var fid := String(squad.get("faction_id", ""))
		if sid.is_empty() or squad_index.has(sid): errors.append("누락되거나 중복된 전대 ID: %s" % sid); continue
		squad_index[sid] = squad
		faction_squadron_counts[fid] = int(faction_squadron_counts.get(fid, 0)) + 1
		if not factions.has(fid): errors.append("전대의 세력이 존재하지 않습니다: %s" % fid)
		var commander = squad.get("commander"); var cid := String(commander.get("id", "")) if commander is Dictionary else ""
		if cid.is_empty() or not rosters.get(fid, {}).has(cid): errors.append("같은 세력의 가용 장수가 아닙니다: %s/%s" % [sid, cid])
		elif assigned_commanders.has("%s/%s" % [fid, cid]): errors.append("지휘관 중복 배치: %s" % cid)
		else: assigned_commanders["%s/%s" % [fid, cid]] = true
		if not squad.get("flagship") is bool: errors.append("전대 기함 여부가 필요합니다: %s" % sid)
		if not _valid_position(squad.get("initial_position"), bounds): errors.append("전대 좌표가 전장 경계 밖입니다: %s" % sid)
		if not ALLOWED_FORMATION_IDS.has(String(squad.get("formation_id", ""))): errors.append("미지 진형 ID: %s/%s" % [sid, squad.get("formation_id", "")])
		var deploy = squad.get("deployment")
		if not deploy is Dictionary or not ["fleet", "independent"].has(String(deploy.get("kind", ""))): errors.append("전대 배치 방식이 필요합니다: %s" % sid)
		var cost_result := calculate_squadron_cost(squad, ships, equipment)
		for error in cost_result.errors: errors.append("%s: %s" % [sid, error])
		if int(cost_result.count) <= 0: errors.append("전대 전체 함선 수는 1척 이상이어야 합니다: %s" % sid)
		if not _nonnegative_int(squad.get("declared_total_cost")) or int(squad.get("declared_total_cost", -1)) != int(cost_result.cost): errors.append("전대 비용 합계 불일치: %s" % sid)
		var out := squad.duplicate(true); out["calculated_total_cost"] = int(cost_result.cost); normalized.append(out)
		for component in squad.get("composition", []):
			if component is Dictionary and ships.has(String(component.get("ship_type_id", ""))) and _nonnegative_int(component.get("count")):
				var used: Dictionary = usage.get(fid, {}); var ship_id := String(component.ship_type_id); used[ship_id] = int(used.get(ship_id, 0)) + int(component.count); usage[fid] = used
	for fid in usage:
		for ship_id in usage[fid]:
			if int(usage[fid][ship_id]) > int(factions.get(fid, {}).get("inventory", {}).get(ship_id, -1)): errors.append("세력 재고 초과: %s/%s" % [fid, ship_id])
	for fid in REQUIRED_FACTIONS:
		var minimum := 2 if fid == "liu_bei" else 1
		if int(faction_squadron_counts.get(fid, 0)) < minimum: errors.append("세력별 최소 전대 누락: %s (최소 %d)" % [fid, minimum])
	_validate_fleets(raw.fleet_groups, squad_index, errors)
	if not errors.is_empty(): return _failure(errors)
	var setup := raw.duplicate(true); setup.squadrons = normalized
	return {"ok": true, "errors": ([] as Array[String]), "setup": setup}


static func calculate_squadron_cost(squad: Dictionary, ships: Dictionary, equipment: Dictionary) -> Dictionary:
	var errors: Array[String] = []; var seen := {}; var cost := 0; var count := 0
	var composition = squad.get("composition")
	if not composition is Array: return {"cost": 0, "count": 0, "errors": ["전대 함종 구성이 필요합니다."]}
	for value in composition:
		if not value is Dictionary: errors.append("전대 구성 행은 객체여야 합니다."); continue
		var row: Dictionary = value; var ship_id := String(row.get("ship_type_id", "")); var quantity = row.get("count")
		if seen.has(ship_id): errors.append("전대 안의 중복 함종: %s" % ship_id); continue
		seen[ship_id] = true
		if not ships.has(ship_id): errors.append("미지 함종: %s" % ship_id); continue
		if not _nonnegative_int(quantity): errors.append("함종 수량은 0 이상의 정수여야 합니다: %s" % ship_id); continue
		var unit_cost := int(ships[ship_id].unit_cost); var eq_id := String(row.get("mission_equipment_id", ""))
		if ship_id == FAST_CRAFT_ID:
			if not equipment.get(ship_id, {}).has(eq_id): errors.append("고속정에는 유효한 임무장비가 필요합니다.")
			else: unit_cost += int(equipment[ship_id][eq_id].unit_cost)
		elif not eq_id.is_empty(): errors.append("고속정 외 함종에는 임무장비를 지정할 수 없습니다: %s" % ship_id)
		cost += int(quantity) * unit_cost; count += int(quantity)
	return {"cost": cost, "count": count, "errors": errors}


static func _validate_balance(balance, errors: Array[String]) -> void:
	if not balance is Dictionary or String(balance.get("id", "")) != "normal-demo-v1" or String(balance.get("statement", "")).is_empty(): errors.append("balance_profile.id는 normal-demo-v1이어야 하며 수치 고지가 필요합니다.")


static func _validate_command_limit_rules(rules, errors: Array[String]) -> void:
	if not rules is Dictionary: errors.append("지휘 한도·초과 불이익 규칙이 필요합니다."); return
	if rules.get("recommended_base_cost") != 40: errors.append("권장 비용 기본값은 40이어야 합니다.")
	if rules.get("recommended_cost_per_command") != 2: errors.append("통솔 1당 권장 비용은 2여야 합니다.")
	if not is_equal_approx(float(rules.get("over_tier_ratio", 0.0)), 0.25): errors.append("초과 단계 비율은 0.25여야 합니다.")
	if rules.get("max_penalty_tier") != 4: errors.append("초과 불이익 최대 단계는 4여야 합니다.")
	var penalty = rules.get("penalty_per_tier")
	if not penalty is Dictionary: errors.append("단계별 불이익 규칙이 필요합니다.")
	else:
		if penalty.get("mobility_percent") != 5: errors.append("단계당 기동 불이익은 5%여야 합니다.")
		if penalty.get("accuracy_percent") != 4: errors.append("단계당 명중 불이익은 4%여야 합니다.")
		if penalty.get("formation_change_percent") != 8: errors.append("단계당 진형 변경 불이익은 8%여야 합니다.")


static func _validate_fleets(fleets: Array, squads: Dictionary, errors: Array[String]) -> void:
	var fleet_ids := {}; var assigned := {}
	for value in fleets:
		if not value is Dictionary: errors.append("함대 행은 객체여야 합니다."); continue
		var fleet: Dictionary = value; var fleet_id := String(fleet.get("id", "")); var fid := String(fleet.get("faction_id", "")); var members = fleet.get("squadron_ids")
		if fleet_id.is_empty() or fleet_ids.has(fleet_id): errors.append("누락되거나 중복된 함대 ID: %s" % fleet_id); continue
		fleet_ids[fleet_id] = true
		if String(fleet.get("name", "")).strip_edges().is_empty(): errors.append("함대 이름이 필요합니다: %s" % fleet_id)
		if not members is Array or members.is_empty(): errors.append("함대에는 최소 1개 전대가 필요합니다: %s" % fleet_id); continue
		var local := {}
		for sid_value in members:
			var sid := String(sid_value)
			if local.has(sid) or assigned.has(sid): errors.append("전대 중복 소속: %s" % sid); continue
			local[sid] = true; assigned[sid] = fleet_id
			if not squads.has(sid): errors.append("미지 전대 함대 소속: %s" % sid)
			elif String(squads[sid].get("faction_id", "")) != fid: errors.append("함대 내 세력 혼합: %s/%s" % [fleet_id, sid])
			elif String(squads[sid].get("deployment", {}).get("fleet_id", "")) != fleet_id: errors.append("전대·함대 소속 불일치: %s" % sid)
		if not local.has(String(fleet.get("flagship_squadron_id", ""))): errors.append("함대 기함 전대가 소속 목록에 없습니다: %s" % fleet_id)
	for sid in squads:
		var deploy: Dictionary = squads[sid].get("deployment", {})
		if String(deploy.get("kind", "")) == "fleet" and not assigned.has(sid): errors.append("함대 소속이 누락된 전대: %s" % sid)
		if String(deploy.get("kind", "")) == "independent" and assigned.has(sid): errors.append("독립 전대가 함대에 중복 소속되었습니다: %s" % sid)
		var should_be_flagship: bool = String(deploy.get("kind", "")) == "fleet" and String(_fleet_flagship_for(String(assigned.get(sid, "")), fleets)) == sid
		if bool(squads[sid].get("flagship", false)) != should_be_flagship: errors.append("전대 기함 표시 불일치: %s" % sid)


static func _fleet_flagship_for(fleet_id: String, fleets: Array) -> String:
	for fleet in fleets:
		if fleet is Dictionary and String(fleet.get("id", "")) == fleet_id: return String(fleet.get("flagship_squadron_id", ""))
	return ""


static func _valid_bounds(value) -> bool:
	return value is Array and value.size() == 4 and _numbers(value) and float(value[2]) > 0 and float(value[3]) > 0


static func _valid_position(value, bounds) -> bool:
	return value is Array and value.size() == 2 and _numbers(value) and _valid_bounds(bounds) and float(value[0]) >= float(bounds[0]) and float(value[1]) >= float(bounds[1]) and float(value[0]) <= float(bounds[0]) + float(bounds[2]) and float(value[1]) <= float(bounds[1]) + float(bounds[3])


static func _numbers(values: Array) -> bool:
	for value in values:
		if not value is int and not value is float: return false
	return true


static func _failure(errors: Array[String]) -> Dictionary:
	return {"ok": false, "errors": errors.duplicate(), "setup": {}}


static func _nonnegative_int(value) -> bool:
	return value is int and int(value) >= 0 or value is float and float(value) >= 0.0 and is_equal_approx(float(value), floor(float(value)))
