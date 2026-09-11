extends SceneTree

## DEMO-RC-G6-02 — 전술 임무 상시 변경과 판정 중 변경의 다음 턴 적용 UI.
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const FastCraft := preload("res://core/demo_red_cliffs/red_cliffs_fast_craft_formation.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")
const BattleView := preload("res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd")

var _pass := 0
var _fail := 0

func _ok(value: bool, label: String) -> void:
	if value: _pass += 1
	else: _fail += 1; print("  x %s" % label)

func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])

func _init() -> void: call_deferred("_run")

func _run() -> void:
	print("DEMO-RC-G6-02 — 전술 임무 상시 변경과 판정 중 변경의 다음 턴 적용 UI")
	root.size = Vector2i(1600, 900)
	await _test_liu_immediate_queue_cancel_promote()
	await _test_sun_manual_and_ai_read_only()
	await _test_turn_limit_read_only()
	_test_source_boundary()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)

func _test_liu_immediate_queue_cancel_promote() -> void:
	var loaded := Setup.load_default(); _ok(loaded.ok, "default setup loads")
	var battle = Battle.new(); _ok(battle.initialize(loaded.setup).ok, "battle initializes")
	var view := BattleView.new(); _ok(view.configure(battle, 1, "g6-02-ui").ok, "battle view configures"); root.add_child(view); await _settle()
	var cross_digest := battle.digest(); view._viewer_faction_id = "cao_cao"; view._on_fast_craft_mission("RC-LIU-FC-01", "liaison"); await _settle()
	_eq(battle.digest(), cross_digest, "cross-faction UI mutation is rejected atomically")
	view._viewer_faction_id = "liu_bei"; view._refresh(); await _settle()
	var select: Button = view.find_child("Select_RC-LIU-FC-01", true, false); _ok(select != null, "Liu fast craft is reachable"); select.pressed.emit(); await _settle()
	var loadout: Label = view.find_child("AppliedFastCraftLoadout", true, false)
	_ok(loadout != null and loadout.text.contains("전투 중 불변") and loadout.text.contains("정찰 장비"), "immutable applied equipment is explicit")
	var title: Label = view.find_child("FastCraftMissionTitle", true, false); _ok(title != null and title.text.contains("현재 턴 즉시 적용"), "core immediate capability is visible")
	var recon: Button = view.find_child("FastTacticalMission_recon", true, false); var liaison: Button = view.find_child("FastTacticalMission_liaison", true, false)
	_ok(recon != null and recon.disabled and liaison != null and not liaison.disabled, "only equipment-supported missions are offered")
	_ok(view.find_child("FastTacticalMission_torpedo", true, false) == null, "unsupported torpedo mission is absent")
	liaison.pressed.emit(); await _settle()
	var staged: Dictionary = battle.viewer_fast_craft_missions("liu_bei").statuses[0]
	_eq(staged.mission_id, "recon", "active mission remains authoritative before submit")
	_eq(staged.display_mission_id, "liaison", "draft mission is the immediate UI-effective choice")
	var state: Label = view.find_child("FastCraftMissionState", true, false); _ok(state.text.contains("활성 정찰") and state.text.contains("이번 명령 초안 연락") and state.text.contains("제출 시 원자 적용"), "active and atomic draft states are distinguished")
	var choose_recon: Button = view.find_child("FastTacticalMission_recon", true, false); _ok(not choose_recon.disabled, "mission remains reselectable before submit"); choose_recon.pressed.emit(); await _settle()
	var reverted: Dictionary = battle.viewer_fast_craft_missions("liu_bei").statuses[0]
	_eq(reverted.draft_mission_id, "", "reselecting active mission clears pending draft")
	_eq(reverted.display_mission_id, "recon", "last valid pre-submit selection wins")
	var choose_liaison: Button = view.find_child("FastTacticalMission_liaison", true, false); choose_liaison.pressed.emit(); await _settle()
	_ok(battle.submit_command_draft().ok, "Liu command submits atomically"); _eq(battle.viewer_fast_craft_missions("liu_bei").statuses[0].mission_id, "liaison", "submitted mission becomes active")
	_ok(battle.submit_sun_control_choice("ai").ok, "Sun AI route reaches resolution"); view._refresh(); await _settle()
	var overview: Label = view.find_child("FastCraftMissionOverview", true, false); _ok(overview != null, "locked judgement phase keeps own fast craft mission overview reachable")
	var queue_title: Label = view.find_child("FastCraftMissionTitle_RC-LIU-FC-01", true, false); _ok(queue_title != null and queue_title.text.contains("다음 턴 예약"), "core queue capability is visible")
	var queue_recon: Button = view.find_child("FastTacticalMission_RC-LIU-FC-01_recon", true, false); _ok(queue_recon != null and not queue_recon.disabled, "judgement-phase supported mission can be queued"); queue_recon.pressed.emit(); await _settle()
	var queued: Dictionary = battle.viewer_fast_craft_missions("liu_bei"); _eq(queued.queued[0].effective_turn, 2, "UI request queues for next turn")
	var cancel: Button = view.find_child("CancelFastCraftMissionQueue_RC-LIU-FC-01", true, false); _ok(cancel != null and not cancel.disabled, "queued mission can be cancelled"); cancel.pressed.emit(); await _settle()
	_eq(battle.viewer_fast_craft_missions("liu_bei").queued, [], "cancel consumes queue")
	queue_recon = view.find_child("FastTacticalMission_RC-LIU-FC-01_recon", true, false); queue_recon.pressed.emit(); await _settle()
	if DisplayServer.get_name() != "headless":
		var output_dir := "res://out/demo-rc-g6-02-fast-craft-mission"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)); await process_frame
		var image := root.get_texture().get_image(); _ok(image != null and image.get_size() == Vector2i(1600, 900), "1600x900 GPU image")
		if image != null: _ok(image.save_png(ProjectSettings.globalize_path(output_dir.path_join("fast-craft-mission-1600x900.png"))) == OK, "GPU capture saved")
	_ok(battle.resolve_turn().ok and battle.continue_turn().ok, "turn resolves and next command begins"); view._refresh(); await _settle()
	var promoted: Dictionary = battle.viewer_fast_craft_missions("liu_bei").statuses[0]
	_eq(promoted.mission_id, "recon", "queued mission promotes next turn")
	_eq(promoted.source, "next_turn_promotion", "promotion source is displayed from core receipt")
	var select_promoted: Button = view.find_child("Select_RC-LIU-FC-01", true, false); select_promoted.pressed.emit(); await _settle()
	var latest: Label = view.find_child("FastCraftMissionLastEvent", true, false); _ok(latest != null and latest.text.contains("예약 승격"), "viewer append order displays promotion as latest event")
	_ok(battle.viewer_fast_craft_missions("cao_cao").statuses.is_empty(), "enemy viewer receives no Liu mission or equipment")
	view.free()

