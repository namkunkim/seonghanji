extends SceneTree

## G-10 slice 2 — SCN-03 progress is derived only from player scenario-outcome commands.
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
	print("SCN-03 진행 원장 저장·복원·재생")
	_test_all_true_and_save_after_event09()
	_test_save_before_final_predecessor()
	_test_dec01_false_outcome()
	_test_tampered_scenario_command()
	_test_rs01_legacy_replay()
	print("\n통과 %d · 실패 %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)


func _new_campaign(seed: int) -> Campaign:
	return Campaign.scenario_03(_data, seed)


func _issue_and_arrive(c: Campaign, event_id: String, outcome: Dictionary) -> void:
	var command := c.issue_scn03_event_outcome(event_id, outcome)
	_ok(not command.is_empty(), "%s 외생 player 명령 발행" % event_id)
	c.step()


func _record_all_true_except_final(c: Campaign) -> void:
	_issue_and_arrive(c, Campaign.SCN03_EVENT03, {"cao_southward_complete": true})
	_issue_and_arrive(c, Campaign.SCN03_EVENT04, {"sun_quan_independent": true})
	_issue_and_arrive(c, Campaign.SCN03_EVENT06, {"liu_bei_hostile_to_cao": true})


func _test_all_true_and_save_after_event09() -> void:
	print("1. all true · Event 09 뒤 저장")
	var c := _new_campaign(20801)
	_record_all_true_except_final(c)
	_issue_and_arrive(c, Campaign.SCN03_EVENT07, {
		"sun_liu_military_pact": true, "yangtze_defense_line": true,
	})
	_eq(int(c.scenario_event_records.get(Campaign.SCN03_EVENT09, 0)), 1,
		"Event 09 one-shot 파생")
	var save := c.to_save_dict()
	_eq(save["world"]["ruleset"], Save.CURRENT_RULESET, "새 ruleset 기록")
	_ok(not save["campaign"].has("scn03_progress"), "진행 원장은 저장하지 않음")
	_eq(save["world"]["commands"].size(), 4, "결과 입력 넷만 로그화")
	var restored := Campaign.from_save_result(save, _data)
	_eq(restored["status"], Save.STATUS_OK, "Event 09 뒤 정상 복원")
	_eq(restored["actual_digest"], c.digest(), "Event 09 뒤 digest 동일")
	_eq(int(restored["campaign"].scenario_event_records.get(Campaign.SCN03_EVENT09, 0)), 1,
		"복원 Event 09 one-shot")
	print("")


func _test_save_before_final_predecessor() -> void:
	print("2. 마지막 선행 사건 전 저장")
	var source := _new_campaign(20802)
	_record_all_true_except_final(source)
	var command := source.issue_scn03_event_outcome(Campaign.SCN03_EVENT07, {
		"sun_liu_military_pact": true, "yangtze_defense_line": true,
	})
	_ok(not command.is_empty(), "마지막 선행 명령 대기열 기록")
	var save := source.to_save_dict()
	_eq(int(source.scenario_event_records.get(Campaign.SCN03_EVENT09, 0)), 0,
		"저장 시점 Event 09 미발화")
	_ok(not source.scn03_progress.has("sun_liu_military_pact")
		and not source.scn03_progress.has("yangtze_defense_line"),
		"마지막 사건 전 조건은 unknown 이며 false가 아님")
	_eq(save["world"]["commands"].size(), 4, "대기 중 마지막 결과도 명령 로그에 포함")
	_ok(not save["campaign"].has("scenario_event_records"), "one-shot 기록도 저장하지 않음")
	var restored := Campaign.from_save_result(save, _data)
	_eq(restored["status"], Save.STATUS_OK, "대기 명령 복원 검증")
	var replayed: Campaign = restored["campaign"]
	source.step()
	replayed.step()
	_eq(int(replayed.scenario_event_records.get(Campaign.SCN03_EVENT09, 0)), 1,
		"복원 뒤 마지막 명령이 Event 09 생성")
	_eq(replayed.digest(), source.digest(), "마지막 선행 뒤 digest 동일")
	print("")


func _test_dec01_false_outcome() -> void:
	print("3. false 결과 → DEC-01")
	var c := _new_campaign(20803)
	_record_all_true_except_final(c)
	_issue_and_arrive(c, Campaign.SCN03_EVENT07, {
		"sun_liu_military_pact": false, "yangtze_defense_line": false,
	})
	_ok(c.ended, "마지막 false 결과가 종료")
	_eq(c.end_reason, "DEC-01: 적벽 미발생", "DEC-01 사유")
	var restored := Campaign.from_save_result(c.to_save_dict(), _data)
	_eq(restored["status"], Save.STATUS_OK, "DEC-01 저장 복원 검증")
	_eq(restored["campaign"].end_reason, c.end_reason, "DEC-01 사유 재생")
	_eq(restored["actual_digest"], c.digest(), "DEC-01 digest 동일")
	print("")


func _test_tampered_scenario_command() -> void:
	print("4. scenario outcome 명령 변조")
	var c := _new_campaign(20804)
	_record_all_true_except_final(c)
	c.issue_scn03_event_outcome(Campaign.SCN03_EVENT07, {
		"sun_liu_military_pact": true, "yangtze_defense_line": true,
	})
	var tampered := c.to_save_dict()
	tampered["world"]["commands"][3]["payload"]["outcome"] = {
		"sun_liu_military_pact": false, "yangtze_defense_line": false,
	}
	_eq(Campaign.from_save_result(tampered, _data)["status"],
		Save.STATUS_VERIFICATION_FAILED, "유효 형식의 결과 변조는 digest 검증 실패")
	var malformed := c.to_save_dict()
	malformed["world"]["commands"][3]["payload"]["outcome"] = {"unexpected": true}
	_eq(Campaign.from_save_result(malformed, _data)["status"], Save.STATUS_PARTIAL_RECOVERY,
		"잘못된 결과 구조는 명령 손상 복구 경로")
	print("")


func _test_rs01_legacy_replay() -> void:
	print("5. RS-0.1 기존 저장 재생")
	var legacy := _new_campaign(20805)
	legacy.world.ruleset = "RS-0.1.0"
	var save := legacy.to_save_dict()
	var restored := Campaign.from_save_result(save, _data)
	_eq(restored["status"], Save.STATUS_OLD_MINOR, "RS-0.1은 old minor 로 허용")
	_eq(restored["actual_digest"], legacy.digest(), "RS-0.1 기존 지문 보존")
	_eq(restored["campaign"].scn03_progress.size(), 0, "기존 저장은 진행 원장 없음")
	_ok(restored["campaign"].issue_scn03_event_outcome(Campaign.SCN03_EVENT03,
		{"cao_southward_complete": true}).is_empty(), "RS-0.1은 새 입력 거부")
	print("")
