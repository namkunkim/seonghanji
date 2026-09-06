extends SceneTree

## 208 홈 지도 시맨틱 줌 회귀 시험.
##
## 화면 픽셀 비교 대신 세 층을 함께 고정한다.
## 1) HomeMapSnapshot의 단계별 데이터 노출,
## 2) GalaxyMap의 1~5 줌/카메라 계약,
## 3) Main이 조립한 기본 적벽 카드의 실제 비활성 상태.

const Snapshot := preload("res://app/home_map_snapshot.gd")
const GalaxyMapScript := preload("res://scripts/GalaxyMap.gd")

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


func _near(got: float, wanted: float, label: String, epsilon := 0.001) -> void:
	_ok(absf(got - wanted) <= epsilon,
		"%s — 기대 %.3f, 실제 %.3f" % [label, wanted, got])


func _by_name(rows: Array, wanted: String) -> Dictionary:
	for row in rows:
		if String(row.get("name", "")) == wanted:
			return row
	return {}


func _has_names(rows: Array, wanted: Array[String]) -> bool:
	for name in wanted:
		if _by_name(rows, name).is_empty():
			return false
	return true


func _lacks_names(rows: Array, unwanted: Array[String]) -> bool:
	for name in unwanted:
		if not _by_name(rows, name).is_empty():
			return false
	return true


func _project_point(raw: Array) -> Array:
	return [float(raw[0]) / 37312.0 * 3200.0,
		float(raw[1]) / 30000.0 * 1800.0]


func _project_rows(rows: Array) -> Array:
	var out: Array = []
	for source in rows:
		var row: Dictionary = source.duplicate(true)
		row["position"] = _project_point(source.get("position", [0.0, 0.0]))
		out.append(row)
	return out


func _project_system_rows(rows: Array) -> Array:
	var out: Array = []
	for source in rows:
		out.append({
			"id": String(source.get("id", "")),
			"name": String(source.get("name", "")),
			"pos": _project_point(source.get("position", [0.0, 0.0])),
			"canonical_position": source.get("position", []).duplicate(true),
			"faction": "neutral",
			"type": "strategic",
		})
	return out


func _expected_overview_zoom(safe_rect: Rect2, world_size: Vector2) -> float:
	# 가장자리 픽셀이 잘리지 않도록 production의 3% overview gutter를 포함한다.
	return minf(safe_rect.size.x / world_size.x, safe_rect.size.y / world_size.y) * 0.97


func _layout_safe_rect(viewport_size: Vector2) -> Rect2:
	var top_height := clampf(viewport_size.y * 0.078, 58.0, 70.0)
	var bottom_height := clampf(viewport_size.y * 0.225, 174.0, 210.0)
	var left_width := clampf(viewport_size.x * 0.115, 168.0, 184.0)
	var right_width := clampf(viewport_size.x * 0.188, 272.0, 302.0)
	return Rect2(left_width, top_height,
		viewport_size.x - left_width - right_width,
		viewport_size.y - top_height - bottom_height)


func _ready_conditions() -> Dictionary:
	return {
		"cao_southward_complete": true,
		"sun_quan_independent": true,
		"liu_bei_hostile_to_cao": true,
		"sun_liu_military_pact": true,
		"yangtze_defense_line": true,
	}


