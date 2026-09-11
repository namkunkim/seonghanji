class_name RedCliffFormationEditor
extends Control

## DEMO-RC-G3-01 — 비용 기반 전대·함대 편성 편집기.
## 모든 변경·비용·권한·검증은 RedCliffsFormationDraft 공개 API에 위임한다.

signal close_requested
signal formation_applied(setup: Dictionary, summary: Dictionary)

const DraftScript := preload("res://core/demo_red_cliffs/red_cliffs_formation_draft.gd")
const FastCraftEditor := preload("res://scripts/red_cliff_turn/red_cliff_fast_craft_editor.gd")
const FACTION_ORDER := ["liu_bei", "sun_quan", "cao_cao"]
const FACTION_LABEL := {
	"liu_bei": "유비군 · 직접 편집",
	"sun_quan": "손권군 · 잠김",
	"cao_cao": "조조군 · AI·읽기 전용",
}

var _draft
var _active_faction := "liu_bei"
var _selected_squadron := ""
var _status_text := "편성 초안을 준비했습니다."
var _status_error := false
var _body: HBoxContainer
var _tabs: HBoxContainer
var _status: Label
var _apply_button: Button
var _apply_in_progress := false
var _fast_craft_editor: Control


func configure(historical_setup: Dictionary, applied_setup: Dictionary = {}) -> Dictionary:
	_draft = DraftScript.new()
	var receipt: Dictionary = _draft.configure(historical_setup, applied_setup)
	if bool(receipt.get("ok", false)):
		_select_first_squadron()
		_status_text = "편성 초안을 준비했습니다. 적용 전에는 전투 준비 상태가 바뀌지 않습니다."
		_status_error = false
	else:
		_set_receipt(receipt)
	if is_node_ready():
		_refresh()
	return receipt


func editor_state() -> Dictionary:
	if _draft == null:
		return {"ready": false}
	return {
		"ready": true,
		"active_faction": _active_faction,
		"selected_squadron": _selected_squadron,
		"dirty": _draft.draft_digest() != _draft.applied_digest(),
		"summary": _draft.summary(),
	}


func draft_controller():
	return _draft


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_shell()
	_refresh()
	set_process_unhandled_key_input(true)


