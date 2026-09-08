extends SceneTree

## G-10 slice 5 — deterministic phase 1→2 and replay-derived resolved result.
const Harness := preload("res://tests/harness.gd")
var _pass := 0
var _fail := 0
var _data: GameData


func _ok(condition: bool, label: String) -> void:
	if condition:
		_pass += 1
	else:
		_fail += 1
		print("  x %s" % label)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])


func _init() -> void:
	_data = GameData.load_all()
	print("SCN-03 적벽 active phase · resolved result")
	_test_phase_result_replay_and_tamper()
	print("\n통과 %d · 실패 %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)


func _new_campaign(seed: int) -> Campaign:
	var campaign := Campaign.scenario_03(_data, seed)
	campaign.ai_domestic_enabled = false
	return campaign


func _outcome(campaign: Campaign, event_id: String, value: Dictionary) -> void:
	_ok(not campaign.issue_scn03_event_outcome(event_id, value).is_empty(),
		"%s outcome 발행" % event_id)
	campaign.step()


func _active_campaign() -> Campaign:
	var campaign := _new_campaign(20851)
	_outcome(campaign, Campaign.SCN03_EVENT03, {"cao_southward_complete": true})
	_outcome(campaign, Campaign.SCN03_EVENT04, {"sun_quan_independent": true})
	_outcome(campaign, Campaign.SCN03_EVENT06, {"liu_bei_hostile_to_cao": true})
	_outcome(campaign, Campaign.SCN03_EVENT07, {
		"sun_liu_military_pact": true, "yangtze_defense_line": true,
	})
	var cao_id := -1
	var sun_id := -1
	for fleet in campaign.fleets:
		if fleet.owner == Campaign.SCN03_CAO_OWNER and cao_id < 0:
			cao_id = fleet.id
		if fleet.owner == Campaign.SCN03_SUN_OWNER and sun_id < 0:
			sun_id = fleet.id
	_ok(not campaign.issue_scn03_red_cliff_manifest([cao_id], [sun_id], {
		str(cao_id): "attack", str(sun_id): "defense",
	}).is_empty(), "manifest 발행")
	campaign.step()
	for entry in [[Campaign.SCN03_CAO_OWNER, cao_id], [Campaign.SCN03_SUN_OWNER, sun_id]]:
		campaign.world.issue(Domestic.CMD_FLEET_MOVE, {
			"faction": String(entry[0]), "fleet": int(entry[1]), "region": "RGN-04",
		}, 0, "player")
	for _tick in 800:
		if campaign.active_battles.size() == 1 \
				and campaign.active_battles[0].status == ActiveBattle.STATUS_ACTIVE:
			return campaign
		campaign.step()
	return campaign


func _test_phase_result_replay_and_tamper() -> void:
	print("1. phase 1→2 · result once · replay/tamper")
	var campaign := _active_campaign()
	var battle: ActiveBattle = campaign.active_battles[0]
	_eq(battle.combat_phase, 1, "activation tick은 phase 1")
	_eq(campaign.scn03_red_cliff_transition_news.size(), 1, "active phase 1 news 한 번")
	_eq(campaign.scn03_red_cliff_transition_news[0]["news_id"],
		"%s:%s" % [Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID,
		Campaign.SCN03_RED_CLIFF_TRANSITION_ACTIVE_PHASE_1], "active news 안정 ID")
	_ok(not campaign._record_scn03_red_cliff_transition_news(battle,
		Campaign.SCN03_RED_CLIFF_TRANSITION_ACTIVE_PHASE_1, campaign.world.clock.tick),
		"동일 active transition 직접 재기록 거부")
	_eq(campaign.scn03_red_cliff_transition_news.size(), 1, "직접 재기록도 ledger 불변")
	_ok(not campaign.to_save_dict()["campaign"].has("scn03_red_cliff_transition_news"),
		"transition news는 snapshot 저장하지 않음")
	var phase_one_restored := Campaign.from_save_result(campaign.to_save_dict(), _data)
	_eq(phase_one_restored["status"], Save.STATUS_OK, "phase 1 save replay")
	_eq(phase_one_restored["campaign"].active_battles[0].combat_phase, 1,
		"phase 1 replay 유지")
	_eq(phase_one_restored["campaign"].scn03_red_cliff_transition_news,
		campaign.scn03_red_cliff_transition_news, "phase 1 news replay")
	campaign.step()
	_eq(battle.combat_phase, 2, "다음 tick에 결정론적으로 phase 2")
	_eq(battle.phase_advanced_tick, campaign.world.clock.tick, "phase transition tick 기록")
	_eq(campaign.scn03_red_cliff_transition_news.size(), 2, "phase 2 news 한 번")
	_eq(campaign.scn03_red_cliff_transition_news[1]["news_id"],
		"%s:%s" % [Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID,
		Campaign.SCN03_RED_CLIFF_TRANSITION_PHASE_2], "phase 2 news 안정 ID")
	var phase_two_restored := Campaign.from_save_result(campaign.to_save_dict(), _data)
	_eq(phase_two_restored["status"], Save.STATUS_OK, "phase 2 save replay")
	_eq(phase_two_restored["campaign"].active_battles[0].combat_phase, 2,
		"phase 2 replay 유지")
	for expected_phase in [2, 3, 4, 5]:
		_ok(not campaign.issue_red_cliff_player_command(battle.battle_id, "advance_phase").is_empty(),
			"phase %d 계산 명령 발행" % expected_phase)
		campaign.step()
	_eq(battle.status, ActiveBattle.STATUS_RESOLVED, "result가 resolved 전이")
	_ok(["cao_side", "sun_liu_side"].has(battle.result.get("winner_faction_id", "")), "result는 코어 계산값")
	_ok(battle.result_applied, "result 적용 기록")
	_eq(battle.phase_results.size(), 5, "접적부터 결착까지 phase 결과 다섯 개")
	_ok(battle.phase_results.all(func(record): return record.has("attacker_loss") \
		and record.has("defender_loss") and record.has("attacker_morale_after") \
		and record.has("defender_morale_after")), "phase별 손실·사기 기록")
	_ok(battle.campaign_result_applied, "함대 결과는 정확히 한 번 투영")
	_eq(campaign.scn03_red_cliff_transition_news.size(), 3, "resolved news 한 번")
	_eq(campaign.scn03_red_cliff_transition_news[2]["news_id"],
		"%s:%s" % [Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID,
		Campaign.SCN03_RED_CLIFF_TRANSITION_RESOLVED], "resolved news 안정 ID")
	_ok(campaign.issue_red_cliff_player_command(battle.battle_id, "advance_phase").is_empty(), "resolved 뒤 reapply 거부")
	campaign.step()
	_eq(campaign.scn03_red_cliff_transition_news.size(), 3, "후속 tick도 news 중복 없음")
	var save := campaign.to_save_dict()
	var restored := Campaign.from_save_result(save, _data)
	_eq(restored["status"], Save.STATUS_OK, "resolved save replay")
	_eq(restored["actual_digest"], campaign.digest(), "resolved replay digest")
	var replay_battle: ActiveBattle = restored["campaign"].active_battles[0]
	_eq(replay_battle.status, ActiveBattle.STATUS_RESOLVED, "replay resolved 상태")
	_eq(replay_battle.result, battle.result, "replay result 동일")
	_eq(restored["campaign"].scn03_red_cliff_transition_news,
		campaign.scn03_red_cliff_transition_news, "resolved news replay")
	var ledger_snapshot_tamper: Dictionary = save.duplicate(true)
	ledger_snapshot_tamper["campaign"]["scn03_red_cliff_transition_news"] = []
	_eq(Campaign.from_save_result(ledger_snapshot_tamper, _data)["status"], Save.STATUS_CORRUPT,
		"news snapshot 주입 거부 — 로그 재생만 정본")
	var manifest_tamper: Dictionary = save.duplicate(true)
	var roles: Dictionary = manifest_tamper["world"]["commands"][4]["payload"]["fleet_roles"]
	var role_keys: Array = roles.keys()
	roles[role_keys[0]] = "changed"
	_eq(Campaign.from_save_result(manifest_tamper, _data)["status"], Save.STATUS_VERIFICATION_FAILED,
		"manifest 변조 검출")
	var phase_tamper: Dictionary = save.duplicate(true)
	phase_tamper["world"]["commands"][-1]["payload"]["kind"] = "unknown"
	_eq(Campaign.from_save_result(phase_tamper, _data)["status"], Save.STATUS_PARTIAL_RECOVERY,
		"phase 변조 구조 거부")
	var result_tamper: Dictionary = save.duplicate(true)
	result_tamper["world"]["commands"][-1]["payload"]["payload"] = {"target_formation_id": "invalid"}
	_eq(Campaign.from_save_result(result_tamper, _data)["status"], Save.STATUS_PARTIAL_RECOVERY,
		"command 변조 구조 거부")
	var reapply_tamper: Dictionary = save.duplicate(true)
	var duplicate: Dictionary = reapply_tamper["world"]["commands"][-1].duplicate(true)
	duplicate["seq"] = int(duplicate["seq"]) + 1
	reapply_tamper["world"]["commands"].append(duplicate)
	_eq(Campaign.from_save_result(reapply_tamper, _data)["status"], Save.STATUS_VERIFICATION_FAILED,
		"result reapply 로그 검출")