## G-10 이후 적벽 표식은 runtime fixture가 아니라 Campaign replay 파생 전투만
## 투영한다. 이 helper는 Event 03/04/06/07의 정본 결과를 접어 pending을 만들고,
## snapshot 투영용 최소 active 상태만 명시적으로 만든다.
func _ready_red_cliff_campaign() -> Campaign:
	var ready_campaign := Campaign.scenario_03(GameData.load_all(), 208)
	ready_campaign.record_scn03_event_outcome(Campaign.SCN03_EVENT03,
		{"cao_southward_complete": true})
	ready_campaign.record_scn03_event_outcome(Campaign.SCN03_EVENT04,
		{"sun_quan_independent": true})
	ready_campaign.record_scn03_event_outcome(Campaign.SCN03_EVENT06,
		{"liu_bei_hostile_to_cao": true})
	ready_campaign.record_scn03_event_outcome(Campaign.SCN03_EVENT07, {
		"sun_liu_military_pact": true, "yangtze_defense_line": true,
	})
	assert(ready_campaign.active_battles.size() == 1,
		"ready fixture must derive the canonical Red-Cliffs pending battle")
	ready_campaign.active_battles[0].activate_red_cliff([], [], {}, "",
		ready_campaign.world.clock.tick)
	return ready_campaign


