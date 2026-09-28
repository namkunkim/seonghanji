class_name RedCliffsDetectionResolver
extends RefCounted

## DEMO-RC-G5-02 — 구조화 편성·장수 지력·진형 탐지 보정 권위.
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Formation := preload("res://core/demo_red_cliffs/red_cliffs_formation_resolver.gd")
const Terrain := preload("res://core/demo_red_cliffs/red_cliffs_terrain_resolver.gd")
const RULES_PATH := "res://data/red-cliffs-sensor-ew-rules.json"
const CHARACTERS_PATH := "res://data/characters.json"
var _setup: Dictionary = {}; var _rules: Dictionary = {}; var _characters: Dictionary = {}; var _formation; var _terrain

func initialize(applied_setup: Dictionary) -> Dictionary:
	var checked := Setup.validate_document(applied_setup); if not checked.ok: return _error("유효한 G3 적용 편성이 필요합니다.")
	var loaded := _load_rules(); if not loaded.ok: return loaded
	var characters := _load_characters(checked.setup); if not characters.ok: return characters
	var formation = Formation.new(); var formation_result: Dictionary = formation.initialize(checked.setup); if not formation_result.ok: return formation_result
	var terrain = Terrain.new(); var terrain_result: Dictionary = terrain.initialize(checked.setup); if not terrain_result.ok: return terrain_result
	_setup = checked.setup.duplicate(true); _rules = loaded.rules.duplicate(true); _characters = characters.characters.duplicate(true); _formation = formation; _terrain = terrain
	return _ok()

func rules_snapshot() -> Dictionary: return _rules.duplicate(true)
func initial_formation_state() -> Dictionary: return _formation.initial_state()

func evaluate(observer_squadron_id: String, target_squadron_id: String, distance: float, formation_state: Dictionary,
		observer_position = null, target_position = null, sensor_effect_percent: int = 0, temporary_zones: Array = []) -> Dictionary:
	if not is_finite(distance) or distance < 0.0: return _error("탐지 거리는 0 이상의 유한값이어야 합니다.")
	var observer := _find_squad(observer_squadron_id); var target := _find_squad(target_squadron_id)
	if observer.is_empty() or target.is_empty() or String(observer.faction_id) == String(target.faction_id): return _error("탐지 observer-target 쌍이 잘못되었습니다.")
	var snapshots: Dictionary = _formation.modifier_snapshots(formation_state)
	if not snapshots.has(observer_squadron_id): return _error("observer 진형 상태가 누락되거나 잘못되었습니다.")
	var ship_sensor := _composition_points(observer, _rules.ship_sensor_points, _rules.fast_equipment_sensor_points)
	var target_ew := _composition_points(target, _rules.ship_ew_points, _rules.fast_equipment_ew_points)
	var commander_id := String(observer.commander.id); var intelligence := int(_characters[commander_id].stats["지력"]); var intelligence_points := _intelligence_points(intelligence)
	var formation_id := String(snapshots[observer_squadron_id].formation_id); var formation_percent := int(snapshots[observer_squadron_id].modifiers.detection_percent)
	var observer_terrain: Dictionary = _terrain.point_effects(observer_position, temporary_zones) if observer_position is Array else _terrain.point_effects([-9999, -9999], temporary_zones)
	var target_terrain: Dictionary = _terrain.point_effects(target_position, temporary_zones) if target_position is Array else _terrain.point_effects([-9999, -9999], temporary_zones)
	var total_sensor_percent := formation_percent + int(observer_terrain.observer_sensor_percent) + sensor_effect_percent
	var adjusted_sensor := _percent_round_half_up(ship_sensor, total_sensor_percent); var distance_penalty := int(floor(distance / float(_rules.distance_penalty.units_per_point)))
	var effective_target_ew := target_ew + int(target_terrain.target_concealment_points)
	var score := adjusted_sensor + intelligence_points - effective_target_ew - distance_penalty
	var state := "confirmed" if score >= int(_rules.thresholds.confirmed) else ("estimated" if score >= int(_rules.thresholds.estimated) else "undetected")
	var threshold := int(_rules.thresholds.confirmed) if state == "confirmed" else int(_rules.thresholds.estimated); var margin := score - threshold
	var labels := {"confirmed": "센서 점수가 확인 임계 이상", "estimated": "센서 점수가 추정 임계 이상", "undetected": "센서 점수가 추정 임계 미만"}
	var own_breakdown := {"ship_sensor_points": ship_sensor, "formation_adjusted_sensor_points": adjusted_sensor, "commander_id": commander_id,
		"commander_name": String(_characters[commander_id].name), "intelligence_band": _intelligence_band_label(intelligence), "intelligence_sensor_points": intelligence_points, "combat_effect_sensor_percent":sensor_effect_percent,
		"own_terrain_zone_ids": observer_terrain.zone_ids.duplicate(), "own_terrain_sensor_percent": int(observer_terrain.observer_sensor_percent)}
	return {"ok": true, "errors": [], "state": state, "margin": margin,
		"authoritative": {"observer_squadron_id": observer_squadron_id, "target_squadron_id": target_squadron_id, "distance": distance,
			"own_sensor_breakdown": own_breakdown.duplicate(true), "target_ew_points": target_ew, "target_terrain_concealment_points": int(target_terrain.target_concealment_points), "distance_penalty": distance_penalty,
			"score": score, "margin": margin, "formation_id": formation_id, "formation_detection_percent": formation_percent, "terrain_modifier_points": 0},
		"viewer_basis": {"result_state": state, "reason_code": "%s_score_gate" % state, "reason_label": labels[state],
			"observer_formation_id": formation_id, "observer_formation_detection_percent": formation_percent, "own_sensor_breakdown": own_breakdown,
			"terrain_status": "active_normal_demo", "terrain_label": String(_rules.terrain.label), "rules_pending": []}}

