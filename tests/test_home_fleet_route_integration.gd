extends SceneTree

## 홈 함대 선택 → 이동 요청 → 항로 관측의 standalone 통합 회귀 시험.
## 기존 홈 테스트와 run_tests/harness의 단언 하한은 수정하지 않는다.

const Harness := preload("res://tests/harness.gd")
const HomeSubmenuScript := preload("res://scripts/HomeSubmenu.gd")
const FleetMovePanelScript := preload("res://scripts/FleetMovePanel.gd")

var _pass := 0
var _fail := 0


func _ok(condition: bool, label: String) -> void:
	if condition:
		_pass += 1
	else:
		_fail += 1
		print("  실패: ", label)


func _eq(got, wanted, label: String) -> void:
	_ok(got == wanted, "%s — 기대 %s, 실제 %s" % [label, str(wanted), str(got)])


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("홈 함대 이동·항로 통합 시험")
	await _test_home_submenu_actions()
	await _test_move_panel_contract()
	await _test_main_integration()
	print("HomeFleetRouteIntegration: %d 통과 / %d 실패" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)


func _test_home_submenu_actions() -> void:
	var submenu = HomeSubmenuScript.new()
	root.add_child(submenu)
	await process_frame
	var actions: Array[Dictionary] = []
	submenu.action_requested.connect(func(action_id: String, payload: Dictionary):
		actions.append({"id": action_id, "payload": payload.duplicate(true)}))

	var base_state := {"player_state": {"faction_id": "손권"}}
	var own_stationary := {
		"type": "fleet", "fleet_id": 71, "display_name": "제71함대",
		"faction": "손권", "system_id": "SYS-15", "status": "stationed",
	}
	var state: Dictionary = base_state.duplicate(true)
	state["selection"] = own_stationary
	submenu.setup(state, null)
	submenu.open_route("selection", "제71함대", "▲")
	actions.clear() # open_route 자체의 route_opened는 함대 행동 계약과 분리한다.
	var move_button = _button_starting_with(submenu, "이동 명령")
	_ok(move_button != null, "아군 주둔 함대에 이동 명령 행동 표시")
	_ok(_button_starting_with(submenu, "항로 관측") == null,
		"아군 주둔 함대에는 항로 관측 미표시")
	if move_button != null:
		move_button.pressed.emit()
	_eq(actions.size(), 1, "주둔 함대 행동 한 번 전달")
	if actions.size() == 1:
		_eq(actions[0]["id"], "fleet_move_requested", "주둔 함대 action_id")
		_eq(int(actions[0]["payload"]["fleet_id"]), 71, "주둔 함대 action payload")

	actions.clear()
	var own_moving: Dictionary = own_stationary.duplicate(true)
	own_moving["status"] = "moving"
	state = base_state.duplicate(true)
	state["selection"] = own_moving
	submenu.setup(state, null)
	submenu.open_route("selection", "제71함대", "▲")
	actions.clear()
	var route_button = _button_starting_with(submenu, "항로 관측")
	_ok(route_button != null, "아군 이동 함대에 항로 관측 행동 표시")
	_ok(_button_starting_with(submenu, "이동 명령") == null,
		"아군 이동 함대에는 이동 명령 미표시")
	if route_button != null:
		route_button.pressed.emit()
	_eq(actions.size(), 1, "이동 함대 행동 한 번 전달")
	if actions.size() == 1:
		_eq(actions[0]["id"], "fleet_route_requested", "이동 함대 action_id")
		_eq(int(actions[0]["payload"]["fleet_id"]), 71, "이동 함대 action payload")

	actions.clear()
	var enemy: Dictionary = own_stationary.duplicate(true)
	enemy["fleet_id"] = 88
	enemy["display_name"] = "미확인 함대 #88"
	enemy["faction"] = "조조"
	state = base_state.duplicate(true)
	state["selection"] = enemy
	submenu.setup(state, null)
	submenu.open_route("selection", "미확인 함대 #88", "▲")
	actions.clear()
	_ok(_button_starting_with(submenu, "이동 명령") == null,
		"적 함대에는 이동 명령 행동 없음")
	_ok(_button_starting_with(submenu, "항로 관측") == null,
		"적 함대에는 항로 관측 행동 없음")
	_eq(actions, [], "적 함대 선택은 명령 action을 내지 않음")
	submenu.free()


