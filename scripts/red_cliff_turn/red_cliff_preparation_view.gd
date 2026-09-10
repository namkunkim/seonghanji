class_name RedCliffPreparationView
extends Control

## DEMO-RC-G2-01 — 유비 직행 전투 준비 화면 및 역사적 초기 상태 경계
## 순수 2D Control 화면이다. 편성 편집과 턴 전투는 후속 Task 경계로 남긴다.

signal close_requested

var _load_result: Dictionary = {}
var _content: VBoxContainer
var _status: Label
var _start_button: Button
var _faction_columns: HBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_render()


func configure(load_result: Dictionary) -> void:
	_load_result = load_result.duplicate(true)
	if is_node_ready():
		_render()


func state() -> Dictionary:
	if not bool(_load_result.get("ok", false)):
		return {"ready": false, "player_faction_id": "", "setup_id": "",
			"errors": _load_result.get("errors", []).duplicate()}
	var setup: Dictionary = _load_result.get("setup", {})
	return {"ready": true, "player_faction_id": String(setup.get("player_faction_id", "")),
		"setup_id": String(setup.get("setup_id", "")),
		"balance_profile_id": String(setup.get("balance_profile", {}).get("id", "")),
		"squadron_count": setup.get("squadrons", []).size(), "errors": []}


func _build() -> void:
	var background := ColorRect.new()
	background.color = Color("050b12")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	add_child(margin)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 10)
	margin.add_child(_content)

	var heading := HBoxContainer.new()
	_content.add_child(heading)
	var title := Label.new()
	title.name = "PreparationTitle"
	title.text = "적 벽 대 전  ·  전투 준비"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("ead49a"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var player := Label.new()
	player.name = "PlayerFaction"
	player.text = "플레이어  ◆  유비"
	player.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	player.add_theme_font_size_override("font_size", 20)
	player.add_theme_color_override("font_color", Color("7ed9a4"))
	heading.add_child(player)

	var context := Label.new()
	context.name = "HistoricalContext"
	context.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	context.add_theme_font_size_override("font_size", 14)
	context.add_theme_color_override("font_color", Color("b8cbd3"))
	_content.add_child(context)

	var notice := PanelContainer.new()
	notice.name = "BalanceProfileNotice"
	notice.add_theme_stylebox_override("panel", _panel_style(Color("1b2530"), Color("967c45")))
	var notice_label := Label.new()
	notice_label.name = "BalanceProfileText"
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.add_theme_font_size_override("font_size", 13)
	notice_label.add_theme_color_override("font_color", Color("efdba4"))
	notice.add_child(notice_label)
	_content.add_child(notice)

	var scroll := ScrollContainer.new()
	scroll.name = "PreparationRosterScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)
	_faction_columns = HBoxContainer.new()
	_faction_columns.name = "FactionColumns"
	_faction_columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_faction_columns.add_theme_constant_override("separation", 12)
	scroll.add_child(_faction_columns)

	_status = Label.new()
	_status.name = "PreparationStatus"
	_status.custom_minimum_size = Vector2(0, 38)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 14)
	_content.add_child(_status)

	var actions := HBoxContainer.new()
	actions.name = "PreparationActions"
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	_content.add_child(actions)
	var restore := _button("역사 편성 복원", "RestoreHistoricalFormation")
	restore.pressed.connect(_on_restore_pressed)
	actions.add_child(restore)
	var custom := _button("사용자 편성", "OpenCustomFormation")
	custom.pressed.connect(_on_custom_pressed)
	actions.add_child(custom)
	_start_button = _button("전투 시작", "StartTurnBattle")
	_start_button.pressed.connect(_on_start_pressed)
	actions.add_child(_start_button)
	var close := _button("천하도로", "ClosePreparation")
	close.pressed.connect(func(): close_requested.emit())
	actions.add_child(close)


func _render() -> void:
	if _content == null:
		return
	for child in _faction_columns.get_children():
		_faction_columns.remove_child(child)
		child.queue_free()
	var ok := bool(_load_result.get("ok", false))
	_start_button.disabled = not ok
	var context: Label = find_child("HistoricalContext", true, false)
	var balance_text: Label = find_child("BalanceProfileText", true, false)
	if not ok:
		context.text = "초기 상태를 검증하지 못했습니다. 이전 적벽 흐름으로 전환하지 않습니다."
		balance_text.text = "데이터 오류 · 전투 시작 잠김"
		var errors: Array = _load_result.get("errors", [])
		_status.text = "초기 데이터 오류\n" + "\n".join(errors)
		_status.add_theme_color_override("font_color", Color("ff8f87"))
		return
	var setup: Dictionary = _load_result["setup"]
	var historical: Dictionary = setup["historical_context"]
	var balance: Dictionary = setup["balance_profile"]
	context.text = "%s  ·  %s\n%s" % [String(historical.get("date_label", "")),
		String(historical.get("location_label", "")), String(historical.get("statement", ""))]
	balance_text.text = "게임 밸런스 프로필  ◆  %s · %s\n%s" % [String(balance.get("id", "")),
		String(balance.get("difficulty", "")), String(balance.get("statement", ""))]
	var ship_types := _ship_type_index(setup["ship_types"])
	for faction_id in ["liu_bei", "sun_quan", "cao_cao"]:
		_faction_columns.add_child(_faction_card(setup, faction_id, ship_types))
	_status.text = "역사 편성이 준비되었습니다. 사용자 편성과 턴 전투는 다음 구현 단계에서 연결됩니다."
	_status.add_theme_color_override("font_color", Color("9fd7bc"))


