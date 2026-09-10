class_name RedCliffTacticalMap
extends Control

## DEMO-RC-G4-02 전술 지도. 전장 좌표와 화면 좌표 변환/입력만 담당한다.
signal squadron_selected(squadron_id: String)
signal waypoint_requested(point: Array)
signal interaction_rejected(message: String)

enum Mode { SELECT, ADD_WAYPOINT, PAN }

const MARKER_RADIUS := 18.0
const DRAG_THRESHOLD := 6.0

var _bounds := Rect2(0, 0, 1600, 900)
var _squadrons: Array = []
var _navigation: Dictionary = {}
var _editable_ids: Array[String] = []
var _selected_id := ""
var _order: Dictionary = {}
var _preview: Dictionary = {}
var _mode := Mode.SELECT
var _zoom := 1.0
var _pan := Vector2.ZERO
var _pressed := false
var _press_position := Vector2.ZERO
var _last_position := Vector2.ZERO
var _dragged := false


func _ready() -> void:
	custom_minimum_size = Vector2(560, 390)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	queue_redraw()


func configure(bounds: Array, squadrons: Array, navigation: Dictionary) -> void:
	if bounds.size() == 4:
		_bounds = Rect2(float(bounds[0]), float(bounds[1]), maxf(1.0, float(bounds[2])), maxf(1.0, float(bounds[3])))
	_squadrons = squadrons.duplicate(true)
	_navigation = navigation.duplicate(true)
	queue_redraw()


func set_interaction(editable_ids: Array, selected_id: String, mode: int) -> void:
	_editable_ids.clear()
	for value in editable_ids: _editable_ids.append(String(value))
	_selected_id = selected_id
	_mode = clampi(mode, Mode.SELECT, Mode.PAN)
	queue_redraw()


func set_route(order: Dictionary, preview: Dictionary) -> void:
	_order = order.duplicate(true)
	_preview = preview.duplicate(true)
	queue_redraw()


func reset_camera() -> void:
	_zoom = 1.0; _pan = Vector2.ZERO; queue_redraw()


func camera_state() -> Dictionary:
	return {"zoom": _zoom, "pan": _pan}


func content_rect() -> Rect2:
	var ratio := minf(size.x / _bounds.size.x, size.y / _bounds.size.y)
	var fitted := _bounds.size * ratio
	return Rect2((size - fitted) * 0.5, fitted)


func battle_to_local(point) -> Vector2:
	var p := Vector2(float(point[0]), float(point[1])) if point is Array else Vector2(point)
	var rect := content_rect()
	var scale := rect.size.x / _bounds.size.x * _zoom
	return rect.get_center() + (p - _bounds.get_center()) * scale + _pan


func local_to_battle(point: Vector2) -> Dictionary:
	var rect := content_rect()
	if point.x < rect.position.x or point.y < rect.position.y or point.x > rect.end.x or point.y > rect.end.y:
		return {"ok": false, "errors": ["전술 지도 바깥 여백입니다."]}
	var scale := rect.size.x / _bounds.size.x * _zoom
	var battle_point := _bounds.get_center() + (point - rect.get_center() - _pan) / scale
	if battle_point.x < _bounds.position.x - 0.001 or battle_point.y < _bounds.position.y - 0.001 or battle_point.x > _bounds.end.x + 0.001 or battle_point.y > _bounds.end.y + 0.001:
		return {"ok": false, "errors": ["전장 경계 밖 좌표입니다."]}
	return {"ok": true, "errors": [], "point": [battle_point.x, battle_point.y]}


func set_camera_for_test(zoom_value: float, pan_value: Vector2) -> void:
	_zoom = clampf(zoom_value, 1.0, 4.0); _pan = pan_value; queue_redraw()


func marker_local_position(squadron_id: String) -> Vector2:
	var row: Dictionary = _navigation.get(squadron_id, {})
	return battle_to_local(row.get("position", [0, 0]))


