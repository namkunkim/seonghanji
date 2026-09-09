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
	_ok(main.red_cliff_scenario_panel.visible and main.campaign.active_battles.is_empty(),
		"브리핑부터 시작하고 고정 전투를 주입하지 않음")
	for _choice_index in 4:
		var choice: Dictionary = main._scenario_next_choice()
		_ok(not choice.is_empty(), "다음 정본 사건 선택 제공")
		if not choice.is_empty():
			main._select_red_cliff_scenario_choice(choice, true)
	_ok(not main.campaign.activate_scn03_red_cliff_demo().is_empty(),
		"선택 뒤 공개 Campaign 활성화 경계")
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
	_ok(main._start_red_cliff_demo(), "동일 입력 재시작")
	_ok(main.campaign.active_battles.is_empty() and main.campaign.scn03_progress.is_empty()
		and main.red_cliff_scenario_panel.visible, "새 시작은 선택 브리핑과 깨끗한 Campaign 상태")
	main.free()
	print("DEMO-RC-01: %d 통과 / %d 실패" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


func _init() -> void:
	call_deferred("_run")
