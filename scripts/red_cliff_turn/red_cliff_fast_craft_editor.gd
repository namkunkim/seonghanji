class_name RedCliffFastCraftEditor
extends Control

## DEMO-RC-G6-01 — 고속정 전대와 요격·뇌격·정찰·구조 임무 장비·코스트 UI.
## 수량·재고·비용·초과 불이익은 RedCliffsFastCraftFormation receipt만 표시한다.

signal close_requested
signal loadout_applied(receipt: Dictionary)

const DraftScript := preload("res://core/demo_red_cliffs/red_cliffs_fast_craft_formation.gd")
const FACTION_LABELS := {"liu_bei":"유비군 · 직접 편집", "sun_quan":"손권군 · 연합 설정", "cao_cao":"조조군 · AI 읽기 전용"}
const MISSION_LABELS := {"intercept":"요격", "torpedo":"뇌격", "recon":"정찰", "rescue":"구조"}

var _draft
var _active_faction := "liu_bei"
var _selected_squadron := ""
var _body: HBoxContainer
var _tabs: HBoxContainer
var _status: Label
var _apply: Button
var _status_text := "역사 고속정 편성을 불러왔습니다."
var _status_error := false
var _applying := false


func configure(historical_setup: Dictionary, applied_setup: Dictionary = {}) -> Dictionary:
	_draft = DraftScript.new()
	var receipt: Dictionary = _draft.configure(historical_setup, applied_setup)
	if bool(receipt.get("ok", false)):
		_select_first()
	else:
		_set_receipt(receipt)
	if is_node_ready(): _refresh()
	return receipt


func draft_controller(): return _draft


func editor_state() -> Dictionary:
	if _draft == null: return {"ready":false}
	return {"ready":true, "active_faction":_active_faction, "selected_squadron":_selected_squadron,
		"dirty":_draft.draft_digest() != _draft.applied_digest(), "applied":_draft.applied_snapshot()}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build(); _refresh(); set_process_unhandled_key_input(true)


func _build() -> void:
	var background := ColorRect.new(); background.color = Color("030910"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); background.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(background)
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left","margin_right"]: margin.add_theme_constant_override(side, 22)
	for side in ["margin_top","margin_bottom"]: margin.add_theme_constant_override(side, 16)
	add_child(margin)
	var root_box := VBoxContainer.new(); root_box.add_theme_constant_override("separation", 9); margin.add_child(root_box)
	var header := HBoxContainer.new(); header.custom_minimum_size.y = 55; root_box.add_child(header)
	var title := Label.new(); title.text = "적 벽 대 전  ·  고속정 임무 편성"; title.add_theme_font_size_override("font_size", 27); title.add_theme_color_override("font_color", Color("ead49a")); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; header.add_child(title)
	var profile := Label.new(); profile.name = "FastCraftProfile"; profile.text = "normal-demo-fast-craft-v1 · 전투 준비 전용"; profile.add_theme_color_override("font_color", Color("9fc0ce")); profile.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; header.add_child(profile)
	var distinction := Label.new(); distinction.name = "FastCraftCategoryBoundary"; distinction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; distinction.text = "고속정(SHP-08 · 소형 전투정) ≠ 요격함(SHP-07 · 독립 고속 전투함) · 재고와 비용을 합산하지 않습니다."; distinction.add_theme_color_override("font_color", Color("f0c978")); distinction.custom_minimum_size.y = 36; root_box.add_child(distinction)
	_tabs = HBoxContainer.new(); _tabs.add_theme_constant_override("separation", 8); root_box.add_child(_tabs)
	_body = HBoxContainer.new(); _body.name = "FastCraftEditorBody"; _body.size_flags_vertical = Control.SIZE_EXPAND_FILL; _body.add_theme_constant_override("separation", 10); root_box.add_child(_body)
	var footer := HBoxContainer.new(); footer.name = "FastCraftFixedFooter"; footer.custom_minimum_size.y = 62; footer.add_theme_constant_override("separation", 8); root_box.add_child(footer)
	_status = Label.new(); _status.name = "FastCraftStatus"; _status.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; footer.add_child(_status)
	var restore := _button("역사 고속정 편성 복원", "RestoreFastCraftHistorical", 190); restore.pressed.connect(_restore); footer.add_child(restore)
	var cancel := _button("변경 취소", "CancelFastCraftDraft", 120); cancel.pressed.connect(_cancel); footer.add_child(cancel)
	_apply = _button("고속정 편성 적용", "ApplyFastCraftDraft", 165); _apply.pressed.connect(_apply_draft); footer.add_child(_apply)
	var close := _button("편성 화면으로", "CloseFastCraftEditor", 145); close.pressed.connect(_request_close); footer.add_child(close)


