extends SceneTree

const Snapshot := preload("res://app/home_map_snapshot.gd")

const READY_CONDITIONS := {
    "cao_southward_complete": true,
    "sun_quan_independent": true,
    "liu_bei_hostile_to_cao": true,
    "sun_liu_military_pact": true,
    "yangtze_defense_line": true,
}

var failures := 0

func _check(condition: bool, label: String) -> void:
    if not condition:
        failures += 1
        print("실패: " + label)

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var campaign := Campaign.scenario_03(GameData.load_all(), 208)
    var main = load("res://scenes/main.tscn").instantiate()
    root.add_child(main)
    await process_frame
    await process_frame

    var default_rows: Array = main._current_status_rows()
    _check(String(default_rows[2][2]) == "적벽 전투: 미활성", "기본 208 전야는 적벽 미활성")

    var unrelated = Snapshot.from_campaign(campaign, 208, {
        "active_battles": [{"id": "BATTLE-UNRELATED", "status": "active"}],
    })
    main.home_state = unrelated.snapshot()
    var unrelated_rows: Array = main._current_status_rows()
    _check(String(unrelated_rows[2][2]) == "적벽 전투: 미활성", "무관한 전투는 적벽을 활성화하지 않음")

    var ready = Snapshot.from_campaign(campaign, 208, {
        "active_battles": [{"id": "BATTLE-RED-CLIFF", "status": "active"}],
        "red_cliff_conditions": READY_CONDITIONS,
    })
    main.home_state = ready.snapshot()
    var ready_rows: Array = main._current_status_rows()
    _check(String(ready_rows[2][2]) == "적벽 전투: 교전 활성", "ready 적벽은 교전 활성")
    _check(String(ready_rows[2][3]) == "구지 궤도 · 전장 확인", "ready 적벽의 전장 위치 표시")

    print("HomeActiveBattleStatus: %d 통과 / %d 실패" % [4 - failures, failures])
    quit(0 if failures == 0 else 1)