func _percent_round_half_up(value: int, percent: int) -> int: return int(floor(float(value * (100 + percent) + 50) / 100.0))

func _composition_points(squad: Dictionary, ship_table: Dictionary, equipment_table: Dictionary) -> int:
	var total := 0
	for value in squad.composition:
		var row: Dictionary = value; var count := int(row.count); total += count * int(ship_table[String(row.ship_type_id)])
		var equipment_id := String(row.get("mission_equipment_id", "")); if not equipment_id.is_empty(): total += count * int(equipment_table[equipment_id])
	return total

func _intelligence_points(intelligence: int) -> int:
	for band in _rules.intelligence_bands:
		if intelligence >= int(band.min) and intelligence <= int(band.max): return int(band.sensor_points)
	return -1

func _intelligence_band_label(intelligence: int) -> String:
	for band in _rules.intelligence_bands:
		if intelligence >= int(band.min) and intelligence <= int(band.max): return "%d~%d" % [int(band.min), int(band.max)]
	return ""

func _find_squad(squadron_id: String) -> Dictionary:
	for squad in _setup.squadrons:
		if String(squad.id) == squadron_id: return squad
	return {}

func _load_characters(setup: Dictionary) -> Dictionary:
	var file := FileAccess.open(CHARACTERS_PATH, FileAccess.READ); if file == null: return _error("characters.json을 열 수 없습니다.")
	var parsed = JSON.parse_string(file.get_as_text()); if not parsed is Array: return _error("characters.json 형식이 잘못되었습니다.")
	var index := {}; for value in parsed:
		if value is Dictionary: index[String(value.get("id", ""))] = value
	var needed := {}
	for squad in setup.squadrons:
		if not bool(squad.get("operational", true)): continue
		var commander_id := String(squad.commander.id); needed[commander_id] = true
		if not index.has(commander_id) or String(index[commander_id].get("name", "")) != String(squad.commander.name): return _error("배치 지휘관 ID·이름이 characters.json과 다릅니다: %s" % commander_id)
		var stats = index[commander_id].get("stats", {}); if not stats is Dictionary or not _bounded_intelligence(stats.get("지력")): return _error("배치 지휘관 지력이 잘못되었습니다: %s" % commander_id)
	var result := {}; for commander_id in needed: result[commander_id] = index[commander_id].duplicate(true)
	return {"ok": true, "errors": [], "characters": result}

