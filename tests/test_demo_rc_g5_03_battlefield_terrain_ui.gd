extends SceneTree

## DEMO-RC-G5-03 — 전장 지형의 이동·탐지·무기 효과 UI.
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
	print("DEMO-RC-G5-03 battlefield terrain UI")
	root.size = Vector2i(1600, 900)
	await _test_map_preview_membership_and_redaction()
	_test_source_boundary()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)

func _test_map_preview_membership_and_redaction() -> void:
	var loaded := Setup.load_default(); _ok(loaded.ok, "setup loads"); var setup: Dictionary = loaded.setup.duplicate(true)
	var positions := {"RC-LIU-SQ-01": [550, 100], "RC-LIU-SQ-02": [200, 600], "RC-SUN-SQ-01": [300, 700], "RC-CAO-SQ-01": [1300, 350]}
	for squad in setup.squadrons: squad.initial_position = positions[String(squad.id)].duplicate(); squad.initial_facing_deg = 0
	var battle = Battle.new(); _ok(battle.initialize(setup).ok, "battle initializes")
	var view := View.new(); view.configure(battle, 0, JSON.stringify(setup)); root.add_child(view); await process_frame; await process_frame
	var map = view.find_child("AppliedSquadronMap", true, false); _ok(map != null, "tactical map exists")
	_eq(map.terrain_zones_for_test().size(), 3, "map consumes three public terrain zones")
	var zone_json := JSON.stringify(map.terrain_zones_for_test()); _ok(zone_json.contains("nebula") and zone_json.contains("debris") and zone_json.contains("planet_shadow"), "three terrain types are text-identifiable")
	_ok(not zone_json.contains("effects") and not zone_json.contains("basis_points"), "public map geometry contains no hidden effects")
	var membership: Label = view.find_child("OwnTerrainMembership", true, false); _ok(membership != null and membership.text.contains("지형 구역 밖"), "own current membership is explicit")
	var move: Dictionary = battle.set_order_move("RC-LIU-SQ-01", [[750, 100]], 0); _ok(move.ok, "core accepts terrain crossing move")
	view._refresh(); await process_frame
	var preview: Label = view.find_child("MovementPreview", true, false); _ok(preview.text.contains("코어 지형 미리보기") and preview.text.contains("TRN-NEBULA-01"), "preview renders core terrain segment")
	_ok(preview.text.contains("이동 비용") and preview.text.contains("내 탐지") and preview.text.contains("은폐"), "preview explains core-provided modifiers")
	var sealed_text: String = view._terrain_weapon_text({"zone_ids":["TRN-NEBULA-01"], "range_basis_points":8500, "arc_delta_deg":-10, "target_source":"sealed_estimated_aim"})
	_ok(sealed_text.contains("8500 bp") and sealed_text.contains("-10°"), "weapon terrain receipt values render verbatim")
	_ok(sealed_text.contains("봉인 추정 조준선"), "estimated fire terrain source is explicit")
	_ok(not sealed_text.contains("실제 표적"), "sealed aim text does not imply actual target terrain")
	view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await process_frame; await process_frame
	view.find_child("SunAiThisTurn", true, false).pressed.emit(); await process_frame; await process_frame
	var transition: Label = view.find_child("OwnTerrainTransition", true, false); _ok(transition != null and transition.text.contains("진입") and transition.text.contains("코어 판정"), "own terrain transition receipt visible")
	var cao_json := JSON.stringify(battle.visible_tactical_events("cao_cao", 1)); _ok(not cao_json.contains("TRN-NEBULA-01"), "enemy viewer cannot infer own terrain crossing")
	var privacy: Label = view.find_child("TerrainPrivacyNote", true, false); _ok(privacy != null and privacy.text.contains("적의 지형 교차") and privacy.text.contains("표시하지 않습니다"), "privacy boundary is explicit")
	if DisplayServer.get_name() != "headless":
		var scroll: ScrollContainer = view.find_child("MovementOrderScroll", true, false); transition = view.find_child("OwnTerrainTransition", true, false); scroll.scroll_vertical = maxi(0, int(transition.position.y) - 8); await process_frame
		var output_dir := "res://out/demo-rc-g5-03-battlefield-terrain"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)); var image := root.get_texture().get_image(); _ok(image != null and image.get_size() == Vector2i(1600, 900), "1600x900 GPU capture available")
		if image != null: _ok(image.save_png(ProjectSettings.globalize_path(output_dir.path_join("battlefield-terrain-1600x900.png"))) == OK, "GPU capture saved")
	view.free()

func _test_source_boundary() -> void:
	for path in ["res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd", "res://scripts/red_cliff_turn/red_cliff_tactical_map.gd"]:
		var source := FileAccess.get_file_as_string(path)
		_ok("Node3D" not in source and ".glb" not in source and "voyage_3d" not in source, "%s has zero 3D refs" % path)
		_ok("terrain_v4" not in source and "red-cliffs-terrain-rules.json" not in source, "%s uses no dirty terrain data/assets" % path)
