extends SceneTree

## G-10 슬라이스 1 — SCN-03 Event 09 진행 원장 계약.
## 실행: godot --headless --path . --script tests/test_scn03_red_cliff_progress.gd

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


func _new_campaign() -> Campaign:
	return Campaign.scenario_03(_data, 208)


## Event 03/04/06/07 결과를 실제 최종 선행 결과 순서로 기록한다.
func _record_all(c: Campaign, southward: bool = true, independent: bool = true,
		hostile: bool = true, pact: bool = true, defense: bool = true) -> void:
	_ok(c.record_scn03_event_outcome(Campaign.SCN03_EVENT03,
		{"cao_southward_complete": southward}), "E03 결과 기록")
	_ok(c.record_scn03_event_outcome(Campaign.SCN03_EVENT04,
		{"sun_quan_independent": independent}), "E04 결과 기록")
	_ok(c.record_scn03_event_outcome(Campaign.SCN03_EVENT06,
		{"liu_bei_hostile_to_cao": hostile}), "E06 결과 기록")
	_ok(c.record_scn03_event_outcome(Campaign.SCN03_EVENT07, {
		"sun_liu_military_pact": pact,
		"yangtze_defense_line": defense,
	}), "E07 결과 기록")


func _init() -> void:
	_data = GameData.load_all()
	print("SCN-03 적벽 Event 09 진행 원장")
	_test_unknown_does_not_evaluate()
	_test_all_true_fires_exactly_once()
	_test_each_false_ends_once_after_final_result()
	_test_invalid_duplicate_and_contradictory_writes()
	_test_identical_sequence_has_identical_digest()
	print("통과 %d · 실패 %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)


func _test_unknown_does_not_evaluate() -> void:
	print("1. unknown은 Event 09/DEC-01을 일으키지 않는다")
	var c := _new_campaign()
	_ok(c.record_scn03_event_outcome(Campaign.SCN03_EVENT03,
		{"cao_southward_complete": false}), "알려진 false 하나는 기록 가능")
	_ok(not c._scn03_event09_evaluated, "나머지가 unknown이면 Event 09 미판정")
	_ok(not c.ended, "나머지가 unknown이면 DEC-01 미종료")
	_eq(int(c.scenario_event_records.get(Campaign.SCN03_EVENT09, 0)), 0, "Event 09 미발화")
	print("")


func _test_all_true_fires_exactly_once() -> void:
	print("2. all true는 Event 09를 한 번만 발화한다")
	var c := _new_campaign()
	_record_all(c)
	_ok(c._scn03_event09_evaluated, "마지막 선행 결과에서 Event 09 판정")
	_eq(int(c.scenario_event_records.get(Campaign.SCN03_EVENT09, 0)), 1, "Event 09 정확히 한 번")
	_ok(not c.ended, "all true는 종료하지 않음")
	_ok(c.record_scn03_event_outcome(Campaign.SCN03_EVENT07, {
		"sun_liu_military_pact": true, "yangtze_defense_line": true,
	}), "같은 E07 결과는 idempotent")
	_eq(int(c.scenario_event_records.get(Campaign.SCN03_EVENT09, 0)), 1, "중복 기록 후에도 Event 09 한 번")
	print("")


func _test_each_false_ends_once_after_final_result() -> void:
	print("3. 완료된 다섯 조건의 각 false는 DEC-01을 한 번만 만든다")
	var cases := [
		[false, true, true, true, true, "E03 남하"],
		[true, false, true, true, true, "E04 독립"],
		[true, true, false, true, true, "E06 적대"],
		[true, true, true, false, false, "E07 군사협정"],
		[true, true, true, true, false, "E07 장강 방어선"],
	]
	for item in cases:
		var c := _new_campaign()
		_record_all(c, bool(item[0]), bool(item[1]), bool(item[2]), bool(item[3]), bool(item[4]))
		_ok(c.ended, "%s false는 마지막 결과 뒤 종료" % item[5])
		_eq(c.end_reason, "DEC-01: 적벽 미발생", "%s DEC-01 사유" % item[5])
		_eq(int(c.scenario_event_records.get(Campaign.SCN03_EVENT09, 0)), 0, "%s Event 09 미발화" % item[5])
		_ok(c.record_scn03_event_outcome(Campaign.SCN03_EVENT07, {
			"sun_liu_military_pact": bool(item[3]),
			"yangtze_defense_line": bool(item[4]),
		}), "%s E07 재기록 idempotent" % item[5])
		_eq(c.end_reason, "DEC-01: 적벽 미발생", "%s 종료 사유 유지" % item[5])
		c._check_end()
		_eq(c.end_reason, "DEC-01: 적벽 미발생", "%s 일반 종료 판정에도 DEC-01 우선" % item[5])
	print("")


func _test_invalid_duplicate_and_contradictory_writes() -> void:
	print("4. 허용되지 않은/모순된 결과는 거부한다")
	var c := _new_campaign()
	_ok(not c.record_scn03_event_outcome("SCN-03-E05", {"anything": true}), "E05는 준비 원장 입력이 아님")
	_ok(not c.record_scn03_event_outcome(Campaign.SCN03_EVENT03, {}), "필수 결과 누락 거부")
	_ok(not c.record_scn03_event_outcome(Campaign.SCN03_EVENT04,
		{"sun_quan_independent": true, "extra": false}), "추가 결과 거부")
	_ok(not c.record_scn03_event_outcome(Campaign.SCN03_EVENT07, {
		"sun_liu_military_pact": false, "yangtze_defense_line": true,
	}), "군사협정 없는 공동 방어는 모순이라 거부")
	_ok(c.record_scn03_event_outcome(Campaign.SCN03_EVENT03,
		{"cao_southward_complete": true}), "첫 E03 결과 수락")
	_ok(not c.record_scn03_event_outcome(Campaign.SCN03_EVENT03,
		{"cao_southward_complete": false}), "모순 E03 결과 거부")
	_eq(bool(c.scn03_progress["cao_southward_complete"]), true, "모순 뒤 최초 결과 보존")
	print("")


func _test_identical_sequence_has_identical_digest() -> void:
	print("5. 같은 기록 순서는 같은 지문을 만든다")
	var a := _new_campaign()
	var b := _new_campaign()
	_record_all(a)
	_record_all(b)
	_eq(a.digest(), b.digest(), "동일 시드·동일 결과 기록 지문")
	var baseline := a.digest()
	_ok(a.record_scn03_event_outcome(Campaign.SCN03_EVENT07, {
		"sun_liu_military_pact": true, "yangtze_defense_line": true,
	}), "지문 시험의 idempotent 재기록")
	_eq(a.digest(), baseline, "idempotent 재기록은 지문 불변")
	print("")