func _load_rules() -> Dictionary:
	var file := FileAccess.open(RULES_PATH, FileAccess.READ); if file == null: return _error("센서·전자전 규칙 파일을 열 수 없습니다.")
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1 or String(parsed.get("profile_id", "")) != "normal-demo-sensor-ew-v1": return _error("지원하지 않는 센서·전자전 프로필입니다.")
	var ship_ids := ["SHP-01", "SHP-02", "SHP-03", "SHP-04", "SHP-05", "SHP-06", "SHP-07", "SHP-08"]
	for table_name in ["ship_sensor_points", "ship_ew_points"]:
		var table = parsed.get(table_name, {}); var ids: Array = table.keys() if table is Dictionary else []; ids.sort()
		if ids != ship_ids: return _error("함종 센서/EW 표가 정확하지 않습니다: %s" % table_name)
		for value in table.values():
			if not _nonnegative_integer(value): return _error("함종 센서/EW 값이 잘못되었습니다.")
	var equipment_ids: Array = Setup.REQUIRED_FAST_EQUIPMENT.duplicate(); equipment_ids.sort()
	for table_name in ["fast_equipment_sensor_points", "fast_equipment_ew_points"]:
		var table = parsed.get(table_name, {}); var ids: Array = table.keys() if table is Dictionary else []; ids.sort()
		if ids != equipment_ids: return _error("고속정 장비 센서/EW 표가 정확하지 않습니다: %s" % table_name)
		for value in table.values():
			if not _nonnegative_integer(value): return _error("고속정 장비 센서/EW 값이 잘못되었습니다.")
	var bands = parsed.get("intelligence_bands", []); if not bands is Array or bands.size() != 5: return _error("지력 구간 표가 잘못되었습니다.")
	var next_min := 0
	for band in bands:
		if not band is Dictionary or int(band.get("min", -1)) != next_min or int(band.get("max", -1)) < next_min or not _nonnegative_integer(band.get("sensor_points")): return _error("지력 구간이 연속적이지 않습니다.")
		next_min = int(band.max) + 1
	if next_min != 101: return _error("지력 구간은 0~100을 정확히 덮어야 합니다.")
	var distance_rule = parsed.get("distance_penalty", {}); var thresholds = parsed.get("thresholds", {})
	if not distance_rule is Dictionary or int(distance_rule.get("units_per_point", 0)) != 25 or String(distance_rule.get("rounding", "")) != "floor_nonnegative" or not thresholds is Dictionary or int(thresholds.get("confirmed", 0)) != 37 or int(thresholds.get("estimated", 0)) != 15: return _error("거리 penalty 또는 threshold 계약이 잘못되었습니다.")
	if String(parsed.get("score_formula", "")) != "score=round_half_up(ship_sensor*(100+formation_detection_percent)/100)+intelligence_band_sensor-target_ew-floor(distance/units_per_point)+terrain_modifier": return _error("탐지 score 공식이 잘못되었습니다.")
	if String(parsed.get("threshold_policy", "")) != "score_gte_confirmed_then_confirmed; else_score_gte_estimated_then_estimated; else_undetected; exact_tie_is_in_range" or String(parsed.get("multi_observer_merge", "")) != "state_rank_desc; last_seen_turn_desc; margin_desc; observer_squadron_id_asc": return _error("탐지 동률·병합 정책이 잘못되었습니다.")
	if String(parsed.get("formation_profile", "")) != "normal-demo-formation-v1" or String(parsed.get("character_source", "")) != "res://data/characters.json#stats.지력; assigned_commander_id_and_name_exact": return _error("진형·장수 정본 연결이 잘못되었습니다.")
	var terrain = parsed.get("terrain", {})
	if not terrain is Dictionary or String(terrain.get("status", "")) != "active_normal_demo" or int(terrain.get("modifier_points", -1)) != 0 or terrain.get("rules_pending") != [] or String(terrain.get("label", "")) != "적벽 전용 지형 보정 적용": return _error("지형 적용 계약이 잘못되었습니다.")
	return {"ok": true, "errors": [], "rules": parsed.duplicate(true)}

func _bounded_intelligence(value) -> bool: return _nonnegative_integer(value) and int(value) <= 100
func _nonnegative_integer(value) -> bool: return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0 and is_equal_approx(float(value), floor(float(value)))
func _ok() -> Dictionary: return {"ok": true, "errors": []}
func _error(message: String) -> Dictionary: return {"ok": false, "errors": [message]}
