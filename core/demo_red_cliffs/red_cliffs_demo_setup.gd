class_name RedCliffsDemoSetup
extends RefCounted

## DEMO-RC-G2-01 — 유비 직행 전투 준비 화면 및 역사적 초기 상태 경계
## 역사적 역할 설명과 normal-demo-v1 게임 수치를 분리해서 검증한다.

const DEFAULT_PATH := "res://data/red-cliffs-demo-setup.json"
const REQUIRED_FACTIONS := ["cao_cao", "sun_quan", "liu_bei"]
const FAST_CRAFT_ID := "SHP-08"
const REQUIRED_FAST_EQUIPMENT := ["FAST-EQ-INTERCEPT", "FAST-EQ-TORPEDO", "FAST-EQ-RECON", "FAST-EQ-RESCUE"]
const REQUIRED_FACTION_CONTROL := {"liu_bei": "player", "sun_quan": "turn_prompt_ai", "cao_cao": "ai"}
## data/formations.json의 현재 정본 ID. 전용 setup 로더가 GameData 전체를
## 초기화하지 않도록 좁은 허용 목록을 명시하고 음성 시험으로 드리프트를 막는다.
const ALLOWED_FORMATION_IDS := ["FRM-01", "FRM-02", "FRM-03", "FRM-04", "FRM-05", "FRM-06", "FRM-07"]


static func load_default() -> Dictionary:
	return load_path(DEFAULT_PATH)


