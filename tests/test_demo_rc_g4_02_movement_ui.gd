extends SceneTree

## Task ID: DEMO-RC-G4-02
## 자유 좌표·다중 경유점·방향 이동 판정 Phase B UI.
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")
const View := preload("res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd")
const TacticalMap := preload("res://scripts/red_cliff_turn/red_cliff_tactical_map.gd")

var _pass := 0
var _fail := 0

func _ok(value: bool, label: String) -> void:
	if value: _pass += 1
	else: _fail += 1; print("  x %s" % label)

func _eq(actual, expected, label: String) -> void: _ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])
func _near(actual: Vector2, expected: Vector2, label: String) -> void: _ok(actual.distance_to(expected) < 0.02, label)
func _init() -> void: call_deferred("_run")

func _run() -> void:
	print("DEMO-RC-G4-02 movement UI")
	root.size = Vector2i(1600, 900)
	await _test_transform_and_input()
	await _test_draft_edit_submit_and_live_redraw()
	_test_source_boundary()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)

func _fixture() -> Array:
	var loaded := Setup.load_default(); _ok(bool(loaded.get("ok", false)), "setup loads")
	var setup: Dictionary = loaded.get("setup", {}); var battle = Battle.new(); _ok(battle.initialize(setup).ok, "battle initializes")
	return [setup, battle]

func _test_transform_and_input() -> void:
	var fixture := _fixture(); var setup: Dictionary = fixture[0]; var battle = fixture[1]
	var map := TacticalMap.new(); map.custom_minimum_size = Vector2.ZERO; map.size = Vector2(800, 600); root.add_child(map); await process_frame
	map.configure(setup.battlefield_bounds, setup.squadrons, battle.live_navigation())
	var rect: Rect2 = map.content_rect(); _eq(rect.size.round(), Vector2(800, 450), "aspect-fit content rect")
	for point in [[0,0], [800,450], [1600,900]]:
		var local := map.battle_to_local(point); var inverse: Dictionary = map.local_to_battle(local)
		_ok(inverse.ok, "corner/center inverse accepted"); _near(Vector2(inverse.point[0], inverse.point[1]), Vector2(point[0], point[1]), "roundtrip")
	_ok(not map.local_to_battle(Vector2(400, 20)).ok, "letterbox rejected")
	map.set_camera_for_test(2.0, Vector2(31, -17)); var p := Vector2(600, 400); var screen := map.battle_to_local([p.x,p.y]); var back: Dictionary = map.local_to_battle(screen); _ok(back.ok, "zoom/pan inverse accepted"); _near(Vector2(back.point[0],back.point[1]), p, "zoom/pan roundtrip")
	map.reset_camera(); _eq(map.camera_state(), {"zoom":1.0,"pan":Vector2.ZERO}, "camera reset")
	var selected: Array[String] = []; var added: Array = []; map.squadron_selected.connect(func(id): selected.append(id)); map.waypoint_requested.connect(func(point): added.append(point))
	map.set_interaction(["RC-LIU-SQ-01"], "RC-LIU-SQ-01", TacticalMap.Mode.ADD_WAYPOINT)
	map.handle_click_for_test(map.marker_local_position("RC-LIU-SQ-01")); _eq(selected, ["RC-LIU-SQ-01"], "marker consumes click before waypoint"); _eq(added.size(), 0, "marker creates no waypoint")
	map.handle_click_for_test(map.battle_to_local([700,500])); _eq(added.size(), 1, "map click adds one waypoint")
	map.handle_click_for_test(map.battle_to_local([750,500]), true); _eq(added.size(), 1, "double-click second event does not duplicate")
	var press := InputEventMouseButton.new(); press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true; press.position = Vector2(300,300); map.call("_gui_input", press)
	var motion := InputEventMouseMotion.new(); motion.position = Vector2(350,330); map.call("_gui_input", motion)
	var release := InputEventMouseButton.new(); release.button_index = MOUSE_BUTTON_LEFT; release.pressed = false; release.position = Vector2(350,330); map.call("_gui_input", release)
	_eq(added.size(), 1, "drag release is not a waypoint")
	map.set_interaction(["RC-LIU-SQ-01"], "RC-LIU-SQ-01", TacticalMap.Mode.PAN); var pan_before: Vector2 = map.camera_state().pan
	press.position = Vector2(300,300); map.call("_gui_input", press); motion.position = Vector2(340,320); map.call("_gui_input", motion); release.position = Vector2(340,320); map.call("_gui_input", release)
	_ok(map.camera_state().pan != pan_before, "pan mode drag changes camera")
	var wheel := InputEventMouseButton.new(); wheel.button_index = MOUSE_BUTTON_WHEEL_UP; wheel.pressed = true; wheel.position = Vector2(400,300); map.call("_gui_input", wheel)
	_ok(float(map.camera_state().zoom) > 1.0, "wheel changes zoom only")
	map.free()

