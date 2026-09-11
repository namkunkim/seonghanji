extends SceneTree

## DEMO-RC-G6-04 — 비상 귀환 기준·목적지 재탐색·조기 귀환·UI 경고 UI.
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")
const BattleView := preload("res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd")

var _pass := 0
var _fail := 0

func _ok(value: bool, label: String) -> void:
	if value: _pass += 1
	else: _fail += 1; print("  x %s" % label)

func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])

func _init() -> void: call_deferred("_run")

func _run() -> void:
	print("DEMO-RC-G6-04 — 비상 귀환 기준·목적지 재탐색·조기 귀환·UI 경고 UI")
	root.size = Vector2i(1600, 900)
	await _test_normal_early_cancel_and_fuel()
	await _test_forced_and_stranded_warnings()
	await _test_viewer_boundary()
	_test_source_boundary()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail else Harness.EXIT_PASS)

func _battle():
	var loaded := Setup.load_default(); _ok(loaded.ok, "default setup loads")
	var battle = Battle.new(); _ok(battle.initialize(loaded.setup).ok, "battle initializes"); return battle

func _view(battle):
	var view := BattleView.new(); _ok(view.configure(battle, 1, "g6-04-ui").ok, "battle view configures"); root.add_child(view); return view

func _select_fast_craft(view) -> void:
	var select: Button = view.find_child("Select_RC-LIU-FC-01", true, false); _ok(select != null, "own fast craft remains reachable")
	if select != null: select.pressed.emit()
	await _settle()

func _test_normal_early_cancel_and_fuel() -> void:
	var battle = _battle(); var view = _view(battle); await _settle(); await _select_fast_craft(view)
	var own: Dictionary = battle.viewer_fast_craft_returns("liu_bei"); var status: Dictionary = own.statuses.filter(func(row): return String(row.squadron_id) == "RC-LIU-FC-01")[0]
	_eq(status.status, "normal", "default craft starts before emergency threshold")
	var title: Label = view.find_child("FastCraftReturnTitle", true, false); _ok(title != null and title.text.contains("정상 임무"), "normal return status is explicit")
	var state: Label = view.find_child("FastCraftReturnState", true, false)
	_ok(state != null and state.text.contains("잔여 연료 %d bp" % int(status.fuel_basis_points)), "remaining fuel comes from viewer receipt")
	_ok(state.text.contains("필요 %d bp" % int(status.required_fuel_basis_points)) and state.text.contains("1턴 예비 %d bp" % int(status.reserve_fuel_basis_points)), "required fuel and one-turn reserve come from viewer receipt")
	_ok(state.text.contains("강제 기준 %d bp" % int(status.threshold_basis_points)) and state.text.contains(String(status.nearest_source_id)), "threshold and nearest reachable source are visible")
	_ok(state.text.contains("거리 %.1f" % float(status.distance)) and state.text.contains("예상 %d턴" % int(status.eta_turns)), "distance and ETA are exact receipt values")
	_ok(state.text.contains("현재 위치 →") and state.text.contains("(%.1f, %.1f)" % [float(status.route[0][0]), float(status.route[0][1])]), "route is presented from current position to receipt destination")
	var map = view.find_child("AppliedSquadronMap", true, false); var routes: Array = map.fast_craft_return_statuses_for_test()
	_ok(routes.any(func(row): return String(row.squadron_id) == "RC-LIU-FC-01" and row.route == status.route), "2D map receives the own viewer route unchanged")
	var request: Button = view.find_child("RequestFastCraftReturn", true, false); var cancel: Button = view.find_child("CancelFastCraftReturn", true, false)
	_ok(request != null and not request.disabled and cancel != null and cancel.disabled, "early return is available before threshold and cancel starts locked")
	request.pressed.emit(); await _settle()
	_eq(battle.viewer_fast_craft_returns("liu_bei").statuses[0].status, "early_return", "early return request uses core mutation")
	var early_title: Label = view.find_child("FastCraftReturnTitle", true, false); _ok(early_title.text.contains("조기 귀환"), "early return state refreshes immediately")
	cancel = view.find_child("CancelFastCraftReturn", true, false); _ok(not cancel.disabled, "early return remains cancellable before threshold"); cancel.pressed.emit(); await _settle()
	_eq(battle.viewer_fast_craft_returns("liu_bei").statuses[0].status, "normal", "cancel restores normal mission")
	request = view.find_child("RequestFastCraftReturn", true, false); request.pressed.emit(); await _settle()
	_ok(battle.submit_command_draft().ok and battle.submit_sun_control_choice("ai").ok and battle.resolve_turn().ok, "early return resolves through automatic core override")
	view._refresh(); await _settle()
	var latest: Label = view.find_child("FastCraftReturnLatest_RC-LIU-FC-01", true, false)
	_ok(latest != null and latest.text.contains("귀환 연료 소비") and latest.text.contains("실제 이동"), "latest authoritative actual-distance fuel event is visible")
	if DisplayServer.get_name() != "headless":
		var order_scroll: ScrollContainer = view.find_child("MovementOrderScroll", true, false)
		if order_scroll != null and latest != null: order_scroll.ensure_control_visible(latest)
		await process_frame; await process_frame
		var output_dir := "res://out/demo-rc-g6-04-fast-craft-return"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)); await process_frame
		var image := root.get_texture().get_image(); _ok(image != null and image.get_size() == Vector2i(1600, 900), "1600x900 GPU image")
		if image != null: _ok(image.save_png(ProjectSettings.globalize_path(output_dir.path_join("fast-craft-return-1600x900.png"))) == OK, "GPU capture saved")
	view.free()

