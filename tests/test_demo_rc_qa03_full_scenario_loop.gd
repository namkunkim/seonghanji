extends SceneTree

## DEMO-RC-QA-03 — public playable scenario-loop acceptance.
## This test deliberately uses only Campaign construction and public commands.
## It never writes progress, battle state, result, news, fleets, or snapshots.

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


func _new_campaign(seed: int) -> Campaign:
	var campaign := Campaign.scenario_03(_data, seed)
	# This is the product demo policy, not a scenario-state injection: Main
	# starts the focused Red-Cliffs demo with unrelated domestic AI disabled.
	campaign.ai_domestic_enabled = false
	return campaign


func _choose_and_arrive(c: Campaign, event_id: String, choice_id: String) -> void:
	_ok(not c.issue_scn03_demo_choice(event_id, choice_id).is_empty(),
		"%s %s public choice accepted" % [event_id, choice_id])
	_ok(c.issue_scn03_demo_choice(event_id, choice_id).is_empty(),
		"%s duplicate queued choice rejected" % event_id)
	c.step()


func _choose_historical_path(c: Campaign) -> void:
	_choose_and_arrive(c, Campaign.SCN03_EVENT03, "direct_annexation")
	_choose_and_arrive(c, Campaign.SCN03_EVENT04, "ally_with_liu_bei")
	_choose_and_arrive(c, Campaign.SCN03_EVENT06, "ally_with_sun_quan")
	_choose_and_arrive(c, Campaign.SCN03_EVENT07, "joint_defense")


func _resolve_with_public_controls(c: Campaign, battle_id: String) -> void:
	var battle: ActiveBattle = c.active_battles[0]
	while battle.status == ActiveBattle.STATUS_ACTIVE and battle.combat_phase < 2:
		c.step()
	while battle.status == ActiveBattle.STATUS_ACTIVE:
		_ok(not c.issue_red_cliff_player_command(battle_id, "advance_phase").is_empty(),
			"phase %d public advance accepted" % battle.combat_phase)
		c.step()


