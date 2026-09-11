extends SceneTree

## DEMO-RC-G5-01 — 전쟁 안개·마지막 확인·추정 사격 UI.
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
	print("DEMO-RC-G5-01 fog and estimated fire UI")
	root.size = Vector2i(1600, 900)
	await _test_unknown_estimated_select_cancel_submit_and_ledger()
	await _test_confirmed_rediscovery_label()
	_test_source_boundary()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)

func _setup(cao_position: Array) -> Dictionary:
	var loaded := Setup.load_default(); _ok(loaded.ok, "setup loads"); var setup: Dictionary = loaded.setup.duplicate(true)
	var positions := {"RC-LIU-SQ-01": [100, 100], "RC-LIU-SQ-02": [100, 800], "RC-LIU-FC-01": [1600, 900], "RC-SUN-SQ-01": [100, 700], "RC-CAO-SQ-01": cao_position}
	for squad in setup.squadrons:
		squad.initial_position = positions[String(squad.id)].duplicate()
		if squad.id == "RC-CAO-SQ-01": squad.initial_facing_deg = 180
	return setup

func _test_unknown_estimated_select_cancel_submit_and_ledger() -> void:
	var setup := _setup([350, 100]); var battle = Battle.new(); _ok(battle.initialize(setup).ok, "estimated fixture initializes")
	var view := View.new(); view.configure(battle, 0, JSON.stringify(setup)); root.add_child(view); await process_frame; await process_frame
	_eq(battle.visible_contacts("liu_bei").contacts.size(), 0, "unknown enemy completely omitted")
	_ok(not JSON.stringify(view.find_child("AppliedSquadronMap", true, false).intelligence_state_for_test()).contains("RC-CAO-SQ-01"), "unknown map leaks no enemy ID")
	view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await process_frame; await process_frame; view.find_child("SunAiThisTurn", true, false).pressed.emit(); await process_frame; await process_frame
	view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await process_frame; await process_frame
	var contacts: Array = battle.visible_contacts("liu_bei").contacts; _eq(contacts.size(), 1, "estimated contact becomes visible")
	var contact: Dictionary = contacts[0]; _eq(contact.state, "estimated", "contact state is core estimated"); _ok(not contact.has("target_squadron_id") and contact.get("display_position") == contact.get("last_known_position"), "estimated contact exposes only last-known display position")
	var text := _visible_text(view); _ok(text.contains("마지막 확인") and text.contains("경과 %d턴" % int(contact.staleness_turns)) and text.contains("신뢰 %d bp" % int(contact.confidence_basis_points)) and text.contains("오차 반경 %d" % int(contact.error_radius)) and text.contains("T%d 뒤 만료" % int(contact.expires_after_turn)), "last-known lifecycle fields displayed from viewer contact")
	var map = view.find_child("AppliedSquadronMap", true, false); map.handle_click_for_test(map.battle_to_local(contact.last_known_position)); await process_frame
	_eq(view.get("_selected_contact_id"), contact.contact_id, "estimated map marker selects opaque contact")
	_ok(view.find_child("SelectedEstimatedContact", true, false) != null, "selected uncertainty summary visible")
	view.find_child("SetEstimatedFire", true, false).pressed.emit(); await process_frame
	var order: Dictionary = battle.estimated_fire_order("RC-LIU-SQ-01").order; _ok(not order.is_empty(), "estimated fire draft staged through core")
	var order_text: Label = view.find_child("EstimatedFireDraft", true, false); _ok(order_text.text.contains("코어 조준") and order_text.text.contains("오차") and order_text.text.contains("명중/피해 pending"), "sealed aim and pending result are explicit")
	_ok(not order.has("target_squadron_id") and not order.has("actual_target_position"), "draft contains no enemy identity or actual position")
	view.find_child("ClearEstimatedFire", true, false).pressed.emit(); await process_frame; _ok(battle.estimated_fire_order("RC-LIU-SQ-01").order.is_empty(), "cancel clears only estimated fire draft")
	view.find_child("SetEstimatedFire", true, false).pressed.emit(); await process_frame; _eq(int(battle.command_draft_summary().estimated_fire_count), 1, "draft summary count comes from core")
	view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await process_frame; await process_frame; view.find_child("SunAiThisTurn", true, false).pressed.emit(); await process_frame; await process_frame
	var barrage: Dictionary = battle.viewer_phase("liu_bei", "barrage"); var barrage_text := JSON.stringify(barrage)
	_ok(barrage_text.contains("estimated_fire_authorized") or barrage_text.contains("estimated_fire_suppressed"), "estimated fire appears in viewer barrage ledger")
	_ok(barrage.phase.pending.has("hit") and barrage.phase.pending.has("damage") and not barrage_text.contains("hit_result") and not barrage_text.contains("damage_result"), "ledger keeps estimated fire result pending")
	if DisplayServer.get_name() != "headless":
		view.call("_on_ledger_phase", "barrage"); await process_frame
		var scroll: ScrollContainer = view.find_child("MovementOrderScroll", true, false); var ledger_title: Label = view.find_child("FivePhaseLedgerTitle", true, false); scroll.scroll_vertical = maxi(0, int(ledger_title.position.y) - 8); await process_frame
		var output_dir := "res://out/demo-rc-g5-01-fog-estimated-fire"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)); var image := root.get_texture().get_image(); _ok(image != null and image.get_size() == Vector2i(1600, 900), "1600x900 GPU capture available")
		if image != null: _ok(image.save_png(ProjectSettings.globalize_path(output_dir.path_join("fog-estimated-fire-1600x900.png"))) == OK, "GPU capture saved")
	view.free()

func _test_confirmed_rediscovery_label() -> void:
	var setup := _setup([200, 100]); var battle = Battle.new(); _ok(battle.initialize(setup).ok, "confirmed fixture initializes")
	var view := View.new(); view.configure(battle, 0, JSON.stringify(setup)); root.add_child(view); await process_frame; battle.submit_command_draft(); battle.submit_sun_control_choice("ai"); battle.resolve_turn(); view.call("_refresh"); await process_frame
	var contacts: Array = battle.visible_contacts("liu_bei").contacts; _ok(not contacts.is_empty() and contacts[0].state == "confirmed", "core reports confirmed contact")
	_ok(_visible_text(view).contains("현재 위치 재확인"), "confirmed rediscovery is distinct from estimate")
	_ok(view.get("_selected_contact_id") == "", "confirmed contact cannot remain selected for estimated fire")
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
