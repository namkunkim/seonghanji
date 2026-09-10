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
var _intelligence_enabled := false
var _viewer_faction_id := ""
var _contacts_by_target: Dictionary = {}
var _contacts_by_id: Dictionary = {}
var _fire_events: Array = []
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


func set_intelligence(viewer_faction_id: String, contacts: Array, fire_events: Array) -> void:
	_intelligence_enabled = true; _viewer_faction_id = viewer_faction_id; _contacts_by_target.clear(); _contacts_by_id.clear()
	for value in contacts:
		if value is Dictionary:
			var row: Dictionary = value.duplicate(true); _contacts_by_id[String(row.get("contact_id", ""))] = row
			if row.has("target_squadron_id"): _contacts_by_target[String(row.target_squadron_id)] = row
	_fire_events = fire_events.duplicate(true); queue_redraw()


func clear_intelligence() -> void:
	_intelligence_enabled = false; _contacts_by_target.clear(); _contacts_by_id.clear(); _fire_events.clear(); queue_redraw()


func reset_camera() -> void:
	_zoom = 1.0; _pan = Vector2.ZERO; queue_redraw()


func camera_state() -> Dictionary:
	return {"zoom": _zoom, "pan": _pan}


func intelligence_state_for_test() -> Dictionary:
	var visible_own: Array[String] = []
	for squad in _squadrons: visible_own.append(String(squad.get("id", "")))
	visible_own.sort()
	return {"viewer_faction_id": _viewer_faction_id, "own_squadron_ids": visible_own,
		"contacts": _contacts_by_id.values().duplicate(true), "tactical_events": _fire_events.duplicate(true)}


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
	var descriptor := _marker_descriptor(squadron_id)
	return battle_to_local(descriptor.get("position", [0, 0]))


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
		if not bool(_marker_descriptor(id).get("visible", false)): continue
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
	_draw_fire_events()
	_draw_opaque_contacts()
	for value in _squadrons:
		var squad: Dictionary = value; var id := String(squad.get("id", "")); var descriptor := _marker_descriptor(id)
		if not bool(descriptor.get("visible", false)): continue
		var faction := String(squad.get("faction_id", "")); var p := marker_local_position(id); var contact_state := String(descriptor.get("state", "friendly"))
		var color: Color = {"liu_bei": Color("63c58a"), "sun_quan": Color("df7d72"), "cao_cao": Color("69add5")}.get(faction, Color.WHITE)
		if contact_state in ["estimated", "lost"]:
			color = Color("e0b66d"); _draw_dashed_circle(p, MARKER_RADIUS + 5.0, color)
		else:
			draw_circle(p, MARKER_RADIUS + (4.0 if id == _selected_id else 0.0), color, false, 3.0); draw_circle(p, 7.0, color, true)
		var label := "추정 접촉 · 마지막 확인 T%d · 실제 위치와 다를 수 있음" % int(descriptor.get("last_seen_turn", 0)) if contact_state in ["estimated", "lost"] else (("◆ " if bool(squad.get("flagship", false)) else "") + String(squad.get("name", id)) + (" · 확인 접촉" if contact_state == "confirmed" else ""))
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


func _marker_descriptor(squadron_id: String) -> Dictionary:
	var squad: Dictionary = {}
	for value in _squadrons:
		if String(value.get("id", "")) == squadron_id: squad = value; break
	var live: Dictionary = _navigation.get(squadron_id, {})
	if not _intelligence_enabled or String(squad.get("faction_id", "")) == _viewer_faction_id:
		return {"visible": true, "state": "friendly", "position": live.get("position", [0, 0])}
	var contact: Dictionary = _contacts_by_target.get(squadron_id, {})
	var state := String(contact.get("state", "undetected"))
	if state in ["undetected", "unknown"] or contact.is_empty(): return {"visible": false, "state": "undetected"}
	return {"visible": true, "state": state, "position": contact.get("display_position", contact.get("last_known_position", [0, 0])), "last_seen_turn": contact.get("last_seen_turn", 0)}


func _draw_fire_events() -> void:
	for index in range(_fire_events.size()):
		var event: Dictionary = _fire_events[index]
		if String(event.get("event_type", "")) != "shot_authorized": continue
		var own_desc := _marker_descriptor(String(event.get("own_squadron_id", ""))); var modifier: Dictionary = event.get("formation_modifier", {})
		if not bool(own_desc.get("visible", false)): continue
		var from := battle_to_local(own_desc.position); var color := Color("f08a68")
		if String(event.get("own_role", "")) == "target":
			draw_circle(from, MARKER_RADIUS + 10.0, color, false, 3.0)
			var target_label := "피격 · 상세 비공개" if modifier.is_empty() else "피격 · %s · 방어 %s" % [_sector_text(String(modifier.incoming_sector)), _percent_text(int(modifier.own_total_defense_percent))]
			draw_string(get_theme_default_font(), from + Vector2(25, 18), target_label, HORIZONTAL_ALIGNMENT_LEFT, 230, 13, color)
			continue
		var contact: Dictionary = _contacts_by_id.get(String(event.get("contact_id", "")), {})
		var contact_position = contact.get("display_position")
		if contact_position == null: contact_position = contact.get("last_known_position")
		if not contact_position is Array: continue
		var to := battle_to_local(contact_position)
		draw_dashed_line(from, to, color, 3.0, 7.0)
		draw_string(get_theme_default_font(), (from + to) * 0.5 + Vector2(5, -6), "사격 %d · 표적 %s · 화력 %s" % [index + 1, _sector_text(String(modifier.get("target_sector", "indeterminate"))), _percent_text(int(modifier.get("own_fire_percent", 0)))], HORIZONTAL_ALIGNMENT_LEFT, 250, 13, color)


func _draw_opaque_contacts() -> void:
	for contact in _contacts_by_id.values():
		var position = contact.get("display_position")
		if position == null: position = contact.get("last_known_position")
		if not position is Array: continue
		var p := battle_to_local(position); var stale := bool(contact.get("stale", false)); var state := String(contact.get("state", "unknown")); var color := Color("9b8d70") if stale else (Color("f08a68") if state == "confirmed" else Color("e0b66d"))
		if state == "confirmed": draw_circle(p, MARKER_RADIUS + 4.0, color, false, 3.0); draw_circle(p, 7.0, color, true)
		else: _draw_dashed_circle(p, MARKER_RADIUS + 5.0, color)
		var label := "확인 접촉" if state == "confirmed" else ("%s · 마지막 확인 T%d · 실제 위치와 다를 수 있음" % ["소실 접촉(stale)" if stale else "추정 접촉", int(contact.get("last_seen_turn", 0))])
		draw_string(get_theme_default_font(), p + Vector2(24, -9), label, HORIZONTAL_ALIGNMENT_LEFT, 390, 14, color)


func _draw_dashed_circle(center: Vector2, radius: float, color: Color) -> void:
	for index in range(16):
		if index % 2 == 0: continue
		var a := TAU * float(index) / 16.0; var b := TAU * float(index + 1) / 16.0
		draw_line(center + Vector2(cos(a), sin(a)) * radius, center + Vector2(cos(b), sin(b)) * radius, color, 3.0)


func _sector_text(sector: String) -> String:
	return {"front":"정면", "flank":"측면", "rear":"후면", "indeterminate":"방향 불명(동일 좌표)"}.get(sector, "방향 불명")


func _percent_text(value: int) -> String:
	return "%+d%%" % value
