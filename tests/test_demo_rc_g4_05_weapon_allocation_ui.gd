extends SceneTree

## DEMO-RC-G4-05 — 무기 비율·프리셋·사격 중지 명령 UI.
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")
const View := preload("res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd")

var _pass := 0
var _fail := 0
func _ok(value: bool, label: String) -> void:
	if value: _pass += 1
	else: _fail += 1; print("  x %s" % label)
func _eq(actual, expected, label: String) -> void: _ok(actual == expected, "%s (%s != %s)" % [label,str(actual),str(expected)])
func _init() -> void: call_deferred("_run")

func _run() -> void:
	print("DEMO-RC-G4-05 weapon allocation UI")
	root.size = Vector2i(1600,900)
	await _test_allocation_presets_hold_and_submit()
	_test_source_boundary()
	print("PASS %d / FAIL %d" % [_pass,_fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)

func _test_allocation_presets_hold_and_submit() -> void:
	var loaded := Setup.load_default(); _ok(loaded.ok, "setup loads"); var setup: Dictionary = loaded.setup; var battle = Battle.new(); _ok(battle.initialize(setup).ok, "battle initializes")
	var view := View.new(); view.configure(battle, int(setup.get("formation_revision",0)), JSON.stringify(setup)); root.add_child(view); await process_frame; await process_frame
	var preset: OptionButton = view.find_child("WeaponPresetPicker", true, false); _ok(preset != null and preset.item_count >= 3, "core provides at least three presets")
	var categories: Array = battle.weapon_categories(); _eq(categories.size(), 4, "four core weapon categories shown")
	var unavailable := 0
	for category in categories:
		var spin: SpinBox = view.find_child("WeaponBps_%s" % category.weapon_id, true, false); _ok(spin != null, "%s basis-point input exists" % category.weapon_id)
		_eq(int(spin.step), 1, "%s supports canonical 1 bp precision" % category.weapon_id)
		if not spin.editable: unavailable += 1; _eq(int(spin.value), 0, "unavailable weapon is disabled at zero")
	_ok(unavailable > 0, "composition availability disables absent weapons")
	_ok(view.find_child("WeaponAllocationTotal", true, false).text.contains("10000 bp") and view.find_child("WeaponAllocationTotal", true, false).text.contains("100.00%"), "core total 100 percent visible")
	var first_available := String(battle.weapon_allocation_state()["RC-LIU-SQ-01"].available_categories[0]); view.call("_on_weapon_basis_points", 7000.0, first_available)
	var normalized: Dictionary = battle.weapon_allocation_order("RC-LIU-SQ-01"); _eq(int(normalized.total_basis_points), 10000, "core normalization returns exact total")
	_ok(view.find_child("WeaponAllocationTotal", true, false).text.contains("100.00%"), "normalized receipt refreshes UI")
	var preset_before := JSON.stringify(normalized.order.allocations); preset = view.find_child("WeaponPresetPicker", true, false); preset.select(mini(1,preset.item_count-1)); view.call("_on_weapon_preset", preset)
	var preset_after := JSON.stringify(battle.weapon_allocation_order("RC-LIU-SQ-01").order.allocations); _ok(preset_after != preset_before, "core preset updates allocation")
	var preserved: Dictionary = battle.weapon_allocation_order("RC-LIU-SQ-01").order.allocations.duplicate(true); view.call("_on_hold_fire", true)
	_ok(battle.weapon_allocation_order("RC-LIU-SQ-01").order.hold_fire, "attack hold stages")
	_eq(battle.weapon_allocation_order("RC-LIU-SQ-01").order.allocations, preserved, "hold preserves allocation")
	view.call("_on_hold_fire", false); _ok(not battle.weapon_allocation_order("RC-LIU-SQ-01").order.hold_fire, "resume restores firing")
	_eq(battle.weapon_allocation_order("RC-LIU-SQ-01").order.allocations, preserved, "resume retains allocation")
	view.call("_on_formation_selected", 3, view.find_child("FormationOrderPicker", true, false)); view.call("_on_arm_move"); view.call("_on_waypoint_requested", [410,590])
	var before: String = battle.digest(); _ok(not battle.set_weapon_basis_points("RC-CAO-SQ-01", first_available, 5000).ok, "enemy allocation edit rejected"); _eq(battle.digest(), before, "enemy rejection is atomic")
	view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await process_frame; await process_frame; view.find_child("SunAiThisTurn", true, false).pressed.emit(); await process_frame
	_eq(battle.weapon_allocation_state()["RC-LIU-SQ-01"].allocations, preserved, "weapon allocation applies with MOVE/formation draft")
	_eq(int(battle.weapon_allocation_state()["RC-LIU-SQ-01"].effective_turn), 1, "weapon state effective at resolution start")
	var all_text := _visible_text(view); _ok(not all_text.contains("적 무기 배분") and not all_text.contains("적 프리셋"), "enemy weapon allocation never rendered")
	if DisplayServer.get_name() != "headless":
		# Return to a direct-command view so allocation controls and the fixed CTA share the capture.
		battle.continue_turn(); view.call("_refresh"); await process_frame
		var output_dir := "res://out/demo-rc-g4-05-weapon-allocation"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)); var image := root.get_texture().get_image(); _ok(image != null and image.get_size() == Vector2i(1600,900), "1600x900 GPU capture available")
		if image != null: _ok(image.save_png(ProjectSettings.globalize_path(output_dir.path_join("weapon-allocation-1600x900.png"))) == OK, "GPU capture saved")
	view.free()

func _visible_text(node: Node) -> String:
	var parts: Array[String] = []
	if node is Label and node.visible: parts.append(node.text)
	if node is Button and node.visible: parts.append(node.text)
	for child in node.get_children(): parts.append(_visible_text(child))
	return "\n".join(parts)

func _test_source_boundary() -> void:
	for path in ["res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd","res://scripts/red_cliff_turn/red_cliff_tactical_map.gd"]:
		var source := FileAccess.get_file_as_string(path); _ok("Node3D" not in source and ".glb" not in source and "voyage_3d" not in source, "%s has zero 3D refs" % path)
