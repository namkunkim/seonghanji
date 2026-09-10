extends SceneTree

## DEMO-RC-G4-03 — 경로 교차 요격·탐지 기반 기회 사격 UI.
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
	print("DEMO-RC-G4-03 interception/detection UI")
	root.size = Vector2i(1600,900)
	await _test_redacted_map_contract()
	await _test_real_viewer_feed_and_fire()
	_test_source_boundary()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)

func _test_redacted_map_contract() -> void:
	var loaded := Setup.load_default(); var setup: Dictionary = loaded.setup; var own: Array = []; var own_nav := {}
	for squad in setup.squadrons:
		if squad.faction_id == "liu_bei": own.append(squad); own_nav[String(squad.id)] = {"position": squad.initial_position, "facing_deg": 0}
	var map := TacticalMap.new(); map.size = Vector2(800,450); root.add_child(map); await process_frame
	map.configure(setup.battlefield_bounds, own, own_nav)
	var contacts := [
		{"contact_id":"OPAQUE-A", "state":"estimated", "display_position":[700,400], "last_known_position":[700,400], "last_seen_turn":2, "stale":false},
		{"contact_id":"OPAQUE-B", "state":"undetected", "display_position":null, "last_known_position":[900,300], "last_seen_turn":1, "stale":true},
		{"contact_id":"OPAQUE-C", "target_squadron_id":"RC-CAO-SQ-01", "state":"confirmed", "display_position":[800,350], "last_known_position":[800,350], "last_seen_turn":3, "stale":false},
	]
	var events := [{"event_id":"VISIBLE-FIRE", "event_type":"shot_authorized", "own_squadron_id":"RC-LIU-SQ-01", "contact_id":"OPAQUE-A", "own_role":"target", "range":260, "distance":200.0, "bearing_deg":180.0, "facing_deg":180.0, "arc_deg":90.0, "damage_pending":true}]
	map.set_intelligence("liu_bei", contacts, events)
	var state: Dictionary = map.intelligence_state_for_test()
	_eq(state.own_squadron_ids, ["RC-LIU-SQ-01","RC-LIU-SQ-02"], "map receives own squadrons only")
	_ok(not JSON.stringify(state).contains("조조 중군") and not JSON.stringify(state).contains("composition"), "nested enemy setup never reaches map")
	_ok(not state.contacts[0].has("target_squadron_id"), "estimated contact remains opaque")
	_eq(state.tactical_events[0].get("outcome", ""), "", "redacted fire feed does not invent outcome fields")
	map.queue_redraw(); await process_frame; map.free()

func _test_real_viewer_feed_and_fire() -> void:
	var loaded := Setup.load_default(); _ok(loaded.ok, "setup loads"); var setup: Dictionary = loaded.setup.duplicate(true)
	for squad in setup.squadrons:
		if squad.id == "RC-LIU-SQ-01": squad.initial_position = [100,100]
		elif squad.id == "RC-LIU-SQ-02": squad.initial_position = [100,800]
		elif squad.id == "RC-SUN-SQ-01": squad.initial_position = [100,700]
		elif squad.id == "RC-CAO-SQ-01": squad.initial_position = [500,100]; squad.initial_facing_deg = 180
	var battle = Battle.new(); _ok(battle.initialize(setup).ok, "battle initializes interception fixture")
	_eq(battle.visible_contacts("liu_bei").contacts.size(), 0, "fresh unknown enemy omitted")
	_ok(battle.set_order_move("RC-LIU-SQ-01", [[240,100]], 0).ok, "Liu target movement stages")
	_ok(battle.submit_command_draft().ok, "Liu draft submits"); _ok(battle.submit_sun_control_choice("ai").ok, "Sun AI submits")
	var receipt: Dictionary = battle.resolve_turn(); _ok(receipt.ok, "turn resolves interception")
	var contacts: Array = battle.visible_contacts("liu_bei").contacts; var events: Array = battle.visible_tactical_events("liu_bei").events
	_ok(not contacts.is_empty() and contacts[0].state == "estimated", "viewer receives estimated contact")
	_ok(not contacts[0].has("target_squadron_id") and not JSON.stringify(contacts).contains("RC-CAO-SQ-01"), "estimated contact hides raw enemy id")
	var fire_count := 0
	for event in events: fire_count += 1 if event.event_type == "shot_authorized" else 0
	_eq(fire_count, 0, "estimated-only contact cannot authorize opportunity fire")
	var view := View.new(); view.configure(battle, int(setup.get("formation_revision",0)), JSON.stringify(setup)); root.add_child(view); await process_frame; await process_frame
	var all_text := _visible_text(view)
	_ok(all_text.contains("추정 접촉") and all_text.contains("실제 위치와 다를 수 있음"), "estimated/stale uncertainty copy visible")
	_ok(not all_text.contains("사격 1 · 승인"), "estimated-only contact does not fabricate fire feedback")
	_ok(not all_text.contains("RC-CAO-SQ-01") and not all_text.contains("조조 중군 전대"), "unknown/estimated enemy identity absent from UI")
	_ok(not all_text.contains("격침") and not all_text.contains("승자"), "no fabricated damage or winner")
	var map = view.find_child("AppliedSquadronMap", true, false); var intel: Dictionary = map.intelligence_state_for_test()
	_eq(intel.own_squadron_ids, ["RC-LIU-SQ-01","RC-LIU-SQ-02"], "view map consumes viewer own navigation only")
	if DisplayServer.get_name() != "headless":
		var output_dir := "res://out/demo-rc-g4-03-interception-detection"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)); await process_frame
		var image := root.get_texture().get_image(); _ok(image != null and image.get_size() == Vector2i(1600,900), "1600x900 GPU capture available")
		if image != null: _ok(image.save_png(ProjectSettings.globalize_path(output_dir.path_join("interception-detection-1600x900.png"))) == OK, "GPU capture saved")
	view.free()

func _visible_text(node: Node) -> String:
	var parts: Array[String] = []
	if node is Label and node.visible: parts.append(node.text)
	if node is Button and node.visible: parts.append(node.text)
	if node is RichTextLabel and node.visible: parts.append(node.text)
	for child in node.get_children(): parts.append(_visible_text(child))
	return "\n".join(parts)

func _test_source_boundary() -> void:
	for path in ["res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd", "res://scripts/red_cliff_turn/red_cliff_tactical_map.gd"]:
		var source := FileAccess.get_file_as_string(path); _ok("Node3D" not in source and ".glb" not in source and "voyage_3d" not in source, "%s has zero 3D refs" % path)