func _build_shell() -> void:
	var background := ColorRect.new()
	background.color = Color("040a10")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 22)
	for side in ["margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 9)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 48
	root.add_child(header)
	var title := Label.new()
	title.text = "적 벽 대 전  ·  사용자 편성"
	title.add_theme_font_size_override("font_size", 27)
	title.add_theme_color_override("font_color", Color("ead49a"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var profile := Label.new()
	profile.name = "EditorProfile"
	profile.text = "normal-demo-v1  ·  초안 편집"
	profile.add_theme_font_size_override("font_size", 15)
	profile.add_theme_color_override("font_color", Color("9fc0ce"))
	profile.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(profile)
	var fast_craft := _button("고속정 임무 편성", "OpenFastCraftEditor", 165)
	fast_craft.pressed.connect(_open_fast_craft_editor)
	header.add_child(fast_craft)

	_tabs = HBoxContainer.new()
	_tabs.name = "FactionPermissionTabs"
	_tabs.add_theme_constant_override("separation", 8)
	root.add_child(_tabs)
	_body = HBoxContainer.new()
	_body.name = "FormationEditorBody"
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	root.add_child(_body)

	var footer := HBoxContainer.new()
	footer.name = "FormationEditorFooter"
	footer.custom_minimum_size.y = 58
	footer.add_theme_constant_override("separation", 9)
	root.add_child(footer)
	_status = Label.new()
	_status.name = "FormationEditorStatus"
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 14)
	footer.add_child(_status)
	var restore := _button("역사 편성 복원", "RestoreHistoricalDraft", 150)
	restore.pressed.connect(_restore_historical)
	footer.add_child(restore)
	var cancel := _button("변경 취소", "CancelFormationDraft", 125)
	cancel.pressed.connect(_cancel_draft)
	footer.add_child(cancel)
	_apply_button = _button("편성 적용", "ApplyFormationDraft", 125)
	_apply_button.pressed.connect(_apply_draft)
	footer.add_child(_apply_button)
	var close := _button("편집기 닫기", "CloseFormationEditor", 125)
	close.pressed.connect(_request_close)
	footer.add_child(close)


func _refresh() -> void:
	if _body == null:
		return
	_clear(_tabs)
	_clear(_body)
	if _draft == null:
		_status.text = "편성 데이터를 불러오지 못했습니다."
		_status.add_theme_color_override("font_color", Color("ff8f87"))
		_apply_button.disabled = true
		return
	_build_faction_tabs()
	var snapshot: Dictionary = _draft.draft_snapshot()
	if _find_squad(snapshot, _selected_squadron).is_empty() \
			or String(_find_squad(snapshot, _selected_squadron).get("faction_id", "")) != _active_faction:
		_select_first_squadron()
	_body.add_child(_build_roster_panel(snapshot))
	_body.add_child(_build_composition_panel(snapshot))
	_body.add_child(_build_summary_panel(snapshot))
	var validation: Dictionary = _draft.validate_draft()
	_apply_button.disabled = _apply_in_progress or not bool(validation.get("ok", false)) \
		or _draft.draft_digest() == _draft.applied_digest()
	_status.text = _status_text
	_status.add_theme_color_override("font_color", Color("ff9b91") if _status_error else Color("a8d9bd"))


func _build_faction_tabs() -> void:
	for faction_id in FACTION_ORDER:
		var label: String = FACTION_LABEL[faction_id]
		if faction_id == "sun_quan" and _draft.can_edit_faction(faction_id):
			label = "손권군 · 수동 편집 켜짐"
		var tab := _button(label, "FactionTab_%s" % faction_id, 250)
		tab.toggle_mode = true
		tab.button_pressed = faction_id == _active_faction
		tab.pressed.connect(_select_faction.bind(faction_id))
		_tabs.add_child(tab)
	if _active_faction == "sun_quan":
		var sun_manual := _button(
			"연합 편성 수동 설정 끄기" if _draft.can_edit_faction("sun_quan") else "연합 편성 수동 설정",
			"ToggleSunManual", 230)
		sun_manual.pressed.connect(_toggle_sun_manual)
		_tabs.add_child(sun_manual)


func _build_roster_panel(snapshot: Dictionary) -> Control:
	var panel := _panel("함대 · 독립 전대", 320)
	var stack: VBoxContainer = panel.get_meta("stack")
	var permission := Label.new()
	permission.text = _permission_label()
	permission.add_theme_color_override("font_color", Color("8fd8ad") if _draft.can_edit_faction(_active_faction) else Color("d7a28f"))
	permission.add_theme_font_size_override("font_size", 14)
	stack.add_child(permission)
	var scroll := ScrollContainer.new()
	scroll.name = "SquadronRosterScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 5)
	scroll.add_child(list)
	for fleet_value in snapshot.get("fleet_groups", []):
		var fleet: Dictionary = fleet_value
		if String(fleet.get("faction_id", "")) != _active_faction:
			continue
		var fleet_label := Label.new()
		fleet_label.text = "◆ %s" % String(fleet.get("name", "함대"))
		fleet_label.add_theme_font_size_override("font_size", 15)
		fleet_label.add_theme_color_override("font_color", Color("e0c77f"))
		list.add_child(fleet_label)
		for squadron_id in fleet.get("squadron_ids", []):
			_add_squadron_button(list, snapshot, String(squadron_id), "  └ ")
	var independent_added := false
	for squad_value in snapshot.get("squadrons", []):
		var squad: Dictionary = squad_value
		if String(squad.get("faction_id", "")) != _active_faction \
				or String(squad.get("deployment", {}).get("kind", "")) != "independent":
			continue
		if not independent_added:
			var independent := Label.new()
			independent.text = "◇ 독립 전대"
			independent.add_theme_color_override("font_color", Color("9fc8d6"))
			list.add_child(independent)
			independent_added = true
		_add_squadron_button(list, snapshot, String(squad.get("id", "")), "  └ ")

	var fleet_name := LineEdit.new()
	fleet_name.name = "NewFleetName"
	fleet_name.placeholder_text = "새 함대 이름"
	fleet_name.custom_minimum_size.y = 44
	fleet_name.editable = _draft.can_edit_faction(_active_faction)
	stack.add_child(fleet_name)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	stack.add_child(row)
	var create := _button("선택 전대로 함대 생성", "CreateFleet", 190)
	create.disabled = not _draft.can_edit_faction(_active_faction) or _selected_squadron.is_empty()
	create.pressed.connect(_create_fleet.bind(fleet_name))
	row.add_child(create)
	var unassign := _button("독립화", "UnassignSquadron", 96)
	unassign.disabled = not _draft.can_edit_faction(_active_faction) or _selected_squadron.is_empty()
	unassign.pressed.connect(_unassign_selected)
	row.add_child(unassign)
	var fleet_select := OptionButton.new()
	fleet_select.name = "FleetAssignment"
	fleet_select.custom_minimum_size.y = 44
	for fleet_value in snapshot.get("fleet_groups", []):
		var fleet: Dictionary = fleet_value
		if String(fleet.get("faction_id", "")) == _active_faction:
			fleet_select.add_item(String(fleet.get("name", "함대")))
			fleet_select.set_item_metadata(fleet_select.item_count - 1, String(fleet.get("id", "")))
	stack.add_child(fleet_select)
	var assign := _button("선택 함대에 편입", "AssignSquadron", 190)
	assign.disabled = not _draft.can_edit_faction(_active_faction) or fleet_select.item_count == 0
	assign.pressed.connect(_assign_selected.bind(fleet_select))
	var fleet_actions := HBoxContainer.new()
	fleet_actions.add_theme_constant_override("separation", 6)
	fleet_actions.add_child(assign)
	var rename := _button("선택 함대 이름 변경", "RenameFleet", 190)
	rename.disabled = not _draft.can_edit_faction(_active_faction) or fleet_select.item_count == 0
	rename.pressed.connect(_rename_selected_fleet.bind(fleet_name, fleet_select))
	fleet_actions.add_child(rename)
	stack.add_child(fleet_actions)
	return panel


func _build_composition_panel(snapshot: Dictionary) -> Control:
	var panel := _panel("선택 전대 편성", 720)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stack: VBoxContainer = panel.get_meta("stack")
	var squad := _find_squad(snapshot, _selected_squadron)
	if squad.is_empty():
		var empty := Label.new(); empty.text = "전대를 선택하세요."; stack.add_child(empty); return panel
	var editable: bool = _draft.can_edit_faction(String(squad.get("faction_id", "")))
	var heading := Label.new()
	heading.text = "%s  ·  %s" % [String(squad.get("name", "전대")), "편집 가능" if editable else "읽기 전용"]
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", Color("e8d394"))
	stack.add_child(heading)

	var fields := GridContainer.new()
	fields.columns = 6
	fields.add_theme_constant_override("h_separation", 8)
	fields.add_theme_constant_override("v_separation", 5)
	stack.add_child(fields)
	_add_field_label(fields, "지휘관")
	var commander := OptionButton.new(); commander.name = "CommanderSelect"; commander.custom_minimum_size = Vector2(145, 44); commander.disabled = not editable
	var faction := _find_faction(snapshot, String(squad.get("faction_id", "")))
	for row in faction.get("demo_roster", []):
		commander.add_item("%s · 통솔 %d" % [row.get("name", ""), int(row.get("command", 0))])
		commander.set_item_metadata(commander.item_count - 1, String(row.get("id", "")))
		if String(row.get("id", "")) == String(squad.get("commander", {}).get("id", "")):
			commander.select(commander.item_count - 1)
	commander.item_selected.connect(_commander_changed.bind(commander))
	fields.add_child(commander)
	_add_field_label(fields, "진형")
	var formation := OptionButton.new(); formation.name = "FormationSelect"; formation.custom_minimum_size = Vector2(125, 44); formation.disabled = not editable
	for formation_id in RedCliffsDemoSetup.ALLOWED_FORMATION_IDS:
		formation.add_item(String(formation_id)); formation.set_item_metadata(formation.item_count - 1, formation_id)
		if String(squad.get("formation_id", "")) == formation_id: formation.select(formation.item_count - 1)
	formation.item_selected.connect(_formation_changed.bind(formation)); fields.add_child(formation)
	_add_field_label(fields, "좌표 X/Y")
	var coordinate_row := HBoxContainer.new()
	for axis in [0, 1]:
		var spin := SpinBox.new(); spin.name = "Position%s" % ("X" if axis == 0 else "Y"); spin.min_value = 0; spin.max_value = 1600 if axis == 0 else 900; spin.step = 1; spin.value = float(squad.get("initial_position", [0, 0])[axis]); spin.custom_minimum_size = Vector2(82, 44); spin.editable = editable; coordinate_row.add_child(spin)
		spin.value_changed.connect(_position_changed.bind(axis, spin))
	fields.add_child(coordinate_row)

	var scroll := ScrollContainer.new()
	scroll.name = "ShipCompositionScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(scroll)
	var rows := VBoxContainer.new(); rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL; rows.add_theme_constant_override("separation", 5); scroll.add_child(rows)
	for ship_value in snapshot.get("ship_types", []):
		var ship: Dictionary = ship_value
		rows.add_child(_build_ship_row(snapshot, squad, ship, editable))
	return panel


func _build_ship_row(_snapshot: Dictionary, squad: Dictionary, ship: Dictionary, editable: bool) -> Control:
	var row := HBoxContainer.new()
	row.name = "ShipRow_%s" % String(ship.get("id", ""))
	row.custom_minimum_size.y = 48
	row.add_theme_constant_override("separation", 8)
	var name := Label.new(); name.text = String(ship.get("name", "")); name.custom_minimum_size.x = 105; name.add_theme_font_size_override("font_size", 14); row.add_child(name)
	var cost := Label.new(); cost.text = "척당 %d" % int(ship.get("unit_cost", 0)); cost.custom_minimum_size.x = 72; cost.add_theme_color_override("font_color", Color("9eb6c0")); row.add_child(cost)
	var component := _find_component(squad, String(ship.get("id", "")))
	var inventory_receipt: Dictionary = _draft.faction_inventory_summary(String(squad.get("faction_id", "")))
	var inventory: Dictionary = inventory_receipt.get("inventory", {})
	var inventory_row: Dictionary = inventory.get(String(ship.get("id", "")), {})
	var quantity := SpinBox.new(); quantity.name = "ShipCount_%s" % String(ship.get("id", "")); quantity.min_value = 0; quantity.max_value = maxi(int(inventory_row.get("total", 0)), int(component.get("count", 0))); quantity.step = 1; quantity.value = int(component.get("count", 0)); quantity.custom_minimum_size = Vector2(105, 44); quantity.editable = editable; quantity.value_changed.connect(_ship_count_changed.bind(String(ship.get("id", "")), quantity)); row.add_child(quantity)
	var equipment := OptionButton.new(); equipment.name = "Equipment_%s" % String(ship.get("id", "")); equipment.custom_minimum_size = Vector2(155, 44); equipment.disabled = not editable or String(ship.get("id", "")) != RedCliffsDemoSetup.FAST_CRAFT_ID
	if String(ship.get("id", "")) == RedCliffsDemoSetup.FAST_CRAFT_ID:
		for eq in ship.get("mission_equipment", []):
			equipment.add_item("%s +%d" % [eq.get("name", ""), int(eq.get("unit_cost", 0))]); equipment.set_item_metadata(equipment.item_count - 1, String(eq.get("id", "")))
			if String(eq.get("id", "")) == String(component.get("mission_equipment_id", "")): equipment.select(equipment.item_count - 1)
		equipment.item_selected.connect(_equipment_changed.bind(equipment))
	else:
		equipment.add_item("해당 없음")
	row.add_child(equipment)
	var availability := Label.new(); availability.name = "ShipAvailability_%s" % String(ship.get("id", "")); availability.text = "가용 %d" % int(inventory_row.get("available", 0)); availability.custom_minimum_size.x = 90; availability.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; row.add_child(availability)
	return row


func _build_summary_panel(snapshot: Dictionary) -> Control:
	var panel := _panel("재고 · 지휘 한도", 390)
	var stack: VBoxContainer = panel.get_meta("stack")
	var metrics: Dictionary = _draft.squadron_metrics(_selected_squadron)
	var metric_label := Label.new(); metric_label.name = "CommandMetrics"; metric_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	metric_label.text = "현재 / 권장 비용  %d / %d\n초과율  %.1f%%  ·  단계 %d\n기동 %d%%  ·  명중 %d%%  ·  진형변경 %d%%" % [int(metrics.get("total_cost", 0)), int(metrics.get("recommended_cost", 0)), float(metrics.get("over_ratio", 0.0)) * 100.0, int(metrics.get("penalty_tier", 0)), int(metrics.get("mobility_percent", 0)), int(metrics.get("accuracy_percent", 0)), int(metrics.get("formation_change_percent", 0))]
	metric_label.add_theme_font_size_override("font_size", 15); metric_label.add_theme_color_override("font_color", Color("ffc987") if metrics.get("warning", false) else Color("9edbb8")); stack.add_child(metric_label)
	var application := Label.new(); application.name = "CommandPenaltyApplication"; application.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	application.text = _penalty_application_text(metrics.get("penalty_application", {}), metrics.get("pending_penalties", []))
	application.add_theme_color_override("font_color", Color("a8d9bd")); stack.add_child(application)
	stack.add_child(HSeparator.new())
	var inventory_scroll := ScrollContainer.new(); inventory_scroll.name = "InventoryScroll"; inventory_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; inventory_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; stack.add_child(inventory_scroll)
	var inventory_rows := VBoxContainer.new(); inventory_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL; inventory_scroll.add_child(inventory_rows)
	var inventory_receipt: Dictionary = _draft.faction_inventory_summary(_active_faction)
	var inventory_summary: Dictionary = inventory_receipt.get("inventory", {})
	for ship in snapshot.get("ship_types", []):
		var ship_id := String(ship.get("id", "")); var values: Dictionary = inventory_summary.get(ship_id, {})
		var label := Label.new(); label.name = "Inventory_%s" % ship_id
		label.text = "%s   가용 %s / 총 %s" % [ship.get("name", ship_id), str(values.get("available", "—")), str(values.get("total", "—"))]
		label.custom_minimum_size.y = 30; label.add_theme_font_size_override("font_size", 14); label.add_theme_color_override("font_color", Color("d2e1e5")); inventory_rows.add_child(label)
	if not bool(inventory_receipt.get("ok", false)):
		var unavailable := Label.new(); unavailable.text = " · ".join(inventory_receipt.get("errors", [])); unavailable.add_theme_color_override("font_color", Color("ff9b91")); inventory_rows.add_child(unavailable)
	return panel


func _penalty_application_text(application, pending) -> String:
	if not application is Dictionary: return "적용 상태 · 코어 영수증 없음"
	var labels := {"mobility_percent":"기동(이동)", "accuracy_percent":"명중(자원 소모 전)", "formation_change_percent":"진형 변경(해결 시작)"}
	var parts: Array[String] = []
	for key in ["mobility_percent", "accuracy_percent", "formation_change_percent"]:
		var state := String(application.get(key, "unavailable")); var active: bool = state.begins_with("active_") and not pending.has(key)
		parts.append("%s %s" % [String(labels[key]), "실제 적용" if active else "미적용"])
	return "적용 상태 · %s\n수동 명령과 AI 명령이 같은 코어 판정을 사용합니다." % " · ".join(parts)


func _select_faction(faction_id: String) -> void:
	_active_faction = faction_id
	_select_first_squadron()
	_status_text = _permission_label()
	_status_error = false
	_refresh()


func _toggle_sun_manual() -> void:
	_set_receipt(_draft.set_sun_manual(not _draft.can_edit_faction("sun_quan")))
	_refresh()


func _select_squadron(squadron_id: String) -> void:
	_selected_squadron = squadron_id
	_status_text = "선택 전대의 편성 초안을 표시합니다."
	_status_error = false
	_refresh()


func _ship_count_changed(value: float, ship_id: String, _spin: SpinBox) -> void:
	_set_receipt(_draft.set_ship_count(_selected_squadron, ship_id, int(value)))
	_refresh()


func _equipment_changed(index: int, option: OptionButton) -> void:
	_set_receipt(_draft.set_fast_equipment(_selected_squadron, String(option.get_item_metadata(index))))
	_refresh()


func _commander_changed(index: int, option: OptionButton) -> void:
	_set_receipt(_draft.set_commander(_selected_squadron, String(option.get_item_metadata(index))))
	_refresh()


func _formation_changed(index: int, option: OptionButton) -> void:
	_set_receipt(_draft.set_formation(_selected_squadron, String(option.get_item_metadata(index))))
	_refresh()


func _position_changed(_value: float, _axis: int, _spin: SpinBox) -> void:
	var x: SpinBox = find_child("PositionX", true, false)
	var y: SpinBox = find_child("PositionY", true, false)
	if x != null and y != null:
		_set_receipt(_draft.set_position(_selected_squadron, Vector2(x.value, y.value)))
		_refresh()


func _create_fleet(name_field: LineEdit) -> void:
	var receipt: Dictionary = _draft.create_fleet(_active_faction, name_field.text, [_selected_squadron])
	_set_receipt(receipt)
	_refresh()


func _assign_selected(option: OptionButton) -> void:
	if option.item_count == 0: return
	_set_receipt(_draft.assign_to_fleet(_selected_squadron, String(option.get_item_metadata(option.selected))))
	_refresh()


func _rename_selected_fleet(name_field: LineEdit, option: OptionButton) -> void:
	if option.item_count == 0: return
	_set_receipt(_draft.rename_fleet(String(option.get_item_metadata(option.selected)), name_field.text))
	_refresh()


func _unassign_selected() -> void:
	_set_receipt(_draft.unassign_to_independent(_selected_squadron))
	_refresh()


func _restore_historical() -> void:
	_set_receipt(_draft.restore_historical())
	_select_first_squadron()
	_status_text = "역사 편성을 초안에 복원했습니다. 편성 적용 전까지 반영되지 않습니다."
	_refresh()


func _cancel_draft() -> void:
	_set_receipt(_draft.cancel())
	_select_first_squadron()
	_status_text = "마지막 적용 상태로 변경을 취소했습니다."
	_refresh()


func _apply_draft() -> void:
	if _apply_in_progress:
		return
	if _draft.draft_digest() == _draft.applied_digest():
		_status_text = "적용할 편성 변경이 없습니다."
		_status_error = false
		_refresh()
		return
	_apply_in_progress = true
	var receipt: Dictionary = _draft.apply()
	_set_receipt(receipt)
	if bool(receipt.get("ok", false)):
		_status_text = "편성을 원자적으로 적용했습니다. 전투 준비 요약이 갱신되었습니다."
		formation_applied.emit(receipt.get("setup", {}).duplicate(true), receipt.get("summary", {}).duplicate(true))
	_apply_in_progress = false
	_refresh()


func _request_close() -> void:
	if _draft != null and _draft.draft_digest() != _draft.applied_digest():
		_status_text = "적용하지 않은 변경이 있습니다. 편성 적용 또는 변경 취소 후 닫아 주세요."
		_status_error = true
		_refresh()
		return
	close_requested.emit()


func _open_fast_craft_editor() -> void:
	if _draft == null: return
	if _draft.draft_digest() != _draft.applied_digest():
		_status_text = "기존 편성 변경을 먼저 적용하거나 취소한 뒤 고속정 임무 편성을 여세요."
		_status_error = true
		_refresh()
		return
	if _fast_craft_editor == null or not is_instance_valid(_fast_craft_editor):
		_fast_craft_editor = FastCraftEditor.new()
		_fast_craft_editor.name = "RedCliffFastCraftEditor"
		add_child(_fast_craft_editor)
		var receipt: Dictionary = _fast_craft_editor.configure(_draft.historical_snapshot(), _draft.applied_snapshot())
		if not bool(receipt.get("ok", false)):
			_set_receipt(receipt)
			_fast_craft_editor.queue_free()
			_fast_craft_editor = null
			_refresh()
			return
		_fast_craft_editor.close_requested.connect(func(): _fast_craft_editor.visible = false)
		_fast_craft_editor.loadout_applied.connect(_on_fast_craft_loadout_applied)
	else:
		var receipt: Dictionary = _fast_craft_editor.configure(_draft.historical_snapshot(), _draft.applied_snapshot())
		if not bool(receipt.get("ok", false)): _set_receipt(receipt); _refresh(); return
	_fast_craft_editor.visible = true
	_fast_craft_editor.move_to_front()


func _on_fast_craft_loadout_applied(receipt: Dictionary) -> void:
	var applied_setup: Dictionary = receipt.get("applied_setup", {})
	if applied_setup.is_empty():
		_set_receipt({"ok":false, "errors":["적용된 고속정 전투 편성이 누락되었습니다."]})
		return
	var configured: Dictionary = _draft.configure(_draft.historical_snapshot(), applied_setup)
	if not bool(configured.get("ok", false)):
		_set_receipt(configured)
		return
	_select_first_squadron()
	_status_text = "고속정 임무 편성을 전투 준비 편성에 적용했습니다. 전투 시작 뒤에는 불변입니다."
	_status_error = false
	formation_applied.emit(applied_setup.duplicate(true), _draft.summary().duplicate(true))
	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_request_close()
		get_viewport().set_input_as_handled()


func _select_first_squadron() -> void:
	_selected_squadron = ""
	if _draft == null: return
	for squad in _draft.draft_snapshot().get("squadrons", []):
		if String(squad.get("faction_id", "")) == _active_faction:
			_selected_squadron = String(squad.get("id", "")); return


func _set_receipt(receipt: Dictionary) -> void:
	_status_error = not bool(receipt.get("ok", false))
	_status_text = " · ".join(receipt.get("errors", [])) if _status_error else "초안 변경을 반영했습니다."


func _permission_label() -> String:
	if _active_faction == "liu_bei": return "연필  유비군 편성은 직접 수정할 수 있습니다."
	if _active_faction == "sun_quan": return "연필  손권군 수동 편집" if _draft.can_edit_faction("sun_quan") else "자물쇠  연합 편성 수동 설정을 켜야 수정할 수 있습니다."
	return "자물쇠  조조군은 AI 역사 편성 읽기 전용입니다."


func _add_squadron_button(parent: Control, snapshot: Dictionary, squadron_id: String, prefix: String) -> void:
	var squad := _find_squad(snapshot, squadron_id)
	if squad.is_empty(): return
	var button := _button("%s%s · 비용 %d" % [prefix, squad.get("name", squadron_id), int(squad.get("declared_total_cost", 0))], "Squadron_%s" % squadron_id, 280)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.toggle_mode = true
	button.button_pressed = squadron_id == _selected_squadron
	button.pressed.connect(_select_squadron.bind(squadron_id))
	parent.add_child(button)


func _panel(title_text: String, minimum_width: float) -> PanelContainer:
	var panel := PanelContainer.new(); panel.custom_minimum_size.x = minimum_width; panel.add_theme_stylebox_override("panel", _style(Color("08151e"), Color("466978")))
	var margin := MarginContainer.new(); margin.add_theme_constant_override("margin_left", 12); margin.add_theme_constant_override("margin_right", 12); margin.add_theme_constant_override("margin_top", 10); margin.add_theme_constant_override("margin_bottom", 10); panel.add_child(margin)
	var stack := VBoxContainer.new(); stack.add_theme_constant_override("separation", 7); margin.add_child(stack)
	var title := Label.new(); title.text = title_text; title.add_theme_font_size_override("font_size", 17); title.add_theme_color_override("font_color", Color("9bd8e7")); stack.add_child(title)
	panel.set_meta("stack", stack)
	return panel


func _button(text: String, node_name: String, width: float) -> Button:
	var button := Button.new(); button.name = node_name; button.text = text; button.custom_minimum_size = Vector2(width, 44); button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 14); button.add_theme_stylebox_override("normal", _style(Color("13232d"), Color("557584"))); button.add_theme_stylebox_override("hover", _style(Color("203743"), Color("d0ad61"))); button.add_theme_stylebox_override("pressed", _style(Color("0d1921"), Color("d0ad61"))); button.add_theme_stylebox_override("focus", _style(Color("192d38"), Color("f0d17b"))); button.add_theme_stylebox_override("disabled", _style(Color("091116"), Color("34434a")))
	return button


func _style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new(); style.bg_color = background; style.border_color = border; style.set_border_width_all(1); style.set_corner_radius_all(4); style.content_margin_left = 10; style.content_margin_right = 10; style.content_margin_top = 6; style.content_margin_bottom = 6; return style


func _add_field_label(parent: Control, text: String) -> void:
	var label := Label.new(); label.text = text; label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; label.add_theme_color_override("font_color", Color("9db5bf")); parent.add_child(label)


func _clear(parent: Node) -> void:
	for child in parent.get_children(): parent.remove_child(child); child.queue_free()


func _find_squad(snapshot: Dictionary, squadron_id: String) -> Dictionary:
	for squad in snapshot.get("squadrons", []):
		if String(squad.get("id", "")) == squadron_id: return squad
	return {}


func _find_faction(snapshot: Dictionary, faction_id: String) -> Dictionary:
	for faction in snapshot.get("factions", []):
		if String(faction.get("id", "")) == faction_id: return faction
	return {}


func _find_component(squad: Dictionary, ship_id: String) -> Dictionary:
	for component in squad.get("composition", []):
		if String(component.get("ship_type_id", "")) == ship_id: return component
	return {}