func _refresh() -> void:
	if _body == null: return
	_clear(_tabs); _clear(_body)
	if _draft == null:
		_status.text = "고속정 편성 데이터를 불러오지 못했습니다."; _status.add_theme_color_override("font_color", Color("ff9b91")); _apply.disabled = true; return
	for faction_id in ["liu_bei", "sun_quan", "cao_cao"]:
		var tab := _button(String(FACTION_LABELS[faction_id]), "FastFaction_%s" % faction_id, 250); tab.toggle_mode = true; tab.button_pressed = faction_id == _active_faction; tab.pressed.connect(_select_faction.bind(faction_id)); _tabs.add_child(tab)
	if _active_faction == "sun_quan":
		var manual := _button("손권 수동 편성 전환", "FastSunManual", 180); manual.pressed.connect(_toggle_sun_manual); _tabs.add_child(manual)
	for row in _draft.faction_summary(_active_faction).get("squadrons", []):
		var id := String(row.get("squadron_id", "")); var select := _button(String(row.get("name", id)), "FastSquad_%s" % id, 180); select.toggle_mode = true; select.button_pressed = id == _selected_squadron; select.pressed.connect(_select_squadron.bind(id)); _tabs.add_child(select)
	var summary: Dictionary = _draft.squadron_summary(_selected_squadron)
	_body.add_child(_build_identity_panel(summary))
	_body.add_child(_build_mission_panel(summary))
	_body.add_child(_build_cost_panel(summary))
	_apply.disabled = _applying or not bool(_draft.validate_draft().get("ok", false)) or _draft.draft_digest() == _draft.applied_digest()
	_status.text = _status_text; _status.add_theme_color_override("font_color", Color("ff9b91") if _status_error else Color("a8d9bd"))


func _build_identity_panel(summary: Dictionary) -> Control:
	var panel := _panel("독립 고속정 전대", 330); var stack: VBoxContainer = panel.get_meta("stack")
	var permission := Label.new(); permission.name = "FastCraftPermission"; permission.text = "편집 가능" if _draft.can_edit_faction(_active_faction) else ("연합 수동 설정 필요" if _active_faction == "sun_quan" else "AI 역사 편성 · 읽기 전용"); permission.add_theme_color_override("font_color", Color("8fd8ad") if _draft.can_edit_faction(_active_faction) else Color("d7a28f")); stack.add_child(permission)
	var name := Label.new(); name.name = "FastCraftSquadronName"; name.text = "%s\n%s · 독립 배치" % [String(summary.get("name", "고속정 전대")), String(summary.get("squadron_id", ""))]; name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; name.add_theme_font_size_override("font_size", 18); name.add_theme_color_override("font_color", Color("e8d394")); stack.add_child(name)
	var commander: Dictionary = summary.get("commander", {}); var commander_label := Label.new(); commander_label.text = "지휘관  %s · 통솔 %d" % [String(commander.get("name", "—")), int(commander.get("command", 0))]; stack.add_child(commander_label)
	stack.add_child(HSeparator.new())
	var history := Label.new(); history.name = "FastCraftHistoricalBaseline"; history.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; history.text = "역사 기본  %d척 · 비용 %d\n현재 초안  %d척 · 임무 %s" % [int(summary.get("historical_count", 0)), int(summary.get("historical_total_cost", 0)), int(summary.get("count", 0)), _mission_label(String(summary.get("mission_id", "")))]; stack.add_child(history)
	var boundary := Label.new(); boundary.name = "FastCraftScopeBoundary"; boundary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; boundary.text = "전투 시작 전에만 편성합니다. 적용된 전투에서는 장비 구성이 변경되지 않습니다. 전술 임무와 자동 보급 상태는 전투 화면에서 표시하며, 자동 귀환·표류·구조 결과는 후속 기능입니다."; boundary.add_theme_color_override("font_color", Color("91aab5")); stack.add_child(boundary)
	var actions := HBoxContainer.new(); actions.add_theme_constant_override("separation", 6); stack.add_child(actions)
	var create := _button("여유 재고로 생성", "CreateFastCraftSquadron", 135); create.disabled = not _draft.can_edit_faction(_active_faction); create.pressed.connect(_create_spare); actions.add_child(create)
	var split := _button("혼성 고속정 분리", "SplitFastCraftSquadron", 135); split.disabled = not _draft.can_edit_faction(_active_faction); split.pressed.connect(_split_mixed); actions.add_child(split)
	var remove := _button("선택 전대 해체", "DeleteFastCraftSquadron", 125); remove.disabled = _selected_squadron.is_empty() or not _draft.can_edit_faction(_active_faction); remove.pressed.connect(_delete_selected); actions.add_child(remove)
	var deployment := _button("독립 ↔ 함대 편입", "ToggleFastCraftDeployment", 150); deployment.disabled = summary.is_empty() or not _draft.can_edit_faction(_active_faction); deployment.pressed.connect(_toggle_deployment); stack.add_child(deployment)
	var basing := _button("운용 기반 전환", "CycleFastCraftBasing", 150); basing.disabled = summary.is_empty() or not _draft.can_edit_faction(_active_faction); basing.pressed.connect(_cycle_basing); stack.add_child(basing)
	var model := Label.new(); model.name = "FastCraftDeploymentModel"; model.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; model.text = "지휘 배치: %s · 운용 기반: %s\n독립/함대 편입과 독립정·강습모함 탑재형·거점 배치형을 준비 단계에서 지정합니다. 자동 보급은 전투 화면에 표시하며 발진·복귀 결과는 후속 기능입니다." % [String(summary.get("deployment", {}).get("kind", "—")), String(summary.get("basing_mode", "—"))]; stack.add_child(model)
	return panel