func _test_forced_and_stranded_warnings() -> void:
	var battle = _battle(); var initial: Dictionary = battle.viewer_fast_craft_returns("liu_bei").statuses[0]
	battle._state.fast_craft_supply_state.resources["RC-LIU-FC-01"].fuel_basis_points = int(initial.threshold_basis_points)
	var view = _view(battle); await _settle(); await _select_fast_craft(view)
	var forced: Dictionary = battle.viewer_fast_craft_returns("liu_bei").statuses[0]; _eq(forced.status, "forced_return", "threshold equality fixture is core-classified forced")
	var state: Label = view.find_child("FastCraftReturnState", true, false); _ok(state.text.contains("강제귀환") and state.text.contains("취소할 수 없습니다"), "forced-return lock warning is explicit")
	var request: Button = view.find_child("RequestFastCraftReturn", true, false); var cancel: Button = view.find_child("CancelFastCraftReturn", true, false)
	_ok(request.disabled and cancel.disabled, "forced return locks both early-return controls")
	battle._state.live_navigation["RC-LIU-FC-01"].position = [800, 450]
	battle._state.fast_craft_supply_state.resources["RC-LIU-FC-01"].fuel_basis_points = 1; view._refresh(); await _settle()
	var risk: Dictionary = battle.viewer_fast_craft_returns("liu_bei").statuses[0]; _eq(risk.status, "stranded_risk", "unreachable fixture is core-classified risk only")
	state = view.find_child("FastCraftReturnState", true, false)
	_ok(state.text.contains("도달 가능한 아군 보급원이 없습니다") and state.text.contains("필요 산출 불가") and state.text.contains("예상 산출 불가"), "unreachable warning avoids fabricated route metrics")
	var boundary: Label = view.find_child("FastCraftReturnBoundary", true, false); _ok(boundary.text.contains("G6-05") and boundary.text.contains("표류·파괴·나포"), "G6-05 outcome boundary stays explicit")
	view.free()

func _test_viewer_boundary() -> void:
	var battle = _battle(); var before := battle.digest()
	_ok(not battle.request_fast_craft_return("cao_cao", "RC-LIU-FC-01").ok and battle.digest() == before, "cross-faction direct mutation is atomically rejected")
	_ok(battle.submit_command_draft().ok and battle.submit_sun_control_choice("ai").ok, "viewer fixture leaves direct-command phase")
	var view = _view(battle); await _settle(); view._viewer_faction_id = "cao_cao"; view._refresh(); await _settle()
	_eq(battle.viewer_fast_craft_returns("cao_cao").statuses.size(), 0, "enemy viewer receives no Liu fuel, source, threshold, ETA, or route")
	var map = view.find_child("AppliedSquadronMap", true, false); _eq(map.fast_craft_return_statuses_for_test().size(), 0, "enemy map receives no hostile return route")
	_ok(view.find_child("FastCraftReturnTitle", true, false) == null and view.find_child("FastCraftReturnTitle_RC-LIU-FC-01", true, false) == null, "enemy panel exposes no hostile return controls")
	view.free()

func _test_source_boundary() -> void:
	var map_source := FileAccess.get_file_as_string("res://scripts/red_cliff_turn/red_cliff_tactical_map.gd")
	var view_source := FileAccess.get_file_as_string("res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd")
	_ok("Node3D" not in map_source and ".glb" not in map_source and "Node3D" not in view_source, "return presentation remains 2D only")
	_ok("viewer_fast_craft_returns" in view_source and "required_fuel_basis_points" in view_source and "threshold_basis_points" in view_source and "eta_turns" in view_source, "UI consumes public core return metrics without formula duplication")
	_ok("fuel_basis_points_per_distance" not in view_source and "reserve_turns" not in view_source and "destination_policy" not in view_source, "UI contains no return calculation authority")
	_ok("request_fast_craft_return(_viewer_faction_id" in view_source and "cancel_fast_craft_return(_viewer_faction_id" in view_source, "UI passes requesting faction to both mutations")
	_ok("capture_result" not in view_source and "drift_result" not in view_source and "destroyed_result" not in view_source, "G6-05 outcomes are not implemented")

func _settle() -> void:
	await process_frame
	await process_frame
