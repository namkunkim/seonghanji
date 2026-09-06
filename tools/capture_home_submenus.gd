extends SceneTree

## 실제 홈 장면의 라우터를 발화해 하위 패널 상태와 시각 결과를 함께 검증한다.
##
## 실행 예:
##   godot --headless --path . --script res://tools/capture_home_submenus.gd \
##     -- --output=C:/temp/seonghanji-home-submenus
##
## production 상태는 변경하지 않는다. 선택 캡처도 GalaxyMap.object_selected 신호를
## 통해 실제 Main 라우터로 진입한다.

const MAIN_SCENE := "res://scenes/main.tscn"
const SETTLE_FRAMES := 3
const ROUTE_CASES: Array[Dictionary] = [
	{"route": "overview", "file": "00-overview", "source": "menu"},
	{"route": "systems", "file": "01-systems", "source": "menu"},
	{"route": "fleets", "file": "02-fleets", "source": "menu"},
	{"route": "domestic", "file": "03-domestic", "source": "menu"},
	{"route": "talent", "file": "04-talent", "source": "menu"},
	{"route": "diplomacy", "file": "05-diplomacy", "source": "menu"},
	{"route": "tech", "file": "06-tech", "source": "menu"},
	{"route": "records", "file": "07-records", "source": "menu"},
	{"route": "resource:funds", "file": "08-resource-funds", "source": "top"},
	{"route": "mail", "file": "09-mail", "source": "top"},
	{"route": "settings", "file": "10-settings", "source": "top"},
	{"route": "red_cliff_lock", "file": "11-red-cliff-lock", "source": "stage_lock"},
	{"route": "selection", "file": "12-selection", "source": "map_selection"},
]

var _failures: Array[String] = []
var _capture_hashes: Dictionary = {}

