class_name HomeSubmenu
extends PanelContainer

## 홈 지도 위에 겹쳐 열리는 읽기 전용 하위 패널.
##
## 이 패널은 Campaign을 변경하지 않는다. 실제 명령은 action_requested로 호스트에
## 요청하며, 스냅숏에 없는 값은 추측하지 않고 명시적으로 "정보 없음"으로 표시한다.

signal closed
signal action_requested(action_id: String, payload: Dictionary)

const ROUTES: Array[Dictionary] = [
	{"id": "systems", "title": "성역", "icon": "◇"},
	{"id": "fleets", "title": "함대", "icon": "▲"},
	{"id": "domestic", "title": "내정", "icon": "▣"},
	{"id": "talent", "title": "인재", "icon": "◆"},
	{"id": "diplomacy", "title": "외교", "icon": "◈"},
	{"id": "tech", "title": "기술", "icon": "✦"},
	{"id": "records", "title": "기록", "icon": "≡"},
]

const RED_CLIFF_CONDITIONS := {
	"cao_southward_complete": "조조군 남하 완료",
	"sun_quan_independent": "손권 세력 독립 유지",
	"liu_bei_hostile_to_cao": "유비·조조 적대",
	"sun_liu_military_pact": "손·유 군사 맹약",
	"yangtze_defense_line": "장강 방어선 형성",
}

var current_route: String = ""
var _state: Dictionary = {}
var _snapshot
var _title_text := ""
var _icon_text := ""
var _content: VBoxContainer
var _tabs: HBoxContainer
var _heading: Label


func preferred_height() -> float:
	if current_route in ["systems", "domestic", "diplomacy", "records", "red_cliff_lock"]:
		return 540.0
	if current_route == "selection":
		return 360.0
	return 320.0


func _ready() -> void:
	custom_minimum_size = Vector2(520.0, 280.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	add_theme_stylebox_override("panel", _panel_style())
	visibility_changed.connect(_on_visibility_changed)
	_build_shell()
	set_process_unhandled_key_input(visible)
	if current_route != "":
		_render_current()


func setup(state: Dictionary, snapshot) -> void:
	_state = state.duplicate(true)
	_snapshot = snapshot
	if is_node_ready() and current_route != "":
		_render_current()


func open_route(route_id: String, title: String, icon: String) -> void:
	current_route = route_id
	_title_text = title
	_icon_text = icon
	visible = true
	if not is_node_ready():
		return
	if not _is_supported_route(route_id):
		current_route = "records"
		_title_text = "기록"
		_icon_text = "≡"
	_render_current()
	grab_focus()
	action_requested.emit("route_opened", {"route_id": current_route})


func close_panel() -> void:
	if not visible:
		return
	visible = false
	current_route = ""
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()


func _build_shell() -> void:
	for child in get_children():
		child.queue_free()
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 48)
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)
	_heading = Label.new()
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_heading.add_theme_font_size_override("font_size", 21)
	_heading.add_theme_color_override("font_color", Color("effaff"))
	header.add_child(_heading)
	var close_button := Button.new()
	close_button.text = "닫기  ×"
	close_button.tooltip_text = "하위 패널 닫기 (Esc)"
	close_button.focus_mode = Control.FOCUS_ALL
	close_button.pressed.connect(close_panel)
	header.add_child(close_button)

	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 4)
	root.add_child(_tabs)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var scrollbar := scroll.get_v_scroll_bar()
	scrollbar.custom_minimum_size.x = 6.0
	scrollbar.add_theme_stylebox_override("scroll", _scroll_style(Color(0.0, 0.0, 0.0, 0.0)))
	scrollbar.add_theme_stylebox_override("grabber", _scroll_style(Color(0.22, 0.68, 0.88, 0.72)))
	scrollbar.add_theme_stylebox_override("grabber_highlight", _scroll_style(Color(0.38, 0.82, 1.0, 0.90)))
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	scroll.add_child(_content)


