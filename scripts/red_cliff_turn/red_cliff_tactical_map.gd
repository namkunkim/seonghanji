class_name RedCliffTacticalMap
extends Control

## DEMO-RC-G4-02 전술 지도. 전장 좌표와 화면 좌표 변환/입력만 담당한다.
signal squadron_selected(squadron_id: String)
signal contact_selected(contact_id: String)
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
var _selected_contact_id := ""
var _fire_events: Array = []
var _terrain_zones: Array = []
var _fast_craft_supply_sources: Array = []
var _fast_craft_return_statuses: Array = []
var _fast_craft_recovery: Dictionary = {}
var _map_label_rects: Array[Rect2] = []
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


func set_selected_contact(contact_id: String) -> void:
	_selected_contact_id = contact_id if _contacts_by_id.has(contact_id) else ""
	queue_redraw()


func set_terrain_zones(zones: Array) -> void:
	_terrain_zones = zones.duplicate(true)
	queue_redraw()


func terrain_zones_for_test() -> Array:
	return _terrain_zones.duplicate(true)


func set_fast_craft_supply(receipt: Dictionary) -> void:
	_fast_craft_supply_sources = receipt.get("sources", []).duplicate(true) if bool(receipt.get("ok", false)) else []
	queue_redraw()


func fast_craft_supply_sources_for_test() -> Array:
	return _fast_craft_supply_sources.duplicate(true)


func set_fast_craft_returns(receipt: Dictionary) -> void:
	_fast_craft_return_statuses = receipt.get("statuses", []).duplicate(true) if bool(receipt.get("ok", false)) else []
	queue_redraw()


func fast_craft_return_statuses_for_test() -> Array:
	return _fast_craft_return_statuses.duplicate(true)


func set_fast_craft_recovery(receipt: Dictionary) -> void:
	_fast_craft_recovery = receipt.duplicate(true) if bool(receipt.get("ok", false)) else {}
	queue_redraw()


func fast_craft_recovery_for_test() -> Dictionary:
	return _fast_craft_recovery.duplicate(true)


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
	var contact_id := _contact_at(point)
	if not contact_id.is_empty():
		if _mode == Mode.SELECT: contact_selected.emit(contact_id)
		else: interaction_rejected.emit("추정 접촉은 선택 모드에서 지정할 수 있습니다.")
		return
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


func _contact_at(point: Vector2) -> String:
	for contact_id in _contacts_by_id:
		var contact: Dictionary = _contacts_by_id[contact_id]; var state := String(contact.get("state", "unknown"))
		if state != "estimated": continue
		var position = contact.get("display_position", contact.get("last_known_position"))
		if position is Array and point.distance_to(battle_to_local(position)) <= MARKER_RADIUS + 8.0: return String(contact_id)
	return ""


func _draw() -> void:
	var rect := content_rect()
	_map_label_rects.clear()
	draw_rect(rect, Color("071923"), true)
	draw_rect(rect, Color("477387"), false, 2.0)
	for index in range(1, 8):
		var x := rect.position.x + rect.size.x * float(index) / 8.0
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color(0.16, 0.31, 0.38, 0.45), 1.0)
	for index in range(1, 5):
		var y := rect.position.y + rect.size.y * float(index) / 5.0
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(0.16, 0.31, 0.38, 0.45), 1.0)
	_draw_terrain_zones()
	_draw_fast_craft_supply_sources()
	_draw_fast_craft_return_routes()
	_draw_fast_craft_recovery()
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
		_draw_map_label(p, label, color, 14, 150.0, Vector2(24, -9))


func _draw_terrain_zones() -> void:
	for value in _terrain_zones:
		if not value is Dictionary: continue
		var zone: Dictionary = value
		var shape = zone.get("shape", {})
		if not shape is Dictionary or String(shape.get("kind", "")) != "rect": continue
		var start := battle_to_local([shape.get("x", 0), shape.get("y", 0)])
		var finish := battle_to_local([float(shape.get("x", 0)) + float(shape.get("width", 0)), float(shape.get("y", 0)) + float(shape.get("height", 0))])
		var zone_rect := Rect2(start, finish - start).abs()
		var terrain_type := String(zone.get("terrain_type", ""))
		var fill: Color = {
			"nebula": Color(0.47, 0.32, 0.62, 0.22),
			"debris": Color(0.62, 0.49, 0.25, 0.20),
			"planet_shadow": Color(0.23, 0.38, 0.53, 0.25),
		}.get(terrain_type, Color(0.45, 0.45, 0.45, 0.18))
		var stroke := Color(fill.r, fill.g, fill.b, 0.85)
		draw_rect(zone_rect, fill, true)
		draw_rect(zone_rect, stroke, false, 2.0)
		var type_label: String = {"nebula":"성운", "debris":"잔해 지대", "planet_shadow":"행성 그림자"}.get(terrain_type, "지형")
		var label := "%s · %s" % [type_label, String(zone.get("name", zone.get("zone_id", "")))]
		draw_string(get_theme_default_font(), zone_rect.position + Vector2(8, 19), label, HORIZONTAL_ALIGNMENT_LEFT, maxf(40.0, zone_rect.size.x - 16.0), 13, stroke)