func _build_mission_panel(summary: Dictionary) -> Control:
	var panel := _panel("임무 장비 1종 선택 · 척수", 650); panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL; var stack: VBoxContainer = panel.get_meta("stack")
	var count_row := HBoxContainer.new(); count_row.add_theme_constant_override("separation", 10); stack.add_child(count_row)
	var count_label := Label.new(); count_label.text = "고속정 척수"; count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; count_label.custom_minimum_size.x = 130; count_row.add_child(count_label)
	var count := SpinBox.new(); count.name = "FastCraftCount"; count.min_value = 1; count.max_value = 999; count.step = 1; count.value = int(summary.get("count", 1)); count.custom_minimum_size = Vector2(150,44); count.editable = _draft.can_edit_faction(_active_faction); count.value_changed.connect(_count_changed); count_row.add_child(count)
	var scroll := ScrollContainer.new(); scroll.name = "FastCraftMissionScroll"; scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; stack.add_child(scroll)
	var rows := VBoxContainer.new(); rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL; rows.add_theme_constant_override("separation", 8); scroll.add_child(rows)
	var catalog: Dictionary = _draft.catalog()
	for value in catalog.get("missions", []):
		if not value is Dictionary: continue
		var mission: Dictionary = value; var selected := String(summary.get("equipment_id", "")) == String(mission.get("equipment_id", ""))
		var button := _button(("● " if selected else "○ ") + "%s 장비" % String(mission.get("label", _mission_label(String(mission.get("mission_id", ""))))), "FastMission_%s" % String(mission.get("mission_id", "")), 590); button.alignment = HORIZONTAL_ALIGNMENT_LEFT; button.disabled = not _draft.can_edit_faction(_active_faction); button.pressed.connect(_equipment_changed.bind(String(mission.get("equipment_id", "")))); rows.add_child(button)
		var cost := Label.new(); cost.name = "FastMissionCost_%s" % String(mission.get("mission_id", "")); cost.text = "    선체 단가 %d + 장비비 %d = 척당 총 %d · 고속정 전용" % [int(mission.get("base_unit_cost", 0)), int(mission.get("equipment_unit_cost", 0)), int(mission.get("total_unit_cost", 0))]; cost.add_theme_color_override("font_color", Color("9eb6c0")); rows.add_child(cost)
	return panel