func _render_current() -> void:
	if _content == null:
		return
	_heading.text = "%s  %s" % [_icon_text, _title_text]
	_render_tabs()
	_clear(_content)
	if not bool(_state.get("valid", true)):
		_add_notice("시나리오 상태를 표시할 수 없습니다.",
			String(_state.get("validation_error", "검증되지 않은 상태")))
		return
	match current_route:
		"systems": _render_systems()
		"fleets": _render_fleets()
		"domestic": _render_domestic()
		"talent": _render_unavailable("확인 가능한 인재 없음", "적벽 전야 인재 명부가 열리면 등용 가능 인물과 배치 현황이 표시됩니다.")
		"diplomacy": _render_diplomacy()
		"tech": _render_tech()
		"records": _render_records()
		"mail": _render_records(true)
		"settings": _render_settings()
		"red_cliff_lock": _render_red_cliff_lock()
		"selection": _render_selection()
		_:
			if current_route.begins_with("resource:"):
				_render_resource()


func _render_tabs() -> void:
	_clear(_tabs)
	_tabs.visible = false
	for route in ROUTES:
		if String(route.id) == current_route:
			_tabs.visible = true
			break
	if not _tabs.visible:
		return
	for route in ROUTES:
		var button := Button.new()
		button.text = "%s %s" % [route.icon, route.title]
		button.toggle_mode = true
		button.button_pressed = String(route.id) == current_route
		button.tooltip_text = "%s 패널 열기 — 지도의 위치와 시간은 유지됩니다." % route.title
		button.add_theme_stylebox_override("normal", _tab_style(false))
		button.add_theme_stylebox_override("hover", _tab_style(true))
		button.add_theme_stylebox_override("pressed", _tab_style(true))
		button.pressed.connect(_open_tab.bind(String(route.id), String(route.title), String(route.icon)))
		_tabs.add_child(button)


func _open_tab(route_id: String, title: String, icon: String) -> void:
	open_route(route_id, title, icon)


func _render_systems() -> void:
	var systems: Array = _state.get("canonical_systems", [])
	var regions: Array = _state.get("canonical_regions", [])
	var routes: Array = _state.get("canonical_routes", [])
	_add_summary("%s · 적벽 전야" % _campaign_date_label(), "%d성역 · %d권역 · %d항로" % [systems.size(), regions.size(), routes.size()])
	for system in systems:
		var sid := String(system.get("id", ""))
		var name := String(system.get("display_name", system.get("name", sid)))
		var region_count := (system.get("regions", []) as Array).size()
		_add_action_row(name, "%d개 권역 · %s" % [region_count, String(system.get("grade", "등급 미기록"))],
			"지도에서 이 성역을 선택", "system_selected", {"system_id": sid})


func _render_fleets() -> void:
	var fleets: Array = _state.get("observed_fleets", [])
	if fleets.is_empty():
		_add_notice("현재 확인된 함대 없음", "아군 정찰망에 포착된 함대가 없습니다. 새로운 관측 정보가 들어오면 이곳에 표시됩니다.")
		return
	for fleet in fleets:
		var fid := str(fleet.get("fleet_id", ""))
		var name := str(fleet.get("display_name", "관측 함대"))
		var details: Array[String] = []
		if str(fleet.get("faction", "")) != "":
			details.append("세력 %s" % _field_value("faction", str(fleet.faction)))
		details.append("성역 %s" % str(fleet.get("system_id", "미확인")))
		details.append("상태 %s" % _status_label(str(fleet.get("status", ""))))
		details.append("척수 %s" % str(fleet.get("ships_display", "미확인")))
		var detail := " · ".join(details)
		_add_action_row(name, detail, "관측이 허용한 정보만 표시", "fleet_selected", {"fleet_id": fid})


func _render_domestic() -> void:
	var regions: Array = _state.get("canonical_regions", [])
	var owners: Dictionary = _state.get("region_owner", {})
	_add_summary("권역 통치 현황", "%d개 권역 중 %d개 소유 상태 확인" % [regions.size(), owners.size()])
	var jingzhou: Array = []
	if _snapshot != null and _snapshot.has_method("jingzhou_regions"):
		jingzhou = _snapshot.jingzhou_regions()
	else:
		for region in regions:
			if String(region.get("system", "")) == "SYS-13":
				jingzhou.append(region)
	for region in jingzhou:
		var rid := String(region.get("id", ""))
		_add_action_row(String(region.get("name", rid)), "통치: %s" % String(owners.get(rid, "미확인")),
			"형주 권역 상세 열기", "region_selected", {"region_id": rid})
	_add_notice("읽기 전용", "개발·복구·징병·건조·위임 명령은 이 요약에서 실행하지 않습니다.")