func _draw_fast_craft_supply_sources() -> void:
	for value in _fast_craft_supply_sources:
		if not value is Dictionary: continue
		var source: Dictionary = value; var position = source.get("position", [])
		if not position is Array or position.size() != 2: continue
		var center := battle_to_local(position); var edge := battle_to_local([float(position[0]) + float(source.get("radius", 0)), float(position[1])])
		var radius := center.distance_to(edge); var source_type := String(source.get("source_type", ""))
		var color: Color = {"supply_ship":Color("74d9b0"), "carrier":Color("7fb8e8"), "friendly_base":Color("e1c36f")}.get(source_type, Color("9fb5bf"))
		draw_circle(center, radius, Color(color.r, color.g, color.b, 0.08), true)
		draw_circle(center, radius, Color(color.r, color.g, color.b, 0.72), false, 2.0)
		var type_label: String = {"supply_ship":"보급함", "carrier":"강습모함", "friendly_base":"아군 거점"}.get(source_type, "보급원")
		_draw_map_label(center, "%s · R%d · %d/턴" % [type_label, int(source.get("radius", 0)), int(source.get("capacity_squadrons_per_turn", 0))], color, 12, 155.0, Vector2(20, -28))


func _draw_fast_craft_return_routes() -> void:
	for value in _fast_craft_return_statuses:
		if not value is Dictionary: continue
		var status: Dictionary = value; var route = status.get("route", [])
		if not route is Array or route.is_empty(): continue
		var mode := String(status.get("status", "normal")); var color: Color = {"normal":Color("78a7b8"), "early_return":Color("e1c36f"), "forced_return":Color("f08a68"), "stranded_risk":Color("ef6c75")}.get(mode, Color("9fb5bf"))
		var display_route: Array = []
		var squadron_id := String(status.get("squadron_id", "")); var live: Dictionary = _navigation.get(squadron_id, {})
		if live.get("position", []) is Array: display_route.append(live.position)
		display_route.append_array(route)
		for index in range(display_route.size() - 1):
			var start = display_route[index]; var finish = display_route[index + 1]
			if start is Array and finish is Array: draw_dashed_line(battle_to_local(start), battle_to_local(finish), color, 3.0, 8.0)
		var destination = display_route[-1]
		if not destination is Array: continue
		var target := battle_to_local(destination); draw_circle(target, 12.0, color, false, 3.0)
		_draw_map_label(target, "%s · %s · ETA %d턴" % [_fast_return_status_label(mode), String(status.get("nearest_source_id", "도달 가능 보급원 없음")), int(status.get("eta_turns", 0))], color, 13, 220.0, Vector2(18, -10))


func _fast_return_status_label(status: String) -> String:
	return String({"normal":"귀환 예측", "early_return":"조기 귀환", "forced_return":"비상 강제귀환", "stranded_risk":"도달 불가 위험"}.get(status, status))