func _function_source(path: String, function_name: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var source := file.get_as_text()
	var start := source.find("func " + function_name + "(")
	if start < 0:
		return ""
	var finish := source.find("\nfunc ", start + 1)
	return source.substr(start) if finish < 0 else source.substr(start, finish - start)


func _world_to_screen(map, camera: Camera2D, world_point: Vector2) -> Vector2:
	var viewport_center: Vector2 = map.get_viewport().get_visible_rect().size * 0.5
	return viewport_center + (world_point - camera.position) * camera.zoom.x


func _rect_contains_inclusive(rect: Rect2, point: Vector2, epsilon := 0.01) -> bool:
	return point.x >= rect.position.x - epsilon and point.x <= rect.end.x + epsilon \
		and point.y >= rect.position.y - epsilon and point.y <= rect.end.y + epsilon


func _assert_world_edges_reach_safe_rect(map, camera: Camera2D,
		safe_rect: Rect2, zoom_value: float, prefix: String) -> void:
	camera.zoom = Vector2(zoom_value, zoom_value)
	camera.position = Vector2(-99999.0, -99999.0)
	map._clamp_camera_position()
	var top_left := _world_to_screen(map, camera, Vector2.ZERO)
	_near(top_left.x, safe_rect.position.x, prefix + " 좌측 월드 끝")
	_near(top_left.y, safe_rect.position.y, prefix + " 상단 월드 끝")
	camera.position = Vector2(99999.0, 99999.0)
	map._clamp_camera_position()
	var bottom_right := _world_to_screen(map, camera, map.world_size)
	_near(bottom_right.x, safe_rect.end.x, prefix + " 우측 월드 끝")
	_near(bottom_right.y, safe_rect.end.y, prefix + " 하단 월드 끝")


func _init() -> void:
	var campaign := Campaign.scenario_03(GameData.load_all(), 208)
	var state = Snapshot.from_campaign(campaign, 208)
	var solar_names: Array[String] = ["구지", "형혹", "태음"]

	# 정본 규모는 줌 표시용 필터링과 무관하게 유지돼야 한다.
	_eq(state.canonical_systems().size(), 19, "208 정본 성계 19개")
	_eq(state.canonical_regions().size(), 45, "208 정본 권역 45개")
	_eq(state.canonical_routes().size(), 37, "208 정본 항로 37개")

	# UI의 Z0~Z4 계약: 태양계 세부 천체는 Z2부터 보인다.
	_ok(_lacks_names(state.visible_bodies(0), solar_names),
		"Z0에는 구지·형혹·태음 미표시")
	_ok(_lacks_names(state.visible_bodies(1), solar_names),
		"Z1에는 구지·형혹·태음 미표시")
	for zoom_level in [2, 3, 4]:
		_ok(_has_names(state.visible_bodies(zoom_level), solar_names),
			"Z%d에는 구지·형혹·태음 표시" % zoom_level)
	_ok(not _by_name(state.canonical_systems(), "형주").is_empty(),
		"Z1 진입 표적인 형주 성역이 정본에 존재")
	_ok(not _by_name(state.jingzhou_regions(), "태양계권").is_empty(),
		"Z1 세부 표적인 태양계권이 형주에 존재")
	_eq(state.presentation().get("solar_detail_min_zoom"), 2,
		"태양계 천체 최소 단계는 Z2")

	# 미래 사건은 명시적인 runtime 사실과 다섯 조건이 모두 있어야 활성화된다.
	_eq(state.active_battles(), [], "기본 시작 active_battles 없음")
	var conditions_only = Snapshot.from_campaign(campaign, 208, {
		"red_cliff_conditions": _ready_conditions(),
	})
	_eq(conditions_only.active_battles(), [], "조건만으로 적벽 marker 활성화 금지")
	var battle_only = Snapshot.from_campaign(campaign, 208, {
		"active_battles": [{"id": "BATTLE-RED-CLIFF", "status": "active"}],
	})
	_eq(battle_only.active_battles(), [], "활성 전투 입력만으로 적벽 marker 활성화 금지")
	var ready = Snapshot.from_campaign(_ready_red_cliff_campaign(), 208)
	_eq(ready.active_battles().size(), 1, "ready snapshot에서만 적벽 marker 활성")
	_eq(ready.active_battles()[0].get("anchor_body_id"), "BODY-RGN-04-01",
		"활성 적벽 marker는 구지에 고정")

	# 208 사산조는 정보 행으로는 남아도 현재 지도 marker 대상은 아니다.
	var sassanid := _by_name(state.external_powers(), "사산조")
	_eq(sassanid.get("status"), "future", "208 사산조 상태는 future")
	_ok(not bool(sassanid.get("visible_as_current", false)),
		"208 사산조는 current marker 대상이 아님")
	var gateway_source := _function_source(
		"res://scripts/GalaxyMap.gd", "_draw_external_gateways")
	_ok(gateway_source.contains("future") and gateway_source.contains("continue"),
		"GalaxyMap은 future 외부 세력을 marker 그리기 전에 제외")
	_ok(gateway_source.contains("_clamp_world_point_to_safe_screen") \
		and gateway_source.contains("_clamp_label_baseline_to_safe_screen") \
		and gateway_source.contains("_draw_gateway_label"),
		"외부 관문 marker와 label은 safe clamp 경로 사용")
	var draw_label_source := _function_source("res://scripts/GalaxyMap.gd", "_draw_label")
	_ok(draw_label_source.contains("_clamp_label_baseline_to_safe_screen") \
		and draw_label_source.contains("semantic_level >= 2") \
		and draw_label_source.contains("/ canvas_scale"),
		"일반 label은 safe clamp와 확대 단계 화면 크기 역보정 사용")
	var faction_label_source := _function_source(
		"res://scripts/GalaxyMap.gd", "_draw_overview_faction_label")
	_ok(faction_label_source.contains("_clamp_label_baseline_to_safe_screen"),
		"세력 label은 모든 줌 단계에서 safe clamp")
	var marker_source := _function_source(
		"res://scripts/GalaxyMap.gd", "_draw_contested_arrows")
	_ok(marker_source.contains("BATTLE-RED-CLIFF"),
		"적벽 marker는 임의 전투가 아니라 ready 적벽 ID만으로 활성")

	# GalaxyMap의 시맨틱 단계는 카메라 배율 증가 방향으로 1→5가 되어야 한다.
	var map = GalaxyMapScript.new()
	var camera := Camera2D.new()
	map.add_child(camera)
	get_root().add_child(map)
	await process_frame
	map.camera = camera
	var red_cliff_modes := ["overview", "rally", "forecast", "approach", "battle"]
	for mode_index in range(red_cliff_modes.size()):
		map.semantic_level = mode_index + 1
		_eq(map._red_cliff_presentation_mode(), red_cliff_modes[mode_index],
			"적벽 표현 단계 %d 계약" % (mode_index + 1))
	var zoom_samples := [0.50, 0.65, 0.90, 1.13, 1.45, 1.80]
	var expected_levels := [1, 2, 3, 4, 5, 5]
	var previous_level := 0
	for index in range(zoom_samples.size()):
		var level: int = map._semantic_level_for_zoom(zoom_samples[index])
		_eq(level, expected_levels[index], "배율 %.2f의 시맨틱 단계" % zoom_samples[index])
		_ok(level >= previous_level, "카메라 배율 증가 시 단계가 역행하지 않음")
		previous_level = level
	_eq(map._semantic_level_for_zoom(map.MIN_ZOOM), 1, "최소 배율은 1단계")
	_eq(map._semantic_level_for_zoom(map.MAX_ZOOM), 5, "최대 배율은 5단계")
	camera.make_current()
	camera.zoom = Vector2.ONE
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	wheel_up.position = Vector2(742.0, 380.0)
	map._unhandled_input(wheel_up)
	_ok(camera.zoom.x > 1.0, "휠 위는 5단계 방향으로 확대")
	camera.zoom = Vector2.ONE
	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	wheel_down.position = Vector2(742.0, 380.0)
	map._unhandled_input(wheel_down)
	_ok(camera.zoom.x < 1.0, "휠 아래는 1단계 방향으로 축소")

	# focus_world는 중앙 영역에서 목표를 HUD 안전 사각형 중앙에 놓는다.
	var safe_rect := Rect2(184.0, 70.0, 1116.0, 620.0)
	map.set_input_safe_rect(safe_rect)
	_eq(map.input_safe_rect, safe_rect, "HUD safe rect 전달")

	# Z0 fit은 HUD가 남긴 실제 사각형과 월드 비율 중 작은 쪽이다.
	var fit_cases := [
		[Vector2(1600.0, 900.0), safe_rect],
		[Vector2(1280.0, 720.0), _layout_safe_rect(Vector2(1280.0, 720.0))],
		[Vector2(1920.0, 1080.0), _layout_safe_rect(Vector2(1920.0, 1080.0))],
	]
	for fit_case in fit_cases:
		var fit_rect: Rect2 = fit_case[1]
		var expected_fit := _expected_overview_zoom(fit_rect, map.world_size)
		map.set_input_safe_rect(fit_rect)
		_near(map.overview_zoom, expected_fit,
			"%dx%d overview fit ≈ min(safe/world)" % [
				int(fit_case[0].x), int(fit_case[0].y)], 0.001)
	map.set_input_safe_rect(safe_rect)

	# 표준 Z0 한 화면에서 월드 네 모서리와 정본 19개 성계가 모두 safe rect 안이다.
	var overview_zoom: float = map.overview_zoom
	camera.zoom = Vector2.ONE * overview_zoom
	var overview_viewport_center := map.get_viewport().get_visible_rect().size * 0.5
	camera.position = map.world_size * 0.5 \
		- (safe_rect.get_center() - overview_viewport_center) / overview_zoom
	await process_frame
	var overview_corners := [Vector2.ZERO, Vector2(map.world_size.x, 0.0),
		map.world_size, Vector2(0.0, map.world_size.y)]
	for corner_index in range(overview_corners.size()):
		_ok(_rect_contains_inclusive(safe_rect,
			_world_to_screen(map, camera, overview_corners[corner_index])),
			"Z0 월드 모서리 %d가 safe rect 내부" % corner_index)
	var overview_systems := _project_system_rows(state.canonical_systems())
	_eq(overview_systems.size(), 19, "Z0 정본 성계 node 19개")
	for system in overview_systems:
		var node_pos := Vector2(float(system.pos[0]), float(system.pos[1]))
		_ok(_rect_contains_inclusive(safe_rect, _world_to_screen(map, camera, node_pos)),
			"Z0 성계 node가 safe rect 내부: " + String(system.name))
	var jiaozhou := _by_name(overview_systems, "교주")
	_eq(jiaozhou.get("id"), "SYS-17", "Z0에 교주 SYS-17 포함")
	_ok(not jiaozhou.is_empty() and _rect_contains_inclusive(safe_rect, _world_to_screen(map, camera,
		Vector2(float(jiaozhou.pos[0]), float(jiaozhou.pos[1])))),
		"교주 node가 Z0 safe rect 내부")

	# 화면용 label 보정과 선택은 정본 node 좌표를 바꾸지 않는다.
	map.setup(camera, overview_systems, [], {}, [], [], [], [], [])
	map.semantic_level = 1
	var canonical_before: Array = jiaozhou.get("canonical_position", []).duplicate(true)
	var projected_before: Array = jiaozhou.get("pos", []).duplicate(true)
	map._clamp_label_baseline_to_safe_screen("교주", Vector2(projected_before[0],
		projected_before[1]), 25, 52.0)
	_eq(jiaozhou.get("canonical_position"), canonical_before,
		"label safe clamp 후 교주 정본 좌표 유지")
	_eq(jiaozhou.get("pos"), projected_before,
		"label safe clamp 후 교주 선택 좌표 유지")
	var selected_rows: Array = []
	map.object_selected.connect(func(data: Dictionary): selected_rows.append(data.duplicate(true)),
		CONNECT_ONE_SHOT)
	map._try_select(_world_to_screen(map, camera,
		Vector2(float(projected_before[0]), float(projected_before[1]))))
	_eq(selected_rows.size(), 1, "Z0 교주 node 선택 성공")
	if selected_rows.size() == 1:
		_eq(selected_rows[0].get("id"), "SYS-17", "Z0 선택 결과는 교주")
		_eq(selected_rows[0].get("canonical_position"), canonical_before,
			"Z0 선택 결과의 정본 좌표 유지")

	# 관문 점/일반·세력 label의 clamp helper는 특정 단계에만 묶이지 않는다.
	for helper_index in range(5):
		map.semantic_level = helper_index + 1
		camera.zoom = Vector2.ONE * float(zoom_samples[helper_index])
		camera.position = map.world_size * 0.5
		await process_frame
		var clamped_gateway: Vector2 = map._clamp_world_point_to_safe_screen(
			Vector2(-9999.0, -9999.0), 30.0)
		var gateway_screen: Vector2 = map.get_canvas_transform() * clamped_gateway
		_near(gateway_screen.x, safe_rect.position.x + 30.0,
			"%d단계 외부 관문 safe X" % (helper_index + 1))
		_near(gateway_screen.y, safe_rect.position.y + 30.0,
			"%d단계 외부 관문 safe Y" % (helper_index + 1))
		var clamped_faction: Vector2 = map._clamp_label_baseline_to_safe_screen(
			"공손강", Vector2(-9999.0, -9999.0), 30, 56.0)
		var faction_screen: Vector2 = map.get_canvas_transform() * clamped_faction
		_ok(safe_rect.has_point(faction_screen),
			"%d단계 세력 label baseline이 safe rect 내부" % (helper_index + 1))
	var focus_target := Vector2(1600.0, 500.0)
	map.focus_world(focus_target, 1.0)
	var viewport_center := map.get_viewport().get_visible_rect().size * 0.5
	var target_screen := viewport_center + \
		(focus_target - camera.position) * camera.zoom.x
	_near(target_screen.x, safe_rect.get_center().x, "focus_world 안전영역 중심 X")
	_near(target_screen.y, safe_rect.get_center().y, "focus_world 안전영역 중심 Y")

	# 모든 시맨틱 줌에서 월드 네 끝을 실제 지도 safe rect 경계까지 볼 수 있다.
	for edge_zoom in zoom_samples:
		_assert_world_edges_reach_safe_rect(map, camera, safe_rect, edge_zoom,
			"배율 %.2f" % edge_zoom)

	# focus_world가 배율을 바꾼 뒤에도 네 끝은 같은 safe rect 경계에 정렬된다.
	for focus_zoom in zoom_samples:
		map.focus_world(Vector2.ZERO, focus_zoom)
		var focused_top_left := _world_to_screen(map, camera, Vector2.ZERO)
		_near(focused_top_left.x, safe_rect.position.x,
			"focus %.2f 좌측 월드 끝" % focus_zoom)
		_near(focused_top_left.y, safe_rect.position.y,
			"focus %.2f 상단 월드 끝" % focus_zoom)
		map.focus_world(map.world_size, focus_zoom)
		var focused_bottom_right := _world_to_screen(map, camera, map.world_size)
		_near(focused_bottom_right.x, safe_rect.end.x,
			"focus %.2f 우측 월드 끝" % focus_zoom)
		_near(focused_bottom_right.y, safe_rect.end.y,
			"focus %.2f 하단 월드 끝" % focus_zoom)

	# 과도한 입력도 배율 경계에서 safe rect 정렬 계약을 유지한다.
	map.focus_world(Vector2(-9999.0, -9999.0), 99.0)
	_near(camera.zoom.x, map.MAX_ZOOM, "focus_world 최대 배율 clamp")
	var max_zoom_top_left := _world_to_screen(map, camera, Vector2.ZERO)
	_near(max_zoom_top_left.x, safe_rect.position.x, "최대 배율 좌측 safe 경계")
	_near(max_zoom_top_left.y, safe_rect.position.y, "최대 배율 상단 safe 경계")
	map.focus_world(Vector2(9999.0, 9999.0), -99.0)
	_near(camera.zoom.x, map.overview_zoom, "focus_world 최소 배율은 동적 overview fit")
	var min_zoom_bottom_right := _world_to_screen(map, camera, map.world_size)
	_ok(_rect_contains_inclusive(safe_rect, min_zoom_bottom_right),
		"동적 최소 배율에서 우하단 월드 모서리가 safe rect 내부")

	# 실제 조립 입력에서도 기본/ready marker 데이터가 정확히 갈린다.
	map.setup(camera, [], [], {}, state.canonical_regions(),
		state.canonical_routes(), _project_rows(state.visible_bodies(2)),
		state.active_battles(), state.external_powers())
	_eq(map.active_battles, [], "GalaxyMap 기본 적벽 marker 입력 없음")
	map.setup(camera, [], [], {}, state.canonical_regions(),
		state.canonical_routes(), _project_rows(ready.visible_bodies(2)),
		ready.active_battles(), ready.external_powers())
	_eq(map.active_battles.size(), 1, "GalaxyMap ready 적벽 marker 입력 1개")

	# Main 장면을 실제로 한 번 조립해 기본 5번 적벽 카드의 접근 상태를 확인한다.
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var main = main_scene.instantiate()
	get_root().add_child(main)
	await process_frame
	await process_frame
	_eq(main.stage_buttons.size(), 5, "홈 지도 단계 카드 5개")
	if main.stage_buttons.size() == 5:
		_ok(not main.stage_buttons[4].disabled, "기본 적벽 잠금 카드도 클릭 가능")
		_eq(String(main.stage_buttons[4].get_meta("route_id", "")), "red_cliff_lock",
			"기본 적벽 카드는 잠금 안내 route")
		main.stage_buttons[4].pressed.emit()
		await process_frame
		_eq(String(main.submenu.get("current_route")), "red_cliff_lock",
			"기본 적벽 클릭 시 잠금 패널")
		main.submenu.call("close_panel")
		_ok(not main.stage_buttons[0].disabled and not main.stage_buttons[3].disabled,
			"1~4단계 카드는 활성")
		main.map.set_input_safe_rect(safe_rect)
		main.stage_buttons[0].pressed.emit()
		await process_frame
		_near(main.cam.zoom.x, main.map.overview_zoom,
			"1단계 카드는 고정 0.50이 아닌 동적 overview fit 사용")
		_eq(main.map._semantic_level_for_zoom(main.cam.zoom.x), 1,
			"동적 overview fit은 시맨틱 1단계")
		var stage_one_corners := [Vector2.ZERO,
			Vector2(main.map.world_size.x, 0.0), main.map.world_size,
			Vector2(0.0, main.map.world_size.y)]
		for stage_corner in stage_one_corners:
			_ok(_rect_contains_inclusive(safe_rect,
				_world_to_screen(main.map, main.cam, stage_corner)),
				"1단계 focus 후 월드 모서리가 safe rect 내부")
		var wheel_level := 1
		var wheel_steps := 0
		while wheel_level < 2 and wheel_steps < 8:
			var before_wheel_zoom: float = main.cam.zoom.x
			var overview_wheel := InputEventMouseButton.new()
			overview_wheel.button_index = MOUSE_BUTTON_WHEEL_UP
			overview_wheel.pressed = true
			overview_wheel.position = safe_rect.get_center()
			main.map._unhandled_input(overview_wheel)
			_ok(main.cam.zoom.x > before_wheel_zoom,
				"Z0 휠 위 입력은 2+단계 방향으로 배율 증가")
			wheel_level = main.map._semantic_level_for_zoom(main.cam.zoom.x)
			wheel_steps += 1
		_ok(wheel_level >= 2, "Z0에서 휠 위 입력을 계속하면 2+단계 진입")

		# A larger viewport raises the dynamic semantic-2 threshold. If the
		# previous zoom now falls into level 1, resize must restore exact overview.
		main.map.set_input_safe_rect(Rect2(168.0,58.0,840.0,480.0))
		main.cam.zoom = Vector2(0.56,0.56)
		main.map.semantic_level = 2
		main.map.set_input_safe_rect(Rect2(184.0,70.0,1400.0,800.0))
		_near(main.cam.zoom.x, main.map.overview_zoom,
			"해상도 확대 후 새 1단계 임계값이면 overview fit 복귀")
		_eq(main.map.semantic_level, 1, "해상도 확대 후 카드와 카메라 단계 일치")

	# 실제 UI 조립에서도 unrelated battle은 적벽 카드를 열지 않고 ready만 연다.
	var unrelated = Snapshot.from_campaign(campaign, 208, {
		"active_battles": [{"id": "BATTLE-UNRELATED", "status": "active"}],
	})
	main.home_snapshot = unrelated
	main.home_state = unrelated.snapshot()
	var galaxy: Dictionary = main._load_json("res://data/galaxy.json")
	var projected_systems: Array = main._project_systems(main.home_state, campaign)
	if get_root().size_changed.is_connected(main._layout_ui):
		get_root().size_changed.disconnect(main._layout_ui)
	main._build_ui(galaxy, projected_systems)
	_eq(main.stage_buttons.size(), 5, "unrelated battle UI도 단계 카드 5개")
	if main.stage_buttons.size() == 5:
		_ok(not main.stage_buttons[4].disabled, "unrelated battle에서도 적벽 잠금 카드 클릭 가능")
		_eq(String(main.stage_buttons[4].get_meta("route_id", "")), "red_cliff_lock",
			"unrelated battle은 적벽 잠금 route 유지")
	main.home_snapshot = ready
	main.home_state = ready.snapshot()
	if get_root().size_changed.is_connected(main._layout_ui):
		get_root().size_changed.disconnect(main._layout_ui)
	main._build_ui(galaxy, projected_systems)
	_eq(main.stage_buttons.size(), 5, "ready 적벽 UI도 단계 카드 5개")
	if main.stage_buttons.size() == 5:
		_ok(not main.stage_buttons[4].disabled, "ready 적벽 카드는 활성")
		_eq(String(main.stage_buttons[4].get_meta("route_id", "")), "stage:5",
			"ready 적벽 카드는 전투 단계 route")

	print("HomeMapZoom: %d 통과 / %d 실패" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