func _test_move_panel_contract() -> void:
	var data := GameData.load_all()
	var campaign := Campaign.scenario_03(data, 1001)
	campaign.world.player_faction = "손권"
	var fleet = _stationary_player_fleet(campaign)
	_ok(fleet != null, "이동 패널용 아군 주둔 함대 확보")
	if fleet == null:
		return

	var panel = FleetMovePanelScript.new()
	root.add_child(panel)
	await process_frame
	panel.setup(data, campaign)
	panel.open_fleet(fleet.id)
	var candidates: Array = panel.candidate_previews()
	var expected_ids: Array[String] = []
	for region_id in data.region_ids:
		var resolved: Dictionary = Orders.resolve_move(
			campaign.world.graph, data, fleet.at_system, String(region_id))
		if bool(resolved.get("ok", false)):
			expected_ids.append(String(region_id))
	expected_ids.sort()
	var candidate_ids: Array[String] = []
	for preview in candidates:
		candidate_ids.append(String(preview.get("destination_region", "")))
	_eq(candidate_ids, expected_ids, "패널 후보는 resolve_move 도달 가능 권역과 일치")
	_ok(not candidates.is_empty(), "이동 패널 후보 존재")

	var picked: Dictionary = _different_system_preview(candidates, fleet.at_system)
	_ok(not picked.is_empty(), "실제 항행 후보 확보")
	if not picked.is_empty():
		var resolved: Dictionary = Orders.resolve_move(campaign.world.graph, data,
			fleet.at_system, String(picked["destination_region"]))
		for key in ["path", "terrain", "travel_ticks", "forced_formation", "allowed_formations"]:
			_eq(picked[key], resolved[key], "패널 preview.%s는 resolve_move 값" % key)
		_eq(picked["corridors"], resolved["corridor_ids"],
			"패널 preview 회랑은 resolve_move 값")

		var requests: Array[Dictionary] = []
		panel.move_requested.connect(func(fid: int, rid: String, preview: Dictionary):
			requests.append({"fleet": fid, "region": rid, "preview": preview.duplicate(true)}))
		var pending_before := campaign.world.pending_commands.size()
		panel.call("_emit_move_request", String(picked["destination_region"]))
		_eq(campaign.world.pending_commands.size(), pending_before,
			"패널 자체는 World 명령을 발행하지 않음")
		_eq(requests.size(), 1, "패널 move_requested 한 번 발생")
		if requests.size() == 1:
			_eq(requests[0]["fleet"], fleet.id, "move_requested 함대 ID")
			_eq(requests[0]["region"], picked["destination_region"],
				"move_requested 목적 권역")
			_eq(requests[0]["preview"]["path"], resolved["path"],
				"move_requested preview 경로")

	var leaked: Array = panel.candidate_previews()
	if not leaked.is_empty():
		(leaked[0] as Dictionary)["path"] = []
		_ok(not (panel.candidate_previews()[0]["path"] as Array).is_empty(),
			"candidate_previews 깊은 복사")
	panel.free()