func _render_tech() -> void:
	var player: Dictionary = _state.get("player_state", {})
	var tech: Dictionary = player.get("tech", {})
	var research: Dictionary = player.get("tech_research", {})
	_add_summary("%s 세력 기술" % String(player.get("faction_id", "관측 세력")),
		"화력 · 방어 · 특수의 실제 Campaign 단계")
	for axis in ["화력", "방어", "특수"]:
		_add_info_row(axis, "%d단계" % int(tech.get(axis, 0)), "현재 적용 중인 기술 단계")
	if research.is_empty():
		_add_notice("진행 중인 연구 없음", "새 연구가 시작되면 완료 예정 tick을 표시합니다.")
	else:
		var now_tick := int((_state.get("scenario", {}) as Dictionary).get("tick", 0))
		var done_tick := int(research.get("done_tick", now_tick))
		_add_info_row("진행 중인 연구", String(research.get("axis", "분야 미확인")),
			"Campaign에 기록된 연구 분야")
		_add_info_row("완료까지", "%d tick" % maxi(0, done_tick - now_tick),
			"Campaign 완료 tick에서 현재 tick을 뺀 값")


func _render_diplomacy() -> void:
	var alliances: Array = _state.get("alliances", [])
	_add_summary("현재 맹약", "%d건" % alliances.size())
	for alliance in alliances:
		_add_info_row(" ↔ ".join(alliance.get("parties", [])), String(alliance.get("tier_name", "맹약")), "캠페인 외교 상태")
	_add_section("외부 세력 · 영토가 아닌 접근축")
	for power in _state.get("external_powers", []):
		var status := _status_label(String(power.get("status", "미확인")))
		var axis := String(power.get("access_axis", "해당 없음"))
		var note := "%s · %s" % [status, axis]
		_add_action_row(String(power.get("name", power.get("id", ""))), note,
			"208년 현재 상태만 표시", "external_power_selected", {"external_power_id": power.get("id", "")})


func _render_records(mail_only: bool = false) -> void:
	var news: Array = _state.get("news", [])
	var battles: Array = _state.get("active_battles", [])
	if not mail_only:
		_add_summary("%s · 적벽 전야 기록" % _campaign_date_label(), "소식 %d건 · 활성 전투 %d건" % [news.size(), battles.size()])
		_render_current_status()
	if mail_only and news.is_empty():
		_add_notice("새 서신 없음", "새로운 외교 서신과 군령이 도착하면 이곳에 표시됩니다.")
	for index in range(news.size()):
		var item: Dictionary = news[index]
		_add_action_row(String(item.get("headline", item.get("title", "소식"))), String(item.get("date", "날짜 미기록")),
			"소식 상세 열기", "news_selected", {"index": index, "item": item.duplicate(true)})
	if not mail_only:
		for battle in battles:
			_add_action_row(String(battle.get("name", battle.get("id", "전투"))), String(battle.get("anchor_kind", battle.get("status", ""))),
				"전투 위치 선택", "battle_selected", {"battle_id": battle.get("id", "")})


func _render_settings() -> void:
	_add_notice("천하도 설정", "지도 조작과 정보 표현 원칙을 확인합니다.")
	_add_info_row("조작", "휠 확대·축소 · 드래그 이동 · Esc 닫기", "현재 홈 지도 조작")
	_add_info_row("표현 원칙", "구지는 천하도에서 비강조, 태양계권 확대부터 표시", "208 적벽 전야 지도 정책")


func _render_resource() -> void:
	var payload: Dictionary = _state.get("route_payload", {})
	var value := String(payload.get("display_value", "표시값 없음"))
	var delta := String(payload.get("display_delta", ""))
	_add_summary(_title_text if _title_text != "" else "자원", value + (" · 증감 %s" % delta if delta != "" else ""))
	_add_info_row("상세 내역", "수입·지출 기록 준비 중", "현재 표시값은 유지하고 확인되지 않은 원인은 표시하지 않습니다.")
	_add_info_row("정보 안내", "확인된 보유량과 변동만 표시", "세부 내역이 확인되면 함께 갱신됩니다.")


