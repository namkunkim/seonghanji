extends SceneTree

## DEMO-RC-QA-01: product entry through result, home return, and replay.

var _fail := 0

func _ok(value: bool, label: String) -> void:
	if not value:
		_fail += 1
		print("  x %s" % label)

func _start_active_demo(main) -> bool:
	if not main._start_red_cliff_demo():
		return false
	var choices := [
		[Campaign.SCN03_EVENT03, {"cao_southward_complete": true}],
		[Campaign.SCN03_EVENT04, {"sun_quan_independent": true}],
		[Campaign.SCN03_EVENT06, {"liu_bei_hostile_to_cao": true}],
		[Campaign.SCN03_EVENT07, {"sun_liu_military_pact": true, "yangtze_defense_line": true}],
	]
	for choice in choices:
		if main.campaign.issue_scn03_event_outcome(String(choice[0]), choice[1]).is_empty():
			return false
		main.campaign.step()
	return not main.campaign.activate_scn03_red_cliff_demo().is_empty()

func _run() -> void:
	get_root().size = Vector2i(1600, 900)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	_ok(_start_active_demo(main), "선택 4건 뒤 정본 적벽 데모 시작")
	var id := Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID
	_ok(main._open_red_cliff_battle_entry_shell(id), "banner/canonical battle entry")
	var battle: ActiveBattle = main.campaign.active_battles[0]
	_ok(battle.combat_phase == 1, "phase 1 접적")
	_ok("접적 좌표 확인" in main.red_cliff_battle_view._report.current_directive,
		"phase 1 directive is visible")
	_ok(main.red_cliff_battle_view._formation.get_item_text(main.red_cliff_battle_view._formation.selected)
		== Formations.name_for_id(battle.attacker_formation_id),
		"formation selector reflects canonical attacker formation")
	_ok(Formations.name_for_id(battle.attacker_formation_id) == main.red_cliff_battle_view._deck.attacker_formation_name,
		"command deck identifies the active formation")
	var formation_before_preview:=battle.attacker_formation_id
	main.red_cliff_battle_view._formation.select(3)
	main.red_cliff_battle_view._formation.item_selected.emit(3)
	main.red_cliff_battle_view._toggle_comparison()
	_ok(main.red_cliff_battle_view._comparison_panel.visible
		and "후보  안행진" in main.red_cliff_battle_view._comparison_summary.text,
		"formation comparison opens from the product battle screen")
	_ok(battle.attacker_formation_id==formation_before_preview,
		"formation comparison never applies or mutates the canonical formation")
	main.red_cliff_battle_view._toggle_comparison()
	var advance_button: Button = main.red_cliff_battle_view._buttons.filter(
		func(button: Button): return String(button.get_meta("action", "")) == "advance_phase")[0]
	_ok(advance_button.disabled, "phase 1 advance control is visibly disabled")
	main.campaign.step()
	_ok(battle.combat_phase == 2, "phase 2 포화")
	await process_frame
	_ok(not advance_button.disabled, "phase 2 advance control becomes available")
	_ok(main.red_cliff_battle_view._phase_alert.visible
		and "PHASE 2 · 포화" in main.red_cliff_battle_view._phase_alert.text,
		"phase transition alert follows canonical phase change")
	_ok("1단계 접적" in main.red_cliff_battle_view._report.summary,
		"phase report reflects the latest canonical outcome")
	_ok(not main.red_cliff_battle_view._map.latest_result.is_empty()
		and main.red_cliff_battle_view._map.result_flash > 0.0,
		"map receives the latest canonical phase result as a non-blocking result cue")
	main.red_cliff_battle_view._toggle_history()
	_ok(main.red_cliff_battle_view._history_panel.visible
		and "1단계  접적" in main.red_cliff_battle_view._history_text.text,
		"cumulative history opens from the live battle")
	main.red_cliff_battle_view._toggle_history()
	_ok(not main.red_cliff_battle_view._history_panel.visible
		and not main.red_cliff_battle_view._history_backdrop.visible,
		"history modal closes without changing battle state")
	_ok(main.red_cliff_battle_view._report.allied_loss >= 0 and main.red_cliff_battle_view._report.wei_loss >= 0,
		"phase report exposes non-negative canonical losses")
	main.red_cliff_battle_view._map.select_fleet("wei_primary")
	var fleet_detail: Dictionary=main.red_cliff_battle_view._map.selection_snapshot()
	_ok(fleet_detail.get("formation","")==Formations.name_for_id(battle.attacker_formation_id)
		and int(fleet_detail.get("ships",-1))==battle.attacker_ships
		and fleet_detail.get("objective","")=="적 전열 압박",
		"selected fleet detail follows canonical battle and formation state")
	main.red_cliff_battle_view._map.grab_focus()
	var key := InputEventKey.new(); key.keycode=KEY_RIGHT; key.pressed=true
	main.red_cliff_battle_view._map._unhandled_key_input(key)
	await process_frame
	_ok(not main.red_cliff_battle_view._map.hover_fleet.is_empty(),
		"keyboard traversal exposes a fleet hover target")
	key = InputEventKey.new(); key.keycode=KEY_ENTER; key.pressed=true
	main.red_cliff_battle_view._map._unhandled_key_input(key)
	await process_frame
	_ok(not main.red_cliff_battle_view._map.selected_fleet.is_empty(),
		"keyboard Enter selects the traversed fleet")
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
	_ok(main.red_cliff_battle_view._state.visible and "결착 완료" in main.red_cliff_battle_view._state.text
		and "승전" in main.red_cliff_battle_view._state.text,
		"visible result banner identifies the winner")
	_ok(not main.red_cliff_battle_view._phase_alert.visible,
		"resolved result banner replaces the transient phase alert without overlap")
	_ok("판정 근거" in main.red_cliff_battle_view._feedback.text
		and not (battle.result.get("decision",{}) as Dictionary).is_empty(),
		"resolved view explains the canonical fleet-and-morale decision evidence")
	main.red_cliff_battle_view._toggle_history()
	_ok(main.red_cliff_battle_view._history_panel.visible
		and "결착 결과" in main.red_cliff_battle_view._history_text.text
		and "승전" in main.red_cliff_battle_view._history_text.text,
		"cumulative history remains available after resolution")
	main.red_cliff_battle_view._toggle_history()
	_ok(main.campaign.issue_red_cliff_player_command(id, "advance_phase").is_empty(), "resolved battle rejects input")
	var saved: Dictionary = main.campaign.to_save_dict()
	var restored: Dictionary = Campaign.from_save_result(saved, GameData.load_all())
	_ok(restored.get("status", "") == Save.STATUS_OK, "save restore")
	_ok(restored.get("campaign").digest() == main.campaign.digest(), "same resolved state after replay")
	main._close_red_cliff_battle_entry_shell()
	_ok(main.red_cliff_scenario_panel.visible and not main.map.visible
		and main.red_cliff_scenario_title.text == "적벽대전 결과", "결착 결과 canonical 브리핑 exactly-once")
	main._return_from_red_cliff_scenario()
	_ok(main.map.visible, "결과 브리핑 뒤 홈 복귀")
	_ok(not main._open_red_cliff_battle_entry_shell(id), "resolved re-entry refused")
	_ok(main._start_red_cliff_demo(), "새 데모 재시작")
	_ok(main.campaign.active_battles.is_empty() and main.campaign.scn03_progress.is_empty(),
		"새 데모에는 이전 선택·전투 상태가 누출되지 않음")
	main.free()
	print("DEMO-RC-QA-01: %d failures" % _fail)
	quit(0 if _fail == 0 else 1)

func _init() -> void:
	call_deferred("_run")
