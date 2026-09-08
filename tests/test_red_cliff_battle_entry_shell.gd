extends SceneTree

## G-10-UI-04: the entry shell exposes a canonical active-battle observation
## without changing the campaign's replay-derived save contract.

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


func _init() -> void:
    _data = GameData.load_all()
    call_deferred("_run")


func _active_campaign() -> Campaign:
    # This seed is the established phase-one activation fixture used by the
    # banner integration test; it keeps the designated manifest fleets intact.
    var campaign := Campaign.scenario_03(_data, 20861)
    campaign.ai_domestic_enabled = false
    for event in [
        [Campaign.SCN03_EVENT03, {"cao_southward_complete": true}],
        [Campaign.SCN03_EVENT04, {"sun_quan_independent": true}],
        [Campaign.SCN03_EVENT06, {"liu_bei_hostile_to_cao": true}],
        [Campaign.SCN03_EVENT07, {"sun_liu_military_pact": true, "yangtze_defense_line": true}],
    ]:
        _ok(not campaign.issue_scn03_event_outcome(String(event[0]), event[1]).is_empty(),
            "%s outcome" % String(event[0]))
        campaign.step()
    var cao_id := -1
    var sun_id := -1
    for fleet in campaign.fleets:
        if fleet.owner == Campaign.SCN03_CAO_OWNER and cao_id < 0:
            cao_id = fleet.id
        if fleet.owner == Campaign.SCN03_SUN_OWNER and sun_id < 0:
            sun_id = fleet.id
    _ok(not campaign.issue_scn03_red_cliff_manifest([cao_id], [sun_id], {
        str(cao_id): "attack", str(sun_id): "defense",
    }).is_empty(), "manifest outcome")
    campaign.step()
    for entry in [[Campaign.SCN03_CAO_OWNER, cao_id], [Campaign.SCN03_SUN_OWNER, sun_id]]:
        campaign.world.issue(Domestic.CMD_FLEET_MOVE, {
            "faction": String(entry[0]), "fleet": int(entry[1]), "region": "RGN-04",
        }, 0, "player")
    for _tick in 800:
        if campaign.active_battles.size() == 1 \
                and campaign.active_battles[0].status == ActiveBattle.STATUS_ACTIVE:
            return campaign
        campaign.step()
    return campaign


func _run() -> void:
    print("G-10 적벽 battle entry shell")
    get_root().size = Vector2i(1600, 900)
    var main = load("res://scenes/main.tscn").instantiate()
    root.add_child(main)
    await process_frame
    main.campaign = _active_campaign()
    main.campaign.world.clock.paused = true
    main._refresh_home_snapshot()
    await process_frame

    _ok(not main._open_red_cliff_battle_entry_shell("BATTLE-RED-CLIFF"),
        "display battle ID is rejected")
    _ok(not main._open_red_cliff_battle_entry_shell("BATTLE-UNKNOWN"),
        "unknown battle ID is rejected")
    _ok(main.battle_screen == null, "rejected IDs create no battle screen")

    var canonical := Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID
    var save_before_open: Dictionary = main.campaign.to_save_dict()
    _ok(main._open_red_cliff_battle_entry_shell(canonical), "canonical active battle opens")
    _ok(main.battle_screen != null and main.battle_screen.visible, "battle shell becomes visible")
    if main.battle_screen == null:
        main.free()
        print("RedCliffBattleEntryShell: %d 통과 / %d 실패" % [_pass, _fail])
        quit(1)
        return
    _eq(main.battle_screen_battle_id, canonical, "shell retains canonical ID only")
    _ok(not main.map.visible, "home map switches to battle shell")
    _ok("정본 전투 ID: %s" % canonical in main.battle_screen_state.text,
        "canonical identity is displayed")
    _ok("상태: active" in main.battle_screen_state.text, "current active status is displayed")
    _ok("전장: 구지 궤도 · RGN-04 / SYS-13" in main.battle_screen_state.text,
        "canonical battle location is displayed")
    _ok("전투 단계: 1" in main.battle_screen_state.text, "current combat phase is displayed")
    _ok("공격측: cao_side" in main.battle_screen_state.text,
        "attacking canonical faction is displayed")
    _ok("방어측: sun_liu_side" in main.battle_screen_state.text,
        "defending canonical faction is displayed")
    var shell: PanelContainer = main.battle_screen
    _ok(main._open_red_cliff_battle_entry_shell(canonical), "reopening canonical battle is safe")
    _eq(main.battle_screen, shell, "reopening reuses one battle screen")
    _eq(main.campaign.to_save_dict(), save_before_open, "entry shell does not alter save contract")

    var battle: ActiveBattle = main.campaign.active_battles[0]
    battle.advance_red_cliff_phase(main.campaign.world.clock.tick + 1)
    main._refresh_battle_entry_shell()
    _ok("전투 단계: 2" in main.battle_screen_state.text, "shell refreshes current state")
    var save_before_return: Dictionary = main.campaign.to_save_dict()
    main._close_red_cliff_battle_entry_shell()
    _ok(main.map.visible, "return action switches back to home")
    _ok(not main.battle_screen.visible, "return action hides battle shell")
    _eq(main.battle_screen_battle_id, canonical, "home return retains canonical shell identity")
    _ok(main._open_red_cliff_battle_entry_shell(canonical), "home return re-enters same active battle")
    _eq(main.battle_screen, shell, "home return re-entry creates no duplicate shell")
    _eq(main.campaign.to_save_dict(), save_before_return, "return and re-entry do not alter save contract")

    # DEMO-RC-02 removed the old UI-facing winner injection. Resolve through
    # the canonical phase command reducer instead.
    while battle.status == ActiveBattle.STATUS_ACTIVE:
        _ok(not main.campaign.issue_red_cliff_player_command(canonical, "advance_phase").is_empty(),
            "resolved 전 phase command 발행")
        main.campaign.step()
    _ok(not main._open_red_cliff_battle_entry_shell(canonical), "resolved battle is rejected")
    main.free()
    print("RedCliffBattleEntryShell: %d 통과 / %d 실패" % [_pass, _fail])
    quit(0 if _fail == 0 else 1)
