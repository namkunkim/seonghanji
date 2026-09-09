extends SceneTree

const Harness := preload("res://tests/harness.gd")
var _pass := 0
var _fail := 0
var _data: GameData

func _ok(value: bool, label: String) -> void:
	if value:
		_pass += 1
	else:
		_fail += 1
		print("  x %s" % label)

func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])

func _init() -> void:
	_data = GameData.load_all()
	print("SCN-03 briefing begin command")
	_test_begin_is_explicit_and_one_shot()
	_test_save_replay_is_deterministic()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail else Harness.EXIT_PASS)

func _campaign(seed: int) -> Campaign:
	return Campaign.scenario_03(_data, seed)

func _test_begin_is_explicit_and_one_shot() -> void:
	var campaign := _campaign(20871)
	_eq(campaign.scn03_demo_progression().get("stage", ""), "briefing", "new scenario remains in briefing")
	_ok(bool(campaign.scn03_demo_progression().get("can_begin", false)), "briefing exposes begin capability")
	_ok(not campaign.issue_scn03_demo_begin().is_empty(), "public begin queues")
	_ok(campaign.issue_scn03_demo_begin().is_empty(), "queued duplicate begin rejected")
	campaign.step()
	_eq(campaign.scn03_demo_progression().get("stage", ""), "choice", "arrived begin exposes Event 03 choice")
	_eq(campaign.scn03_demo_progression().get("current_event", ""), Campaign.SCN03_EVENT03, "begin does not skip Event 03")
	_ok(bool(campaign.scn03_demo_progression().get("briefing_started", false)), "progression derives begin acknowledgement")
	_ok(not bool(campaign.scn03_demo_progression().get("can_begin", true)), "completed briefing cannot begin again")
	_ok(campaign.issue_scn03_demo_begin().is_empty(), "applied duplicate begin rejected")

func _test_save_replay_is_deterministic() -> void:
	var source := _campaign(20872)
	_ok(not source.issue_scn03_demo_begin().is_empty(), "begin queues before save")
	var queued_save := source.to_save_dict()
	var queued_restore := Campaign.from_save_result(queued_save, _data)
	_eq(queued_restore.get("status", ""), Save.STATUS_OK, "queued begin save restores")
	var restored: Campaign = queued_restore.get("campaign")
	_ok(restored != null, "queued begin campaign restored")
	if restored != null:
		_eq(restored.digest(), source.digest(), "queued begin digest is replay-stable")
		source.step()
		restored.step()
		_eq(restored.digest(), source.digest(), "arrived begin digest is replay-stable")
		_eq(restored.scn03_demo_progression().get("stage", ""), "choice", "restored begin reaches choice")
	var tampered := queued_save.duplicate(true)
	tampered["world"]["commands"][0]["payload"] = {"skip": true}
	_eq(Save.inspect(tampered).get("status", ""), Save.STATUS_PARTIAL_RECOVERY,
		"nonempty begin payload is rejected before replay")
	var twin := _campaign(20872)
	twin.issue_scn03_demo_begin()
	twin.step()
	_eq(twin.digest(), source.digest(), "same seed and begin command are deterministic")