func _run() -> void:
	_data = GameData.load_all()
	print("DEMO-RC-QA-03 full Red-Cliffs scenario loop")
	await _test_product_overlay_loop()
	_test_choices_pending_active_resolved_and_restore()
	_test_dec01_early_ending_and_restore()
	_test_determinism_and_invalid_boundaries()
	print("통과 %d · 실패 %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)


func _init() -> void:
	call_deferred("_run")


func _press_product_choice(main, label_prefix: String) -> bool:
	var list: VBoxContainer = main.find_child("ScenarioChoiceList", true, false)
	if list == null:
		return false
	for child in list.get_children():
		if child is Button and String(child.text).begins_with(label_prefix):
			child.pressed.emit()
			await process_frame
			return true
	return false


func _test_product_overlay_loop() -> void:
	print("0. product overlay → selection → occurrence / early restart")
	get_root().size = Vector2i(1600, 900)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	_ok(main._start_red_cliff_demo(), "product demo opens briefing")
	await process_frame
	var overlay: Control = main.find_child("RedCliffScenarioOverlay", true, false)
	_ok(overlay != null and overlay.visible, "briefing overlay is visible")
	var title: Label = main.find_child("ScenarioTitle", true, false)
	_ok(title != null and title.text == "적벽 전야",
		"product briefing does not expose an internal event ID")
	for label in ["직접 병합", "유비 연합", "손권 동맹", "공동 방어"]:
		_ok(await _press_product_choice(main, label), "mouse-equivalent product choice %s" % label)
	_ok(main.campaign.scn03_demo_progression().get("stage", "") == "red_cliff_pending",
		"product choices reach occurrence condition screen")
	var continue_button: Button = main.find_child("ScenarioContinue", true, false)
	_ok(continue_button != null and continue_button.visible, "product continue is focusable at deployment")
	continue_button.pressed.emit()
	await process_frame
	_ok(main.campaign.scn03_demo_progression().get("stage", "") == "active",
		"product continue reaches existing active battle")
	_ok(not overlay.visible, "active battle hides scenario overlay")
	# A new demo owns a fresh Campaign.  The alternative Event 04 is selected
	# through the same visible product buttons and must never leak old battle/news.
	_ok(main._start_red_cliff_demo(), "new product demo restarts cleanly")
	await process_frame
	for label in ["직접 병합", "조조 항복", "손권 동맹", "공동 방어"]:
		_ok(await _press_product_choice(main, label), "alternate product choice %s" % label)
	_ok(main.campaign.ended and main.campaign.active_battles.is_empty(), "product DEC-01 has no leaked battle")
	continue_button = main.find_child("ScenarioContinue", true, false)
	continue_button.pressed.emit()
	await process_frame
	_ok(not main.red_cliff_demo_mode and not overlay.visible, "early ending returns to home without stale overlay")
	main.free()


func _test_choices_pending_active_resolved_and_restore() -> void:
	print("1. public choices → occurrence → active → resolved")
	var c := _new_campaign(20861)
	var initial: Dictionary = c.scn03_demo_progression()
	_eq(initial.get("stage", ""), "briefing", "new demo begins at briefing")
	_eq(initial.get("player_faction", ""), "손권", "playable faction is projected")
	_eq(initial.get("current_event", ""), Campaign.SCN03_EVENT03, "first canonical event")
	_choose_and_arrive(c, Campaign.SCN03_EVENT03, "direct_annexation")
	var in_choice_save := c.to_save_dict()
	var in_choice_restore := Campaign.from_save_result(in_choice_save, _data)
	_eq(in_choice_restore.get("status", ""), Save.STATUS_OK, "choice-stage save restores")
	_eq(in_choice_restore.get("campaign").scn03_demo_progression().get("current_event", ""), Campaign.SCN03_EVENT04,
		"restored choice stage is canonical next event")
	_choose_and_arrive(c, Campaign.SCN03_EVENT04, "ally_with_liu_bei")
	_choose_and_arrive(c, Campaign.SCN03_EVENT06, "ally_with_sun_quan")
	_choose_and_arrive(c, Campaign.SCN03_EVENT07, "joint_defense")
	var progress: Dictionary = c.scn03_demo_progression()
	_eq(progress.get("stage", ""), "red_cliff_pending", "all historical choices create pending occurrence")
	_eq(c.active_battles.size(), 1, "one canonical pending battle")
	_eq(int(c.scenario_event_records.get(Campaign.SCN03_EVENT09, 0)), 1, "Event 09 exactly once")
	_ok(not c.continue_red_cliff_scenario_demo().is_empty(), "public deployment accepted")
	var duplicate_deployment: Dictionary = c.continue_red_cliff_scenario_demo()
	_ok(not bool(duplicate_deployment.get("accepted", false)), "duplicate deployment is not accepted")
	# The first public continue queues the canonical manifest.  Once its normal
	# reducer has accepted that command, a second continue emits only the
	# manifest-derived voyage commands; neither call writes battle state.
	c.step()
	_ok(not c.continue_red_cliff_scenario_demo().is_empty(), "accepted manifest emits canonical deployment voyage")
	c.step()
	_ok(not bool(c.continue_red_cliff_scenario_demo().get("accepted", false)),
		"deployment voyage is not duplicated")
	for _i in range(720):
		c.step()
		if c.active_battles[0].status == ActiveBattle.STATUS_ACTIVE:
			break
	var battle: ActiveBattle = c.active_battles[0]
	_eq(battle.status, ActiveBattle.STATUS_ACTIVE, "participants reach active battle through normal commands")
	_eq(c.scn03_red_cliff_transition_news.size(), 1, "opening news exactly once")
	var active_restore := Campaign.from_save_result(c.to_save_dict(), _data)
	_eq(active_restore.get("status", ""), Save.STATUS_OK, "active save restores")
	_eq(active_restore.get("campaign").digest(), c.digest(), "active replay digest identical")
	_resolve_with_public_controls(c, Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID)
	_eq(battle.status, ActiveBattle.STATUS_RESOLVED, "five-phase public battle resolves")
	_ok(battle.campaign_result_applied, "result projection applied once")
	_eq(c.scn03_red_cliff_transition_news.filter(func(row): return String(row.get("transition", "")) == Campaign.SCN03_RED_CLIFF_TRANSITION_RESOLVED).size(), 1,
		"resolved news exactly once")
	_ok(c.issue_red_cliff_player_command(Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID, "advance_phase").is_empty(),
		"resolved battle rejects re-entry command")
	var resolved_restore := Campaign.from_save_result(c.to_save_dict(), _data)
	_eq(resolved_restore.get("status", ""), Save.STATUS_OK, "resolved save restores")
	_eq(resolved_restore.get("campaign").digest(), c.digest(), "resolved replay digest identical")


func _test_dec01_early_ending_and_restore() -> void:
	print("2. public alternate choice → DEC-01 without battle")
	var c := _new_campaign(20862)
	_choose_and_arrive(c, Campaign.SCN03_EVENT03, "direct_annexation")
	_choose_and_arrive(c, Campaign.SCN03_EVENT04, "surrender_to_cao")
	_choose_and_arrive(c, Campaign.SCN03_EVENT06, "ally_with_sun_quan")
	_choose_and_arrive(c, Campaign.SCN03_EVENT07, "joint_defense")
	_eq(c.scn03_demo_progression().get("stage", ""), "early_ending", "non-occurrence projects early ending")
	_ok(c.ended, "DEC-01 terminates canonical campaign")
	_eq(c.end_reason, "DEC-01: 적벽 미발생", "DEC-01 canonical reason")
	_eq(c.active_battles.size(), 0, "DEC-01 creates no substitute battle")
	_eq(int(c.scenario_event_records.get(Campaign.SCN03_EVENT09, 0)), 0, "DEC-01 does not fire Event 09")
	_ok(c.continue_red_cliff_scenario_demo().is_empty(), "ended route cannot deploy battle")
	var restored := Campaign.from_save_result(c.to_save_dict(), _data)
	_eq(restored.get("status", ""), Save.STATUS_OK, "early-ending save restores")
	_eq(restored.get("campaign").end_reason, c.end_reason, "early-ending reason restored")
	_eq(restored.get("campaign").digest(), c.digest(), "early-ending replay digest identical")


func _test_determinism_and_invalid_boundaries() -> void:
	print("3. deterministic sequence and public rejection boundaries")
	var a := _new_campaign(20863)
	var b := _new_campaign(20863)
	_choose_historical_path(a)
	_choose_historical_path(b)
	_eq(a.digest(), b.digest(), "same seed and choices have same digest")
	_eq(a.world.applied_commands, b.world.applied_commands, "same seed and choices have same command log")
	_ok(a.issue_scn03_demo_choice(Campaign.SCN03_EVENT03, "direct_annexation").is_empty(),
		"already-completed event is rejected")
	_ok(a.issue_scn03_demo_choice(Campaign.SCN03_EVENT07, "not_a_choice").is_empty(),
		"unknown documented choice is rejected")
	_ok(a.issue_red_cliff_player_command("BATTLE-RED-CLIFF", "advance_phase").is_empty(),
		"display battle ID is rejected")
	_ok(a.issue_red_cliff_player_command("unknown", "advance_phase").is_empty(),
		"unknown battle ID is rejected")
