extends SceneTree

## DEMO-RC-G4-04 — 진형과 정면·측면·후면 보정 UI.
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
func _init() -> void: call_deferred("_run")

func _run() -> void:
	print("DEMO-RC-G4-04 formation/facing UI")
	root.size = Vector2i(1600,900)
	await _test_editor_draft_and_resolution()
	await _test_redacted_sector_presentation()
	_test_source_boundary()
	print("PASS %d / FAIL %d" % [_pass,_fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)

func _fixture() -> Array:
	var loaded := Setup.load_default(); _ok(loaded.ok, "setup loads"); var battle = Battle.new(); _ok(battle.initialize(loaded.setup).ok, "battle initializes")
	return [loaded.setup, battle]

func _test_editor_draft_and_resolution() -> void:
	var fixture := _fixture(); var setup: Dictionary = fixture[0]; var battle = fixture[1]; var view := View.new()
	view.configure(battle, int(setup.get("formation_revision",0)), JSON.stringify(setup)); root.add_child(view); await process_frame; await process_frame
	var picker: OptionButton = view.find_child("FormationOrderPicker", true, false); _ok(picker != null and picker.item_count == 7, "seven core allowed formations shown")
	_ok(view.find_child("FormationModifierSnapshot", true, false).text.contains("코어 profile"), "core modifier snapshot visible")
	var target_index := _picker_index(picker, "FRM-04"); _ok(target_index >= 0, "formation option metadata available")
	picker.item_selected.emit(target_index); await process_frame
	_eq(battle.formation_order("RC-LIU-SQ-01").order.formation_id, "FRM-04", "picker stages core formation order")
	view.call("_on_arm_move"); view.call("_on_waypoint_requested", [410,590]); _eq(battle.command_order("RC-LIU-SQ-01").order.action, "move", "MOVE stages beside formation")
	view.call("_select_squadron", "RC-LIU-SQ-02"); view.call("_select_squadron", "RC-LIU-SQ-01")
	_eq(battle.formation_order("RC-LIU-SQ-01").order.formation_id, "FRM-04", "formation draft persists across selection")
	var before: String = battle.digest(); view.call("_select_squadron", "RC-CAO-SQ-01"); _eq(battle.digest(), before, "programmatic enemy edit rejected atomically")
	view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await process_frame; await process_frame
	_eq(battle.phase(), "sun_control_prompt", "movement and formation draft submit together")
	view.find_child("SunAiThisTurn", true, false).pressed.emit(); await process_frame
	_eq(battle.formation_state()["RC-LIU-SQ-01"].formation_id, "FRM-04", "formation applies at resolution start")
	_eq(int(battle.formation_state()["RC-LIU-SQ-01"].effective_turn), 1, "formation effective same turn")
	view.free()

func _test_redacted_sector_presentation() -> void:
	var fixture := _fixture(); var setup: Dictionary = fixture[0]; var battle = fixture[1]
	var view := View.new(); view.configure(battle, 0, JSON.stringify(setup)); root.add_child(view); await process_frame
	var map = view.find_child("AppliedSquadronMap", true, false)
	var contacts := [{"contact_id":"OPAQUE", "state":"estimated", "display_position":[500,300], "last_known_position":[500,300], "last_seen_turn":1, "stale":false}]
	var target_event := {"event_id":"TARGET", "event_type":"shot_authorized", "own_squadron_id":"RC-LIU-SQ-01", "contact_id":"OPAQUE", "own_role":"target", "outcome":"shot_authorized", "damage_pending":true, "formation_modifier":{"own_role":"target","own_formation_id":"FRM-01","own_defense_percent":-5,"incoming_sector":"indeterminate","own_sector_defense_percent":0,"own_total_defense_percent":-5,"result_pending":["hit","damage"]}}
	map.set_intelligence("liu_bei", contacts, [target_event]); var intel: Dictionary = map.intelligence_state_for_test()
	_ok(not JSON.stringify(intel).contains("facing_deg") and not JSON.stringify(intel).contains("arc_deg") and not JSON.stringify(intel).contains("range"), "target feed exposes no hostile shooter geometry")
	_ok(not JSON.stringify(contacts).contains("formation_id"), "estimated contact exposes no enemy formation")
	_eq(view.call("_sector_label", "front"), "정면", "front has text label"); _eq(view.call("_sector_label", "flank"), "측면", "flank has text label"); _eq(view.call("_sector_label", "rear"), "후면", "rear has text label"); _ok(String(view.call("_sector_label", "indeterminate")).contains("동일 좌표"), "coincident sector is indeterminate text")
	if DisplayServer.get_name() != "headless":
		var output_dir := "res://out/demo-rc-g4-04-formation-facing"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)); await process_frame
		var image := root.get_texture().get_image(); _ok(image != null and image.get_size() == Vector2i(1600,900), "1600x900 GPU capture available")
		if image != null: _ok(image.save_png(ProjectSettings.globalize_path(output_dir.path_join("formation-facing-1600x900.png"))) == OK, "GPU capture saved")
	view.free()

func _picker_index(picker: OptionButton, formation_id: String) -> int:
	for index in range(picker.item_count):
		if String(picker.get_item_metadata(index)) == formation_id: return index
	return -1

func _test_source_boundary() -> void:
	for path in ["res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd","res://scripts/red_cliff_turn/red_cliff_tactical_map.gd"]:
		var source := FileAccess.get_file_as_string(path); _ok("Node3D" not in source and ".glb" not in source and "voyage_3d" not in source, "%s has zero 3D refs" % path)
