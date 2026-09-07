extends SceneTree

## G-10-QA-01 acceptance path: condition -> campaign news -> active battle ->
## banner -> canonical entry request -> observation shell -> home -> re-entry.
## This is intentionally an independent E2E test rather than a collection of
## unit assertions from the banner and shell tests.

const Snapshot := preload("res://app/home_map_snapshot.gd")
const CAPTURE_DIR := "res://out/g10-qa01-red-cliffs-entry-e2e-acceptance"

var _pass := 0
var _fail := 0
var _data: GameData
var _capture_enabled := false


func _ok(condition: bool, label: String) -> void:
	if condition:
		_pass += 1
	else:
		_fail += 1
		print("  x %s" % label)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])


func _capture(main, file_name: String, label: String) -> void:
	if not _capture_enabled:
		return
	await process_frame
	await process_frame
	var image: Image = main.get_viewport().get_texture().get_image()
	_ok(image != null, "%s viewport image is available" % label)
	if image == null:
		return
	_eq(image.get_size(), Vector2i(1600, 900), "%s is 1600x900" % label)
	_ok(image.save_png(ProjectSettings.globalize_path(CAPTURE_DIR.path_join(file_name))) == OK,
		"%s saved" % label)


func _issue_outcome(campaign: Campaign, event_id: String, values: Dictionary) -> void:
	_ok(not campaign.issue_scn03_event_outcome(event_id, values).is_empty(),
		"condition outcome %s issued" % event_id)
	campaign.step()


func _prepare_pending_campaign() -> Campaign:
	var campaign := Campaign.scenario_03(_data, 20861)
	campaign.ai_domestic_enabled = false
	_issue_outcome(campaign, Campaign.SCN03_EVENT03, {"cao_southward_complete": true})
	_issue_outcome(campaign, Campaign.SCN03_EVENT04, {"sun_quan_independent": true})
	_issue_outcome(campaign, Campaign.SCN03_EVENT06, {"liu_bei_hostile_to_cao": true})
	_issue_outcome(campaign, Campaign.SCN03_EVENT07, {
		"sun_liu_military_pact": true, "yangtze_defense_line": true,
	})
	return campaign


func _activate_red_cliffs(campaign: Campaign) -> void:
	var cao_id := -1
	var sun_id := -1
	for fleet in campaign.fleets:
		if fleet.owner == Campaign.SCN03_CAO_OWNER and cao_id < 0:
			cao_id = fleet.id
		if fleet.owner == Campaign.SCN03_SUN_OWNER and sun_id < 0:
			sun_id = fleet.id
	_ok(not campaign.issue_scn03_red_cliff_manifest([cao_id], [sun_id], {
		str(cao_id): "attack", str(sun_id): "defense",
	}).is_empty(), "Red Cliffs manifest issued")
	campaign.step()
	for row in [[Campaign.SCN03_CAO_OWNER, cao_id], [Campaign.SCN03_SUN_OWNER, sun_id]]:
		campaign.world.issue(Domestic.CMD_FLEET_MOVE, {
			"faction": String(row[0]), "fleet": int(row[1]), "region": "RGN-04",
		}, 0, "player")
	for _tick in 800:
		if campaign.active_battles.size() == 1 \
				and campaign.active_battles[0].status == ActiveBattle.STATUS_ACTIVE:
			return
		campaign.step()


func _run() -> void:
	print("G-10-QA-01 Red Cliffs entry E2E")
	get_root().size = Vector2i(1600, 900)
	_capture_enabled = "--capture" in OS.get_cmdline_user_args()
	if _capture_enabled:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR))
	var campaign := _prepare_pending_campaign()
	_eq(campaign.active_battles.size(), 1, "conditions create one Red Cliffs battle")
	_eq(campaign.active_battles[0].status, ActiveBattle.STATUS_PENDING,
		"conditions alone leave battle pending")
	_eq(Snapshot.from_campaign(campaign, 208).news().size(), 0,
		"pending battle has no interrupt news")

	_activate_red_cliffs(campaign)
	_eq(campaign.active_battles.size(), 1, "activation retains one battle")
	var battle: ActiveBattle = campaign.active_battles[0]
	_eq(battle.battle_id, Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID,
		"active battle uses canonical ID")
	_eq(battle.status, ActiveBattle.STATUS_ACTIVE, "arrivals activate battle")
	var news := Snapshot.from_campaign(campaign, 208).news()
	_eq(news.size(), 1, "activation projects one news item")
	if not news.is_empty():
		_eq(news[0].get("action_battle_id", ""), Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID,
			"news action preserves canonical ID")

	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.campaign = campaign
	campaign.world.clock.paused = true
	main._refresh_home_snapshot()
	await process_frame
	_ok(main.red_cliff_banner.visible, "active battle displays interrupt banner")
	_ok(not main.red_cliff_banner_action.disabled, "banner entry is available")
	await _capture(main, "01-active-banner-1600x900.png", "active banner capture")

	main.red_cliff_banner_action.pressed.emit()
	await process_frame
	_ok(main.battle_screen != null and main.battle_screen.visible,
		"banner button opens entry shell")
	_eq(main.battle_screen_battle_id, Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID,
		"entry shell stores canonical ID")
	_ok("정본 전투 ID: %s" % Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID
		in main.battle_screen_state.text, "shell renders canonical battle identity")
	_ok(not main.map.visible, "entry shell hides home map")
	await _capture(main, "02-entry-shell-1600x900.png", "entry shell capture")

	var return_home: Button = main.battle_screen.get_node("Content/ReturnHome")
	return_home.pressed.emit()
	await process_frame
	_ok(main.map.visible and not main.battle_screen.visible, "return restores home")
	_ok(main.red_cliff_banner.visible, "return restores active interrupt banner")
	await _capture(main, "03-home-return-1600x900.png", "home return capture")

	var original_shell = main.battle_screen
	main.red_cliff_banner_action.pressed.emit()
	await process_frame
	_ok(main.battle_screen.visible, "banner permits re-entry")
	_eq(main.battle_screen, original_shell, "re-entry reuses observation shell")
	_eq(main.battle_screen_battle_id, Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID,
		"re-entry remains canonical")
	await _capture(main, "04-reentry-shell-1600x900.png", "re-entry shell capture")

	main.free()
	print("G10QA01RedCliffsEntryE2E: %d passed / %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


func _init() -> void:
	_data = GameData.load_all()
	call_deferred("_run")