func _faction_card(setup: Dictionary, faction_id: String, ship_types: Dictionary) -> Control:
	var faction := _find_by_id(setup["factions"], faction_id)
	var panel := PanelContainer.new()
	panel.name = "Faction_%s" % faction_id
	panel.custom_minimum_size = Vector2(495, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tint: Color = {"liu_bei": Color("4d9a70"), "sun_quan": Color("bd655d"),
		"cao_cao": Color("4e94bd")}.get(faction_id, Color("71838c"))
	panel.add_theme_stylebox_override("panel", _panel_style(Color("091721"), tint))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 7)
	margin.add_child(stack)
	var title := Label.new()
	var control_text: String = {"player": "직접 지휘", "turn_prompt_ai": "턴마다 수동 여부 선택",
		"ai": "AI 지휘"}.get(String(faction.get("control", "")), "")
	title.text = "%s  ·  %s" % [String(faction.get("name", faction_id)), control_text]
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", tint.lightened(0.25))
	stack.add_child(title)
	var command := Label.new()
	command.text = "총지휘  %s\n역사 역할  %s" % [String(faction.get("supreme_commander", "")),
		String(faction.get("historical_role", ""))]
	command.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	command.add_theme_font_size_override("font_size", 13)
	command.add_theme_color_override("font_color", Color("c5d5da"))
	stack.add_child(command)
	for squadron_value in setup["squadrons"]:
		var squadron: Dictionary = squadron_value
		if String(squadron.get("faction_id", "")) != faction_id:
			continue
		stack.add_child(_squadron_summary(squadron, ship_types, tint))
	return panel


func _squadron_summary(squadron: Dictionary, ship_types: Dictionary, tint: Color) -> Control:
	var box := VBoxContainer.new()
	box.name = "Squadron_%s" % String(squadron.get("id", ""))
	box.add_theme_constant_override("separation", 3)
	var heading := Label.new()
	heading.text = "%s%s  ·  지휘관 %s" % ["◆ " if bool(squadron.get("flagship", false)) else "",
		String(squadron.get("name", "")), String(squadron.get("commander", {}).get("name", ""))]
	heading.add_theme_font_size_override("font_size", 16)
	heading.add_theme_color_override("font_color", tint.lightened(0.32))
	box.add_child(heading)
	var position: Array = squadron.get("initial_position", [])
	var meta := Label.new()
	meta.text = "ID %s  ·  위치 (%d, %d)  ·  진형 %s  ·  총비용 %d" % [
		String(squadron.get("id", "")), int(position[0]), int(position[1]),
		String(squadron.get("formation_id", "")), int(squadron.get("calculated_total_cost", 0))]
	meta.add_theme_font_size_override("font_size", 12)
	meta.add_theme_color_override("font_color", Color("9db4be"))
	box.add_child(meta)
	for component_value in squadron.get("composition", []):
		var component: Dictionary = component_value
		var ship: Dictionary = ship_types.get(String(component.get("ship_type_id", "")), {})
		var unit_cost := int(ship.get("unit_cost", 0))
		var equipment_text := ""
		if not String(component.get("mission_equipment_id", "")).is_empty():
			for equipment_value in ship.get("mission_equipment", []):
				var equipment: Dictionary = equipment_value
				if String(equipment.get("id", "")) == String(component["mission_equipment_id"]):
					unit_cost += int(equipment.get("unit_cost", 0))
					equipment_text = " · %s 장비" % String(equipment.get("name", ""))
		var row := Label.new()
		row.text = "  %s%s  %d척 × %d = %d" % [String(ship.get("name", "")), equipment_text,
			int(component.get("count", 0)), unit_cost, int(component.get("count", 0)) * unit_cost]
		row.add_theme_font_size_override("font_size", 13)
		row.add_theme_color_override("font_color", Color("d8e3e6"))
		box.add_child(row)
	return box


func _on_restore_pressed() -> void:
	if bool(_load_result.get("ok", false)):
		_status.text = "역사 편성을 복원했습니다. normal-demo-v1 초기값은 변경되지 않았습니다."


func _on_custom_pressed() -> void:
	_status.text = "사용자 편성은 다음 구현 단계에서 제공됩니다. 현재 데이터는 변경되지 않았습니다."


func _on_start_pressed() -> void:
	if not bool(_load_result.get("ok", false)):
		return
	_status.text = "전투 준비 완료 · 턴 전투 엔진 연결이 필요합니다. 아직 전투를 시작하지 않았습니다."


func _button(text: String, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(150, 44)
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_stylebox_override("normal", _panel_style(Color("142531"), Color("617f8d")))
	button.add_theme_stylebox_override("hover", _panel_style(Color("213845"), Color("d1af61")))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("0d1b24"), Color("d1af61")))
	button.add_theme_stylebox_override("disabled", _panel_style(Color("0a1117"), Color("34434a")))
	return button


func _panel_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _ship_type_index(rows: Array) -> Dictionary:
	var out: Dictionary = {}
	for row_value in rows:
		var row: Dictionary = row_value
		out[String(row.get("id", ""))] = row
	return out


func _find_by_id(rows: Array, wanted_id: String) -> Dictionary:
	for row_value in rows:
		var row: Dictionary = row_value
		if String(row.get("id", "")) == wanted_id:
			return row
	return {}
