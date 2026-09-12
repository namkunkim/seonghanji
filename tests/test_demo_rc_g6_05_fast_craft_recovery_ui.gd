extends SceneTree

## DEMO-RC-G6-05 — 표류·구조·나포와 나포 보급함 무력화 UI.
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Mission := preload("res://core/demo_red_cliffs/red_cliffs_fast_craft_mission.gd")
const Recovery := preload("res://core/demo_red_cliffs/red_cliffs_fast_craft_recovery.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")
const BattleView := preload("res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd")
const TacticalMap := preload("res://scripts/red_cliff_turn/red_cliff_tactical_map.gd")

var _pass := 0
var _fail := 0

func _ok(value: bool, label: String) -> void:
	if value: _pass += 1
	else: _fail += 1; print("  x %s" % label)

func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])

func _near(actual: float, expected: float, label: String) -> void:
	_ok(absf(actual - expected) < 0.0001, "%s (%s != %s)" % [label, actual, expected])

func _init() -> void: call_deferred("_run")

func _run() -> void:
	print("DEMO-RC-G6-05 — 표류·구조·나포와 나포 보급함 무력화")
	root.size = Vector2i(1600, 900)
	await _test_low_fuel_preview_matches_resolve()
	await _test_drift_lock_and_authoritative_supply_capture()
	await _test_hidden_viewer_boundary()
	_test_authoritative_rescue_route()
	_test_source_boundary()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail else Harness.EXIT_PASS)

func _battle():
	var loaded := Setup.load_default(); _ok(loaded.ok, "default setup loads")
	var battle = Battle.new(); _ok(battle.initialize(loaded.setup).ok, "battle initializes"); return battle

func _drifting_battle():
	var battle = _battle()
	battle._state.live_navigation["RC-LIU-FC-01"].position = [700, 700]
	battle._state.fast_craft_supply_state.resources["RC-LIU-FC-01"].fuel_basis_points = 405
	battle._state.fast_craft_supply_state.queue.erase("RC-LIU-FC-01")
	_ok(battle.set_order_move("RC-LIU-FC-01", [[1000, 700]], 0).ok, "remaining-fuel movement stages")
	_ok(battle.submit_command_draft().ok and battle.submit_sun_control_choice("ai").ok, "fixture reaches resolution")
	var resolved: Dictionary = battle.resolve_turn(); _ok(resolved.ok and resolved.fast_craft_recovery_events.any(func(row): return String(row.status) == "drifting"), "core creates authoritative drift event")
	_ok(battle.continue_turn().ok, "drift command-lock turn begins")
	return battle

func _view(battle):
	var view := BattleView.new(); _ok(view.configure(battle, 1, "g6-05-ui").ok, "battle view configures"); root.add_child(view); return view

func _test_low_fuel_preview_matches_resolve() -> void:
	var battle = _battle(); battle._state.live_navigation["RC-LIU-FC-01"].position = [700, 700]; battle._state.fast_craft_supply_state.resources["RC-LIU-FC-01"].fuel_basis_points = 405; battle._state.fast_craft_supply_state.queue.erase("RC-LIU-FC-01")
	_ok(battle.set_order_move("RC-LIU-FC-01", [[1000, 700]], 0).ok, "low-fuel long movement stages")
	var preview: Dictionary = battle.movement_preview("RC-LIU-FC-01", [[1000, 700]], 0)
	_ok(preview.ok and preview.fuel_limited, "preview exposes authoritative fuel clamp")
	_eq(preview.available_fuel_basis_points, 405, "preview exposes exact available fuel")
	_near(float(preview.maximum_fuel_distance), 40.5, "preview exposes maximum fuel distance")
	_near(float(preview.predicted_actual_distance), 40.5, "preview exposes clamped actual distance")
	_eq(preview.predicted_position, [740.5, 700.0], "preview exposes clamped stop point")
	_ok(not preview.path_complete and int(preview.eta_turns) == -1, "fuel-limited path is incomplete without fabricated ETA")
	var view = _view(battle); await _settle(); var select: Button = view.find_child("Select_RC-LIU-FC-01", true, false); _ok(select != null, "low-fuel craft is selectable before drift"); select.pressed.emit(); await _settle()
	var label: Label = view.find_child("MovementPreview", true, false)
	_ok(label != null and label.text.contains("연료 제한") and label.text.contains("요청 거리 300.0") and label.text.contains("예상 실제 40.5") and label.text.contains("가용 연료 405 bp"), "UI renders core fuel-limit metrics")
	_ok(label.text.contains("예상 정지 (740.5, 700.0)") and label.text.contains("실제 판정과 동일"), "UI makes predicted stop and resolve parity explicit")
	if DisplayServer.get_name() != "headless":
		var scroll: ScrollContainer = view.find_child("MovementOrderScroll", true, false)
		if scroll != null and label != null: scroll.ensure_control_visible(label)
		await process_frame; await process_frame
		var output_dir := "res://out/demo-rc-g6-05-fast-craft-recovery"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)); var image := root.get_texture().get_image()
		_ok(image != null and image.get_size() == Vector2i(1600, 900), "1600x900 fuel-preview GPU image")
		if image != null: _ok(image.save_png(ProjectSettings.globalize_path(output_dir.path_join("fast-craft-fuel-preview-1600x900.png"))) == OK, "fuel-preview GPU capture saved")
	_ok(battle.submit_command_draft().ok and battle.submit_sun_control_choice("ai").ok, "preview fixture reaches resolution")
	var resolved: Dictionary = battle.resolve_turn(); _ok(resolved.ok, "preview fixture resolves")
	var movement: Dictionary = resolved.movement_events.filter(func(row): return String(row.squadron_id) == "RC-LIU-FC-01")[0]
	_near(float(movement.actual_distance), float(preview.predicted_actual_distance), "resolved distance matches UI preview")
	_eq(movement.to, preview.predicted_position, "resolved endpoint matches UI preview")
	view.free()

