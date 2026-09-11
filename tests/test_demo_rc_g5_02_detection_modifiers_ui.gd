extends SceneTree

## DEMO-RC-G5-02 — 센서·전자전·진형·장수 탐지 보정 UI.
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")
const View := preload("res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd")

var _pass := 0
var _fail := 0
func _ok(value: bool, label: String) -> void:
	if value: _pass += 1
	else: _fail += 1; print("  x %s" % label)
func _eq(actual, expected, label: String) -> void: _ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])
func _init() -> void: call_deferred("_run")

func _run() -> void:
	print("DEMO-RC-G5-02 detection modifier UI")
	root.size = Vector2i(1600, 900)
	await _test_viewer_safe_rationale_and_g5_01_regression()
	_test_source_boundary()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)

func _test_viewer_safe_rationale_and_g5_01_regression() -> void:
	var loaded := Setup.load_default(); _ok(loaded.ok, "setup loads"); var setup: Dictionary = loaded.setup.duplicate(true)
	var positions := {"RC-LIU-SQ-01": [100, 100], "RC-LIU-SQ-02": [100, 100], "RC-SUN-SQ-01": [100, 700], "RC-CAO-SQ-01": [400, 100]}
	for squad in setup.squadrons: squad.initial_position = positions[String(squad.id)].duplicate(); squad.initial_facing_deg = 0
	var battle = Battle.new(); _ok(battle.initialize(setup).ok, "battle initializes")
	var view := View.new(); view.configure(battle, 0, JSON.stringify(setup)); root.add_child(view); await process_frame; await process_frame
	var auto: Button = view.find_child("DetectionAutomatic", true, false); _ok(auto != null and auto.disabled and auto.text.contains("자동 코어 판정"), "detection is automatic, not a fake command")
	view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await process_frame; await process_frame; view.find_child("SunAiThisTurn", true, false).pressed.emit(); await process_frame; await process_frame
	var contacts: Array = battle.visible_contacts("liu_bei").contacts; _eq(contacts.size(), 1, "multi-observer merge exposes one contact")
	var contact: Dictionary = contacts[0]; var rationale: Dictionary = contact.detection_rationale; var own: Dictionary = rationale.own_sensor_breakdown
	var label: Label = view.find_child("DetectionRationaleContact", true, false); _ok(label != null, "contact rationale label exists")
	var text := label.text
	_ok(text.contains(String(rationale.reason_label)) and text.contains("내 함선 센서 %d" % int(own.ship_sensor_points)) and text.contains("진형 적용 %d" % int(own.formation_adjusted_sensor_points)), "core reason and own sensor summary visible")
	_ok(text.contains(String(own.commander_name)) and text.contains(String(own.intelligence_band)) and text.contains("%+d" % int(own.intelligence_sensor_points)), "own commander intelligence band visible")
	_ok(text.contains(String(rationale.observer_formation_id)) and text.contains("%+d%%" % int(rationale.observer_formation_detection_percent)), "own formation modifier visible")
	_ok(text.contains(String(rationale.terrain_label)) and text.contains("내 지형") and not text.contains("terrain_detection"), "terrain rationale follows active G5-03 viewer contract")
	var public_json := JSON.stringify(contact)
	for forbidden in ["target_ew_points", "distance_penalty", "confirmed_range", "estimated_range", "target_formation", "target_commander"]: _ok(not public_json.contains(forbidden), "viewer omits %s" % forbidden)
	_ok(not text.contains("정확 거리") and not text.contains("임계값"), "UI does not expose distance or threshold")
	var detection_event := {}
	for event in battle.visible_tactical_events("liu_bei").events:
		if String(event.get("event_type", "")) == "detection": detection_event = event; break
	_ok(not detection_event.is_empty() and detection_event.detection_rationale == rationale, "viewer detection event repeats safe rationale")
	view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await process_frame; await process_frame
	_ok(view.find_child("SetEstimatedFire", true, false) != null, "G5-01 estimated-fire UI remains available")
	if DisplayServer.get_name() != "headless":
		var scroll: ScrollContainer = view.find_child("MovementOrderScroll", true, false); label = view.find_child("DetectionRationaleContact", true, false); scroll.scroll_vertical = maxi(0, int(label.position.y) - 8); await process_frame
		var output_dir := "res://out/demo-rc-g5-02-detection-modifiers"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)); var image := root.get_texture().get_image(); _ok(image != null and image.get_size() == Vector2i(1600, 900), "1600x900 GPU capture available")
		if image != null: _ok(image.save_png(ProjectSettings.globalize_path(output_dir.path_join("detection-modifiers-1600x900.png"))) == OK, "GPU capture saved")
	view.free()

func _test_source_boundary() -> void:
	for path in ["res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd", "res://scripts/red_cliff_turn/red_cliff_tactical_map.gd"]:
		var source := FileAccess.get_file_as_string(path); _ok("Node3D" not in source and ".glb" not in source and "voyage_3d" not in source, "%s has zero 3D refs" % path)
