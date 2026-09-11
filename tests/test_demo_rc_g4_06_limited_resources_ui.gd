extends SceneTree

## DEMO-RC-G4-06 — 제한 전투 자원과 결정론적 소모 UI.
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")
const View := preload("res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd")

var _pass := 0
var _fail := 0

class ResourceEventBattle:
	extends RefCounted
	func visible_contacts(_viewer: String) -> Dictionary: return {"contacts": []}
	func visible_tactical_events(_viewer: String) -> Dictionary:
		var events: Array = []
		for row in [["ammo", "탄약 부족"], ["energy", "에너지 부족"], ["overheat", "과열 한계"], ["carrier_not_returned", "함재기 미복귀"], ["special", "특수 자원 부족"]]:
			events.append({"event_type": "fire_suppressed", "weapon_id": "line_fire", "reason": row[0], "reason_label": row[1]})
		return {"events": events}
	func weapon_categories() -> Array: return [{"weapon_id": "line_fire", "name": "전열 사격"}]

func _ok(value: bool, label: String) -> void:
	if value: _pass += 1
	else: _fail += 1; print("  x %s" % label)

func _eq(actual, expected, label: String) -> void: _ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])
func _init() -> void: call_deferred("_run")

func _run() -> void:
	print("DEMO-RC-G4-06 limited resources UI")
	root.size = Vector2i(1600, 900)
	await _test_own_state_consumption_recovery_and_redaction()
	_test_suppression_reason_labels()
	_test_source_boundary()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)

func _test_own_state_consumption_recovery_and_redaction() -> void:
	var loaded := Setup.load_default(); _ok(loaded.ok, "setup loads"); var setup: Dictionary = loaded.setup.duplicate(true)
	var positions := {"RC-LIU-SQ-01": [100, 100], "RC-LIU-SQ-02": [100, 800], "RC-LIU-FC-01": [1600, 900], "RC-SUN-SQ-01": [100, 700], "RC-CAO-SQ-01": [400, 100]}
	for squad in setup.squadrons:
		squad.initial_position = positions[String(squad.id)].duplicate()
		if squad.id == "RC-CAO-SQ-01": squad.initial_facing_deg = 180
	var battle = Battle.new(); _ok(battle.initialize(setup).ok, "battle initializes")
	var view := View.new(); view.configure(battle, int(setup.get("formation_revision", 0)), JSON.stringify(setup)); root.add_child(view); await process_frame; await process_frame
	var viewer: Dictionary = battle.viewer_snapshot("liu_bei"); var liu: Dictionary = viewer.own_combat_resources["RC-LIU-SQ-01"]
	var shared: Label = view.find_child("CombatResourceShared", true, false); _ok(shared != null, "own shared resource panel exists")
	_ok(shared.text.contains("에너지 %d/%d" % [liu.shared.energy, liu.shared.energy_capacity]) and shared.text.contains("열 %d/%d" % [liu.shared.heat, liu.shared.heat_capacity]), "energy and heat match viewer snapshot")
	for category in viewer.weapon_categories:
		var row: Label = view.find_child("CombatResource_%s" % category.weapon_id, true, false); _ok(row != null, "%s resource row exists" % category.weapon_id)
		var weapon: Dictionary = liu.weapons[category.weapon_id]
		_ok(row.text.contains("탄약 %d/%d" % [weapon.ammo, weapon.ammo_capacity]) and row.text.contains("함재기 %d/%d" % [weapon.carrier_ready, weapon.carrier_capacity]) and row.text.contains("특수 %d/%d" % [weapon.special, weapon.special_capacity]), "%s values come from viewer snapshot" % category.weapon_id)
	_ok(not battle.visible_combat_resources("liu_bei").resource_state.has("RC-CAO-SQ-01"), "viewer API omits enemy resource state")
	_ok(not _visible_text(view).contains("RC-CAO-SQ-01") and not _visible_text(view).contains("적 자원"), "enemy resources are not rendered")
	view.call("_on_arm_move"); view.call("_on_waypoint_requested", [240, 100]); view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await process_frame; await process_frame
	view.find_child("SunAiThisTurn", true, false).pressed.emit(); await process_frame; await process_frame
	var liu_events: Array = battle.visible_tactical_events("liu_bei").events
	_ok(liu_events.filter(func(event): return String(event.get("event_type", "")) == "resource_consumed").all(func(event): return String(event.get("squadron_id", "")).begins_with("RC-LIU-")), "target viewer sees no enemy consumption")
	view.set("_viewer_faction_id", "cao_cao"); view.call("_refresh"); await process_frame
	_ok(_visible_text(view).contains("자원 소모") and _visible_text(view).contains("전→후"), "shooter viewer sees core consumption receipt")
	var cao_events: Dictionary = battle.visible_tactical_events("cao_cao"); var consumed := false
	for event in cao_events.events: consumed = consumed or String(event.get("event_type", "")) == "resource_consumed"
	_ok(consumed, "visible event authority contains own consumption")
	view.set("_viewer_faction_id", "liu_bei"); view.call("_on_primary"); await process_frame; await process_frame
	_ok(view.find_child("CombatResourceRecovery", true, false) == null, "turn 2 command phase does not recover early")
	_ok(battle.submit_command_draft().ok and battle.submit_sun_control_choice("ai").ok, "turn 2 orders reach resolution")
	_ok(battle.resolve_turn().ok, "turn 2 resolution applies recovery"); view.call("_refresh"); await process_frame
	_ok(_visible_text(view).contains("턴 2 판정 시작 회복"), "resolution-start recovery receipt is visible")
	_ok(not battle.viewer_snapshot("liu_bei").own_combat_resources.has("RC-CAO-SQ-01"), "viewer snapshot remains own-only after recovery")
	if DisplayServer.get_name() != "headless":
		var scroll: ScrollContainer = view.find_child("MovementOrderScroll", true, false); scroll.scroll_vertical = 440; await process_frame
		var output_dir := "res://out/demo-rc-g4-06-limited-resources"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)); var image := root.get_texture().get_image(); _ok(image != null and image.get_size() == Vector2i(1600, 900), "1600x900 GPU capture available")
		if image != null: _ok(image.save_png(ProjectSettings.globalize_path(output_dir.path_join("limited-resources-1600x900.png"))) == OK, "GPU capture saved")
	view.free()

func _test_suppression_reason_labels() -> void:
	var view := View.new(); var orders := VBoxContainer.new(); view.set("_battle", ResourceEventBattle.new()); view.set("_orders", orders); view.set("_viewer_faction_id", "liu_bei")
	view.call("_add_intelligence_panel"); var text := _visible_text(orders)
	for label in ["탄약 부족", "에너지 부족", "과열 한계", "함재기 미복귀", "특수 자원 부족"]: _ok(text.contains(label), "%s core suppression label visible" % label)
	view.free(); orders.free()

func _visible_text(node: Node) -> String:
	var parts: Array[String] = []
	if node is Label and node.visible: parts.append(node.text)
	if node is Button and node.visible: parts.append(node.text)
	for child in node.get_children(): parts.append(_visible_text(child))
	return "\n".join(parts)

func _test_source_boundary() -> void:
	for path in ["res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd", "res://scripts/red_cliff_turn/red_cliff_tactical_map.gd"]:
		var source := FileAccess.get_file_as_string(path); _ok("Node3D" not in source and ".glb" not in source and "voyage_3d" not in source, "%s has zero 3D refs" % path)