static func load_path(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure(["초기 전투 준비 데이터를 열 수 없습니다: %s" % path])
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	if parse_error != OK:
		return _failure(["초기 전투 준비 JSON이 올바르지 않습니다: %s" % json.get_error_message()])
	if not json.data is Dictionary:
		return _failure(["초기 전투 준비 데이터의 최상위 값은 객체여야 합니다."])
	return validate_document(json.data)


static func validate_document(raw: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	for key in ["schema_version", "setup_id", "battle_id", "title", "player_faction_id",
			"historical_context", "balance_profile", "ship_types", "factions", "squadrons"]:
		if not raw.has(key):
			errors.append("필수 항목 누락: %s" % key)
	if not errors.is_empty():
		return _failure(errors)
	if int(raw.get("schema_version", 0)) != 1:
		errors.append("지원하지 않는 schema_version입니다.")
	if String(raw.get("player_faction_id", "")) != "liu_bei":
		errors.append("플레이어 세력은 liu_bei여야 합니다.")
	var historical = raw.get("historical_context")
	var balance = raw.get("balance_profile")
	if not historical is Dictionary or String(historical.get("statement", "")).is_empty():
		errors.append("역사적 맥락과 한계 설명이 필요합니다.")
	if not balance is Dictionary or String(balance.get("id", "")).is_empty() \
			or String(balance.get("statement", "")).is_empty():
		errors.append("데모 밸런스 프로필과 수치 고지가 필요합니다.")
	elif String(balance.get("id", "")) != "normal-demo-v1":
		errors.append("balance_profile.id는 normal-demo-v1이어야 합니다.")
	if not raw.get("ship_types") is Array or not raw.get("factions") is Array \
			or not raw.get("squadrons") is Array:
		errors.append("ship_types, factions, squadrons는 배열이어야 합니다.")
		return _failure(errors)

	var ship_types: Dictionary = {}
	var equipment_by_ship: Dictionary = {}
	for value in raw["ship_types"]:
		if not value is Dictionary:
			errors.append("함종 행은 객체여야 합니다.")
			continue
		var row: Dictionary = value
		var ship_id := String(row.get("id", ""))
		var name := String(row.get("name", ""))
		var unit_cost = row.get("unit_cost")
		if ship_id.is_empty() or name.is_empty() or not _is_nonnegative_integer(unit_cost):
			errors.append("함종 ID·이름·0 이상의 정수 비용이 필요합니다: %s" % ship_id)
			continue
		if ship_types.has(ship_id):
			errors.append("중복 함종 ID: %s" % ship_id)
			continue
		ship_types[ship_id] = row.duplicate(true)
		var equipment: Dictionary = {}
		if row.has("mission_equipment"):
			if not row["mission_equipment"] is Array:
				errors.append("임무장비 목록은 배열이어야 합니다: %s" % ship_id)
			else:
				for equipment_value in row["mission_equipment"]:
					if not equipment_value is Dictionary:
						errors.append("임무장비 행은 객체여야 합니다: %s" % ship_id)
						continue
					var equipment_row: Dictionary = equipment_value
					var equipment_id := String(equipment_row.get("id", ""))
					var equipment_cost = equipment_row.get("unit_cost")
					if equipment_id.is_empty() or equipment.has(equipment_id) \
							or not _is_nonnegative_integer(equipment_cost):
						errors.append("중복되거나 잘못된 임무장비: %s" % equipment_id)
					else:
						equipment[equipment_id] = equipment_row.duplicate(true)
		equipment_by_ship[ship_id] = equipment
	if not ship_types.has("SHP-07") or String(ship_types["SHP-07"].get("name", "")) != "요격함":
		errors.append("SHP-07 요격함 경계가 필요합니다.")
	if not ship_types.has(FAST_CRAFT_ID):
		errors.append("고속정 기본 선체가 필요합니다.")
	else:
		var fast_equipment: Dictionary = equipment_by_ship.get(FAST_CRAFT_ID, {})
		var equipment_ids: Array = fast_equipment.keys()
		equipment_ids.sort()
		var expected_ids: Array = REQUIRED_FAST_EQUIPMENT.duplicate()
		expected_ids.sort()
		if equipment_ids != expected_ids:
			errors.append("고속정 임무장비는 요격·뇌격·정찰·구조 4종만 허용합니다.")

	var faction_ids: Dictionary = {}
	var faction_controls: Dictionary = {}
	for value in raw["factions"]:
		if not value is Dictionary:
			errors.append("세력 행은 객체여야 합니다.")
			continue
		var faction: Dictionary = value
		var faction_id := String(faction.get("id", ""))
		if faction_id.is_empty() or faction_ids.has(faction_id):
			errors.append("누락되거나 중복된 세력 ID: %s" % faction_id)
		else:
			faction_ids[faction_id] = true
			faction_controls[faction_id] = String(faction.get("control", ""))
		if String(faction.get("name", "")).is_empty() or String(faction.get("control", "")).is_empty() \
				or String(faction.get("supreme_commander", "")).is_empty():
			errors.append("세력 이름·제어 방식·지휘관이 필요합니다: %s" % faction_id)
	for faction_id in REQUIRED_FACTIONS:
		if not faction_ids.has(faction_id):
			errors.append("필수 참가 세력 누락: %s" % faction_id)
		elif String(faction_controls.get(faction_id, "")) != String(REQUIRED_FACTION_CONTROL[faction_id]):
			errors.append("세력 제어 방식 불일치: %s는 %s여야 합니다." % [faction_id,
			String(REQUIRED_FACTION_CONTROL[faction_id])])

	var squadron_ids: Dictionary = {}
	var faction_squadron_counts: Dictionary = {}
	var normalized_squadrons: Array[Dictionary] = []
	for value in raw["squadrons"]:
		if not value is Dictionary:
			errors.append("전대 행은 객체여야 합니다.")
			continue
		var squadron: Dictionary = value
		var squadron_id := String(squadron.get("id", ""))
		var faction_id := String(squadron.get("faction_id", ""))
		if squadron_id.is_empty() or squadron_ids.has(squadron_id):
			errors.append("누락되거나 중복된 전대 ID: %s" % squadron_id)
			continue
		squadron_ids[squadron_id] = true
		if not faction_ids.has(faction_id):
			errors.append("전대의 세력이 존재하지 않습니다: %s" % faction_id)
		if not squadron.get("commander") is Dictionary \
				or String(squadron["commander"].get("id", "")).is_empty() \
				or String(squadron["commander"].get("name", "")).is_empty():
			errors.append("전대 지휘관 ID·이름이 필요합니다: %s" % squadron_id)
		if not squadron.get("flagship") is bool:
			errors.append("전대 기함 여부가 필요합니다: %s" % squadron_id)
		if not squadron.get("initial_position") is Array or squadron["initial_position"].size() != 2 \
				or not squadron["initial_position"][0] is int and not squadron["initial_position"][0] is float \
				or not squadron["initial_position"][1] is int and not squadron["initial_position"][1] is float:
			errors.append("전대 초기 2D 좌표 두 값이 필요합니다: %s" % squadron_id)
		if String(squadron.get("name", "")).is_empty() or String(squadron.get("formation_id", "")).is_empty() \
				or String(squadron.get("historical_basis", "")).is_empty():
			errors.append("전대 이름·진형·역사 역할 기준이 필요합니다: %s" % squadron_id)
		elif not ALLOWED_FORMATION_IDS.has(String(squadron.get("formation_id", ""))):
			errors.append("미지 진형 ID: %s/%s" % [squadron_id, String(squadron.get("formation_id", ""))])
		var composition = squadron.get("composition")
		if not composition is Array or composition.is_empty():
			errors.append("전대 함종 구성이 필요합니다: %s" % squadron_id)
			continue
		var composition_ship_ids: Dictionary = {}
		var calculated_total := 0
		for component_value in composition:
			if not component_value is Dictionary:
				errors.append("전대 구성 행은 객체여야 합니다: %s" % squadron_id)
				continue
			var component: Dictionary = component_value
			var ship_id := String(component.get("ship_type_id", ""))
			var count = component.get("count")
			if composition_ship_ids.has(ship_id):
				errors.append("전대 안의 중복 함종: %s/%s" % [squadron_id, ship_id])
				continue
			composition_ship_ids[ship_id] = true
			if not ship_types.has(ship_id):
				errors.append("미지 함종: %s/%s" % [squadron_id, ship_id])
				continue
			if not _is_nonnegative_integer(count):
				errors.append("함종 수량은 0 이상의 정수여야 합니다: %s/%s" % [squadron_id, ship_id])
				continue
			var component_cost := int(ship_types[ship_id]["unit_cost"])
			var equipment_id := String(component.get("mission_equipment_id", ""))
			if ship_id == FAST_CRAFT_ID:
				var equipment: Dictionary = equipment_by_ship.get(ship_id, {})
				if equipment_id.is_empty() or not equipment.has(equipment_id):
					errors.append("고속정에는 유효한 임무장비가 필요합니다: %s" % squadron_id)
				else:
					component_cost += int(equipment[equipment_id]["unit_cost"])
			elif not equipment_id.is_empty():
				errors.append("고속정 외 함종에는 임무장비를 지정할 수 없습니다: %s/%s" % [squadron_id, ship_id])
			calculated_total += int(count) * component_cost
		var declared = squadron.get("declared_total_cost")
		if not _is_nonnegative_integer(declared):
			errors.append("전대 선언 총비용은 0 이상의 정수여야 합니다: %s" % squadron_id)
		elif int(declared) != calculated_total:
			errors.append("전대 비용 합계 불일치: %s (선언 %d / 계산 %d)" % [squadron_id, int(declared), calculated_total])
		var normalized := squadron.duplicate(true)
		normalized["calculated_total_cost"] = calculated_total
		normalized_squadrons.append(normalized)
		faction_squadron_counts[faction_id] = int(faction_squadron_counts.get(faction_id, 0)) + 1
	for faction_id in REQUIRED_FACTIONS:
		if int(faction_squadron_counts.get(faction_id, 0)) < 1:
			errors.append("세력별 최소 전대 누락: %s" % faction_id)
	if not errors.is_empty():
		return _failure(errors)
	var setup := raw.duplicate(true)
	setup["squadrons"] = normalized_squadrons
	return {"ok": true, "errors": ([] as Array[String]), "setup": setup}


static func _failure(errors: Array[String]) -> Dictionary:
	return {"ok": false, "errors": errors.duplicate(), "setup": {}}


static func _is_nonnegative_integer(value) -> bool:
	if value is int:
		return int(value) >= 0
	if value is float:
		return float(value) >= 0.0 and is_equal_approx(float(value), floor(float(value)))
	return false