func _render_red_cliff_lock() -> void:
	var active: Dictionary = {}
	for battle in _state.get("active_battles", []):
		if String(battle.get("id", "")) == "BATTLE-RED-CLIFF" and String(battle.get("status", "")) == "active":
			active = battle
			break
	var known: Dictionary = _state.get("red_cliff_conditions", {})
	if not active.is_empty():
		known = active.get("conditions", known)
	var confirmed := 0
	for key in RED_CLIFF_CONDITIONS:
		if bool(known.get(key, false)):
			confirmed += 1
	_add_summary("적벽 · 구지 궤도", "교전 활성" if not active.is_empty() else "개전 조건 %d/5 확인" % confirmed)
	for key in RED_CLIFF_CONDITIONS:
		var status := "충족" if bool(known.get(key, false)) else ("미충족" if known.has(key) else "확인 대기")
		_add_info_row(String(RED_CLIFF_CONDITIONS[key]), status, "다섯 조건이 모두 충족되고 실제 전투가 활성화되어야 적벽이 열립니다.")
	if active.is_empty():
		_add_notice("개전 전", "확인된 다섯 조건과 실제 교전 상태가 모두 갖춰질 때 전장이 열립니다.")


func _render_selection() -> void:
	var selected = _state.get("selection", {})
	if not selected is Dictionary or selected.is_empty():
		_add_notice("선택 정보 없음", "지도에서 성역·권역·함대·천체를 선택하면 확인 가능한 항목을 표시합니다.")
		return
	var data: Dictionary = selected
	var type_name := _type_label(String(data.get("type", "유형 미확인")))
	var summary_parts: Array[String] = [type_name]
	for key in ["grade", "faction"]:
		if data.has(key) and String(data[key]) != "":
			summary_parts.append(_field_value(key, String(data[key])))
	_add_summary("선택 대상", " · ".join(summary_parts))
	if data.has("region_ids"):
		_add_info_row("관할 권역", "%d개" % (data.get("region_ids", []) as Array).size(), "선택한 성역에 속한 권역 수")
	for key in ["faction", "system_id", "region_id", "grade", "status"]:
		if data.has(key):
			_add_info_row(_field_label(key), _field_value(key, String(data[key])), "선택 정보")


func _render_unavailable(title: String, reason: String) -> void:
	_add_notice(title, reason)
	_add_info_row("현재 상태", "준비 중", "확인된 정보만 표시합니다.")


func _render_current_status() -> void:
	var owners: Dictionary = _state.get("region_owner", {})
	var regions: Array = _state.get("canonical_regions", [])
	var owner_set := {}
	for owner in owners.values():
		if String(owner) != "":
			owner_set[String(owner)] = true
	_add_section("현재 상황")
	_add_info_row("%s 캠페인" % _campaign_date_label(), "%d개 통치 세력 · %d개 권역" % [owner_set.size(), regions.size()], "적벽 전야")
	_add_info_row("형주 북부권", _field_value("faction", String(owners.get("RGN-01", "미확인"))), "형주 권역 통치 현황")
	var active := false
	for battle in _state.get("active_battles", []):
		if String(battle.get("id", "")) == "BATTLE-RED-CLIFF" and String(battle.get("status", "")) == "active":
			active = true
			break
	_add_info_row("적벽 전투", "교전 활성" if active else "개전 전", "구지 궤도 적벽 전투 상태")
	var present: Array[String] = []
	for power in _state.get("external_powers", []):
		if String(power.get("status", "")) == "present":
			present.append(String(power.get("name", "")))
	_add_info_row("외부 관문", " · ".join(present) if not present.is_empty() else "현재 접촉 없음", "영토가 아닌 외부 접근축")


func _add_summary(title: String, detail: String) -> void:
	_add_info_row(title, detail, "현재 캠페인 홈 스냅숏 요약", true)


func _add_section(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color("78cfee"))
	label.add_theme_constant_override("outline_size", 1)
	_content.add_child(label)


func _add_notice(title: String, detail: String) -> void:
	_add_info_row(title, detail, detail, true)