func _test_sun_manual_and_ai_read_only() -> void:
	var loaded := Setup.load_default(); var formation = FastCraft.new(); _ok(formation.initialize(loaded.setup).ok, "Sun fixture formation initializes")
	_ok(formation.set_sun_manual(true).ok, "Sun preparation opt-in applies")
	var created: Dictionary = formation.create_squadron("sun_quan", "손권 구조정대", "CHR-0186", 4, "FAST-EQ-RESCUE", "FRM-07", Vector2(400, 600)); _ok(created.ok, "Sun pure fast craft fixture is created")
	var applied: Dictionary = formation.apply(); _ok(applied.ok, "Sun fixture applies"); var sun_id := String(created.squadron_id)
	var manual_battle = Battle.new(); _ok(manual_battle.initialize(applied.applied_setup).ok, "manual Sun battle initializes")
	_ok(manual_battle.submit_command_draft().ok and manual_battle.submit_sun_control_choice("manual").ok, "manual Sun command phase opens")
	var manual_view := BattleView.new(); manual_view.configure(manual_battle, int(applied.formation_revision), String(applied.digest)); root.add_child(manual_view); await _settle()
	var select: Button = manual_view.find_child("Select_%s" % sun_id, true, false); _ok(select != null, "manual Sun fast craft is selectable"); select.pressed.emit(); await _settle()
	var manual_title: Label = manual_view.find_child("FastCraftMissionTitle", true, false); _ok(manual_title != null and manual_title.text.contains("현재 턴 즉시 적용"), "manual Sun may change supported mission")
	var liaison: Button = manual_view.find_child("FastTacticalMission_liaison", true, false); _ok(liaison != null and not liaison.disabled, "manual Sun mission control is enabled"); liaison.pressed.emit(); await _settle()
	_eq(manual_battle.viewer_fast_craft_missions("sun_quan").statuses[0].display_mission_id, "liaison", "direct Sun UI sends requester identity and stages mission")
	manual_view.free()
	var ai_battle = Battle.new(); _ok(ai_battle.initialize(applied.applied_setup).ok, "AI Sun battle initializes")
	_ok(ai_battle.submit_command_draft().ok and ai_battle.submit_sun_control_choice("ai").ok, "AI Sun resolves through common core path")
	var ai_view := BattleView.new(); ai_view.configure(ai_battle, int(applied.formation_revision), String(applied.digest)); root.add_child(ai_view); await _settle()
	ai_view._viewer_faction_id = "sun_quan"; ai_view._refresh(); await _settle()
	var read_only: Label = ai_view.find_child("FastCraftMissionTitle_%s" % sun_id, true, false); _ok(read_only != null and read_only.text.contains("읽기 전용"), "AI-controlled Sun mission is read-only")
	var ai_button: Button = ai_view.find_child("FastTacticalMission_%s_liaison" % sun_id, true, false); _ok(ai_button != null and ai_button.disabled, "AI Sun cannot be manipulated by viewer")
	var ai_row: Label = ai_view.find_child("AiFastCraftMissionRow", true, false); _ok(ai_row != null and ai_row.text.contains("동일 코어 validator 통과"), "own AI mission receipt displays common validator provenance")
	ai_view.free()

