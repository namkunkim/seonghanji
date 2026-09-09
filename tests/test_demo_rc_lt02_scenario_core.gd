extends SceneTree

const Harness := preload("res://tests/harness.gd")
var _pass := 0
var _fail := 0
var _data: GameData

func _ok(value: bool, label: String) -> void:
	if value: _pass += 1
	else:
		_fail += 1
		print("  x %s" % label)

func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])

func _init() -> void:
	_data = GameData.load_all()
	print("DEMO-RC-LT-02 scenario choice core")
	_test_playable_choices_and_dec01()
	_test_save_replay_and_determinism()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail else Harness.EXIT_PASS)

func _campaign(seed: int) -> Campaign:
	return Campaign.scenario_03(_data, seed)

func _choose(c: Campaign, event_id: String, choice_id: String) -> void:
	_ok(not c.issue_scn03_demo_choice(event_id, choice_id).is_empty(), "%s choice queues" % event_id)
	c.step()

func _test_playable_choices_and_dec01() -> void:
	var c := _campaign(20802)
	var initial := c.scn03_demo_progression()
	_eq(initial["stage"], "briefing", "new demo begins at briefing")
	_eq(initial["current_event"], Campaign.SCN03_EVENT03, "Event 03 first")
	_ok(c.issue_scn03_demo_choice(Campaign.SCN03_EVENT04, "maintain_independence").is_empty(), "out-of-order choice rejected")
	_ok(not c.issue_scn03_demo_choice(Campaign.SCN03_EVENT03, "direct_annexation").is_empty(), "first choice accepted")
	_ok(c.issue_scn03_demo_choice(Campaign.SCN03_EVENT03, "direct_annexation").is_empty(), "queued duplicate rejected")
	c.step()
	_choose(c, Campaign.SCN03_EVENT04, "maintain_independence")
	_choose(c, Campaign.SCN03_EVENT06, "ally_with_sun_quan")
	_choose(c, Campaign.SCN03_EVENT07, "joint_defense")
	_eq(c.scn03_demo_progression()["red_cliff_state"], "pending", "all canonical choices create pending Red Cliffs")
	_ok(not c.ended, "Red Cliffs route does not early-end")
	var no_cliff := _campaign(20803)
	_choose(no_cliff, Campaign.SCN03_EVENT03, "prioritize_sun_quan")
	_choose(no_cliff, Campaign.SCN03_EVENT04, "maintain_independence")
	_choose(no_cliff, Campaign.SCN03_EVENT06, "ally_with_sun_quan")
	_choose(no_cliff, Campaign.SCN03_EVENT07, "joint_defense")
	_ok(no_cliff.ended, "unmet condition ends short scenario")
	_eq(no_cliff.end_reason, "DEC-01: 적벽 미발생", "DEC-01 is canonical early ending")
	_eq(no_cliff.scn03_demo_progression()["stage"], "early_ending", "ending is displayable")

func _test_save_replay_and_determinism() -> void:
	var c := _campaign(20804)
	_choose(c, Campaign.SCN03_EVENT03, "direct_annexation")
	_ok(not c.issue_scn03_demo_choice(Campaign.SCN03_EVENT04, "maintain_independence").is_empty(), "pending Event 04 choice queues before save")
	var restored_result := Campaign.from_save_result(c.to_save_dict(), _data)
	_eq(restored_result["status"], Save.STATUS_OK, "choice-stage save restores")
	var restored: Campaign = restored_result["campaign"]
	c.step()
	restored.step()
	_eq(restored.digest(), c.digest(), "queued choice replay digest deterministic")
	_eq(restored.scn03_demo_progression()["current_event"], Campaign.SCN03_EVENT06, "restored next event advances once")
	var twin := _campaign(20804)
	_choose(twin, Campaign.SCN03_EVENT03, "direct_annexation")
	_choose(twin, Campaign.SCN03_EVENT04, "maintain_independence")
	_eq(twin.digest(), c.digest(), "same seed and choices share command-log digest")