func _draw_fast_craft_recovery() -> void:
	for value in _fast_craft_recovery.get("disabled_supply_sources", []):
		if not value is Dictionary: continue
		var disabled: Dictionary = value; var position = disabled.get("position", [])
		if not position is Array or position.size() != 2: continue
		var point := battle_to_local(position); var color := Color("ef6c75")
		draw_line(point + Vector2(-13, -13), point + Vector2(13, 13), color, 4.0)
		draw_line(point + Vector2(-13, 13), point + Vector2(13, -13), color, 4.0)
		_draw_map_label(point, "보급 무력화 · %s · 0/턴" % String(disabled.get("source_id", "")), color, 13, 210.0, Vector2(20, -12))
	for value in _fast_craft_recovery.get("statuses", []):
		if not value is Dictionary: continue
		var status: Dictionary = value; var incident := String(status.get("status", "active"))
		if incident in ["active", "depleted_docked"]: continue
		var position = status.get("display_position", [])
		if (not position is Array or position.size() != 2) and _navigation.has(String(status.get("squadron_id", ""))): position = _navigation[String(status.squadron_id)].get("position", [])
		if not position is Array or position.size() != 2: continue
		var point := battle_to_local(position); var viewer_state := String(status.get("viewer_state", "own")); var color := Color("e0b66d") if viewer_state == "estimated" else (Color("ef6c75") if incident == "captured" else Color("f0a45f"))
		draw_circle(point, MARKER_RADIUS + 10.0, color, false, 3.0)
		if incident == "drifting": draw_circle(point, MARKER_RADIUS + 16.0, color, false, 2.0)
		var route = status.get("rescue_route", [])
		if route is Array and route.size() >= 2:
			for index in range(route.size() - 1):
				if route[index] is Array and route[index + 1] is Array: draw_dashed_line(battle_to_local(route[index]), battle_to_local(route[index + 1]), Color("74d9b0"), 3.0, 8.0)
		var prefix := "추정 · " if viewer_state == "estimated" else ("확인 · " if viewer_state == "confirmed" else "")
		_draw_map_label(point, "%s%s" % [prefix, _fast_recovery_status_label(incident)], color, 13, 145.0, Vector2(24, 18))
	for value in _fast_craft_recovery.get("events", []):
		if not value is Dictionary: continue
		var event: Dictionary = value; var responder_route = event.get("responder_route", []); var target_route = event.get("target_route", [])
		if target_route is Array and target_route.size() >= 2:
			for index in range(target_route.size() - 1):
				if target_route[index] is Array and target_route[index + 1] is Array: draw_dashed_line(battle_to_local(target_route[index]), battle_to_local(target_route[index + 1]), Color("f0a45f"), 3.0, 8.0)
		if responder_route is Array and responder_route.size() >= 2:
			for index in range(responder_route.size() - 1):
				if responder_route[index] is Array and responder_route[index + 1] is Array: draw_dashed_line(battle_to_local(responder_route[index]), battle_to_local(responder_route[index + 1]), Color("74d9b0"), 3.0, 8.0)
		var target = event.get("position", [])
		if target is Array and target.size() == 2 and ((responder_route is Array and not responder_route.is_empty()) or (target_route is Array and not target_route.is_empty())): _draw_map_label(battle_to_local(target), "%s · 자동 판정" % _fast_recovery_status_label(String(event.get("status", ""))), Color("74d9b0"), 13, 155.0, Vector2(24, 44))


func _fast_recovery_status_label(status: String) -> String:
	return String({"drifting":"연료 0 · 표류", "rescued":"구조 완료", "captured":"나포됨", "rescue_assigned":"구조 배정", "rescue_in_progress":"구조 진행"}.get(status, status))


func _draw_map_label(anchor: Vector2, label: String, color: Color, font_size: int, width: float, preferred_offset: Vector2) -> void:
	var height := float(font_size + 9)
	var offsets: Array[Vector2] = [preferred_offset, Vector2(22, -34), Vector2(22, 8), Vector2(22, 34), Vector2(-width - 22, -34), Vector2(-width - 22, 8), Vector2(-width - 22, 34), Vector2(22, 60)]
	var bounds := content_rect().grow(-4.0); var chosen := Rect2(anchor + preferred_offset, Vector2(width, height))
	for offset in offsets:
		var candidate := Rect2(anchor + offset, Vector2(width, height))
		candidate.position.x = clampf(candidate.position.x, bounds.position.x, bounds.end.x - candidate.size.x)
		candidate.position.y = clampf(candidate.position.y, bounds.position.y, bounds.end.y - candidate.size.y)
		chosen = candidate
		var collides := false
		for occupied in _map_label_rects:
			if candidate.grow(3.0).intersects(occupied): collides = true; break
		if not collides: chosen = candidate; break
	_map_label_rects.append(chosen)
	draw_rect(chosen, Color(0.025, 0.075, 0.095, 0.86), true)
	draw_rect(chosen, Color(color.r, color.g, color.b, 0.68), false, 1.0)
	draw_string(get_theme_default_font(), chosen.position + Vector2(5, font_size + 2), label, HORIZONTAL_ALIGNMENT_LEFT, chosen.size.x - 10.0, font_size, color)


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
		else:
			_draw_dashed_circle(p, MARKER_RADIUS + 5.0, color)
			if String(contact.get("contact_id", "")) == _selected_contact_id: draw_circle(p, MARKER_RADIUS + 11.0, Color("f3d27a"), false, 2.0)
		var label := "확인 접촉 · 현재 위치 재확인" if state == "confirmed" else ("%s · 확인 T%d · 경과 %d · 오차 %d · 실제 좌표 아님" % ["소실 접촉(stale)" if state == "lost" else "추정 접촉", int(contact.get("last_seen_turn", 0)), int(contact.get("staleness_turns", 0)), int(contact.get("error_radius", 0))])
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
