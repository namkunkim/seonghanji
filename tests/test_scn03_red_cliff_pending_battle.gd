extends SceneTree

## G-10 slice 3 — Event 09 derives one pending Red-Cliffs battle, with no activation.
const Harness := preload("res://tests/harness.gd")
var _pass := 0
var _fail := 0
var _data: GameData


func _ok(condition: bool, message: String) -> void:
	if condition:
		_pass += 1
	else:
		_fail += 1
		print("  ✗ %s" % message)


func _eq(actual, expected, message: String) -> void:
	_ok(actual == expected, "%s  (%s != %s)" % [message, str(actual), str(expected)])


func _init() -> void:
	_data = GameData.load_all()
	print("SCN-03 적벽 pending active battle")
	_test_event09_creates_exact_pending_contract()
	_test_duplicate_and_replay_keep_one_identity()
	_test_false_or_unknown_creates_nothing()
	_test_save_replay_keeps_pending_digest()
	_test_generic_immediate_battle_does_not_create_pending()
	print("\n통과 %d · 실패 %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)


func _new_campaign(seed: int) -> Campaign:
	return Campaign.scenario_03(_data, seed)


func _issue_and_arrive(c: Campaign, event_id: String, outcome: Dictionary) -> void:
	_ok(not c.issue_scn03_event_outcome(event_id, outcome).is_empty(),
		"%s player 결과 명령 발행" % event_id)
	c.step()


func _record_all_true(c: Campaign) -> void:
	_issue_and_arrive(c, Campaign.SCN03_EVENT03, {"cao_southward_complete": true})
	_issue_and_arrive(c, Campaign.SCN03_EVENT04, {"sun_quan_independent": true})
	_issue_and_arrive(c, Campaign.SCN03_EVENT06, {"liu_bei_hostile_to_cao": true})
	_issue_and_arrive(c, Campaign.SCN03_EVENT07, {
		"sun_liu_military_pact": true,
		"yangtze_defense_line": true,
	})


func _test_event09_creates_exact_pending_contract() -> void:
	print("1. all true → exact pending contract")
	var c := _new_campaign(20831)
	_record_all_true(c)
	_eq(c.active_battles.size(), 1, "Event 09 성공은 pending 하나")
	var battle: ActiveBattle = c.active_battles[0]
	_eq(battle.battle_id, Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID, "canonical battle ID")
	_eq(battle.cause_event_id, Campaign.SCN03_EVENT09, "원인 Event 09")
	_eq(battle.scenario_id, "SCN-03", "시나리오 고정")
	_eq(battle.status, ActiveBattle.STATUS_PENDING, "pending만 생성")
	_eq(battle.region_id, "RGN-04", "권위 지역 고정")
	_eq(battle.system_id, "SYS-13", "권위 성계 고정")
	_eq(battle.anchor_body_id, "BODY-RGN-04-01", "구지의 canonical 표시 앵커")
	_eq(battle.created_tick, c.world.clock.tick, "마지막 선행 결과 도달 tick")
	_eq(battle.rng_anchor, "%d|%s" % [battle.created_tick, battle.battle_id],
		"Rng 소비 없는 안정 앵커")
	_eq(battle.attacker_faction_id, "", "공격 세력 미조립")
	_eq(battle.defender_faction_id, "", "방어 세력 미조립")
	_eq(battle.attacker_fleet_ids, [], "공격 함대 미조립")
	_eq(battle.defender_fleet_ids, [], "방어 함대 미조립")
	_eq(battle.participant_roles, {}, "역할 미조립")
	_ok(not battle.entry_available, "전투 진입 불가")


func _test_duplicate_and_replay_keep_one_identity() -> void:
	print("2. duplicate/replay → same single identity")
	var c := _new_campaign(20832)
	_record_all_true(c)
	var original_digest := c.digest()
	_ok(c.record_scn03_event_outcome(Campaign.SCN03_EVENT07, {
		"sun_liu_military_pact": true, "yangtze_defense_line": true,
	}), "동일 Event 07 reducer 재기록 허용")
	_eq(c.active_battles.size(), 1, "중복 Event 09가 pending을 복제하지 않음")
	_eq(c.active_battles[0].battle_id, Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID,
		"중복 뒤 ID 불변")
	_eq(c.digest(), original_digest, "중복 reducer 뒤 digest 불변")
	var restored := Campaign.from_save_result(c.to_save_dict(), _data)
	_eq(restored["status"], Save.STATUS_OK, "pending 저장 재생 검증")
	var replayed: Campaign = restored["campaign"]
	_eq(replayed.active_battles.size(), 1, "재생 pending 하나")
	_eq(replayed.active_battles[0].battle_id, c.active_battles[0].battle_id,
		"재생 canonical ID 동일")
	_eq(replayed.digest(), c.digest(), "재생 pending digest 동일")


func _test_false_or_unknown_creates_nothing() -> void:
	print("3. false/unknown → no pending")
	var unknown := _new_campaign(20833)
	_issue_and_arrive(unknown, Campaign.SCN03_EVENT03, {"cao_southward_complete": true})
	_eq(unknown.active_battles.size(), 0, "미확정 조건은 pending을 만들지 않음")
	var false_result := _new_campaign(20834)
	_issue_and_arrive(false_result, Campaign.SCN03_EVENT03, {"cao_southward_complete": false})
	_issue_and_arrive(false_result, Campaign.SCN03_EVENT04, {"sun_quan_independent": true})
	_issue_and_arrive(false_result, Campaign.SCN03_EVENT06, {"liu_bei_hostile_to_cao": true})
	_issue_and_arrive(false_result, Campaign.SCN03_EVENT07, {
		"sun_liu_military_pact": true, "yangtze_defense_line": true,
	})
	_eq(false_result.active_battles.size(), 0, "false Event 09는 pending을 만들지 않음")
	_ok(false_result.ended, "false는 기존 DEC-01로 종료")


func _test_save_replay_keeps_pending_digest() -> void:
	print("4. pending save/replay digest")
	var source := _new_campaign(20835)
	_record_all_true(source)
	var save := source.to_save_dict()
	_ok(not save["campaign"].has("active_battles"), "pending은 독립 스냅숏 저장이 아님")
	var restored := Campaign.from_save_result(save, _data)
	_eq(restored["status"], Save.STATUS_OK, "pending 세이브 검증")
	_eq(restored["actual_digest"], source.digest(), "pending 재생 digest 일치")


func _test_generic_immediate_battle_does_not_create_pending() -> void:
	print("5. generic immediate battle remains separate")
	var c := _new_campaign(20836)
	var region_id := ""
	for rid in _data.region_ids:
		if String(c.world.region_states[rid].owner) == "손권":
			region_id = rid
			break
	_ok(region_id != "", "손권 권역 확보")
	var defender := Fleet.new()
	defender.id = 90001
	defender.owner = "손권"
	defender.at_system = _data.system_of(region_id)
	defender.ships = Battle.FLEET_SHIPS
	c.fleets.append(defender)
	var attacker := Fleet.new()
	attacker.id = 90002
	attacker.owner = "조조"
	attacker.at_system = _data.system_of(region_id)
	attacker.ships = Battle.FLEET_SHIPS
	c.fleets.append(attacker)
	var battles_before := c.battles
	c._resolve_battle(attacker, region_id)
	_eq(c.battles, battles_before + 1, "기존 즉시 전투는 해결됨")
	_eq(c.active_battles.size(), 0, "일반 즉시 전투가 적벽 pending을 만들지 않음")