func handle_click_for_test(point: Vector2, double_click := false) -> void:
	_activate_click(point, double_click)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
		var before := local_to_battle(event.position)
		_zoom = clampf(_zoom * (1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 1.0, 4.0)
		if bool(before.get("ok", false)):
			var after := battle_to_local(before.point); _pan += event.position - after
		queue_redraw(); accept_event(); return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true; _dragged = false; _press_position = event.position; _last_position = event.position
		else:
			if not _pressed: return
			_pressed = false
			if not _dragged: _activate_click(event.position, event.double_click)
		accept_event(); return
	if event is InputEventMouseMotion and _pressed:
		if event.position.distance_to(_press_position) >= DRAG_THRESHOLD: _dragged = true
		if _dragged and _mode == Mode.PAN:
			_pan += event.position - _last_position; queue_redraw()
		_last_position = event.position; accept_event()


func _activate_click(point: Vector2, double_click: bool) -> void:
	var marker_id := _marker_at(point)
	if not marker_id.is_empty():
		if _editable_ids.has(marker_id): squadron_selected.emit(marker_id)
		else: interaction_rejected.emit("현재 단계에서 직접 지휘할 수 없는 전대입니다.")
		return
	if _mode != Mode.ADD_WAYPOINT: return
	var converted := local_to_battle(point)
	if not bool(converted.get("ok", false)):
		interaction_rejected.emit(" · ".join(converted.get("errors", []))); return
	# OS double-click은 두 번째 클릭 이벤트이므로 한 경유점만 요청한다.
	if double_click: return
	waypoint_requested.emit(converted.point)


func _marker_at(point: Vector2) -> String:
	for value in _squadrons:
		var id := String(value.get("id", ""))
		if point.distance_to(marker_local_position(id)) <= MARKER_RADIUS + 6.0: return id
	return ""


func _draw() -> void:
	var rect := content_rect()
	draw_rect(rect, Color("071923"), true)
	draw_rect(rect, Color("477387"), false, 2.0)
	for index in range(1, 8):
		var x := rect.position.x + rect.size.x * float(index) / 8.0
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color(0.16, 0.31, 0.38, 0.45), 1.0)
	for index in range(1, 5):
		var y := rect.position.y + rect.size.y * float(index) / 5.0
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(0.16, 0.31, 0.38, 0.45), 1.0)
	_draw_route()
	for value in _squadrons:
		var squad: Dictionary = value; var id := String(squad.get("id", "")); var faction := String(squad.get("faction_id", "")); var p := marker_local_position(id)
		var color: Color = {"liu_bei": Color("63c58a"), "sun_quan": Color("df7d72"), "cao_cao": Color("69add5")}.get(faction, Color.WHITE)
		draw_circle(p, MARKER_RADIUS + (4.0 if id == _selected_id else 0.0), color, false, 3.0)
		draw_circle(p, 7.0, color, true)
		var label := ("◆ " if bool(squad.get("flagship", false)) else "") + String(squad.get("name", id))
		draw_string(get_theme_default_font(), p + Vector2(24, -9), label, HORIZONTAL_ALIGNMENT_LEFT, 150, 14, color)


func _draw_route() -> void:
	if String(_order.get("action", "")) != "move" or _selected_id.is_empty(): return
	var nav: Dictionary = _navigation.get(_selected_id, {}); var cursor := marker_local_position(_selected_id)
	var predicted = _preview.get("predicted_position", nav.get("position", [0, 0]))
	var predicted_local := battle_to_local(predicted); var reached := true
	for index in range(_order.get("waypoints", []).size()):
		var target := battle_to_local(_order.waypoints[index])
		if reached and not bool(_preview.get("path_complete", true)):
			var segment := target - cursor
			if segment.length() > 0.0 and cursor.distance_to(predicted_local) < segment.length() - 0.01:
				draw_line(cursor, predicted_local, Color("70e0a1"), 4.0)
				draw_dashed_line(predicted_local, target, Color("e8a766"), 3.0, 8.0); reached = false
			else: draw_line(cursor, target, Color("70e0a1"), 4.0)
		else: draw_dashed_line(cursor, target, Color("e8a766"), 3.0, 8.0)
		draw_circle(target, 12, Color("f0d17b"), true)
		draw_string(get_theme_default_font(), target + Vector2(-4, 5), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("071018"))
		cursor = target