func _test_drift_lock_and_authoritative_supply_capture() -> void:
	var battle = _drifting_battle(); var before_sources: Array = battle.viewer_fast_craft_supply("liu_bei").sources
	var source: Dictionary = before_sources.filter(func(row): return String(row.get("source_type", "")) == "supply_ship")[0]
	var denied: Dictionary = battle._apply_authoritative_supply_capture({"source_id": source.source_id}); _ok(not denied.ok, "normal proximity cannot disable a healthy supply ship")
	var applied: Dictionary = battle._apply_authoritative_supply_capture({"authority":"G8-00", "status":"authorized_capture", "effective_turn":battle.turn(), "source_id":source.source_id, "responder_squadron_id":"RC-CAO-SQ-01", "responder_faction_id":"cao_cao"})
	_ok(applied.ok, "authoritative capture intent disables exact supply source")
	var view = _view(battle); await _settle()
	var select: Button = view.find_child("Select_RC-LIU-FC-01", true, false); _ok(select != null and select.text.contains("잠금"), "locked fast craft remains selectable for status viewing"); select.pressed.emit(); await _settle()
	_ok(view._selectable_squadron_ids(battle.snapshot()).has("RC-LIU-FC-01") and not view._editable_squadron_ids(battle.snapshot()).has("RC-LIU-FC-01"), "selection and edit capability are separated")
	var title: Label = view.find_child("FastCraftRecoveryTitle", true, false); _ok(title != null and title.text.contains("자동 판정") and title.text.contains("읽기 전용"), "incident card is explicitly automatic and read-only")
	var state: Label = view.find_child("FastCraftRecoveryState", true, false); _ok(state != null and state.text.contains("연료 0 · 표류") and state.text.contains("명령 잠금") and state.text.contains("이동 잠금") and state.text.contains("공격 잠금") and state.text.contains("임무 변경 잠금"), "own drift status renders all core command capabilities")
	var hold: Button = view.find_child("SetOrderHold", true, false); var move: Button = view.find_child("ArmOrderMove", true, false)
	_ok(hold.disabled and move.disabled, "movement controls are visibly locked")
	var mission: Button = view.find_child("FastTacticalMission_liaison", true, false); _ok(mission != null and mission.disabled, "mission control is visibly locked")
	var formation: OptionButton = view.find_child("FormationOrderPicker", true, false); _ok(formation != null and formation.disabled, "formation command is visibly locked")
	var map = view.find_child("AppliedSquadronMap", true, false); var recovery: Dictionary = map.fast_craft_recovery_for_test()
	_ok(recovery.statuses.any(func(row): return String(row.squadron_id) == "RC-LIU-FC-01" and String(row.status) == "drifting"), "2D map receives authoritative drift status")
	_ok(recovery.disabled_supply_sources.any(func(row): return String(row.source_id) == String(source.source_id) and int(row.capacity_squadrons_per_turn) == 0), "2D map receives captured-source disable receipt")
	_ok(not map.fast_craft_supply_sources_for_test().any(func(row): return String(row.source_id) == String(source.source_id)), "disabled supply source disappears from active zones")
	var disabled: Label = view.find_child("CapturedSupplyDisabled_%s" % String(source.source_id), true, false)
	_ok(disabled != null and disabled.text.contains("처리량 0/턴") and disabled.text.contains("captor gain 0") and disabled.text.contains("같은 턴 보급 제외"), "captured supply source is read-only and grants nothing")
	var boundary: Label = view.find_child("FastCraftRecoveryBoundary", true, false)
	_ok(boundary != null and boundary.text.contains("수동 구조·나포 버튼 없음") and boundary.text.contains("G8-00") and boundary.text.contains("G6-06"), "manual-action and future-scope boundaries are explicit")
	var forbidden_buttons := view.find_children("*", "Button", true, false).filter(func(node): return String(node.text).contains("구조") or String(node.text).contains("나포"))
	_eq(forbidden_buttons.size(), 0, "no manual rescue or capture button exists")
	if DisplayServer.get_name() != "headless":
		var scroll: ScrollContainer = view.find_child("MovementOrderScroll", true, false)
		if scroll != null and disabled != null: scroll.ensure_control_visible(disabled)
		await process_frame; await process_frame
		var output_dir := "res://out/demo-rc-g6-05-fast-craft-recovery"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
		var image := root.get_texture().get_image(); _ok(image != null and image.get_size() == Vector2i(1600, 900), "1600x900 GPU image")
		if image != null: _ok(image.save_png(ProjectSettings.globalize_path(output_dir.path_join("fast-craft-recovery-1600x900.png"))) == OK, "GPU capture saved")
	view.free()