func _build_cost_panel(summary: Dictionary) -> Control:
	var panel := _panel("비용 · 재고 · 지휘 한도", 420); var stack: VBoxContainer = panel.get_meta("stack")
	var costs := Label.new(); costs.name = "FastCraftCostSummary"; costs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; costs.text = "선체 단가  %d\n장비비  %d\n척당 총비용  %d\n척수  %d\n전대 소계  %d" % [int(summary.get("base_unit_cost", 0)), int(summary.get("equipment_unit_cost", 0)), int(summary.get("total_unit_cost", 0)), int(summary.get("count", 0)), int(summary.get("subtotal_cost", 0))]; stack.add_child(costs)
	stack.add_child(HSeparator.new())
	var faction: Dictionary = _draft.faction_summary(_active_faction); var inventory: Dictionary = faction.get("inventory", {})
	var stock := Label.new(); stock.name = "FastCraftInventorySummary"; stock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; stock.text = "시나리오 재고  %d\n기존 전대 배치  %d\n고속정대 예약  %d\n잔여  %d" % [int(inventory.get("total", 0)), int(inventory.get("committed_other_squadrons", 0)), int(inventory.get("reserved_fast_craft_squadrons", 0)), int(inventory.get("remaining", 0))]; stock.add_theme_color_override("font_color", Color("a8d9bd") if bool(faction.get("within_inventory", false)) else Color("ff9b91")); stack.add_child(stock)
	stack.add_child(HSeparator.new())
	var penalty: Dictionary = summary.get("penalties", {}); var metrics := Label.new(); metrics.name = "FastCraftCommandMetrics"; metrics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; metrics.text = "현재 / 권장 비용  %d / %d\n초과율  %.2f%% · 단계 %d\n기동 %d%% · 명중 %d%% · 진형변경 %d%%" % [int(summary.get("subtotal_cost", 0)), int(summary.get("recommended_cost", 0)), float(int(summary.get("over_ratio_basis_points", 0))) / 100.0, int(summary.get("penalty_tier", 0)), int(penalty.get("mobility_percent", 0)), int(penalty.get("accuracy_percent", 0)), int(penalty.get("formation_change_percent", 0))]; metrics.add_theme_color_override("font_color", Color("ffc987") if bool(summary.get("over_cap_warning", false)) else Color("9edbb8")); stack.add_child(metrics)
	var warning := Label.new(); warning.name = "FastCraftBudgetWarning"; warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; warning.text = "초과 편성은 적용 가능합니다. 기동·명중·진형변경 수치는 모두 공개 코어 영수증의 실제 전투 소비 상태입니다." if bool(summary.get("over_cap_warning", false)) else "권장 지휘 비용 이내입니다."; stack.add_child(warning)
	return panel


func _select_faction(faction_id: String) -> void: _active_faction = faction_id; _select_first(); _status_text = "선택 세력의 고속정 초안을 표시합니다."; _status_error = false; _refresh()
func _select_squadron(squadron_id: String) -> void: _selected_squadron = squadron_id; _status_text = "고속정 전대를 선택했습니다."; _status_error = false; _refresh()
func _count_changed(value: float) -> void: _set_receipt(_draft.set_count(_selected_squadron, int(value))); _refresh()
func _equipment_changed(equipment_id: String) -> void: _set_receipt(_draft.set_equipment(_selected_squadron, equipment_id)); _refresh()
func _toggle_sun_manual() -> void: _set_receipt(_draft.set_sun_manual(not _draft.can_edit_faction("sun_quan"))); _select_first(); _refresh()

func _create_spare() -> void:
	var commander := _unused_commander(_active_faction); var position := _default_position()
	if commander.is_empty(): _set_receipt({"ok":false,"errors":["새 전대에 배치할 가용 장수가 없습니다."]}); _refresh(); return
	var receipt: Dictionary = _draft.create_squadron(_active_faction, "신규 고속정대", commander, 1, "FAST-EQ-RECON", "FRM-06", position)
	_set_receipt(receipt); if receipt.ok: _selected_squadron = String(receipt.squadron_id); _refresh()

func _split_mixed() -> void:
	var commander := _unused_commander(_active_faction); var source := _first_mixed_fast_squadron(_active_faction)
	if commander.is_empty() or source.is_empty(): _set_receipt({"ok":false,"errors":["분리할 혼성 고속정 또는 가용 장수가 없습니다."]}); _refresh(); return
	var receipt: Dictionary = _draft.split_from_mixed_squadron(source, "혼성 분리 고속정대", commander, 1, "FAST-EQ-RECON", "FRM-06", _default_position())
	_set_receipt(receipt); if receipt.ok: _selected_squadron = String(receipt.squadron_id); _refresh()

func _delete_selected() -> void: _set_receipt(_draft.delete_squadron(_selected_squadron)); _select_first(); _refresh()
func _toggle_deployment() -> void:
	var summary: Dictionary = _draft.squadron_summary(_selected_squadron); var current := String(summary.get("deployment", {}).get("kind", "independent")); var fleet_id := _first_fleet_id(_active_faction)
	_set_receipt(_draft.set_deployment(_selected_squadron, "independent" if current == "fleet" else "fleet", "" if current == "fleet" else fleet_id)); _refresh()
func _cycle_basing() -> void:
	var modes := ["independent", "carrier", "base"]; var current := String(_draft.squadron_summary(_selected_squadron).get("basing_mode", "independent")); _set_receipt(_draft.set_basing_mode(_selected_squadron, String(modes[(modes.find(current) + 1) % modes.size()]))); _refresh()


