extends SceneTree

## S5-02 — public viewer projection -> product BattleView -> isolated 3D renderer.

const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")
const BattleView := preload("res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd")

var passed := 0
var failed := 0


func check(value: bool, label: String) -> void:
	if value: passed += 1
	else: failed += 1; print("  x %s" % label)


func _init() -> void: call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var loaded: Dictionary = Setup.load_default(); check(bool(loaded.get("ok", false)), "default setup loads")
	var battle := Battle.new(); var initialized: Dictionary = battle.initialize(loaded.get("setup", {})); check(bool(initialized.get("ok", false)), "battle initializes")
	if initialized.get("ok", false): await _test_product_flow(battle)
	await _test_main_product_entry()
	_test_source_boundary()
	print("PASS %d / FAIL %d" % [passed, failed])
	quit(Harness.EXIT_FAIL if failed > 0 else Harness.EXIT_PASS)


func _test_product_flow(battle) -> void:
	var navigation: Dictionary = battle.live_navigation(); var start: Array = navigation.get("RC-LIU-SQ-01", {}).get("position", [])
	check(start.size() == 2 and bool(battle.set_order_move("RC-LIU-SQ-01", [[float(start[0]) + 24.0, float(start[1])]], 0.0).get("ok", false)), "public movement order staged for visible event")
	check(bool(battle.submit_command_draft().get("ok", false)), "Liu command submits through public flow")
	check(bool(battle.submit_sun_control_choice("no", true).get("ok", false)), "Sun AI choice submits through public flow")
	check(bool(battle.resolve_turn().get("ok", false)), "turn resolves through public flow")
	var before_digest: String = battle.digest()
	var public_projection: Dictionary = battle.viewer_3d_projection("liu_bei")
	check(bool(public_projection.get("ok", false)) and String(public_projection.get("profile_id", "")) == "S5-02", "public S5-02 viewer projection available")
	var view := BattleView.new(); check(bool(view.configure(battle, 0, before_digest).get("ok", false)), "product battle view accepts initialized controller")
	root.add_child(view); await _settle()
	var split := view.find_child("BattlefieldVisualizationSplit", true, false) as HSplitContainer
	var map := view.find_child("AppliedSquadronMap", true, false) as Control
	var renderer := view.find_child("RedCliffVisibleFleet3D", true, false) as Control
	check(split != null and map != null and renderer != null, "product view contains one 2D/3D split")
	check(renderer.find_children("VisibleFleet3DViewport", "SubViewport", true, false).size() == 1, "isolated renderer owns exactly one SubViewport")
	check(JSON.stringify(renderer.projection_for_test()) == JSON.stringify(public_projection), "renderer receives the public projection unchanged")
	check(battle.digest() == before_digest, "rendering leaves authoritative battle state unchanged")
	var expected_count := 0
	for squadron in public_projection.get("own_squadrons", []):
		for component in squadron.get("composition_current", []): expected_count += maxi(0, int(component.get("count", 0)))
	var summary: Dictionary = renderer.visual_summary_for_test()
	check(int(summary.get("own_ship_count", -1)) == mini(204, expected_count), "own exact composition renders up to the 204-ship cap")
	check(int(summary.get("confirmed_proxy_count", 0)) + int(summary.get("estimated_proxy_count", 0)) == public_projection.get("contacts", []).size(), "visible enemy contacts render as opaque proxies only")
	check(renderer.projection_for_test().get("events", []) == public_projection.get("events", []), "product renderer receives the complete public viewer event list")
	check(public_projection.get("events", []).any(func(event): return String(event.get("event_type", "")) == "movement_resolved" and String(event.get("own_squadron_id", "")) == "RC-LIU-SQ-01"), "own resolved movement enters the public projection")
	check(int(summary.get("trail_count", 0)) >= 1, "public resolved movement produces a 3D trail")
	check(renderer.model_paths_for_test().size() == 7 and renderer.imported_material_override_count_for_test() == 0, "all seven GLBs load without material override")
	var orientation: Dictionary = renderer.orientation_for_test(0.0)
	check((orientation.forward as Vector3).is_equal_approx(Vector3.RIGHT) and (orientation.aft as Vector3).is_equal_approx(Vector3.LEFT), "battle facing 0 maps to +X and aft trail to +Z-local")
	if split != null and map != null and renderer != null:
		var total_width := maxf(1.0, map.size.x + renderer.size.x)
		check(map.size.x / total_width > 0.58 and renderer.size.x / total_width < 0.42, "default evidence layout is approximately 2D:3D = 2:1")
		var toggle := view.find_child("ToggleVisibleFleet3D", true, false) as Button; toggle.pressed.emit(); await _settle()
		total_width = maxf(1.0, map.size.x + renderer.size.x)
		check(renderer.size.x / total_width > 0.58 and toggle.text == "2D 중심으로", "3D enlarge toggle changes layout to approximately 1:2")
		var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true; root.push_input(escape, true); await _settle()
		total_width = maxf(1.0, map.size.x + renderer.size.x)
		check(map.size.x / total_width > 0.58 and toggle.text == "3D 크게 보기", "Escape returns from enlarged 3D without closing battle")
	check(not view.find_children("*", "Button", true, false).any(func(button): return String(button.text).contains("3D 이동") or String(button.text).contains("WASD")), "renderer adds no navigation or mutation controls")
	view.free()


