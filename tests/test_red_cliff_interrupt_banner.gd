extends SceneTree

## G-10: the campaign transition ledger is the only source for the Red-Cliffs
## interrupt banner.  The display route ID must never cross the entry boundary.
const Snapshot := preload("res://app/home_map_snapshot.gd")

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


func _outcome(campaign: Campaign, event_id: String, value: Dictionary) -> void:
    _ok(not campaign.issue_scn03_event_outcome(event_id, value).is_empty(),
        "%s outcome 발행" % event_id)
    campaign.step()


func _active_phase_one_campaign() -> Campaign:
    var campaign := Campaign.scenario_03(_data, 20861)
    campaign.ai_domestic_enabled = false
    _outcome(campaign, Campaign.SCN03_EVENT03, {"cao_southward_complete": true})
    _outcome(campaign, Campaign.SCN03_EVENT04, {"sun_quan_independent": true})
    _outcome(campaign, Campaign.SCN03_EVENT06, {"liu_bei_hostile_to_cao": true})
    _outcome(campaign, Campaign.SCN03_EVENT07, {
        "sun_liu_military_pact": true, "yangtze_defense_line": true,
    })
    var cao_id := -1
    var sun_id := -1
    for fleet in campaign.fleets:
        if fleet.owner == Campaign.SCN03_CAO_OWNER and cao_id < 0:
            cao_id = fleet.id
        if fleet.owner == Campaign.SCN03_SUN_OWNER and sun_id < 0:
            sun_id = fleet.id
    _ok(not campaign.issue_scn03_red_cliff_manifest([cao_id], [sun_id], {
        str(cao_id): "attack", str(sun_id): "defense",
    }).is_empty(), "manifest 발행")
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


func _news_by_transition(rows: Array, transition: String) -> Dictionary:
    for value in rows:
        if value is Dictionary and String(value.get("transition", "")) == transition:
            return (value as Dictionary).duplicate(true)
    return {}


func _run() -> void:
    print("G-10 적벽 전용 interrupt banner")
    get_root().size = Vector2i(1600, 900)
    await process_frame
    var campaign := _active_phase_one_campaign()
    var battle: ActiveBattle = campaign.active_battles[0]
    _eq(battle.combat_phase, 1, "active phase 1 도달")

    var starting := Snapshot.from_campaign(Campaign.scenario_03(_data, 20862), 208)
    _eq(starting.news(), [], "시작에는 적벽 뉴스·배너 없음")
    _eq(starting.provenance().get("news", ""), "campaign_core",
        "시작에도 news capability/provenance는 campaign_core")
    var pending_campaign := Campaign.scenario_03(_data, 20863)
    pending_campaign.record_scn03_event_outcome(Campaign.SCN03_EVENT03,
        {"cao_southward_complete": true})
    pending_campaign.record_scn03_event_outcome(Campaign.SCN03_EVENT04,
        {"sun_quan_independent": true})
    pending_campaign.record_scn03_event_outcome(Campaign.SCN03_EVENT06,
        {"liu_bei_hostile_to_cao": true})
    pending_campaign.record_scn03_event_outcome(Campaign.SCN03_EVENT07, {
        "sun_liu_military_pact": true, "yangtze_defense_line": true,
    })
    _eq(pending_campaign.active_battles[0].status, ActiveBattle.STATUS_PENDING,
        "conditions만 충족하면 pending")
    var pending_state := Snapshot.from_campaign(pending_campaign, 208)
    _eq(pending_state.news(), [],
        "pending에는 banner 또는 open action 없음")
    _eq(pending_state.provenance().get("news", ""), "campaign_core",
        "pending에도 news capability/provenance는 campaign_core")

    var state := Snapshot.from_campaign(campaign, 208)
    var news := state.news()
    _eq(news.size(), 1, "active phase 1 transition news 하나 투영")
    var active_news := _news_by_transition(news, Campaign.SCN03_RED_CLIFF_TRANSITION_ACTIVE_PHASE_1)
    _eq(active_news.get("battle_id", ""), Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID,
        "news battle_id는 canonical")
    _ok(String(active_news.get("battle_id", "")) != "BATTLE-RED-CLIFF",
        "display ID와 canonical battle_id 분리")
    _eq(active_news.get("action_battle_id", ""), Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID,
        "action도 canonical battle_id만 사용")
    _ok(not bool(active_news.get("acknowledged", true)), "acknowledged는 로컬 저장 없이 false 투영")
    _eq(state.provenance().get("news", ""), "campaign_core", "news provenance는 campaign_core")
    _ok(bool(state.capabilities().get("news", false)), "news capability는 실제 코어 지원")
    _ok(bool(active_news.get("is_interrupt_banner", false)), "phase 1만 interrupt banner 후보")
    _eq(active_news.get("expiry_kind", ""), "unsupported", "expiry 정책은 미구현 명시")

    var injected := Snapshot.from_campaign(campaign, 208, {"news": [{
        "news_id": "%s:%s" % [Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID,
            Campaign.SCN03_RED_CLIFF_TRANSITION_ACTIVE_PHASE_1],
        "battle_id": Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID,
        "action_id": "open_active_battle", "action_battle_id": "BATTLE-RED-CLIFF",
        "headline": "주입된 적벽 뉴스",
    }]})
    var injected_active := _news_by_transition(injected.news(),
        Campaign.SCN03_RED_CLIFF_TRANSITION_ACTIVE_PHASE_1)
    _eq(injected.news().size(), 1, "runtime fixture는 canonical 적벽 news 주입 불가")
    _eq(injected_active.get("action_battle_id", ""), Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID,
        "runtime fixture는 canonical action 덮어쓰기 불가")
    var action_target_injected := Snapshot.from_campaign(campaign, 208, {"news": [{
        "news_id": "fixture:other-action", "battle_id": "BATTLE-FIXTURE",
        "action_id": "other_action", "action_battle_id": Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID,
    }]})
    _eq(action_target_injected.news().size(), 1,
        "다른 action_id도 canonical action target runtime 주입 불가")
    var mutable_news := state.news()
    mutable_news[0]["headline"] = "변조"
    _eq(_news_by_transition(state.news(), Campaign.SCN03_RED_CLIFF_TRANSITION_ACTIVE_PHASE_1)
        .get("headline", ""), "적벽 전투 개전", "snapshot 반환값 변조는 원장을 바꾸지 않음")
    _eq(Snapshot.from_campaign(campaign, 208).news().size(), 1, "refresh 후 news 중복 없음")

    var main = load("res://scenes/main.tscn").instantiate()
    root.add_child(main)
    await process_frame
    main.campaign = campaign
    campaign.world.clock.paused = true
    main._refresh_home_snapshot()
    await process_frame
    _ok(main.red_cliff_banner.visible, "active phase 1 배너 1행 표시")
    _eq(main.get_viewport().get_visible_rect().size, Vector2(1600, 900),
        "acceptance viewport는 Windows 1600x900")
    _eq(main.top_panel.size.y, 70.0, "배너는 시간 바 바로 아래의 70px top bar 기준")
    _eq(main.red_cliff_banner.position, Vector2(196, 78),
        "배너는 시간 바 아래 safe content 시작점에 배치")
    _ok(is_equal_approx(main.red_cliff_banner.size.x, 1091.2),
        "1600x900에서 중앙 safe content 폭만 사용")
    _eq(main.red_cliff_banner.size.y, 42.0, "배너는 1행 높이")
    _eq(main.red_cliff_banner.mouse_filter, Control.MOUSE_FILTER_IGNORE,
        "배너 표시만으로 현재 화면 입력을 차단하지 않음")
    _eq(main.red_cliff_banner.get_child(0).mouse_filter, Control.MOUSE_FILTER_IGNORE,
        "배너 여백은 지도 외부 클릭을 가로채지 않음")
    _eq(main.red_cliff_banner_action.text, "전투 진입", "action에 내부 ID를 노출하지 않음")
    _ok(not main.red_cliff_banner_action.disabled, "entry_available이면 action 활성")
    if "--visual-hold" in OS.get_cmdline_user_args():
        var capture_dir := ProjectSettings.globalize_path("res://out/g10-ui02-red-cliffs-banner-windows-acceptance")
        DirAccess.make_dir_recursive_absolute(capture_dir)
        var capture_path := capture_dir.path_join("red-cliffs-banner-1600x900.png")
        _ok(main.get_viewport().get_texture().get_image().save_png(capture_path) == OK,
            "Windows 1600x900 active banner capture 저장")
        print("G-10-UI-02 visual hold: active banner is visible for 60 seconds")
        await create_timer(60.0).timeout
    main.home_state = main.home_state.duplicate(true)
    main.home_state["news"].append({
        "news_id": "fixture:other-action", "battle_id": "BATTLE-FIXTURE",
        "action_id": "other_action", "action_battle_id": Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID,
    })
    _ok(not main._snapshot_runtime_context().has("news"),
        "Main refresh도 다른 action_id의 canonical action target을 재주입하지 않음")
    var requested: Array[String] = []
    main.battle_entry_requested.connect(func(battle_id: String): requested.append(battle_id))
    _ok(not main._request_red_cliff_battle_entry("BATTLE-RED-CLIFF"), "display ID 진입 요청 거부")
    _ok(not main._request_red_cliff_battle_entry("BATTLE-UNKNOWN"), "unknown battle_id 진입 요청 거부")
    main.red_cliff_banner_action.pressed.emit()
    _eq(requested, [Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID],
        "canonical active battle_id만 entry signal 발생")
    main._route_home_action("stage:5", "", "", {"position": main.cam.position, "zoom": 1.65})
    _eq(requested.size(), 1, "stage:5 카메라 경로는 entry signal과 분리")

    var ui_layer_before: CanvasLayer = main.ui_layer
    var galaxy: Dictionary = main._load_json("res://data/galaxy.json")
    main._build_ui(galaxy, main.projected_systems)
    await process_frame
    _ok(not is_instance_valid(ui_layer_before), "UI 재구성 시 이전 banner canvas 제거")
    _eq(main.get_tree().get_nodes_in_group("RedCliffInterruptBanner").size(), 0,
        "banner는 group 없이 별도 중복 등록하지 않음")
    _eq(main.ui_layer.get_child_count(), 1, "UI 재구성 뒤 owned canvas에는 단일 root만 존재")
    _eq(main.red_cliff_banner.name, "RedCliffInterruptBanner", "재구성 뒤 banner identity 유지")
    _ok(main.red_cliff_banner.visible, "재구성 뒤 active phase 1 banner 유지")
    main.red_cliff_banner_action.pressed.emit()
    _eq(requested, [Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID,
        Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID], "재구성 뒤 action signal은 한 번만 발생")

    battle.entry_available = false
    main._refresh_home_snapshot()
    _ok(main.red_cliff_banner.visible, "phase 1 entry 불가여도 배너 사실은 유지")
    _ok(main.red_cliff_banner_action.disabled, "entry_available false면 action 비활성")
    _ok(not main._request_red_cliff_battle_entry(Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID),
        "entry unavailable canonical 요청 거부")
    battle.entry_available = true
    battle.advance_red_cliff_phase(campaign.world.clock.tick + 1)
    campaign._record_scn03_red_cliff_transition_news(battle,
        Campaign.SCN03_RED_CLIFF_TRANSITION_PHASE_2, campaign.world.clock.tick + 1)
    main._refresh_home_snapshot()
    _ok(not main.red_cliff_banner.visible, "phase 2는 새 긴급 배너를 만들지 않음")
    _eq(main.home_state.get("news", []).size(), 2, "phase 2 news 이력은 유지")
    battle.resolve_red_cliff("sun_liu_side", campaign.world.clock.tick + 2)
    campaign._record_scn03_red_cliff_transition_news(battle,
        Campaign.SCN03_RED_CLIFF_TRANSITION_RESOLVED, campaign.world.clock.tick + 2)
    main._refresh_home_snapshot()
    _ok(not main.red_cliff_banner.visible, "resolved 뒤 배너 제거")
    _eq(main.home_state.get("news", []).size(), 3, "resolved news 이력 유지")
    main.free()

    var replay_source := _active_phase_one_campaign()
    var replay := Campaign.from_save_result(replay_source.to_save_dict(), _data)
    _eq(replay.get("status", ""), Save.STATUS_OK, "phase 1 save replay")
    var replay_news := Snapshot.from_campaign(replay.get("campaign"), 208).news()
    _eq(_news_by_transition(replay_news, Campaign.SCN03_RED_CLIFF_TRANSITION_ACTIVE_PHASE_1)
        .get("news_id", ""), _news_by_transition(Snapshot.from_campaign(replay_source, 208).news(),
            Campaign.SCN03_RED_CLIFF_TRANSITION_ACTIVE_PHASE_1).get("news_id", ""),
        "replay 후 news_id 동일")
    _eq(_news_by_transition(replay_news, Campaign.SCN03_RED_CLIFF_TRANSITION_ACTIVE_PHASE_1)
        .get("battle_id", ""), Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID,
        "replay 후 canonical battle_id 동일")

    print("RedCliffInterruptBanner: %d 통과 / %d 실패" % [_pass, _fail])
    quit(0 if _fail == 0 else 1)