const ROUTE_SENTINELS := {
	"systems": "208 · 적벽 전야",
	"fleets": "현재 확인된 함대 없음",
	"domestic": "권역 통치 현황",
	"talent": "확인 가능한 인재 없음",
	"diplomacy": "현재 접촉 가능",
	"tech": "확인 가능한 기술 없음",
	"records": "현재 상황",
	"resource:funds": "자금",
	"mail": "새 서신 없음",
	"settings": "천하도 설정",
	"red_cliff_lock": "조조군 남하 완료",
	"selection": "수도 성역",
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var output_dir := _output_directory()
	print("HomeSubmenuCapture: 시작 — " + output_dir)
	var directory_error := DirAccess.make_dir_recursive_absolute(output_dir)
	if directory_error != OK:
		push_error("캡처 디렉터리를 만들 수 없음: %s (%s)" % [output_dir, directory_error])
		quit(2)
		return

	var packed: PackedScene = load(MAIN_SCENE)
	if packed == null:
		push_error("Main 장면을 읽을 수 없음: " + MAIN_SCENE)
		quit(2)
		return
	var main = packed.instantiate()
	root.add_child(main)
	print("HomeSubmenuCapture: 홈 장면 생성 완료 (paused=%s, speed=%s)" % [paused, Engine.time_scale])
	await _wait_frames(5)
	print("HomeSubmenuCapture: 초기 프레임 안정화 완료")

	if main.submenu == null or main.map_input_blocker == null:
		push_error("Main의 HomeSubmenu 또는 MapInputBlocker가 생성되지 않음")
		quit(1)
		return
	main.cam.position_smoothing_enabled = false
	main.cam.reset_smoothing()

	var preserved_camera: Dictionary = {}
	for route_case in ROUTE_CASES:
		var route_id := String(route_case.route)
		print("HomeSubmenuCapture: route=" + route_id)
		var before := _camera_state(main)
		if not _activate_route(main, route_case):
			_failures.append("%s: 실제 버튼/신호 라우트를 발화할 수 없음" % route_id)
			continue
		main.cam.reset_smoothing()
		await _wait_frames(SETTLE_FRAMES)

		_validate_route_state(main, route_id)
		_validate_route_content(main, route_id)
		if route_id == "systems":
			# 성역 버튼은 설계대로 형주에 초점을 옮긴다. 이후 하위 패널은 이
			# 카메라 상태를 보존해야 한다.
			preserved_camera = _camera_state(main)
		elif route_id != "overview" and not preserved_camera.is_empty():
			_validate_camera_unchanged(route_id, preserved_camera, _camera_state(main))

		# 일부 Windows headless 드라이버는 frame_post_draw 신호를 보내지 않는다.
		# 동기 강제 그리기로 동일 프레임을 확정해 자동 캡처가 멈추지 않게 한다.
		RenderingServer.force_draw(false)
		var path := output_dir.path_join(String(route_case.file) + ".png")
		var save_error := root.get_texture().get_image().save_png(path)
		if save_error != OK:
			_failures.append("%s: PNG 저장 실패 (%s)" % [route_id, save_error])
		else:
			var bytes := FileAccess.get_file_as_bytes(path)
			if bytes.is_empty():
				_failures.append("%s: 저장된 PNG가 비어 있음" % route_id)
			else:
				var hashing := HashingContext.new()
				hashing.start(HashingContext.HASH_SHA256)
				hashing.update(bytes)
				_capture_hashes[route_id] = hashing.finish().hex_encode()
			_print_capture_state(main, route_id, before, path)

	if _capture_hashes.size() == ROUTE_CASES.size():
		var unique_hashes := {}
		for value in _capture_hashes.values():
			unique_hashes[value] = true
		if unique_hashes.size() != ROUTE_CASES.size():
			_failures.append("서로 다른 라우트 중 동일한 캡처 이미지가 있음")

	if _failures.is_empty():
		print("HomeSubmenuCapture: %d개 라우트 검증/캡처 통과 — %s" % [ROUTE_CASES.size(), output_dir])
		quit(0)
		return
	for failure in _failures:
		print("실패: " + failure)
	print("HomeSubmenuCapture: %d개 실패" % _failures.size())
	quit(1)


func _activate_route(main, route_case: Dictionary) -> bool:
	var route_id := String(route_case.route)
	match String(route_case.source):
		"menu":
			if not main.menu_buttons.has(route_id):
				return false
			var menu_button: Button = main.menu_buttons[route_id]
			if menu_button.disabled:
				return false
			menu_button.pressed.emit()
			return true
		"top":
			if not main.top_route_buttons.has(route_id):
				return false
			var top_button: Button = main.top_route_buttons[route_id]
			if top_button.disabled:
				return false
			top_button.pressed.emit()
			return true
		"stage_lock":
			if main.stage_buttons.size() < 5:
				return false
			var stage_button: Button = main.stage_buttons[4]
			if stage_button.disabled:
				return false
			stage_button.pressed.emit()
			return true
		"map_selection":
			if main.projected_systems.is_empty():
				return false
			var selected: Dictionary = main.projected_systems[0].duplicate(true)
			main.map.object_selected.emit(selected)
			return true
	return false


func _validate_route_state(main, route_id: String) -> void:
	var submenu: Control = main.submenu
	var blocker: Control = main.map_input_blocker
	var safe: Rect2 = main.hud_safe_rect
	if route_id == "overview":
		if submenu.visible:
			_failures.append("overview: submenu가 닫히지 않음")
		if blocker.visible:
			_failures.append("overview: blocker가 닫히지 않음")
		if String(submenu.get("current_route")) != "":
			_failures.append("overview: current_route가 비워지지 않음")
		return

	if not submenu.visible:
		_failures.append("%s: submenu.visible=false" % route_id)
	if String(submenu.get("current_route")) != route_id:
		_failures.append("%s: current_route=%s" % [route_id, submenu.get("current_route")])
	if not blocker.visible:
		_failures.append("%s: MapInputBlocker가 보이지 않음" % route_id)
	if blocker.mouse_filter != Control.MOUSE_FILTER_STOP:
		_failures.append("%s: MapInputBlocker가 지도 입력을 차단하지 않음" % route_id)
	if not blocker.position.is_equal_approx(safe.position) or not blocker.size.is_equal_approx(safe.size):
		_failures.append("%s: blocker rect=%s, hud_safe_rect=%s" % [
			route_id, Rect2(blocker.position, blocker.size), safe])
	var panel_rect := Rect2(submenu.position, submenu.size)
	if not safe.encloses(panel_rect):
		_failures.append("%s: submenu가 hud_safe_rect 밖에 있음 panel=%s safe=%s" % [
			route_id, panel_rect, safe])
	if submenu.get_parent() != blocker.get_parent():
		_failures.append("%s: submenu와 blocker가 같은 UI 좌표계를 쓰지 않음" % route_id)
	elif submenu.get_index() <= blocker.get_index():
		_failures.append("%s: blocker가 submenu 위에 그려질 수 있음" % route_id)


func _validate_route_content(main, route_id: String) -> void:
	if not ROUTE_SENTINELS.has(route_id):
		return
	var visible_text := _visible_text(main.submenu)
	var sentinel := String(ROUTE_SENTINELS[route_id])
	if not visible_text.contains(sentinel):
		_failures.append("%s: 대표 문구 누락 (%s)" % [route_id, sentinel])


func _visible_text(node: Node) -> String:
	var parts: Array[String] = []
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return ""
	if node is Label:
		parts.append((node as Label).text)
	elif node is Button:
		parts.append((node as Button).text)
	for child in node.get_children():
		var child_text := _visible_text(child)
		if child_text != "":
			parts.append(child_text)
	return "\n".join(parts)


func _validate_camera_unchanged(route_id: String, expected: Dictionary, actual: Dictionary) -> void:
	var expected_position: Vector2 = expected.position
	var actual_position: Vector2 = actual.position
	var expected_zoom: Vector2 = expected.zoom
	var actual_zoom: Vector2 = actual.zoom
	if not expected_position.is_equal_approx(actual_position) or not expected_zoom.is_equal_approx(actual_zoom):
		_failures.append("%s: 패널을 여는 동안 카메라가 변경됨 expected=%s/%s actual=%s/%s" % [
			route_id, expected_position, expected_zoom, actual_position, actual_zoom])


func _camera_state(main) -> Dictionary:
	return {"position": main.cam.position, "zoom": main.cam.zoom}


func _print_capture_state(main, route_id: String, before: Dictionary, path: String) -> void:
	print("CAPTURE route=%s current=%s visible=%s blocker=%s safe=%s camera_before=%s/%s camera_after=%s/%s path=%s" % [
		route_id,
		String(main.submenu.get("current_route")),
		main.submenu.visible,
		main.map_input_blocker.visible,
		main.hud_safe_rect,
		before.position,
		before.zoom,
		main.cam.position,
		main.cam.zoom,
		path,
	])


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _output_directory() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			return argument.trim_prefix("--output=").replace("\\", "/")
	return OS.get_temp_dir().path_join("seonghanji-home-submenus")
