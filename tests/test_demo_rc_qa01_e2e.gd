extends SceneTree

## DEMO-RC-QA-01: product entry through result, home return, and replay.

var _fail := 0

func _ok(value: bool, label: String) -> void:
	if not value:
		_fail += 1
		print("  x %s" % label)

func _run() -> void:
	get_root().size = Vector2i(1600, 900)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	_ok(main._start_red_cliff_demo(), "데모 시작")
	var id := Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID
	_ok(main._open_red_cliff_battle_entry_shell(id), "banner/canonical battle entry")
	var battle: ActiveBattle = main.campaign.active_battles[0]
	_ok(battle.combat_phase == 1, "phase 1 접적")
	main.campaign.step()
	_ok(battle.combat_phase == 2, "phase 2 포화")
	_ok(main.campaign.issue_red_cliff_player_command(id, "change_formation", {"target_formation_id": "INVALID"}).is_empty(), "invalid formation rejected")
	_ok(not main.campaign.issue_red_cliff_player_command(id, "hold_formation").is_empty(), "hold formation command")
	main.campaign.step()
	for expected_phase in [3, 4, 5]:
		_ok(not main.campaign.issue_red_cliff_player_command(id, "advance_phase").is_empty(), "advance request %d" % expected_phase)
		main.campaign.step()
		_ok(battle.combat_phase == expected_phase or battle.status == ActiveBattle.STATUS_RESOLVED, "phase %d reached" % expected_phase)
		if battle.status == ActiveBattle.STATUS_RESOLVED:
			break
	if battle.status != ActiveBattle.STATUS_RESOLVED:
		_ok(not main.campaign.issue_red_cliff_player_command(id, "advance_phase").is_empty(), "phase 5 settlement request")
		main.campaign.step()
	_ok(battle.status == ActiveBattle.STATUS_RESOLVED, "core resolved result")
	_ok(battle.campaign_result_applied, "campaign result exactly-once applied")
	_ok(main.campaign.scn03_red_cliff_transition_news.filter(func(row): return String(row.get("transition", "")) == Campaign.SCN03_RED_CLIFF_TRANSITION_RESOLVED).size() == 1, "result news exactly-once")
	await process_frame
	_ok("전투 결과" in main.red_cliff_battle_view._state.text, "result screen shown")
	_ok(main.campaign.issue_red_cliff_player_command(id, "advance_phase").is_empty(), "resolved battle rejects input")
	var saved: Dictionary = main.campaign.to_save_dict()
	var restored: Dictionary = Campaign.from_save_result(saved, GameData.load_all())
	_ok(restored.get("status", "") == Save.STATUS_OK, "save restore")
	_ok(restored.get("campaign").digest() == main.campaign.digest(), "same resolved state after replay")
	main._close_red_cliff_battle_entry_shell()
	_ok(main.map.visible, "return home")
	_ok(not main._open_red_cliff_battle_entry_shell(id), "resolved re-entry refused")
	main.free()
	print("DEMO-RC-QA-01: %d failures" % _fail)
	quit(0 if _fail == 0 else 1)

func _init() -> void:
	call_deferred("_run")