func _restore() -> void: _set_receipt(_draft.restore_historical()); _select_first(); _status_text = "역사 고속정 편성을 초안에 복원했습니다."; _refresh()
func _cancel() -> void: _set_receipt(_draft.cancel()); _select_first(); _status_text = "마지막 적용 고속정 편성으로 변경을 취소했습니다."; _refresh()
func _apply_draft() -> void:
	if _applying: return
	if _draft.draft_digest() == _draft.applied_digest(): _status_text = "적용할 고속정 편성 변경이 없습니다."; _status_error = false; _refresh(); return
	_applying = true; var receipt: Dictionary = _draft.apply(); _set_receipt(receipt)
	if bool(receipt.get("ok", false)): _status_text = "고속정 편성을 원자적으로 적용했습니다. 전투 배치 후에는 불변입니다."; loadout_applied.emit(receipt.duplicate(true))
	_applying = false; _refresh()
func _request_close() -> void:
	if _draft != null and _draft.draft_digest() != _draft.applied_digest(): _status_text = "적용하지 않은 변경이 있습니다. 적용 또는 변경 취소 후 닫아 주세요."; _status_error = true; _refresh(); return
	close_requested.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE: _request_close(); get_viewport().set_input_as_handled()


func _select_first() -> void:
	_selected_squadron = ""
	if _draft == null: return
	for value in _draft.faction_summary(_active_faction).get("squadrons", []):
		if value is Dictionary and bool(value.get("ok", false)): _selected_squadron = String(value.get("squadron_id", "")); return
func _unused_commander(faction_id: String) -> String:
	var setup: Dictionary = _draft.draft_snapshot(); var used := {}
	for squad in setup.squadrons:
		if String(squad.faction_id) == faction_id: used[String(squad.commander.id)] = true
	for faction in setup.factions:
		if String(faction.id) == faction_id:
			for commander in faction.demo_roster:
				if not used.has(String(commander.id)): return String(commander.id)
	return ""
func _first_mixed_fast_squadron(faction_id: String) -> String:
	for squad in _draft.draft_snapshot().squadrons:
		if String(squad.faction_id) != faction_id or squad.composition.size() <= 1: continue
		if squad.composition.any(func(row): return String(row.ship_type_id) == "SHP-08" and int(row.count) > 0): return String(squad.id)
	return ""
func _first_fleet_id(faction_id: String) -> String:
	for fleet in _draft.draft_snapshot().fleet_groups:
		if String(fleet.faction_id) == faction_id: return String(fleet.id)
	return ""
func _default_position() -> Vector2:
	var bounds: Array = _draft.draft_snapshot().battlefield_bounds; return Vector2(float(bounds[0]) + 20.0, float(bounds[1]) + 20.0)
func _set_receipt(receipt: Dictionary) -> void: _status_error = not bool(receipt.get("ok", false)); _status_text = " · ".join(receipt.get("errors", [])) if _status_error else "고속정 편성 초안을 갱신했습니다."
func _mission_label(id: String) -> String: return String(MISSION_LABELS.get(id, id))
func _clear(parent: Node) -> void:
	for child in parent.get_children(): parent.remove_child(child); child.queue_free()


func _panel(title_text: String, width: float) -> PanelContainer:
	var panel := PanelContainer.new(); panel.custom_minimum_size.x = width; panel.add_theme_stylebox_override("panel", _style(Color("08151e"), Color("466978")))
	var margin := MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	panel.add_child(margin)
	var stack := VBoxContainer.new(); stack.add_theme_constant_override("separation", 8); margin.add_child(stack)
	var title := Label.new(); title.text = title_text; title.add_theme_font_size_override("font_size", 17); title.add_theme_color_override("font_color", Color("9bd8e7")); stack.add_child(title); panel.set_meta("stack", stack); return panel
func _button(text_value: String, node_name: String, width: float) -> Button:
	var button := Button.new(); button.name = node_name; button.text = text_value; button.custom_minimum_size = Vector2(width,44); button.focus_mode = Control.FOCUS_ALL; button.add_theme_stylebox_override("normal", _style(Color("13232d"), Color("557584"))); button.add_theme_stylebox_override("hover", _style(Color("203743"), Color("d0ad61"))); button.add_theme_stylebox_override("focus", _style(Color("192d38"), Color("f0d17b"))); button.add_theme_stylebox_override("disabled", _style(Color("091116"), Color("34434a"))); return button
func _style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new(); style.bg_color = background; style.border_color = border; style.set_border_width_all(1); style.set_corner_radius_all(4); style.content_margin_left = 10; style.content_margin_right = 10; style.content_margin_top = 6; style.content_margin_bottom = 6; return style
