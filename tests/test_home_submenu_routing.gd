extends SceneTree

## 홈 HUD 라우팅 회귀 시험. UI 탐색은 표시 문자열이 아니라 route_id 메타 계약을 쓴다.

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


func _near_vec(got: Vector2, wanted: Vector2, label: String, epsilon := 0.01) -> void:
	_ok(got.distance_to(wanted) <= epsilon,
		"%s — 기대 %s, 실제 %s" % [label, str(wanted), str(got)])


func _buttons_under(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	for child in node.find_children("*", "Button", true, false):
		if child is Button:
			out.append(child)
	return out


func _visible_text_under(node: Node) -> String:
	var lines: Array[String] = []
	for child in node.find_children("*", "Label", true, false):
		if child is Label and child.is_visible_in_tree():
			lines.append(child.text)
	for child in node.find_children("*", "Button", true, false):
		if child is Button and child.is_visible_in_tree() and child.text != "":
			lines.append(child.text)
	return "\n".join(lines)


func _submenu_rows(submenu: Control) -> Dictionary:
	var rows := {}
	var content = submenu.get("_content")
	if not content is Node:
		return rows
	for child in content.get_children():
		if not child is PanelContainer:
			continue
		var labels: Array[Node] = child.find_children("*", "Label", true, false)
		if labels.size() >= 2:
			rows[String(labels[0].text)] = String(labels[1].text)
	return rows


func _action_text(submenu: Control, title: String) -> String:
	var content = submenu.get("_content")
	if not content is Node:
		return ""
	for child in content.find_children("*", "Button", true, false):
		if child is Button and String(child.text).begins_with(title + "  ›"):
			return String(child.text)
	return ""


func _action_button(submenu: Control, title: String) -> Button:
	var content = submenu.get("_content")
	if not content is Node:
		return null
	for child in content.find_children("*", "Button", true, false):
		if child is Button and String(child.text).begins_with(title + "  ›"):
			return child
	return null


func _assert_button_contract(buttons: Array[Button], expected_routes: Array[String],
		group_name: String) -> void:
	_eq(buttons.size(), expected_routes.size(), "%s 활성 버튼 수" % group_name)
	for index in range(mini(buttons.size(), expected_routes.size())):
		var button := buttons[index]
		_ok(not button.disabled, "%s %s 버튼 활성" % [group_name, expected_routes[index]])
		_eq(String(button.get_meta("route_id", "")), expected_routes[index],
			"%s route_id" % expected_routes[index])
		_ok(button.pressed.get_connections().size() > 0,
			"%s pressed 연결" % expected_routes[index])


func _safe_rect(viewport_size: Vector2) -> Rect2:
	var top_height := clampf(viewport_size.y * 0.078, 58.0, 70.0)
	var bottom_height := clampf(viewport_size.y * 0.225, 174.0, 210.0)
	var left_width := clampf(viewport_size.x * 0.115, 168.0, 184.0)
	var right_width := clampf(viewport_size.x * 0.188, 272.0, 302.0)
	return Rect2(left_width, top_height,
		viewport_size.x - left_width - right_width,
		viewport_size.y - top_height - bottom_height)


func _rect_inside(inner: Rect2, outer: Rect2, epsilon := 0.01) -> bool:
	return inner.position.x >= outer.position.x - epsilon \
		and inner.position.y >= outer.position.y - epsilon \
		and inner.end.x <= outer.end.x + epsilon \
		and inner.end.y <= outer.end.y + epsilon


func _init() -> void:
	var original_paused := paused
	var original_time_scale := Engine.time_scale
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var snapshot_before: Dictionary = main.home_state.duplicate(true)
	var snapshot_object_before: Dictionary = main.home_snapshot.snapshot()
	var left_routes: Array[String] = [
		"overview", "systems", "fleets", "domestic",
		"talent", "diplomacy", "tech", "records",
	]
	var top_routes: Array[String] = [
		"resource:calendar", "resource:funds", "resource:mandate",
		"resource:hegemony", "resource:mobilized", "resource:capacity",
		"pause", "speed", "mail", "settings",
	]
	var right_routes: Array[String] = ["records"]
	var bottom_routes: Array[String] = [
		"stage:1", "stage:2", "stage:3", "stage:4", "red_cliff_lock",
	]
	var left_buttons := _buttons_under(main.left_panel)
	var top_buttons := _buttons_under(main.top_panel)
	var right_buttons := _buttons_under(main.right_panel)
	var bottom_buttons := _buttons_under(main.bottom_panel)
	_assert_button_contract(left_buttons, left_routes, "좌측")
	_assert_button_contract(top_buttons, top_routes, "상단")
	_assert_button_contract(right_buttons, right_routes, "우측 더보기")
	_assert_button_contract(bottom_buttons, bottom_routes, "하단")
	_ok(main.campaign != null, "Main 단일 Campaign 보유")
	_eq(main.campaign.world.player_faction, "손권", "홈 플레이어 세력 손권")
	_eq(main.campaign.world.clock.speed, 1, "홈 시작 배속 x1")
	_ok(not main.campaign.world.clock.paused, "홈 시작 로컬 pause 해제")
	_eq(paused, original_paused, "Main 생성이 SceneTree pause를 변경하지 않음")
	_ok(is_equal_approx(Engine.time_scale, original_time_scale),
		"Main 생성이 Engine time_scale을 변경하지 않음")

	# 천하도는 고정 0.50이 아니라 현재 safe rect의 동적 전체 fit을 쓴다.
	if left_buttons.size() >= 2:
		left_buttons[0].pressed.emit()
		await process_frame
		_eq(main.active_menu_id, "overview", "천하도 active_menu_id")
		_eq(main.map.semantic_level, 1, "천하도 semantic 1")
		_ok(absf(main.cam.zoom.x - main.map.overview_zoom) <= 0.001,
			"천하도 dynamic overview zoom")

		left_buttons[1].pressed.emit()
		await process_frame
		_eq(main.active_menu_id, "systems", "성역 active_menu_id")
		_eq(String(main.submenu.get("current_route")), "systems", "성역 current_route")
		_eq(main.map._semantic_level_for_zoom(main.cam.zoom.x), 2, "성역 semantic 2")

	# 업무 메뉴는 같은 패널의 내용만 전환하며 카메라와 snapshot을 건드리지 않는다.
	var business_indexes := [2, 3, 4, 5, 6, 7]
	for index in business_indexes:
		if index >= left_buttons.size():
			continue
		var camera_before: Vector2 = main.cam.position
		var zoom_before: Vector2 = main.cam.zoom
		left_buttons[index].pressed.emit()
		await process_frame
		var route_id := left_routes[index]
		_eq(main.active_menu_id, route_id, route_id + " active_menu_id")
		_eq(String(main.submenu.get("current_route")), route_id, route_id + " current_route")
		_near_vec(main.cam.position, camera_before, route_id + " 카메라 위치 불변")
		_near_vec(main.cam.zoom, zoom_before, route_id + " 카메라 배율 불변")
		_eq(main.ui_root.find_children("HomeSubmenu", "Control", true, false).size(), 1,
			route_id + " 단일 submenu")

	# 관측 함대는 안전 표시 필드로 서로 구분되고 stable fleet_id를 선택에 사용한다.
	left_buttons[2].pressed.emit()
	await process_frame
	var observed_fleets: Array = main.home_state.get("observed_fleets", [])
	_ok(not observed_fleets.is_empty(), "손권 관점 관측 함대 존재")
	var fleet_names := {}
	for observed in observed_fleets:
		var display_name := str(observed.get("display_name", ""))
		fleet_names[display_name] = true
		var fleet_text := _action_text(main.submenu, display_name)
		_ok(display_name != "" and fleet_text != "", "관측 함대 구분 이름 표시")
		_ok(fleet_text.contains("성역 %s" % str(observed.get("system_id", ""))),
			"관측 함대 성역 표시")
		_ok(fleet_text.contains("상태 %s" % ("이동 중" if str(observed.get("status", "")) == "moving" else "주둔")),
			"관측 함대 상태 한글 표시")
		_ok(fleet_text.contains("척수 %s" % str(observed.get("ships_display", ""))),
			"관측 함대 안전 척수 표시")
	_eq(fleet_names.size(), observed_fleets.size(), "관측 함대 표시 이름 유일")
	if not observed_fleets.is_empty():
		var first_fleet: Dictionary = observed_fleets[0]
		var fleet_button := _action_button(main.submenu, String(first_fleet.display_name))
		_ok(fleet_button != null, "관측 함대 선택 버튼 존재")
		if fleet_button != null:
			fleet_button.pressed.emit()
			await process_frame
			_eq(String(main.submenu.get("current_route")), "selection", "관측 함대 selection route")
			_eq(str(main._selection_data.get("fleet_id", "")), str(first_fleet.fleet_id),
				"관측 함대 stable fleet_id 선택")
			main._refresh_home_snapshot()
			_eq(str(main._selection_data.get("fleet_id", "")), str(first_fleet.fleet_id),
				"snapshot refresh 후 stable fleet_id 선택 보존")
	var exact_observed := 0
	for observed in observed_fleets:
		if observed.has("ships"):
			exact_observed += 1
	_eq(main._map_fleets.size(), exact_observed, "정확 척수 관측만 지도 어댑터 연결")
	for rendered in main._map_fleets:
		_eq((rendered.get("path", []) as Array).size(), 2, "지도 함대 표시 경로 두 점")
		_eq(float(rendered.get("speed", -1.0)), 0.0, "지도 함대 목적선 정적 표시")
		var path: Array = rendered.get("path", [])
		if path.size() == 2:
			_eq(path[0], path[1], "주둔 함대는 같은 점 두 개로 표시")
	var moving_fixture: Dictionary = main.home_state.duplicate(true)
	moving_fixture["observed_fleets"] = [{
		"fleet_id": 999, "system_id": "SYS-15", "status": "moving",
		"dest_region": "RGN-04", "display_name": "시험 관측 함대",
		"faction": "", "ships": 10, "ships_display": "10",
	}]
	var moving_render: Array = main._adapt_observed_fleets(
		moving_fixture, main.projected_systems, main._project_regions(main.home_state))
	_eq(moving_render.size(), 1, "이동 관측 함대 지도 어댑터")
	if moving_render.size() == 1:
		var moving_path: Array = moving_render[0].get("path", [])
		_ok(moving_path.size() == 2 and moving_path[0] != moving_path[1],
			"이동 함대는 현재 성역과 목적 권역의 정적 목적선")
		_eq(float(moving_render[0].get("speed", -1.0)), 0.0, "이동 함대도 속도를 발명하지 않음")
		_eq(String(moving_render[0].get("faction", "x")), "", "미확인 함대 소유자 미발명")

	# 기술 패널은 player_state의 실제 단계와 진행 중 연구만 표시한다.
	left_buttons[6].pressed.emit()
	await process_frame
	var tech_rows := _submenu_rows(main.submenu)
	var player_tech: Dictionary = (main.home_state.get("player_state", {}) as Dictionary).get("tech", {})
	for axis in ["화력", "방어", "특수"]:
		_eq(tech_rows.get(axis), "%d단계" % int(player_tech.get(axis, 0)), axis + " 실제 기술 단계")
	var tech_text := _visible_text_under(main.submenu)
	_ok(not tech_text.contains("확인 가능한 기술 없음"), "기술 미지원 고정 문구 제거")
	var researching_state: Dictionary = main.home_state.duplicate(true)
	researching_state["player_state"]["tech"] = {"화력": 1, "방어": 2, "특수": 3}
	var current_tick := int(researching_state["scenario"].get("tick", 0))
	researching_state["player_state"]["tech_research"] = {
		"axis": "방어", "done_tick": current_tick + 12,
	}
	main.submenu.call("setup", researching_state, main.home_snapshot)
	main.submenu.call("open_route", "tech", "기술", "✦")
	await process_frame
	tech_rows = _submenu_rows(main.submenu)
	_eq(tech_rows.get("화력"), "1단계", "기술 fixture 화력 단계")
	_eq(tech_rows.get("방어"), "2단계", "기술 fixture 방어 단계")
	_eq(tech_rows.get("특수"), "3단계", "기술 fixture 특수 단계")
	_eq(tech_rows.get("진행 중인 연구"), "방어", "진행 중 기술 분야")
	_eq(tech_rows.get("완료까지"), "12 tick", "진행 중 기술 남은 tick")

	# 여섯 자원은 내부 route suffix 대신 한글 제목과 버튼이 전달한 표시값을 쓴다.
	var resource_contracts: Array[Dictionary] = [
		{"route": "resource:calendar", "title": "연대"},
		{"route": "resource:funds", "title": "자금"},
		{"route": "resource:mandate", "title": "천명"},
		{"route": "resource:hegemony", "title": "패권 압력"},
		{"route": "resource:mobilized", "title": "동원력"},
		{"route": "resource:capacity", "title": "함대 수용량"},
	]
	var scenario: Dictionary = main.home_state.get("scenario", {})
	var player: Dictionary = main.home_state.get("player_state", {})
	var expected_resource_values := {
		"resource:calendar": "건안 %d년 %d월" % [
			13 + int(scenario.get("year", 208)) - 208, int(scenario.get("month", 1))],
		"resource:funds": str(player.get("treasury", "—")),
		"resource:mandate": str(player.get("mandate", "—")),
		"resource:hegemony": str(player.get("hegemony", "—")),
		"resource:mobilized": str(player.get("mobilized", "—")),
		"resource:capacity": "%s/%s" % [str(player.get("fleet_used_milli", "—")),
			str(player.get("fleet_capacity_milli", "—"))],
	}
	for index in range(resource_contracts.size()):
		var contract: Dictionary = resource_contracts[index]
		top_buttons[index].pressed.emit()
		await process_frame
		var route_id := String(contract.route)
		var title := String(contract.title)
		var payload: Dictionary = main._resource_payload(route_id)
		var value := String(payload.get("display_value", ""))
		var delta := String(payload.get("display_delta", ""))
		var rows := _submenu_rows(main.submenu)
		var visible_text := _visible_text_under(main.submenu)
		_eq(String(main.submenu.get("current_route")), route_id, route_id + " 패널 route")
		_ok(visible_text.contains(title), route_id + " 한글 제목 표시")
		_ok(visible_text.contains(value), route_id + " 표시값 payload 표시")
		_eq(value, String(expected_resource_values[route_id]), route_id + " 실제 Campaign 값")
		if delta != "":
			_ok(visible_text.contains(delta), route_id + " 증감 payload 표시")
		_ok(not visible_text.contains(route_id.trim_prefix("resource:")),
			route_id + " raw suffix 미노출")
		_ok(rows.has(title) and String(rows[title]).contains(value),
			route_id + " 한글 제목과 표시값 결합")
	for removed_route in ["resource:supply", "resource:influence", "resource:intel"]:
		_ok(not main.top_route_buttons.has(removed_route), removed_route + " 가짜 자원 제거")

	# 외교의 네 외부 세력은 서로 다른 한글 현재 상태를 표시한다.
	left_buttons[5].pressed.emit()
	await process_frame
	var diplomacy_text := _visible_text_under(main.submenu)
	for raw_status in ["present", "background", "future"]:
		_ok(not diplomacy_text.contains(raw_status), "외교 raw status 미노출: " + raw_status)
	for expected in [
		["동이 연합", "현재 접촉 가능"],
		["대월지", "현재 접촉 가능"],
		["로마", "교역 배경"],
		["사산조", "224년 이후 등장"],
	]:
		var action_text := _action_text(main.submenu, String(expected[0]))
		_ok(action_text.contains(String(expected[1])),
			"외부 세력 상태 한글화: %s" % String(expected[0]))

	# 자원·메일·설정 및 우측 더보기도 동일한 단일 패널 라우팅을 사용한다.
	for index in [0, 1, 2, 3, 4, 5, 8, 9]:
		if index >= top_buttons.size():
			continue
		var route_id := top_routes[index]
		var camera_before: Vector2 = main.cam.position
		var zoom_before: Vector2 = main.cam.zoom
		top_buttons[index].pressed.emit()
		await process_frame
		_eq(String(main.submenu.get("current_route")), route_id, route_id + " 패널 route")
		_near_vec(main.cam.position, camera_before, route_id + " 카메라 위치 불변")
		_near_vec(main.cam.zoom, zoom_before, route_id + " 카메라 배율 불변")
	if not right_buttons.is_empty():
		right_buttons[0].pressed.emit()
		await process_frame
		_eq(String(main.submenu.get("current_route")), "records", "더보기 records route")

	# 열린 패널은 지도 영역 blocker 하나로 입력을 막는다.
	_ok(main.submenu.visible, "submenu 표시")
	_ok(main.map_input_blocker.visible, "map blocker 표시")
	_eq(main.map_input_blocker.mouse_filter, Control.MOUSE_FILTER_STOP,
		"map blocker 입력 중단")
	_eq(main.ui_root.find_children("MapInputBlocker", "Control", true, false).size(), 1,
		"map blocker 단일 인스턴스")

	# 세 표준 해상도의 safe rect 안에 blocker와 submenu가 유지된다.
	for viewport_size in [Vector2(1280,720), Vector2(1600,900), Vector2(1920,1080)]:
		var safe := _safe_rect(viewport_size)
		main.hud_safe_rect = safe
		main._layout_submenu()
		_eq(Rect2(main.map_input_blocker.position, main.map_input_blocker.size), safe,
			"%dx%d blocker safe rect" % [int(viewport_size.x), int(viewport_size.y)])
		_ok(_rect_inside(Rect2(main.submenu.position, main.submenu.size), safe),
			"%dx%d submenu safe rect 내부" % [int(viewport_size.x), int(viewport_size.y)])

	# 잠긴 적벽도 클릭 가능하며 지도 이동 대신 잠금 안내 패널을 연다.
	if bottom_buttons.size() == 5:
		var camera_before: Vector2 = main.cam.position
		var zoom_before: Vector2 = main.cam.zoom
		bottom_buttons[4].pressed.emit()
		await process_frame
		_ok(not bottom_buttons[4].disabled, "잠긴 적벽 버튼 클릭 가능")
		_eq(String(main.submenu.get("current_route")), "red_cliff_lock", "적벽 잠금 패널 route")
		_near_vec(main.cam.position, camera_before, "적벽 잠금 시 카메라 위치 불변")
		_near_vec(main.cam.zoom, zoom_before, "적벽 잠금 시 카메라 배율 불변")

	# 조건은 true/false/missing을 충족/미충족/확인 대기로 구분한다.
	var lock_state: Dictionary = main.home_state.duplicate(true)
	lock_state["red_cliff_conditions"] = {
		"cao_southward_complete": true,
		"sun_quan_independent": false,
	}
	main.submenu.call("setup", lock_state, main.home_snapshot)
	main.submenu.call("open_route", "red_cliff_lock", "적벽 개전 조건", "🔒")
	await process_frame
	var lock_rows := _submenu_rows(main.submenu)
	_eq(lock_rows.get("조조군 남하 완료"), "충족", "적벽 true 조건 표시")
	_eq(lock_rows.get("손권 세력 독립 유지"), "미충족", "적벽 false 조건 표시")
	_eq(lock_rows.get("유비·조조 적대"), "확인 대기", "적벽 missing 조건 표시")
	_eq(lock_rows.get("손·유 군사 맹약"), "확인 대기", "적벽 missing 맹약 표시")
	_eq(lock_rows.get("장강 방어선 형성"), "확인 대기", "적벽 missing 방어선 표시")

	# 5단계 callback은 빌드 당시가 아니라 누르는 순간의 최신 전투 상태를 읽는다.
	var default_home_state: Dictionary = main.home_state
	main.home_state = main.home_state.duplicate(true)
	main.home_state["active_battles"] = [{"id": "BATTLE-RED-CLIFF", "status": "active"}]
	main._refresh_stage_five()
	_eq(String(bottom_buttons[4].get_meta("route_id")), "stage:5", "적벽 활성 시 최신 stage:5 route")
	bottom_buttons[4].pressed.emit()
	await process_frame
	_eq(main.map.semantic_level, 5, "적벽 활성 시 5단계 이동")
	_ok(not main.submenu.visible, "적벽 활성 시 잠금 패널 미표시")
	main.home_state = default_home_state
	main._refresh_stage_five()
	_eq(String(bottom_buttons[4].get_meta("route_id")), "red_cliff_lock", "적벽 상태 복원 시 잠금 route")

	# 실제 지도 선택은 capital을 한글화하고 관할 권역 수를 표시한다.
	var selected_capital: Dictionary = {}
	for system in main.projected_systems:
		if String(system.get("type", "")) == "capital":
			selected_capital = system.duplicate(true)
			break
	_ok(not selected_capital.is_empty(), "선택 가능한 수도 성역 존재")
	if not selected_capital.is_empty():
		main.map.object_selected.emit(selected_capital)
		await process_frame
		var selection_text := _visible_text_under(main.submenu)
		_eq(String(main.submenu.get("current_route")), "selection", "수도 선택 route")
		_ok(selection_text.contains("수도 성역"), "capital 유형 한글화")
		_ok(not selection_text.contains("capital"), "capital raw 유형 미노출")
		_ok(selection_text.contains("관할 권역"), "수도 관할 권역 제목")
		_ok(selection_text.contains("%d개" % (selected_capital.get("region_ids", []) as Array).size()),
			"수도 관할 권역 수")

	# close_panel은 패널과 blocker를 함께 닫는다.
	main.submenu.call("close_panel")
	await process_frame
	_ok(not main.submenu.visible, "close_panel submenu 숨김")
	_ok(not main.map_input_blocker.visible, "close_panel blocker 숨김")

	# pause 두 번과 speed 다섯 번은 Campaign 시계와 UI만 시작 상태로 왕복한다.
	if top_buttons.size() == 10:
		var original_pause_text := String(main.pause_button.text)
		var original_speed_text := String(main.speed_button.text)
		var original_speed_index := int(main.playback_speed_index)
		top_buttons[6].pressed.emit()
		_ok(main.campaign.world.clock.paused, "pause route Campaign 시계 토글")
		_eq(String(main.pause_button.text), "▶", "pause 버튼 토글 표시")
		_eq(paused, original_paused, "pause가 SceneTree 전역에 영향 없음")
		top_buttons[6].pressed.emit()
		_ok(not main.campaign.world.clock.paused, "pause 두 번 원상 복귀")
		_eq(String(main.pause_button.text), original_pause_text, "pause 버튼 문자 원상 복귀")
		for _step in range(5):
			top_buttons[7].pressed.emit()
		_eq(main.playback_speed_index, original_speed_index, "speed 다섯 번 index 원상 복귀")
		_eq(main.campaign.world.clock.speed, 1, "speed 다섯 번 Campaign 시계 원상 복귀")
		_eq(String(main.speed_button.text), original_speed_text, "speed 버튼 문자 원상 복귀")
		_ok(is_equal_approx(Engine.time_scale, original_time_scale),
			"speed가 Engine time_scale에 영향 없음")

	for key in snapshot_before:
		_eq(main.home_state.get(key), snapshot_before[key],
			"메뉴 탐색 후 home_state.%s 불변" % String(key))
	var snapshot_after_navigation: Dictionary = main.home_snapshot.snapshot()
	for key in snapshot_object_before:
		_eq(snapshot_after_navigation.get(key), snapshot_object_before[key],
			"메뉴 탐색 후 HomeMapSnapshot.%s 불변" % String(key))

	# 열린 selection과 카메라를 보존하면서 x1/x2/x4 비율로 Campaign만 진행한다.
	if not selected_capital.is_empty():
		main.map.object_selected.emit(selected_capital)
		await process_frame
	var campaign_ref = main.campaign
	var snapshot_ref = main.home_snapshot
	var preserved_route := String(main.submenu.get("current_route"))
	var preserved_active_menu: String = main.active_menu_id
	var preserved_camera_position: Vector2 = main.cam.position
	var preserved_camera_zoom: Vector2 = main.cam.zoom
	var preserved_semantic: int = main.map.semantic_level
	var tick_before := int(main.campaign.world.clock.tick)
	main._process(60.0)
	_eq(main.campaign, campaign_ref, "snapshot refresh 후 Campaign identity 유지")
	_eq(main.campaign.world.clock.tick, tick_before + 1, "x1은 60초에 1 tick")
	_ok(main.home_snapshot != snapshot_ref, "tick 진행 시 snapshot 교체")
	_eq(String(main.submenu.get("current_route")), preserved_route, "refresh 열린 route 보존")
	_eq(main.active_menu_id, preserved_active_menu, "refresh active menu 보존")
	_near_vec(main.cam.position, preserved_camera_position, "refresh 카메라 위치 보존")
	_near_vec(main.cam.zoom, preserved_camera_zoom, "refresh 카메라 배율 보존")
	_eq(main.map.semantic_level, preserved_semantic, "refresh semantic 보존")
	_ok(_visible_text_under(main.submenu).contains("수도 성역"), "refresh selection 표시 보존")

	top_buttons[7].pressed.emit()
	tick_before = int(main.campaign.world.clock.tick)
	main._process(60.0)
	_eq(main.campaign.world.clock.tick, tick_before + 2, "x2는 60초에 2 tick")
	top_buttons[7].pressed.emit()
	tick_before = int(main.campaign.world.clock.tick)
	main._process(60.0)
	_eq(main.campaign.world.clock.tick, tick_before + 4, "x4는 60초에 4 tick")
	top_buttons[7].pressed.emit()
	tick_before = int(main.campaign.world.clock.tick)
	main._process(60.0)
	_eq(main.campaign.world.clock.tick, tick_before + 16, "x16은 60초에 16 tick")
	top_buttons[7].pressed.emit()
	tick_before = int(main.campaign.world.clock.tick)
	main._process(60.0)
	_eq(main.campaign.world.clock.tick, tick_before + 64, "x64는 60초에 64 tick")
	top_buttons[7].pressed.emit()
	_eq(main.campaign.world.clock.speed, 1, "진행 비율 시험 후 x1 복귀")

	top_buttons[6].pressed.emit()
	tick_before = int(main.campaign.world.clock.tick)
	main._process(60.0)
	_eq(main.campaign.world.clock.tick, tick_before, "로컬 pause 중 Campaign tick 정지")
	_eq(String(main.submenu.get("current_route")), preserved_route, "로컬 pause 중 메뉴 유지")
	_eq(paused, original_paused, "로컬 pause 중 SceneTree 전역 불변")
	_ok(is_equal_approx(Engine.time_scale, original_time_scale),
		"런타임 진행 후 Engine time_scale 불변")

	# Main 종료도 소유하지 않은 전역 시간 상태를 건드리지 않는다.
	if top_buttons.size() == 10:
		top_buttons[7].pressed.emit()
		_ok(main.campaign.world.clock.paused, "Main exit 전 Campaign pause 상태")
		_eq(main.campaign.world.clock.speed, 2, "Main exit 전 Campaign speed 상태")
	main.free()
	_eq(paused, original_paused, "Main exit tree pause 전역 불변")
	_ok(is_equal_approx(Engine.time_scale, original_time_scale), "Main exit tree time_scale 전역 불변")
	print("HomeSubmenuRouting: %d 통과 / %d 실패" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