func _test_main_integration() -> void:
	var original_tree_paused := paused
	var original_time_scale := Engine.time_scale
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	_ok(main.fleet_move_panel != null, "Main이 FleetMovePanel 동적 생성")
	_ok(main.tactical_route_view != null, "Main이 TacticalRouteView 동적 생성")
	_ok(main.fleet_voyage_view != null, "Main이 FleetVoyage3D 동적 생성")
	if main.fleet_move_panel == null or main.tactical_route_view == null:
		main.free()
		return

	var fleet = _stationary_player_fleet(main.campaign)
	_ok(fleet != null, "Main 캠페인의 아군 주둔 함대 확보")
	if fleet == null:
		main.free()
		return
	_eq(fleet.ships, 1, "제3함대 정본 편성은 전열함 한 척")
	_eq(int(fleet.ships_by_kind().get("전열", 0)), 1,
		"제3함대 유일 함선의 함종은 전열")
	var selected: Dictionary = _observed_fleet(main.home_state, fleet.id)
	_ok(not selected.is_empty(), "홈 스냅샷에서 아군 함대 선택 데이터 확보")
	if selected.is_empty():
		main.free()
		return
	var map_fleet: Dictionary = {}
	for value in main._map_fleets:
		if String(value.get("fleet_id", "")) == str(fleet.id):
			map_fleet = value
			break
	_ok(not map_fleet.is_empty(), "전략 지도에 아군 함대 선택 표식 생성")
	if not map_fleet.is_empty():
		var direct_selections: Array[Dictionary] = []
		main.map.object_selected.connect(func(data: Dictionary):
			direct_selections.append(data.duplicate(true)))
		var fleet_world: Vector2 = main.map.call("_fleet_position", map_fleet)
		var fleet_screen: Vector2 = main.map.get_canvas_transform() * fleet_world
		main.map.call("_try_select", fleet_screen)
		_eq(direct_selections.size(), 1, "전략 지도 함대 표식 직접 선택")
		if direct_selections.size() == 1:
			_eq(String(direct_selections[0].get("type", "")), "fleet",
				"지도 직접 선택은 함대 데이터 전달")
	selected["type"] = "fleet"
	main._route_home_action("selection", String(selected.get("display_name", "함대")), "▲", selected)
	await process_frame

	main.cam.position = Vector2(1375.0, 812.0)
	main.cam.zoom = Vector2(0.83, 0.83)
	main.cam.reset_smoothing()
	main.map.semantic_level = 3
	var camera_before: Vector2 = main.cam.position
	var zoom_before: Vector2 = main.cam.zoom
	var semantic_before: int = main.map.semantic_level
	var active_before: String = main.active_menu_id
	var map_context_before: String = main.map_context_menu_id
	var selection_before: Dictionary = main._selection_data.duplicate(true)
	var route_before := String(main.submenu.get("current_route"))
	var submenu_visible_before := bool(main.submenu.visible)
	var campaign_ref = main.campaign

	main._on_submenu_action_requested("fleet_move_requested", {"fleet_id": fleet.id})
	_ok(main.fleet_move_panel.visible, "이동 요청 행동이 FleetMovePanel 표시")
	_ok(not main.tactical_route_view.visible, "이동 패널 중 항로 화면 숨김")
	_ok(not main.submenu.visible, "함대 overlay 중 홈 submenu 숨김")
	_ok(main.map_input_blocker.visible, "함대 overlay 중 지도 입력 차단")

	var candidates: Array = main.fleet_move_panel.call("candidate_previews")
	var picked: Dictionary = _different_system_preview(candidates, fleet.at_system)
	_ok(not picked.is_empty(), "Main 이동 패널 실제 항행 후보")
	if picked.is_empty():
		main.free()
		return
	var pending_before: int = int(main.campaign.world.pending_commands.size())
	main.fleet_move_panel.call("_emit_move_request", String(picked["destination_region"]))
	_eq(main.campaign.world.pending_commands.size(), pending_before + 1,
		"Main 호스트가 World pending 명령 1개 발행")
	_ok(main.tactical_route_view.visible, "이동 발행 뒤 항로 관측 화면 표시")
	_ok(not main.fleet_move_panel.visible, "이동 발행 뒤 이동 패널 숨김")
	_eq(Rect2(main.tactical_route_view.position, main.tactical_route_view.size),
		main.hud_safe_rect, "항로 관측은 홈 HUD 안전 영역만 점유")
	_ok(Rect2(main.tactical_route_view.position, main.tactical_route_view.size).encloses(
		Rect2(main.map_input_blocker.position, main.map_input_blocker.size)),
		"항로 관측과 입력 차단 영역이 같은 홈 안전 영역 안에 있음")
	var route_pending: Dictionary = main.tactical_route_view.get("_context").duplicate(true)
	_eq(route_pending["status"], "pending", "발행 직후 항로 상태 pending")
	_eq(route_pending["fleet_id"], fleet.id, "pending 항로 함대 ID")
	_eq(route_pending["destination_region"], picked["destination_region"],
		"pending 항로 목적 권역")
	_ok(not fleet.is_moving(), "발행 직후 실제 Fleet은 아직 주둔")
	var receipt: Dictionary = main.campaign.world.pending_commands.back()
	_eq(String(receipt["kind"]), Domestic.CMD_FLEET_MOVE, "pending 명령 kind")
	_eq(int(receipt["payload"]["fleet"]), fleet.id, "pending 명령 함대 payload")
	_eq(String(receipt["payload"]["region"]), picked["destination_region"],
		"pending 명령 목적 payload")

	var tick_before := int(main.campaign.world.clock.tick)
	main._process(60.0)
	_eq(main.campaign, campaign_ref, "항로 관측 중 Campaign identity 유지")
	_eq(main.campaign.world.clock.tick, tick_before + 1,
		"항로 관측 중 x1 한 tick 진행")
	_ok(fleet.is_moving(), "다음 tick에 Fleet moving")
	var route_moving: Dictionary = main.tactical_route_view.get("_context").duplicate(true)
	_eq(route_moving["status"], "moving", "항로 화면 pending → moving 갱신")
	_eq(route_moving["arrival_tick"], fleet.arrival_tick, "항로 화면 실제 arrival_tick")
	_eq(route_moving["remaining_ticks"], fleet.arrival_tick - main.campaign.world.clock.tick,
		"항로 화면 실제 remaining_ticks")
	_eq(fleet.departure_tick, int(main.campaign.world.clock.tick),
		"적용 tick을 Fleet 출항 tick으로 기록")
	main._on_tactical_route_detail_requested(fleet.id)
	_ok(main.fleet_voyage_view.visible, "함대 선택 뒤 3D 항행 관측 표시")
	_ok(not main.tactical_route_view.visible, "3D 관측 중 전략 항로 숨김")
	var represented_line_ships := 0
	for ship in main.fleet_voyage_view.get("_formation").get_children():
		if String(ship.get_meta("fleet_ship_kind", "")) == "전열":
			represented_line_ships += 1
	_eq(represented_line_ships, 1, "3D 관측 함대는 전열함 한 척만 표시")
	_eq(main.fleet_voyage_view.get("_formation").get_child_count(), 1,
		"3D 관측 함대에는 호위·축약 함선이 없음")
	main._on_fleet_voyage_closed(fleet.id)
	_ok(main.tactical_route_view.visible, "3D 관측 닫기 뒤 전략 항로 복귀")
	_eq((main.tactical_route_view.get("_context") as Dictionary)["destination_region"],
		picked["destination_region"], "3D 관측 왕복 뒤 같은 이동 컨텍스트 유지")
	_eq(paused, original_tree_paused, "항로 overlay가 SceneTree pause 불변")
	_ok(is_equal_approx(Engine.time_scale, original_time_scale),
		"항로 overlay가 Engine time_scale 불변")

	main.tactical_route_view.call("_close")
	_eq(main.cam.position, camera_before, "항로 닫기 후 카메라 위치 복원")
	_eq(main.cam.zoom, zoom_before, "항로 닫기 후 카메라 zoom 복원")
	_eq(main.map.semantic_level, semantic_before, "항로 닫기 후 semantic 복원")
	_eq(main.active_menu_id, active_before, "항로 닫기 후 active menu 복원")
	_eq(main.map_context_menu_id, map_context_before, "항로 닫기 후 map context 복원")
	_eq(main._selection_data, selection_before, "항로 닫기 후 selection 복원")
	_eq(String(main.submenu.get("current_route")), route_before,
		"항로 닫기 후 submenu route 복원")
	_eq(bool(main.submenu.visible), submenu_visible_before, "항로 닫기 후 submenu 표시 복원")
	_eq(bool(main.map_input_blocker.visible), submenu_visible_before,
		"항로 닫기 후 홈 blocker 상태 복원")
	_ok(not main.tactical_route_view.visible, "항로 닫기 후 overlay 숨김")
	_eq(paused, original_tree_paused, "Main 통합 종료 후 SceneTree pause 불변")
	_ok(is_equal_approx(Engine.time_scale, original_time_scale),
		"Main 통합 종료 후 Engine time_scale 불변")
	main.free()


func _button_starting_with(node: Node, prefix: String):
	for child in node.find_children("*", "Button", true, false):
		if child is Button and String(child.text).begins_with(prefix):
			return child
	return null


func _stationary_player_fleet(campaign):
	for fleet in campaign.fleets:
		if fleet.is_alive() and not fleet.is_moving() \
				and String(fleet.owner) == String(campaign.world.player_faction):
			return fleet
	return null


func _different_system_preview(candidates: Array, origin_system: String) -> Dictionary:
	for value in candidates:
		if value is Dictionary and String(value.get("destination_system", "")) != origin_system \
				and int(value.get("travel_ticks", -1)) > 2:
			return (value as Dictionary).duplicate(true)
	return {}


func _observed_fleet(state: Dictionary, fleet_id: int) -> Dictionary:
	for value in state.get("observed_fleets", []):
		if value is Dictionary and int(value.get("fleet_id", -1)) == fleet_id:
			return (value as Dictionary).duplicate(true)
	return {}