func _test_turn_limit_read_only() -> void:
	var loaded := Setup.load_default(); var battle = Battle.new(); _ok(battle.initialize(loaded.setup).ok, "turn-limit UI fixture initializes")
	var advanced := true
	for _turn in range(1, 20):
		advanced = advanced and battle.submit_command_draft().ok and battle.submit_sun_control_choice("ai").ok and battle.resolve_turn().ok and battle.continue_turn().ok
	_ok(advanced and battle.turn() == 20, "fixture reaches turn 20")
	_ok(battle.submit_command_draft().ok and battle.submit_sun_control_choice("ai").ok, "turn 20 reaches judgement")
	var view := BattleView.new(); view.configure(battle, 1, "turn-limit"); root.add_child(view); await _settle()
	var title: Label = view.find_child("FastCraftMissionTitle_RC-LIU-FC-01", true, false); _ok(title != null and title.text.contains("읽기 전용"), "turn 20 mission panel is read-only")
	var state: Label = view.find_child("FastCraftMissionState", true, false); _ok(state != null and state.text.contains("적용할 다음 턴이 없습니다"), "turn 20 denial reason is clear")
	var liaison: Button = view.find_child("FastTacticalMission_RC-LIU-FC-01_liaison", true, false); _ok(liaison != null and liaison.disabled, "turn 20 cannot queue an impossible next-turn mission")
	view.free()

func _test_source_boundary() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd")
	_ok("Node3D" not in source and ".glb" not in source and "voyage_3d" not in source, "mission UI remains 2D only")
	_ok("viewer_fast_craft_missions" in source and "supported_mission_ids" in source and "can_change" in source and "application" in source, "UI consumes public core receipt capabilities")
	_ok("mission_effect" not in source and "fuel_cost" not in source, "UI does not implement G6-03+ mission results")

func _settle() -> void:
	await process_frame
	await process_frame
