extends SceneTree

## DEMO-RC-01 — product button path, with no fixture-state injection.

var _pass := 0
var _fail := 0


func _ok(value: bool, label: String) -> void:
	if value:
		_pass += 1
	else:
		_fail += 1
		print("  x %s" % label)


func _run() -> void:
	get_root().size = Vector2i(1600, 900)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	_ok(main._start_red_cliff_demo(), "제품 데모 시작 경로")
	_ok(main.campaign.scn03_demo_progression().get("stage", "") == "briefing", "제품 시작은 시나리오 브리핑")
	for choice in [[Campaign.SCN03_EVENT03, "direct_annexation"],
		[Campaign.SCN03_EVENT04, "maintain_independence"],
		[Campaign.SCN03_EVENT06, "ally_with_sun_quan"],
		[Campaign.SCN03_EVENT07, "joint_defense"]]:
		_ok(not main.campaign.issue_scn03_demo_choice(String(choice[0]), String(choice[1])).is_empty(),
			"플레이어 사건 선택 %s" % String(choice[0]))
		main.campaign.step()
	_ok(not main.campaign.continue_red_cliff_scenario_demo().is_empty(), "정본 참가 원장 준비")
	main.campaign.step()
	_ok(not main.campaign.continue_red_cliff_scenario_demo().is_empty(), "정본 참가 함대 이동")
	for _tick in 800:
		main.campaign.step()
		if main.campaign.scn03_demo_progression().get("stage", "") == "active":
			break
	var battle: ActiveBattle = main.campaign.active_battles[0] if main.campaign.active_battles.size() == 1 else null
	_ok(battle != null, "pending→active canonical battle 생성")
	if battle != null:
		_ok(battle.status == ActiveBattle.STATUS_ACTIVE, "active 상태")
		_ok(battle.battle_id == Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID, "canonical battle ID")
		_ok(main.campaign.scn03_red_cliff_transition_news.size() == 1, "개전 뉴스 exactly-once")
		var restored := Campaign.from_save_result(main.campaign.to_save_dict(), GameData.load_all())
		_ok(restored.get("status", "") == Save.STATUS_OK, "시작 상태 저장·복원")
		if restored.get("campaign") != null:
			_ok(restored["campaign"].digest() == main.campaign.digest(), "저장 후 동일 시작 상태")
	var first_digest: int = main.campaign.digest()
	_ok(main._start_red_cliff_demo(), "동일 입력 재시작")
	for choice in [[Campaign.SCN03_EVENT03, "direct_annexation"],
		[Campaign.SCN03_EVENT04, "maintain_independence"],
		[Campaign.SCN03_EVENT06, "ally_with_sun_quan"],
		[Campaign.SCN03_EVENT07, "joint_defense"]]:
		main.campaign.issue_scn03_demo_choice(String(choice[0]), String(choice[1]))
		main.campaign.step()
	main.campaign.continue_red_cliff_scenario_demo()
	main.campaign.step()
	main.campaign.continue_red_cliff_scenario_demo()
	for _tick in 800:
		main.campaign.step()
		if main.campaign.scn03_demo_progression().get("stage", "") == "active":
			break
	_ok(main.campaign.digest() == first_digest, "동일 시작 입력은 동일 상태")
	main.free()
	print("DEMO-RC-01: %d 통과 / %d 실패" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


func _init() -> void:
	call_deferred("_run")
