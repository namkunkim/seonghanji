extends SceneTree

## 실제 Main 장면의 단계 카드를 발화해 Z0~Z4 렌더를 저장하는 시각 QA 도구.
## 적벽 카드는 기본 캠페인에서 잠겨 있으므로 이 도구 안에서만 계약의 다섯 조건과
## active battle을 주입한다. production 장면/스크립트/데이터는 변경하지 않는다.

const Snapshot := preload("res://app/home_map_snapshot.gd")

const READY_CONDITIONS := {
    "cao_southward_complete": true,
    "sun_quan_independent": true,
    "liu_bei_hostile_to_cao": true,
    "sun_liu_military_pact": true,
    "yangtze_defense_line": true,
}

const LEVEL_NAMES := ["z0-overview", "z1-jingzhou", "z2-solar", "z3-guji", "z4-red-cliff"]
const EXPECTED_LEVELS := [1, 2, 3, 4, 5]
const SETTLE_FRAMES := 2

var _failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var output_dir := _output_directory()
    var error := DirAccess.make_dir_recursive_absolute(output_dir)
    if error != OK:
        push_error("캡처 디렉터리를 만들 수 없음: %s (%s)" % [output_dir, error])
        quit(2)
        return

    var packed: PackedScene = load("res://scenes/main.tscn")
    var main = packed.instantiate()
    root.add_child(main)
    await _wait_frames(4)
    _enable_ready_red_cliff_in_harness(main)
    await _wait_frames(3)
    if main.stage_buttons.size() != 5:
        push_error("홈 단계 카드 수 불일치: expected=5 actual=%d" % main.stage_buttons.size())
        quit(1)
        return
    main.cam.position_smoothing_enabled = false
    main.cam.reset_smoothing()

    for index in range(main.stage_buttons.size()):
        var button: Button = main.stage_buttons[index]
        if button.disabled:
            _failures.append("stage_buttons[%d]가 비활성" % index)
            continue
        button.emit_signal("pressed")
        main.cam.reset_smoothing()
        await _wait_frames(SETTLE_FRAMES)
        var expected: int = EXPECTED_LEVELS[index]
        var actual: int = main.map._semantic_level_for_zoom(main.cam.zoom.x)
        if actual != expected or main.map.semantic_level != expected:
            _failures.append("Z%d 단계 불일치: expected=%d actual=%d map=%d zoom=%.4f" % [
                index, expected, actual, main.map.semantic_level, main.cam.zoom.x])
        await RenderingServer.frame_post_draw
        var path := output_dir.path_join(LEVEL_NAMES[index] + ".png")
        var save_error := root.get_texture().get_image().save_png(path)
        if save_error != OK:
            _failures.append("Z%d PNG 저장 실패: %s" % [index, save_error])
        else:
            print("CAPTURE Z%d semantic=%d zoom=%.4f camera=%s path=%s" % [
                index, main.map.semantic_level, main.cam.zoom.x, main.cam.position, path])

    if _failures.is_empty():
        print("HomeSemanticCapture: 5단계 검증/캡처 통과 — " + output_dir)
        quit(0)
    else:
        for failure in _failures:
            print("실패: " + failure)
        print("HomeSemanticCapture: %d 실패" % _failures.size())
        quit(1)

func _enable_ready_red_cliff_in_harness(main) -> void:
    var data := GameData.load_all()
    var campaign := Campaign.scenario_03(data, 208)
    var ready = Snapshot.from_campaign(campaign, 208, {
        "active_battles": [{"id": "BATTLE-RED-CLIFF", "status": "active"}],
        "red_cliff_conditions": READY_CONDITIONS,
    })
    main.home_snapshot = ready
    main.home_state = ready.snapshot()
    main.map.active_battles = ready.active_battles()
    main.map.canonical_bodies = main._project_body_rows(ready.visible_bodies(2))
    main.map.queue_redraw()

    if root.size_changed.is_connected(main._layout_ui):
        root.size_changed.disconnect(main._layout_ui)
    for child in main.get_children():
        if child is CanvasLayer:
            main.remove_child(child)
            child.queue_free()
    var projected_systems: Array = main._project_systems(main.home_state, campaign)
    main._build_ui(main._load_json("res://data/galaxy.json"), projected_systems)

func _wait_frames(count: int) -> void:
    for _index in range(count):
        await process_frame

func _output_directory() -> String:
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--output="):
            return argument.trim_prefix("--output=").replace("\\", "/")
    return OS.get_temp_dir().path_join("seonghanji-semantic-captures")