func _test_main_product_entry() -> void:
	var main = load("res://scenes/main.tscn").instantiate(); root.add_child(main); await _settle()
	var menu_button := main.red_cliff_demo_button as Button
	check(menu_button != null and not menu_button.disabled, "Main exposes enabled Red Cliffs menu action")
	menu_button.pressed.emit(); await _settle()
	var preparation := main.red_cliff_preparation_view as Control
	check(preparation != null and preparation.visible, "Main menu action opens product preparation")
	var start := preparation.find_child("StartTurnBattle", true, false) as Button
	check(start != null and not start.disabled, "validated preparation exposes battle start")
	start.pressed.emit(); await _settle()
	var turn_view := main.red_cliff_turn_battle_view as Control
	var renderer := turn_view.find_child("RedCliffVisibleFleet3D", true, false) if turn_view != null else null
	check(turn_view != null and turn_view.visible and not preparation.visible, "preparation signal opens actual turn battle view")
	check(renderer != null and renderer.find_children("VisibleFleet3DViewport", "SubViewport", true, false).size() == 1, "actual Main battle path mounts isolated 3D evidence viewport")
	if renderer != null:
		check(renderer.model_paths_for_test().size() == 7 and String(renderer.projection_for_test().get("profile_id", "")) == "S5-02", "actual Main battle path loads seven models from public S5-02 projection")
		if DisplayServer.get_name() != "headless":
			var output_dir := "res://out/s5-02-red-cliff-visible-fleet-3d"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
			var default_image := root.get_texture().get_image(); check(default_image != null and default_image.get_size() == Vector2i(1600, 900), "Main entry default GPU capture is 1600x900")
			if default_image != null: check(default_image.save_png(ProjectSettings.globalize_path(output_dir.path_join("visible-fleet-3d-main-entry-default-1600x900.png"))) == OK, "Main entry default GPU capture saved")
			var toggle := turn_view.find_child("ToggleVisibleFleet3D", true, false) as Button; toggle.pressed.emit(); await _settle()
			var expanded_image := root.get_texture().get_image(); check(expanded_image != null and expanded_image.get_size() == Vector2i(1600, 900), "Main entry expanded GPU capture is 1600x900")
			if expanded_image != null: check(expanded_image.save_png(ProjectSettings.globalize_path(output_dir.path_join("visible-fleet-3d-main-entry-expanded-1600x900.png"))) == OK, "Main entry expanded GPU capture saved")
	main.free()


func _test_source_boundary() -> void:
	var view_source := FileAccess.get_file_as_string("res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd")
	var renderer_source := FileAccess.get_file_as_string("res://scripts/red_cliff_turn/visible_fleet_3d/red_cliff_visible_fleet_3d.gd")
	check(view_source.count("viewer_3d_projection(_viewer_faction_id)") == 1, "battle view uses the single frozen viewer projection API")
	check("snapshot())" not in renderer_source and "battle_controller" not in renderer_source and "RedCliffsTurnBattle" not in renderer_source, "isolated renderer cannot reach controller or raw snapshot")
	check("RandomNumberGenerator" not in renderer_source and "randf" not in renderer_source and "randi" not in renderer_source, "renderer placement is deterministic")
	check("material_override =" not in renderer_source and "set_surface_override_material" not in renderer_source, "renderer never overrides imported PBR materials")
	check("_input(" not in renderer_source and "_unhandled_input(" not in renderer_source and "KEY_W" not in renderer_source, "renderer has no WASD or direct input path")


func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame
