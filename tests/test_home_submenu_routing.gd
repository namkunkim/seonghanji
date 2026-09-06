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
		"resource:calendar", "resource:funds", "resource:supply",
		"resource:influence", "resource:intel", "resource:capacity",
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

	# 여섯 자원은 내부 route suffix 대신 한글 제목과 버튼이 전달한 표시값을 쓴다.
	var resource_contracts: Array[Dictionary] = [
		{"route": "resource:calendar", "title": "연대", "value": "건안 13년 · 208", "delta": ""},
		{"route": "resource:funds", "title": "자금", "value": "12.4M", "delta": "+24"},
		{"route": "resource:supply", "title": "군량", "value": "8.7M", "delta": "+317"},
		{"route": "resource:influence", "title": "영향력", "value": "3.1M", "delta": "+92"},
		{"route": "resource:intel", "title": "정보", "value": "421K", "delta": "+11"},
		{"route": "resource:capacity", "title": "함대 수용력", "value": "98/120", "delta": ""},
	]
	for index in range(resource_contracts.size()):
		var contract: Dictionary = resource_contracts[index]
		top_buttons[index].pressed.emit()
		await process_frame
		var route_id := String(contract.route)
		var title := String(contract.title)
		var value := String(contract.value)
		var delta := String(contract.delta)
		var rows := _submenu_rows(main.submenu)
		var visible_text := _visible_text_under(main.submenu)
		_eq(String(main.submenu.get("current_route")), route_id, route_id + " 패널 route")
		_ok(visible_text.contains(title), route_id + " 한글 제목 표시")
		_ok(visible_text.contains(value), route_id + " 표시값 payload 표시")
		if delta != "":
			_ok(visible_text.contains(delta), route_id + " 증감 payload 표시")
		_ok(not visible_text.contains(route_id.trim_prefix("resource:")),
			route_id + " raw suffix 미노출")
		_ok(rows.has(title) and String(rows[title]).contains(value),
			route_id + " 한글 제목과 표시값 결합")

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

	# pause 두 번과 speed 세 번은 UI를 포함해 시작 상태로 왕복한다.
	if top_buttons.size() == 10:
		var original_pause_text := String(main.pause_button.text)
		var original_speed_text := String(main.speed_button.text)
		var original_speed_index := int(main.playback_speed_index)
		top_buttons[6].pressed.emit()
		_eq(paused, not original_paused, "pause route 토글")
		_eq(String(main.pause_button.text), "▶" if paused else "II", "pause 버튼 토글 표시")
		top_buttons[6].pressed.emit()
		_eq(paused, original_paused, "pause 두 번 원상 복귀")
		_eq(String(main.pause_button.text), original_pause_text, "pause 버튼 문자 원상 복귀")
		for _step in range(3):
			top_buttons[7].pressed.emit()
		_eq(main.playback_speed_index, original_speed_index, "speed 세 번 index 원상 복귀")
		_ok(is_equal_approx(Engine.time_scale, original_time_scale), "speed 세 번 time_scale 원상 복귀")
		_eq(String(main.speed_button.text), original_speed_text, "speed 버튼 문자 원상 복귀")

	_eq(main.home_state, snapshot_before, "메뉴 탐색 후 home_state 불변")
	_eq(main.home_snapshot.snapshot(), snapshot_object_before,
		"메뉴 탐색 후 HomeMapSnapshot 불변")

	# Main이 사라질 때 변경 중이던 전역 시간 상태도 생성 전 값으로 복구한다.
	if top_buttons.size() == 10:
		top_buttons[6].pressed.emit()
		top_buttons[7].pressed.emit()
		_ok(paused != original_paused, "Main exit 전 pause 변경 상태 준비")
		_ok(not is_equal_approx(Engine.time_scale, original_time_scale),
			"Main exit 전 speed 변경 상태 준비")
	main.free()
	_eq(paused, original_paused, "Main exit tree pause 복원")
	_ok(is_equal_approx(Engine.time_scale, original_time_scale), "Main exit tree time_scale 복원")
	print("HomeSubmenuRouting: %d 통과 / %d 실패" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