func _test_draft_edit_submit_and_live_redraw() -> void:
	var fixture := _fixture(); var setup: Dictionary = fixture[0]; var battle = fixture[1]; var view := View.new()
	view.configure(battle, int(setup.get("formation_revision",0)), JSON.stringify(setup)); root.add_child(view); await process_frame; await process_frame
	_eq(view.size.round(), Vector2(1600,900), "view fills 1600x900")
	_ok(view.find_child("FormationOrderPicker", true, false) != null, "formation command is available after G4-04")
	_ok(view.find_child("MovementOrderScroll", true, false) != null, "independent order scroll exists")
	view.call("_select_squadron", "RC-CAO-SQ-01"); _eq(battle.command_draft_summary().faction_id, "liu_bei", "programmatic enemy selection cannot edit")
	view.call("_select_squadron", "RC-LIU-SQ-01"); view.call("_on_arm_move")
	for point in [[410,590],[510,590],[610,590],[710,590],[810,590]]: view.call("_on_waypoint_requested", point)
	_eq(battle.command_order("RC-LIU-SQ-01").order.waypoints.size(), 5, "one through five waypoints persist in core")
	if DisplayServer.get_name() != "headless":
		var output_dir := "res://out/demo-rc-g4-02-movement"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)); await process_frame
		var image := root.get_texture().get_image(); _ok(image != null and image.get_size() == Vector2i(1600,900), "1600x900 GPU capture available")
		if image != null: _ok(image.save_png(ProjectSettings.globalize_path(output_dir.path_join("movement-ui-1600x900.png"))) == OK, "GPU capture saved")
	var before: String = battle.digest(); view.call("_on_waypoint_requested", [910,590]); _eq(battle.digest(), before, "sixth waypoint rejected atomically")
	_ok(view.find_child("TurnStatus", true, false).text.contains("1~5"), "sixth waypoint Korean error visible")
	view.call("_delete_waypoint", 2); _eq(battle.command_order("RC-LIU-SQ-01").order.waypoints.size(), 4, "middle waypoint deletion persists")
	view.find_child("FacingDegrees", true, false).value = 270; await process_frame
	_eq(float(battle.command_order("RC-LIU-SQ-01").order.facing_deg), 270.0, "facing update uses core setter")
	_ok(view.find_child("MovementPreview", true, false).text.contains("예산"), "core movement budget/ETA preview visible")
	view.call("_select_squadron", "RC-LIU-SQ-02"); _eq(battle.command_order("RC-LIU-SQ-02").order.action, "hold", "per-squad draft remains independent")
	view.call("_select_squadron", "RC-LIU-SQ-01"); _eq(battle.command_order("RC-LIU-SQ-01").order.waypoints.size(), 4, "selection refresh preserves core draft")
	view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await process_frame; await process_frame
	_eq(battle.phase(), "sun_control_prompt", "draft submit advances exactly once")
	view.find_child("SunAiThisTurn", true, false).pressed.emit(); await process_frame
	_eq(battle.phase(), "victory_check", "AI branch resolves movement")
	var event := _event(battle.turn_log()[0].resolution_receipt.movement_events, "RC-LIU-SQ-01")
	_ok(not event.is_empty() and float(event.actual_distance) > 0, "movement receipt recorded")
	_eq(view.find_child("AppliedSquadronMap", true, false).marker_local_position("RC-LIU-SQ-01"), view.find_child("AppliedSquadronMap", true, false).battle_to_local(event.to), "map redraw uses live position")
	_ok(view.find_child("TurnLedger", true, false).text.contains("판정 확정"), "viewer-redacted resolution visible in ledger")
	for name in ["Disabled무기", "Disabled탐지"]:
		var control: Button = view.find_child(name, true, false); _ok(control != null and control.disabled, "%s remains disabled" % name)
	view.free()

func _event(events: Array, id: String) -> Dictionary:
	for event in events:
		if String(event.get("squadron_id", "")) == id: return event
	return {}

func _test_source_boundary() -> void:
	for path in ["res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd", "res://scripts/red_cliff_turn/red_cliff_tactical_map.gd"]:
		var source := FileAccess.get_file_as_string(path); _ok("Node3D" not in source and ".glb" not in source and "voyage_3d" not in source, "%s has zero 3D refs" % path)