func _test_hidden_viewer_boundary() -> void:
	var battle = _drifting_battle(); var own: Dictionary = battle.viewer_fast_craft_recovery("liu_bei"); var hidden: Dictionary = battle.viewer_fast_craft_recovery("cao_cao")
	_ok(own.statuses.any(func(row): return String(row.squadron_id) == "RC-LIU-FC-01"), "own viewer receives exact recovery status")
	_ok(hidden.statuses.all(func(row): return String(row.get("viewer_state", "")) in ["confirmed", "estimated"] and not row.has("fuel_basis_points")), "observed enemy rows expose no private fuel or own-state payload")
	_ok(hidden.statuses.filter(func(row): return String(row.get("viewer_state", "")) == "estimated").all(func(row): return String(row.get("squadron_id", "")).is_empty() and row.has("uncertainty")), "estimated rows redact identity and retain uncertainty")
	var confirmed: Dictionary = battle._fast_craft_recovery.visible("cao_cao", battle._state.fast_craft_recovery_state, battle._state.fast_craft_supply_state, [{"target_squadron_id":"RC-LIU-FC-01", "contact_id":"RC-CONFIRMED", "state":"confirmed", "display_position":[700,700], "error_radius":0, "confidence_basis_points":10000, "staleness_turns":0}])
	var estimated: Dictionary = battle._fast_craft_recovery.visible("cao_cao", battle._state.fast_craft_recovery_state, battle._state.fast_craft_supply_state, [{"target_squadron_id":"RC-LIU-FC-01", "contact_id":"RC-ESTIMATED", "state":"estimated", "display_position":[680,690], "error_radius":90, "confidence_basis_points":6200, "staleness_turns":1}])
	_ok(confirmed.statuses.size() == 1 and confirmed.statuses[0].viewer_state == "confirmed" and confirmed.statuses[0].squadron_id == "RC-LIU-FC-01", "confirmed observation exposes exact identity allowed by core")
	_ok(estimated.statuses.size() == 1 and estimated.statuses[0].viewer_state == "estimated" and String(estimated.statuses[0].squadron_id).is_empty(), "estimated observation keeps identity redacted")
	_eq(int(estimated.statuses[0].uncertainty.error_radius), 90, "estimated observation preserves core uncertainty")
	_ok(battle.submit_command_draft().ok and battle.submit_sun_control_choice("ai").ok, "privacy fixture leaves direct-command phase")
	var view = _view(battle); await _settle(); view._viewer_faction_id = "cao_cao"; view._refresh(); await _settle()
	var map = view.find_child("AppliedSquadronMap", true, false); var map_receipt: Dictionary = map.fast_craft_recovery_for_test()
	_ok(map_receipt.get("statuses", []).all(func(row): return String(row.get("viewer_state", "")) in ["confirmed", "estimated"]), "enemy map receives observed classifications only")
	_ok(view.find_child("FastCraftRecoveryTitle_RC-LIU-FC-01", true, false) == null, "hidden panel receives no hostile incident card")
	var hidden_receipt: Dictionary = battle._fast_craft_recovery.visible("cao_cao", battle._state.fast_craft_recovery_state, battle._state.fast_craft_supply_state, [])
	map.set_fast_craft_recovery(hidden_receipt); _eq(map.fast_craft_recovery_for_test().statuses.size(), 0, "truly hidden row produces no map marker")
	map.set_fast_craft_recovery(confirmed); _eq(map.fast_craft_recovery_for_test().statuses[0].viewer_state, "confirmed", "map consumes confirmed classification")
	map.set_fast_craft_recovery(estimated); _eq(map.fast_craft_recovery_for_test().statuses[0].viewer_state, "estimated", "map consumes estimated classification")
	view.free()

