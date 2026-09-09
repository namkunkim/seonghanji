extends SceneTree

## DEMO-RC-LT-02 core acceptance: scenario choices are public, one-shot player
## commands; Event 09/DEC-01 are derived only after their arrival and replay.
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


func _new_campaign(seed: int) -> Campaign:
	return Campaign.scenario_03(_data, seed)


func _select_and_arrive(campaign: Campaign, event_id: String, outcome: Dictionary) -> void:
	_ok(not campaign.issue_scn03_event_outcome(event_id, outcome).is_empty(),
		"%s public choice accepted" % event_id)
	campaign.step()


func _select_history(campaign: Campaign, southward: bool) -> void:
	_select_and_arrive(campaign, Campaign.SCN03_EVENT03, {"cao_southward_complete": southward})
	_select_and_arrive(campaign, Campaign.SCN03_EVENT04, {"sun_quan_independent": true})
	_select_and_arrive(campaign, Campaign.SCN03_EVENT06, {"liu_bei_hostile_to_cao": true})
	_select_and_arrive(campaign, Campaign.SCN03_EVENT07, {
		"sun_liu_military_pact": true,
		"yangtze_defense_line": true,
	})


func _init() -> void:
	_data = GameData.load_all()
	print("DEMO-RC-LT-02 scenario-choice campaign loop core")
	_test_choice_is_one_shot_before_and_after_arrival()
	_test_same_seed_and_choices_replay_deterministically()
	_test_non_occurrence_ends_and_restores_as_dec01()
	print("통과 %d · 실패 %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)


func _test_choice_is_one_shot_before_and_after_arrival() -> void:
	print("1. public choice one-shot")
	var campaign := _new_campaign(20862)
	_ok(campaign.activate_scn03_red_cliff_demo().is_empty(), "non-pending activation rejected")
	var first := campaign.issue_scn03_event_outcome(Campaign.SCN03_EVENT03,
		{"cao_southward_complete": true})
	_ok(not first.is_empty(), "first Event 03 choice queues")
	_ok(campaign.issue_scn03_event_outcome(Campaign.SCN03_EVENT03,
		{"cao_southward_complete": true}).is_empty(), "same pending choice rejected")
	_ok(campaign.issue_scn03_event_outcome(Campaign.SCN03_EVENT03,
		{"cao_southward_complete": false}).is_empty(), "conflicting pending choice rejected")
	_eq(campaign.to_save_dict()["world"]["commands"].size(), 1, "only first choice is logged")
	campaign.step()
	_ok(campaign.issue_scn03_event_outcome(Campaign.SCN03_EVENT03,
		{"cao_southward_complete": true}).is_empty(), "arrived choice cannot be reselected")
	_eq(bool(campaign.scn03_progress.get("cao_southward_complete", false)), true,
		"arrived choice is derived in the canonical ledger")
	print("")


func _test_same_seed_and_choices_replay_deterministically() -> void:
	print("2. occurrence is deterministic and replay-derived")
	var left := _new_campaign(20863)
	var right := _new_campaign(20863)
	_select_history(left, true)
	_select_history(right, true)
	_eq(left.digest(), right.digest(), "same seed plus choices has same digest")
	_eq(left.active_battles.size(), 1, "all five canonical conditions create one battle")
	_eq(left.active_battles[0].battle_id, Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID,
		"occurrence uses canonical battle identity")
	var activation := left.activate_scn03_red_cliff_demo()
	_ok(not activation.is_empty() and bool(activation.get("accepted", false)),
		"public demo activation accepts the pending battle")
	_eq(left.active_battles[0].status, ActiveBattle.STATUS_ACTIVE,
		"activation reaches the existing five-phase battle without injected result")
	_eq(left.active_battles[0].combat_phase, 1, "activation starts at phase 1")
	_ok(not right.activate_scn03_red_cliff_demo().is_empty(),
		"same scenario choices activate through the same public boundary")
	_eq(left.digest(), right.digest(), "same seed plus choices has same active-battle digest")
	_ok(left.activate_scn03_red_cliff_demo().is_empty(), "active battle cannot be reactivated")
	var restored := Campaign.from_save_result(left.to_save_dict(), _data)
	_eq(restored["status"], Save.STATUS_OK, "choice log restores")
	_eq(restored["actual_digest"], left.digest(), "restored occurrence digest matches")
	_eq(restored["campaign"].active_battles[0].status, ActiveBattle.STATUS_ACTIVE,
		"restored occurrence retains the derived active battle")
	print("")


func _test_non_occurrence_ends_and_restores_as_dec01() -> void:
	print("3. non-occurrence is DEC-01")
	var campaign := _new_campaign(20864)
	_select_history(campaign, false)
	_ok(campaign.ended, "a completed false condition ends the short scenario")
	_eq(campaign.end_reason, "DEC-01: 적벽 미발생", "canonical DEC-01 reason")
	_eq(campaign.active_battles.size(), 0, "DEC-01 creates no battle")
	_ok(campaign.issue_scn03_event_outcome(Campaign.SCN03_EVENT07, {
		"sun_liu_military_pact": true, "yangtze_defense_line": true,
	}).is_empty(), "ended campaign rejects further player selection")
	var restored := Campaign.from_save_result(campaign.to_save_dict(), _data)
	_eq(restored["status"], Save.STATUS_OK, "DEC-01 choice log restores")
	_eq(restored["campaign"].end_reason, campaign.end_reason, "restored DEC-01 reason matches")
	_eq(restored["actual_digest"], campaign.digest(), "restored DEC-01 digest matches")
	print("")