func _add_info_row(title: String, detail: String, tooltip: String, emphasized: bool = false) -> void:
	var row := PanelContainer.new()
	row.tooltip_text = tooltip
	row.add_theme_stylebox_override("panel", _row_style(emphasized))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	row.add_child(box)
	var name_label := Label.new()
	name_label.text = title
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", Color("f1fbff") if emphasized else Color("d8edf7"))
	box.add_child(name_label)
	var detail_label := Label.new()
	detail_label.text = detail
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.add_theme_font_size_override("font_size", 13)
	detail_label.add_theme_color_override("font_color", Color("b4cad5"))
	box.add_child(detail_label)
	_content.add_child(row)


func _add_action_row(title: String, detail: String, tooltip: String, action_id: String, payload: Dictionary) -> void:
	var button := Button.new()
	button.text = "%s  ›\n%s" % [title, detail if detail != "" else "확인된 세부 정보 없음"]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(0, 52)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_stylebox_override("normal", _row_style(false))
	button.add_theme_stylebox_override("hover", _row_style(true))
	button.pressed.connect(_emit_action.bind(action_id, payload.duplicate(true)))
	_content.add_child(button)


func _emit_action(action_id: String, payload: Dictionary) -> void:
	action_requested.emit(action_id, payload)


func _known_fields(row: Dictionary, keys: Array[String]) -> String:
	var values: Array[String] = []
	for key in keys:
		if row.has(key) and String(row[key]) != "":
			values.append("%s %s" % [_field_label(key), _field_value(key, String(row[key]))])
	return " · ".join(values) if not values.is_empty() else "관측된 식별 정보만 확인"


func _field_label(key: String) -> String:
	return {"faction": "세력", "system_id": "성역", "region_id": "권역", "status": "상태", "ships": "척수", "grade": "등급"}.get(key, key)


func _field_value(key: String, value: String) -> String:
	if key == "status":
		return _status_label(value)
	if key == "faction" and value == "마등한수":
		return "마등·한수"
	return value


func _status_label(value: String) -> String:
	return {
		"present": "현재 접촉 가능",
		"background": "교역 배경",
		"future": "224년 이후 등장",
		"active": "현재 활동",
		"inactive": "비활성",
		"ready": "준비 완료",
		"moving": "이동 중",
		"stationed": "주둔",
	}.get(value, value if value != "" else "미확인")


func _type_label(value: String) -> String:
	return {
		"capital": "수도 성역",
		"fortress": "요충 성역",
		"strategic": "전략 성역",
		"external_power": "외부 세력",
		"news": "소식",
		"battle": "전투",
		"system": "성역",
		"region": "권역",
		"fleet": "함대",
		"body": "천체",
		"star": "항성",
		"planet": "행성",
		"moon": "위성",
	}.get(value, value if value != "" else "유형 미확인")


func _campaign_date_label() -> String:
	var scenario: Dictionary = _state.get("scenario", {})
	var year := int(scenario.get("year", 208))
	var month := int(scenario.get("month", 1))
	return "건안 %d년 %d월" % [13 + (year - 208), month]


func _tab_style(selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.18, 0.27, 0.96) if selected else Color(0.01, 0.045, 0.07, 0.82)
	style.border_color = Color(0.35, 0.82, 1.0, 0.88 if selected else 0.28)
	style.border_width_bottom = 2 if selected else 1
	style.set_corner_radius_all(3)
	style.set_content_margin_all(7)
	return style


func _scroll_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(3)
	return style


func _is_supported_route(route_id: String) -> bool:
	if route_id.begins_with("resource:"):
		return true
	if route_id in ["mail", "settings", "red_cliff_lock", "selection"]:
		return true
	for route in ROUTES:
		if String(route.id) == route_id:
			return true
	return false


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _on_visibility_changed() -> void:
	set_process_unhandled_key_input(visible)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.005, 0.025, 0.043, 0.985)
	style.border_color = Color(0.32, 0.78, 1.0, 0.92)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	style.shadow_color = Color(0.0, 0.45, 0.78, 0.28)
	style.shadow_size = 12
	return style


func _row_style(emphasized: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.11, 0.17, 0.94) if emphasized else Color(0.012, 0.052, 0.082, 0.88)
	style.border_color = Color(0.34, 0.74, 0.94, 0.72 if emphasized else 0.32)
	style.border_width_left = 2 if emphasized else 1
	style.border_width_bottom = 1
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	return style