func _test_authoritative_rescue_route() -> void:
	var loaded := Setup.load_default(); var setup: Dictionary = loaded.setup.duplicate(true)
	setup.squadrons.append({"id":"RC-LIU-FC-RESCUE", "faction_id":"liu_bei", "name":"구조 고속정대", "commander":{"id":"CHR-0107", "name":"관우"}, "flagship":false, "operational":true, "initial_position":[660,300], "formation_id":"FRM-07", "deployment":{"kind":"independent"}, "fast_craft_basing":{"source_type":"base_deployed", "source_id":"RC-BASE-LIU-01"}, "composition":[{"ship_type_id":"SHP-08", "count":1, "mission_equipment_id":"FAST-EQ-RESCUE"}], "declared_total_cost":3})
	var recovery = Recovery.new(); var mission = Mission.new(); _ok(recovery.initialize(setup).ok and mission.initialize(setup).ok, "rescue-route core fixture initializes")
	var state: Dictionary = recovery.initial_state(); state.squadrons["RC-LIU-FC-01"].status = "drifting"; state.squadrons["RC-LIU-FC-01"].drift_started_turn = 1; state.squadrons["RC-LIU-FC-01"].drift_vector = [1.0, 0.0]
	var nav := {}; var movements: Array = []
	for squad in setup.squadrons:
		var sid := String(squad.id); nav[sid] = {"position":[700,300] if sid == "RC-LIU-FC-01" else squad.initial_position.duplicate(), "facing_deg":0.0}; movements.append({"squadron_id":sid, "from":nav[sid].position.duplicate(), "to":nav[sid].position.duplicate(), "actual_distance":0.0, "terrain_segments":[]})
	var resolved: Dictionary = recovery.resolve_contacts(state, mission.initial_state(), nav, movements, 2); _ok(resolved.ok and resolved.events[0].status == "rescued", "rescue equipment and active rescue mission produce authoritative event")
	var route: Array = resolved.events[0].responder_route; _ok(route.size() == 2, "core event supplies responder route")
	var map = TacticalMap.new(); map.configure(setup.battlefield_bounds, setup.squadrons, nav); map.set_fast_craft_recovery({"ok":true, "statuses":[], "events":resolved.events, "disabled_supply_sources":[]})
	_eq(map.fast_craft_recovery_for_test().events[0].responder_route, route, "map preserves authoritative rescue route without calculation")
	var formatter = BattleView.new(); _ok(formatter._fast_recovery_event_text(resolved.events[0]).contains("구조 완료"), "read-only event formatter labels rescue outcome"); formatter.free(); map.free()

func _test_source_boundary() -> void:
	var map_source := FileAccess.get_file_as_string("res://scripts/red_cliff_turn/red_cliff_tactical_map.gd")
	var view_source := FileAccess.get_file_as_string("res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd")
	_ok("Node3D" not in map_source and ".glb" not in map_source and "Node3D" not in view_source, "recovery presentation remains 2D only")
	_ok("viewer_fast_craft_recovery" in view_source and "command_locked" in view_source and "disabled_supply_sources" in view_source, "UI consumes public viewer capabilities and disable receipt")
	_ok("passive_drift_distance" not in view_source and "contact_radius" not in view_source and "_first_contact_progress" not in view_source, "UI duplicates no drift, rescue, or capture formula")
	_ok("apply_authoritative_supply_capture" not in view_source and "request_rescue" not in view_source and "request_capture" not in view_source, "UI exposes no incident mutation path")

func _settle() -> void:
	await process_frame
	await process_frame
