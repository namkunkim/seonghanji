extends SceneTree

const Harness := preload("res://tests/harness.gd")
var _pass := 0
var _fail := 0


func _ok(condition: bool, label: String) -> void:
	if condition:
		_pass += 1
	else:
		_fail += 1
		print("  실패: %s" % label)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])


func _init() -> void:
	print("A-05 진형 전투 코어")
	_test_ids_and_persistence()
	_test_coefficients_and_matchups()
	_test_paljin_and_terrain_verdicts()
	_test_fixed_point_composition()
	_test_generic_resolver_reads_live_formation()
	_test_battle_change_contract()
	_test_exhaustive_coefficients_and_command_arrival()
	print("통과 %d · 실패 %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)


func _test_ids_and_persistence() -> void:
	var names := ["어린진", "학익진", "방원진", "안행진", "봉시진", "장사진", "팔진"]
	for index in names.size():
		var formation_id := "FRM-%02d" % [index + 1]
		_eq(Formations.id_for_name(names[index]), formation_id, "%s ID" % names[index])
		_eq(Formations.name_for_id(formation_id), names[index], "%s name" % formation_id)
		_eq(Formations.normalized_persisted_name(formation_id), names[index], "ID→persisted Korean")
		_eq(Formations.normalized_persisted_name(names[index]), names[index], "legacy Korean retained")
	_eq(Formations.name_for_id("FRM-99"), "", "unknown ID rejected")
	_eq(Formations.normalized_persisted_name("없는진"), "", "unknown name rejected")


func _test_coefficients_and_matchups() -> void:
	_eq(Formations.coefficient_milli("FRM-04", Battle.Phase.BARRAGE), 1400, "안행 ② 1.4")
	_eq(Formations.coefficient_milli("FRM-01", Battle.Phase.ENGAGEMENT), 1300, "어린 ③ 1.3")
	_eq(Formations.coefficient_milli("FRM-06", Battle.Phase.RESOLUTION), 900, "장사 ⑤ 0.9")
	_eq(Formations.coefficient_milli("FRM-99", Battle.Phase.CONTACT), 1000, "unknown coefficient neutral")
	_eq(Formations.matchup_modifier_milli("FRM-02", "FRM-01", Battle.Phase.ENGAGEMENT), 1200,
		"학익→어린 ③ +20%")
	_eq(Formations.matchup_modifier_milli("FRM-01", "FRM-02", Battle.Phase.ENGAGEMENT), 1000,
		"reverse matchup neutral")
	_eq(Formations.matchup_modifier_milli("FRM-06", "FRM-01", Battle.Phase.ENGAGEMENT), 900,
		"장사진 ③ −10%")
	_eq(Formations.matchup_modifier_milli("FRM-07", "FRM-01", Battle.Phase.ENGAGEMENT), 1000,
		"팔진 nullifies matchup")
	_eq(Formations.matchup_modifier_milli("FRM-02", "FRM-01", Battle.Phase.BARRAGE), 1000,
		"matchup only at ③")


func _test_paljin_and_terrain_verdicts() -> void:
	var eligible := Formations.combat_verdict("FRM-07", "FRM-01", Battle.Phase.CONTACT,
		90, ["「신기묘산」 전투 전 배치 1회 재조정"], "개활")
	_ok(bool(eligible["usable"]), "팔진 actual trait + 통솔 90")
	_eq(int(eligible["formation_milli"]), 1200, "eligible 팔진 coefficient")
	var no_trait := Formations.combat_verdict("FRM-07", "FRM-01", Battle.Phase.CONTACT,
		90, ["팔진 전용"], "개활")
	_eq(String(no_trait["formation_id"]), "FRM-01", "display trait label cannot unlock 팔진")
	_eq(int(no_trait["combat_milli"]), 1000, "ineligible 팔진 safely downgrades")
	var grand := Formations.combat_verdict("FRM-02", "FRM-06", Battle.Phase.CONTACT,
		80, [], "대회랑")
	_eq(String(grand["formation_id"]), "FRM-06", "대회랑 forces 장사진")
	_eq(String(grand["forced_formation_id"]), "FRM-06", "대회랑 forced ID")


func _test_fixed_point_composition() -> void:
	_eq(Battle.formation_adjusted_ship_coefficient_milli(1800, "FRM-04", "FRM-01",
		Battle.Phase.BARRAGE, 70, [], "개활"), 2520, "ship 1.8 × 안행 1.4")
	_eq(Battle.formation_adjusted_ship_coefficient_milli(1000, "FRM-02", "FRM-01",
		Battle.Phase.ENGAGEMENT, 80, [], "개활"), 1440, "formation and matchup compose")


func _test_generic_resolver_reads_live_formation() -> void:
	var neutral := _generic_battle_result("어린진")
	var hawk := _generic_battle_result("학익진")
	_eq(_generic_battle_result("학익진"), hawk, "generic formation combat stays deterministic")
	_ok(neutral != hawk, "generic five-phase resolver reads live Fleet.formation")


func _generic_battle_result(attacker_formation: String) -> Array:
	var data := GameData.load_all()
	var campaign := Campaign.scenario_03(data, 51001)
	campaign.fleets.clear()
	var region_id := "RGN-04"
	campaign.world.region_states[region_id].owner = Campaign.SCN03_SUN_OWNER
	var system_id := data.system_of(region_id)
	var attacker := Fleet.new()
	attacker.id = 97001
	attacker.owner = Campaign.SCN03_CAO_OWNER
	attacker.at_system = system_id
	attacker.ships = Battle.FLEET_SHIPS
	attacker.morale = Battle.MORALE_MAX
	attacker.command = 80
	attacker.drill = Battle.DRILL_MAX
	attacker.formation = attacker_formation
	var defender := Fleet.new()
	defender.id = 97002
	defender.owner = Campaign.SCN03_SUN_OWNER
	defender.at_system = system_id
	defender.ships = Battle.FLEET_SHIPS
	defender.morale = Battle.MORALE_MAX
	defender.command = 80
	defender.drill = Battle.DRILL_MAX
	defender.formation = "어린진"
	campaign.fleets.append(attacker)
	campaign.fleets.append(defender)
	campaign._resolve_battle(attacker, region_id)
	return [attacker.ships, attacker.morale, defender.ships, defender.morale]


func _test_battle_change_contract() -> void:
	var campaign := Campaign.scenario_03(GameData.load_all(), 51002)
	var fleet := Fleet.new()
	fleet.id = 98001
	fleet.command = 50
	campaign._battle_formation_commands["B-1"] = [{
		"next_phase": 2, "fleet_id": fleet.id, "target_formation_id": "FRM-02", "seq": 1,
	}]
	var used := {}
	var failed := campaign._apply_battle_formation_change("B-1", 2, fleet, "FRM-01", "개활", used)
	_eq(int(failed["penalty_milli"]), 800, "command failure applies only destination 800 multiplier")
	_eq(String(failed["formation_id"]), "FRM-01", "failed change retains prior formation")
	campaign._apply_battle_formation_change("B-1", 2, fleet, "FRM-01", "개활", used)
	_eq(String(campaign.battle_formation_results.back()["status"]), "rejected_duplicate", "once per fleet per battle")
	_eq(campaign.issue_battle_formation_change(Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID, 2,
		fleet.id, "FRM-02"), {}, "G10 battle ID rejected before command log")


func _test_exhaustive_coefficients_and_command_arrival() -> void:
	for formation_index in range(1, 8):
		var formation_id := "FRM-%02d" % formation_index
		var row := Formations.coefficients(Formations.name_for_id(formation_id))
		for phase in range(5):
			_eq(Formations.coefficient_milli(formation_id, phase),
				roundi(float(row[Formations.PHASE_KEYS[phase]]) * 1000.0),
				"%s phase %d coefficient" % [formation_id, phase + 1])
	var campaign := Campaign.scenario_03(GameData.load_all(), 51003)
	var fleet_id := 98003
	_ok(not campaign.issue_battle_formation_change("B-ARRIVE", 2, fleet_id, "FRM-02").is_empty(),
		"generic formation command issued")
	campaign.step()
	_ok(campaign._battle_formation_commands.has("B-ARRIVE"), "arrived World command queues generic battle change")
	var replay := Campaign.from_save_result(campaign.to_save_dict(), GameData.load_all())
	_eq(String(replay["status"]), Save.STATUS_OK, "formation command save/replay verifies")
	_eq(int(replay["actual_digest"]), campaign.digest(), "formation command replay digest identity")
