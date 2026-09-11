extends SceneTree

## DEMO-RC-G4-07 — 턴 전투 5단계 판정 원장 UI.
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
	print("DEMO-RC-G4-07 five-phase ledger UI")
	root.size = Vector2i(1600, 900)
	await _test_timeline_auto_step_digest_and_redaction()
	_test_source_boundary()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)

func _test_timeline_auto_step_digest_and_redaction() -> void:
	var loaded := Setup.load_default(); _ok(loaded.ok, "setup loads"); var setup: Dictionary = loaded.setup.duplicate(true)
	var positions := {"RC-LIU-SQ-01": [100, 100], "RC-LIU-SQ-02": [100, 800], "RC-SUN-SQ-01": [100, 700], "RC-CAO-SQ-01": [400, 100]}
	for squad in setup.squadrons:
		squad.initial_position = positions[String(squad.id)].duplicate()
		if squad.id == "RC-CAO-SQ-01": squad.initial_facing_deg = 180
	var battle = Battle.new(); _ok(battle.initialize(setup).ok, "battle initializes")
	var view := View.new(); view.configure(battle, int(setup.get("formation_revision", 0)), JSON.stringify(setup)); root.add_child(view); await process_frame; await process_frame
	_ok(view.find_child("FivePhaseLedgerPending", true, false) != null, "command phase does not fabricate ledger")
	view.call("_on_arm_move"); view.call("_on_waypoint_requested", [240, 100]); view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await process_frame; await process_frame
	view.find_child("SunAiThisTurn", true, false).pressed.emit(); await process_frame; await process_frame
	var summary: Dictionary = battle.viewer_phase_summary("liu_bei"); _ok(summary.ok, "viewer phase summary available after resolve"); _eq(summary.phases.size(), 5, "five phases exactly")
	_eq(summary.phases.map(func(row): return row.phase_name), ["접적", "포화", "교전", "강습", "결착"], "core phase names and order")
	var digest: Label = view.find_child("FivePhaseTurnDigest", true, false); _ok(digest != null and digest.text.contains(summary.turn_digest), "full core turn digest visible")
	for row in summary.phases:
		var button: Button = view.find_child("LedgerPhase_%s" % row.phase_id, true, false); _ok(button != null and button.text.contains(row.phase_name), "%s timeline button exists" % row.phase_name)
	var auto_text := _visible_text(view); _ok(auto_text.contains("pending") and auto_text.contains("LED-"), "automatic view shows actual event IDs and pending labels")
	_ok(auto_text.contains("가시 이벤트 없음"), "redacted no-visible state avoids hidden-versus-empty claim")
	var stable_digest: String = String(summary.turn_digest); view.call("_refresh"); await process_frame; _eq(battle.viewer_phase_summary("liu_bei").turn_digest, stable_digest, "refresh does not change digest")
	view.call("_on_ledger_phase", "engagement"); await process_frame
	_eq(view.get("_ledger_phase_filter"), "engagement", "step view selects core phase ID")
	var detail_count := 0
	for child in view.find_child("CurrentFactionOrders", true, false).get_children():
		if child is Label and child.text.begins_with("3. 교전"): detail_count += 1
	_eq(detail_count, 1, "step view renders selected phase detail once")
	var viewer_ledger: Dictionary = battle.viewer_phase_ledger("liu_bei"); var encoded := JSON.stringify(viewer_ledger)
	_ok(bool(viewer_ledger.get("viewer_redacted", false)), "viewer ledger explicitly redacted")
	_ok(not encoded.contains("cao_ai_decision") and not encoded.contains("sun_ai_decision") and not encoded.contains("reserve_basis_points"), "viewer ledger omits foreign AI plan and resource reserve")
	_ok(not encoded.contains("winner") and not encoded.contains("hit_result") and not encoded.contains("damage_result"), "no unfinished result fabricated")
	if DisplayServer.get_name() != "headless":
		view.call("_on_ledger_phase", ""); await process_frame
		var scroll: ScrollContainer = view.find_child("MovementOrderScroll", true, false); var ledger_title: Label = view.find_child("FivePhaseLedgerTitle", true, false); scroll.scroll_vertical = maxi(0, int(ledger_title.position.y) - 8); await process_frame
		var output_dir := "res://out/demo-rc-g4-07-five-phase-ledger"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)); var image := root.get_texture().get_image(); _ok(image != null and image.get_size() == Vector2i(1600, 900), "1600x900 GPU capture available")
		if image != null: _ok(image.save_png(ProjectSettings.globalize_path(output_dir.path_join("five-phase-ledger-1600x900.png"))) == OK, "GPU capture saved")
	view.free()

func _visible_text(node: Node) -> String:
	var parts: Array[String] = []
	if node is Label and node.visible: parts.append(node.text)
	if node is Button and node.visible: parts.append(node.text)
	for child in node.get_children(): parts.append(_visible_text(child))
	return "\n".join(parts)

func _test_source_boundary() -> void:
	for path in ["res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd", "res://scripts/red_cliff_turn/red_cliff_tactical_map.gd"]:
		var source := FileAccess.get_file_as_string(path); _ok("Node3D" not in source and ".glb" not in source and "voyage_3d" not in source, "%s has zero 3D refs" % path)
