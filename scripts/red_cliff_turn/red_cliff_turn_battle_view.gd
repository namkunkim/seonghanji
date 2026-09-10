class_name RedCliffTurnBattleView
extends Control

## DEMO-RC-G4-01 — 유비 명령·손권 제어 선택·20턴 판정 루프.
## 턴 규칙과 전이는 RedCliffsTurnBattle 공개 API/snapshot만 소비한다.

signal close_requested
signal state_changed(snapshot: Dictionary)

const PHASE_LABELS := {
	"liu_command": "유비군 명령",
	"sun_control_prompt": "손권군 제어 선택",
	"sun_command": "손권군 수동 명령",
	"resolution": "명령 원장 판정",
	"victory_check": "승리 조건 판정 대기",
	"turn_limit_reached": "20턴 결과 판정 대기",
}
const FACTION_NAMES := {"liu_bei": "유비군", "sun_quan": "손권군", "cao_cao": "조조군"}
const FACTION_COLORS := {"liu_bei": Color("63c58a"), "sun_quan": Color("df7d72"), "cao_cao": Color("69add5")}
const TacticalMap := preload("res://scripts/red_cliff_turn/red_cliff_tactical_map.gd")

var _battle
var _applied_revision := 0
var _applied_digest := ""
var _busy := false
var _last_error := ""
var _header: Label
var _phase_text: Label
var _steps: VBoxContainer
var _map
var _orders: VBoxContainer
var _log: RichTextLabel
var _status: Label
var _primary: Button
var _prompt: PanelContainer
var _reenable_prompt: Button
var _squad_list: VBoxContainer
var _selected_squadron_id := ""
var _move_armed := false
var _coordinate_x: SpinBox
var _coordinate_y: SpinBox
var _facing: SpinBox
var _waypoint_rows: VBoxContainer
var _preview_text: Label
var _map_mode_text: Label
var _viewer_faction_id := "liu_bei"
var _ledger_phase_filter := ""
var _selected_contact_id := ""


func configure(battle_controller, applied_revision: int, applied_digest: String) -> Dictionary:
	if battle_controller == null or battle_controller.phase() == "uninitialized":
		return {"ok": false, "errors": ["초기화된 턴 전투가 필요합니다."]}
	_battle = battle_controller
	_applied_revision = applied_revision
	_applied_digest = applied_digest
	if is_node_ready():
		_refresh()
	return {"ok": true, "errors": []}


func view_state() -> Dictionary:
	if _battle == null: return {"ready": false}
	return {"ready": true, "turn": _battle.turn(), "phase": _battle.phase(),
		"applied_revision": _applied_revision, "applied_digest": _applied_digest,
		"prompt_policy": _battle.prompt_policy(), "log_count": _battle.turn_log().size(),
		"busy": _busy}


func battle_controller():
	return _battle


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_refresh()
	set_process_unhandled_key_input(true)


func _build() -> void:
	var background := ColorRect.new(); background.color = Color("040a10"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); background.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(background)
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right"]: margin.add_theme_constant_override(side, 22)
	for side in ["margin_top", "margin_bottom"]: margin.add_theme_constant_override(side, 16)
	add_child(margin)
	var root_box := VBoxContainer.new(); root_box.add_theme_constant_override("separation", 9); margin.add_child(root_box)
	var header_row := HBoxContainer.new(); header_row.custom_minimum_size.y = 55; root_box.add_child(header_row)
	_header = Label.new(); _header.name = "TurnHeader"; _header.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _header.add_theme_font_size_override("font_size", 27); _header.add_theme_color_override("font_color", Color("ead49a")); header_row.add_child(_header)
	_phase_text = Label.new(); _phase_text.name = "CurrentPhase"; _phase_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; _phase_text.add_theme_font_size_override("font_size", 17); _phase_text.add_theme_color_override("font_color", Color("9fd4e2")); header_row.add_child(_phase_text)
	var body := HBoxContainer.new(); body.name = "TurnBattleBody"; body.size_flags_vertical = Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation", 10); root_box.add_child(body)
	var step_panel := _panel("진행 단계 / 전대", 225); body.add_child(step_panel); _steps = VBoxContainer.new(); _steps.name = "PhaseSteps"; _steps.add_theme_constant_override("separation", 4); step_panel.get_meta("stack").add_child(_steps)
	var squad_scroll := ScrollContainer.new(); squad_scroll.name = "DirectSquadronScroll"; squad_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; step_panel.get_meta("stack").add_child(squad_scroll)
	_squad_list = VBoxContainer.new(); _squad_list.name = "DirectSquadronList"; _squad_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; squad_scroll.add_child(_squad_list)
	var map_panel := _panel("2D 전술 지도 · 자유 좌표 이동", 700); map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL; body.add_child(map_panel)
	var map_tools := HBoxContainer.new(); map_tools.add_theme_constant_override("separation", 5); map_panel.get_meta("stack").add_child(map_tools)
	for row in [["선택", "MapModeSelect", 0], ["경유점 추가", "MapModeAdd", 1], ["지도 이동", "MapModePan", 2]]:
		var mode_button := _button(row[0], row[1], 112); mode_button.pressed.connect(_on_map_mode.bind(row[2])); map_tools.add_child(mode_button)
	var reset_camera := _button("보기 초기화", "ResetMapCamera", 110); reset_camera.pressed.connect(func(): _map.reset_camera()); map_tools.add_child(reset_camera)
	_map_mode_text = Label.new(); _map_mode_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _map_mode_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; _map_mode_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; map_tools.add_child(_map_mode_text)
	_map = TacticalMap.new(); _map.name = "AppliedSquadronMap"; _map.size_flags_vertical = Control.SIZE_EXPAND_FILL; _map.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _map.squadron_selected.connect(_on_map_squadron_selected); _map.contact_selected.connect(_on_map_contact_selected); _map.waypoint_requested.connect(_on_waypoint_requested); _map.interaction_rejected.connect(_on_interaction_rejected); map_panel.get_meta("stack").add_child(_map)
	var order_panel := _panel("이동 명령 초안", 405); body.add_child(order_panel)
	var order_scroll := ScrollContainer.new(); order_scroll.name = "MovementOrderScroll"; order_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; order_panel.get_meta("stack").add_child(order_scroll)
	_orders = VBoxContainer.new(); _orders.name = "CurrentFactionOrders"; _orders.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _orders.add_theme_constant_override("separation", 6); order_scroll.add_child(_orders)
	var footer := HBoxContainer.new(); footer.custom_minimum_size.y = 158; footer.add_theme_constant_override("separation", 10); root_box.add_child(footer)
	var log_panel := _panel("턴 명령 원장", 850); log_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL; footer.add_child(log_panel)
	_log = RichTextLabel.new(); _log.name = "TurnLedger"; _log.bbcode_enabled = true; _log.fit_content = false; _log.scroll_active = true; _log.size_flags_vertical = Control.SIZE_EXPAND_FILL; log_panel.get_meta("stack").add_child(_log)
	var action_panel := _panel("진행", 500); footer.add_child(action_panel); var action_stack: VBoxContainer = action_panel.get_meta("stack")
	_status = Label.new(); _status.name = "TurnStatus"; _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _status.size_flags_vertical = Control.SIZE_EXPAND_FILL; action_stack.add_child(_status)
	var controls := HBoxContainer.new(); controls.add_theme_constant_override("separation", 7); action_stack.add_child(controls)
	_reenable_prompt = _button("손권 문의 다시 켜기", "ReenableSunPrompt", 170); _reenable_prompt.pressed.connect(_on_reenable_prompt); controls.add_child(_reenable_prompt)
	_primary = _button("턴 진행", "PrimaryTurnAction", 155); _primary.pressed.connect(_on_primary); controls.add_child(_primary)
	var back := _button("준비 화면", "ReturnToPreparation", 120); back.pressed.connect(func(): close_requested.emit()); controls.add_child(back)
	_build_prompt()


func _build_prompt() -> void:
	_prompt = PanelContainer.new(); _prompt.name = "SunControlPrompt"; _prompt.custom_minimum_size = Vector2(580, 330); _prompt.add_theme_stylebox_override("panel", _style(Color("0b1b25"), Color("d1ad61"))); _prompt.visible = false; add_child(_prompt)
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.offset_left = -290; _prompt.offset_top = -165; _prompt.offset_right = 290; _prompt.offset_bottom = 165
	_prompt.mouse_filter = Control.MOUSE_FILTER_STOP
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	_prompt.add_child(margin)
	var stack := VBoxContainer.new(); stack.add_theme_constant_override("separation", 10); margin.add_child(stack)
	var title := Label.new(); title.text = "손권군을 이번 턴에 직접 지휘하시겠습니까?"; title.add_theme_font_size_override("font_size", 21); title.add_theme_color_override("font_color", Color("f0d48e")); stack.add_child(title)
	var note := Label.new(); note.text = "선택 전에는 Esc로 닫히지 않습니다. ‘더 이상 묻지 않음’은 AI 위임에만 적용됩니다."; note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; stack.add_child(note)
	var manual := _button("이번 턴 직접 명령", "SunManualThisTurn", 520); manual.pressed.connect(_on_sun_choice.bind("manual", false)); stack.add_child(manual)
	var ai := _button("이번 턴 AI 위임", "SunAiThisTurn", 520); ai.pressed.connect(_on_sun_choice.bind("ai", false)); stack.add_child(ai)
	var ai_always := _button("AI 위임하고 더 이상 묻지 않음", "SunAiDontAsk", 520); ai_always.pressed.connect(_on_sun_choice.bind("ai", true)); stack.add_child(ai_always)


func _refresh() -> void:
	if _battle == null or _header == null:
		return
	var snapshot: Dictionary = _battle.snapshot(); var phase: String = _battle.phase()
	_header.text = "적 벽 대 전  ·  턴 %d/%d" % [_battle.turn(), int(snapshot.get("max_turns", 20))]
	_phase_text.text = String(PHASE_LABELS.get(phase, phase))
	_rebuild_steps(phase); _rebuild_squad_list(snapshot); _rebuild_map(snapshot); _rebuild_orders(snapshot, phase); _rebuild_log()
	_prompt.visible = phase == "sun_control_prompt"
	if _prompt.visible:
		var first: Button = _prompt.find_child("SunManualThisTurn", true, false); if first != null: first.grab_focus()
	var policy_enabled := bool(_battle.prompt_policy().get("enabled", true))
	_reenable_prompt.disabled = _busy or policy_enabled or phase == "sun_control_prompt"
	var draft_summary: Dictionary = _battle.command_draft_summary()
	_primary.disabled = _busy or not ["liu_command", "sun_command", "victory_check"].has(phase) or (["liu_command", "sun_command"].has(phase) and not bool(draft_summary.get("all_orders_ready", false)))
	_primary.text = {"liu_command": "유비 명령 제출", "sun_command": "손권 명령 제출", "victory_check": "다음 턴"}.get(phase, "처리 대기")
	_status.text = _status_for_phase(phase)
	_status.add_theme_color_override("font_color", Color("ff9d91") if not _last_error.is_empty() else Color("a8d9bd"))
	state_changed.emit(_battle.snapshot())


func _rebuild_steps(phase: String) -> void:
	_clear(_steps)
	var order := ["liu_command", "sun_control_prompt", "sun_command", "resolution", "victory_check"]
	for step in order:
		var label := Label.new(); label.custom_minimum_size.y = 38; label.text = ("▶ " if step == phase else "○ ") + String(PHASE_LABELS[step]); label.add_theme_color_override("font_color", Color("f0cf7e") if step == phase else Color("77929d")); _steps.add_child(label)
	if phase == "turn_limit_reached":
		var limit := Label.new(); limit.text = "▶ 20/20 · 결과 판정 대기"; limit.add_theme_color_override("font_color", Color("f0cf7e")); _steps.add_child(limit)


func _rebuild_map(snapshot: Dictionary) -> void:
	var setup: Dictionary = snapshot.get("applied_setup", {})
	var direct: String = _battle.current_direct_faction_id()
	if not direct.is_empty(): _viewer_faction_id = direct
	if _battle.has_method("viewer_snapshot"):
		var viewer: Dictionary = _battle.viewer_snapshot(_viewer_faction_id)
		_map.configure(setup.get("battlefield_bounds", [0, 0, 1600, 900]), viewer.get("own_squadrons", []), viewer.get("own_navigation", {}))
		_map.set_intelligence(_viewer_faction_id, viewer.get("contacts", []), viewer.get("tactical_events", []))
		var selectable_contacts: Array[String] = []
		for value in viewer.get("contacts", []):
			if String(value.get("state", "")) == "estimated": selectable_contacts.append(String(value.get("contact_id", "")))
		if not selectable_contacts.has(_selected_contact_id): _selected_contact_id = ""
		_map.set_selected_contact(_selected_contact_id)
	else: _map.clear_intelligence()
	var editable := _editable_squadron_ids(snapshot)
	if not editable.has(_selected_squadron_id): _selected_squadron_id = editable[0] if not editable.is_empty() else ""
	var mode := TacticalMap.Mode.ADD_WAYPOINT if _move_armed else TacticalMap.Mode.SELECT
	_map.set_interaction(editable, _selected_squadron_id, mode)
	var order_result: Dictionary = _battle.command_order(_selected_squadron_id) if not _selected_squadron_id.is_empty() else {}
	var order: Dictionary = order_result.get("order", {})
	var preview: Dictionary = {}
	if String(order.get("action", "")) == "move": preview = _battle.movement_preview(_selected_squadron_id, order.get("waypoints", []), order.get("facing_deg", 0))
	_map.set_route(order, preview)
	_map_mode_text.text = "모드: %s" % ("경유점 추가" if _move_armed else "선택")


func _rebuild_squad_list(snapshot: Dictionary) -> void:
	_clear(_squad_list)
	for id in _editable_squadron_ids(snapshot):
		var squad := _find_squad(snapshot, id); var button := _button(("● " if id == _selected_squadron_id else "○ ") + String(squad.get("name", id)), "Select_%s" % id, 185)
		button.pressed.connect(_select_squadron.bind(id)); _squad_list.add_child(button)


func _rebuild_orders(snapshot: Dictionary, phase: String) -> void:
	_clear(_orders)
	var faction_id: String = _battle.current_direct_faction_id()
	var heading := Label.new(); heading.text = "%s · %s" % [FACTION_NAMES.get(faction_id, "자동 처리"), "직접 명령" if not faction_id.is_empty() else "입력 잠김"]; heading.add_theme_font_size_override("font_size", 17); _orders.add_child(heading)
	if _selected_squadron_id.is_empty():
		var empty := Label.new(); empty.text = "현재 편집 가능한 전대가 없습니다."; _orders.add_child(empty)
		_add_intelligence_panel()
		var viewer: Dictionary = _battle.viewer_snapshot(_viewer_faction_id) if _battle.has_method("viewer_snapshot") else {}
		var resource_ids: Array = viewer.get("own_combat_resources", {}).keys(); resource_ids.sort()
		if not resource_ids.is_empty(): _add_combat_resource_panel(String(resource_ids[0]))
		_add_phase_ledger()
		for future in ["탐지"]:
			var disabled_empty := _button("%s · 후속 기능 · 현재 사용 불가" % future, "Disabled%s" % future, 340); disabled_empty.disabled = true; _orders.add_child(disabled_empty)
		return
	var squad := _find_squad(snapshot, _selected_squadron_id)
	var selected := Label.new(); selected.text = "선택: %s" % String(squad.get("name", _selected_squadron_id)); selected.add_theme_color_override("font_color", Color("f0cf7e")); _orders.add_child(selected)
	var action_row := HBoxContainer.new(); _orders.add_child(action_row)
	var hold := _button("대기 HOLD", "SetOrderHold", 165); hold.pressed.connect(_on_set_hold); action_row.add_child(hold)
	var move := _button("이동 MOVE", "ArmOrderMove", 165); move.pressed.connect(_on_arm_move); action_row.add_child(move)
	var order_result: Dictionary = _battle.command_order(_selected_squadron_id); var order: Dictionary = order_result.get("order", {})
	var action := String(order.get("action", "hold")); var state := Label.new(); state.name = "OrderActionState"; state.text = "현재: %s%s" % [action.to_upper(), " · 첫 경유점 대기" if _move_armed and action != "move" else ""]; _orders.add_child(state)
	_add_formation_editor()
	_add_weapon_editor()
	_add_combat_resource_panel()
	var coord_row := HBoxContainer.new(); _orders.add_child(coord_row)
	_coordinate_x = _spin("CoordinateX", float(snapshot.get("applied_setup", {}).get("battlefield_bounds", [0,0,1600,900])[0]), float(snapshot.get("applied_setup", {}).get("battlefield_bounds", [0,0,1600,900])[0] + snapshot.get("applied_setup", {}).get("battlefield_bounds", [0,0,1600,900])[2])); coord_row.add_child(_coordinate_x)
	_coordinate_y = _spin("CoordinateY", float(snapshot.get("applied_setup", {}).get("battlefield_bounds", [0,0,1600,900])[1]), float(snapshot.get("applied_setup", {}).get("battlefield_bounds", [0,0,1600,900])[1] + snapshot.get("applied_setup", {}).get("battlefield_bounds", [0,0,1600,900])[3])); coord_row.add_child(_coordinate_y)
	var add_coord := _button("좌표 추가", "AddCoordinateWaypoint", 115); add_coord.pressed.connect(func(): _on_waypoint_requested([_coordinate_x.value, _coordinate_y.value])); coord_row.add_child(add_coord)
	_facing = _spin("FacingDegrees", 0, 359); _facing.prefix = "방향 ° "; _facing.value = float(order.get("facing_deg", _battle.live_navigation().get(_selected_squadron_id, {}).get("facing_deg", 0))); _facing.value_changed.connect(_on_facing_changed); _orders.add_child(_facing)
	_waypoint_rows = VBoxContainer.new(); _waypoint_rows.name = "WaypointRows"; _orders.add_child(_waypoint_rows)
	for index in range(order.get("waypoints", []).size()):
		var waypoint: Array = order.waypoints[index]; var waypoint_row := HBoxContainer.new(); _waypoint_rows.add_child(waypoint_row)
		var wp_label := Label.new(); wp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; wp_label.text = "%d. (%.1f, %.1f)" % [index + 1, float(waypoint[0]), float(waypoint[1])]; waypoint_row.add_child(wp_label)
		var remove := _button("삭제", "DeleteWaypoint%d" % (index + 1), 72); remove.pressed.connect(_delete_waypoint.bind(index)); waypoint_row.add_child(remove)
	var clear := _button("경유점 전체 초기화", "ClearWaypoints", 340); clear.disabled = action != "move"; clear.pressed.connect(_clear_waypoints); _orders.add_child(clear)
	_preview_text = Label.new(); _preview_text.name = "MovementPreview"; _preview_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _orders.add_child(_preview_text)
	_update_preview_text(order)
	_add_intelligence_panel()
	_add_estimated_fire_editor()
	_add_phase_ledger()
	for future in ["탐지"]:
		var disabled := _button("%s · 후속 기능 · 현재 사용 불가" % future, "Disabled%s" % future, 340); disabled.disabled = true; _orders.add_child(disabled)


func _rebuild_log() -> void:
	var lines: Array[String] = []
	var visible_log: Dictionary = _battle.viewer_turn_log(_viewer_faction_id) if _battle.has_method("viewer_turn_log") else {"turn_log": []}
	for value in visible_log.get("turn_log", []):
		var entry: Dictionary = value; var turn_number := int(entry.get("turn", 0)); var parts: Array[String] = []
		if not entry.get("own_orders", []).is_empty():
			var moved := 0
			for order in entry.own_orders: moved += 1 if String(order.get("action", "")) == "move" else 0
			parts.append("내 명령 %d · MOVE %d" % [entry.own_orders.size(), moved])
		var intersections := 0; var detections := 0; var shots := 0
		for event in entry.get("tactical_events", []):
			var kind := String(event.get("event_type", "")); intersections += 1 if kind == "path_intersection" else 0; detections += 1 if kind == "detection" else 0; shots += 1 if kind == "shot_authorized" else 0
		if intersections + detections + shots > 0: parts.append("교차 %d · 탐지 %d · 기회 사격 %d · 피해 판정 후속" % [intersections, detections, shots])
		if bool(entry.get("resolved", false)): parts.append("판정 확정 · rules_pending")
		lines.append("[턴 %d] %s" % [turn_number, " · ".join(parts) if not parts.is_empty() else "유비 명령 대기"])
	_log.text = "\n".join(lines); _log.scroll_to_line(maxi(0, lines.size() - 1))


func _on_primary() -> void:
	if _battle == null or _busy: return
	var phase: String = _battle.phase()
	if not ["liu_command", "sun_command", "victory_check"].has(phase): return
	_busy = true
	_last_error = ""; _primary.disabled = true
	var receipt: Dictionary
	if phase == "liu_command" or phase == "sun_command": receipt = _battle.submit_command_draft()
	elif phase == "victory_check": receipt = _battle.continue_turn()
	_set_receipt(receipt); _finish_automatic_resolution(); _refresh()
	await get_tree().process_frame
	_busy = false; _refresh()


func _on_sun_choice(answer: String, dont_ask: bool) -> void:
	if _battle == null or _battle.phase() != "sun_control_prompt" or _busy: return
	_busy = true
	_last_error = ""; _set_receipt(_battle.submit_sun_control_choice(answer, dont_ask)); _finish_automatic_resolution(); _busy = false; _refresh()


func _finish_automatic_resolution() -> void:
	if _battle.phase() == "resolution":
		_set_receipt(_battle.resolve_turn())


func _on_reenable_prompt() -> void:
	if _battle == null or _busy: return
	_busy = true
	_set_receipt(_battle.set_sun_prompt_enabled(true)); _busy = false; _refresh()


func _status_for_phase(phase: String) -> String:
	if not _last_error.is_empty(): return _last_error
	if phase == "liu_command": return "유비군 전대별 HOLD/MOVE 초안을 검토한 뒤 제출합니다."
	if phase == "sun_control_prompt": return "손권군 제어 방식을 선택해야 계속할 수 있습니다."
	if phase == "sun_command": return "손권군 전대별 HOLD/MOVE 초안을 검토한 뒤 제출합니다."
	if phase == "victory_check": return "진형·이동·경로 교차·탐지·기회 사격 판정이 확정되었습니다. 명중·피해·승패는 후속 구현 대기입니다."
	if phase == "turn_limit_reached": return "20/20 · 결과 판정 대기. 승자와 피해는 아직 계산하지 않았습니다."
	return "AI 명령 및 명령 원장을 처리하는 중입니다."


func _set_receipt(receipt: Dictionary) -> void:
	if not bool(receipt.get("ok", false)): _last_error = " · ".join(receipt.get("errors", []))


func _editable_squadron_ids(snapshot: Dictionary) -> Array[String]:
	var result: Array[String] = []; var direct: String = _battle.current_direct_faction_id()
	if direct.is_empty(): return result
	for value in snapshot.get("applied_setup", {}).get("squadrons", []):
		if value is Dictionary and String(value.get("faction_id", "")) == direct and bool(value.get("operational", true)):
			result.append(String(value.get("id", "")))
	return result


func _find_squad(snapshot: Dictionary, id: String) -> Dictionary:
	for value in snapshot.get("applied_setup", {}).get("squadrons", []):
		if value is Dictionary and String(value.get("id", "")) == id: return value
	return {}


func _select_squadron(id: String) -> void:
	if not _editable_squadron_ids(_battle.snapshot()).has(id):
		_last_error = "현재 단계에서 직접 지휘할 수 없는 전대입니다."; _refresh(); return
	_selected_squadron_id = id; _move_armed = false; _last_error = ""; _refresh()


func _on_map_squadron_selected(id: String) -> void: _select_squadron(id)


func _on_map_contact_selected(contact_id: String) -> void:
	var contact := _viewer_contact(contact_id)
	if contact.is_empty() or String(contact.get("state", "")) != "estimated":
		_last_error = "현재 추정 상태인 접촉만 선택할 수 있습니다."; _refresh(); return
	_selected_contact_id = contact_id; _move_armed = false; _last_error = ""; _refresh()


func _on_map_mode(mode: int) -> void:
	if mode == TacticalMap.Mode.ADD_WAYPOINT:
		_on_arm_move(); return
	_move_armed = false; _map.set_interaction(_editable_squadron_ids(_battle.snapshot()), _selected_squadron_id, mode)
	_map_mode_text.text = "모드: %s" % ("지도 이동" if mode == TacticalMap.Mode.PAN else "선택")


func _on_arm_move() -> void:
	if _selected_squadron_id.is_empty() or not _editable_squadron_ids(_battle.snapshot()).has(_selected_squadron_id): return
	_move_armed = true; _last_error = ""; _refresh()


func _on_set_hold() -> void:
	_move_armed = false; _set_receipt(_battle.set_order_hold(_selected_squadron_id)); _refresh()


func _on_waypoint_requested(point: Array) -> void:
	if not _move_armed or not _editable_squadron_ids(_battle.snapshot()).has(_selected_squadron_id):
		_last_error = "MOVE와 경유점 추가 모드에서만 좌표를 추가할 수 있습니다."; _refresh(); return
	var order_result: Dictionary = _battle.command_order(_selected_squadron_id); var order: Dictionary = order_result.get("order", {})
	var points: Array = order.get("waypoints", []).duplicate(true) if String(order.get("action", "")) == "move" else []
	points.append(point.duplicate())
	var facing_value := float(_facing.value) if _facing != null else float(_battle.live_navigation().get(_selected_squadron_id, {}).get("facing_deg", 0))
	var receipt: Dictionary = _battle.set_order_move(_selected_squadron_id, points, facing_value)
	_set_receipt(receipt); if bool(receipt.get("ok", false)): _last_error = ""
	_refresh()


func _delete_waypoint(index: int) -> void:
	var result: Dictionary = _battle.command_order(_selected_squadron_id); var order: Dictionary = result.get("order", {})
	if String(order.get("action", "")) != "move": return
	var points: Array = order.get("waypoints", []).duplicate(true)
	if index < 0 or index >= points.size(): return
	points.remove_at(index)
	if points.is_empty(): _set_receipt(_battle.set_order_hold(_selected_squadron_id)); _move_armed = true
	else: _set_receipt(_battle.set_order_move(_selected_squadron_id, points, float(order.get("facing_deg", 0))))
	_refresh()


func _clear_waypoints() -> void:
	_set_receipt(_battle.set_order_hold(_selected_squadron_id)); _move_armed = true; _refresh()


func _on_facing_changed(value: float) -> void:
	var result: Dictionary = _battle.command_order(_selected_squadron_id); var order: Dictionary = result.get("order", {})
	if String(order.get("action", "")) == "move":
		_set_receipt(_battle.set_order_move(_selected_squadron_id, order.get("waypoints", []), value)); _refresh()


func _update_preview_text(order: Dictionary) -> void:
	if String(order.get("action", "")) != "move":
		_preview_text.text = "HOLD · 현재 위치와 방향 유지"; return
	var preview: Dictionary = _battle.movement_preview(_selected_squadron_id, order.get("waypoints", []), order.get("facing_deg", 0))
	if not bool(preview.get("ok", false)):
		_preview_text.text = "이동 미리보기 오류: %s" % " · ".join(preview.get("errors", [])); return
	_preview_text.text = "거리 %.1f / 이번 턴 예산 %d · ETA %d턴\n예상 도달 (%.1f, %.1f) · %s\n%s" % [float(preview.total_distance), int(preview.movement_budget), int(preview.eta_turns), float(preview.predicted_position[0]), float(preview.predicted_position[1]), "이번 턴 도달" if bool(preview.path_complete) else "예산 밖 경로 있음", "초록 실선: 이번 턴 · 주황 점선: 이후 턴"]


func _on_interaction_rejected(message: String) -> void:
	_last_error = message; _refresh()


func _add_intelligence_panel() -> void:
	if not _battle.has_method("visible_contacts") or not _battle.has_method("visible_tactical_events"): return
	var divider := HSeparator.new(); _orders.add_child(divider)
	var title := Label.new(); title.text = "접촉 및 기회 사격 · %s 시야" % FACTION_NAMES.get(_viewer_faction_id, _viewer_faction_id); title.add_theme_color_override("font_color", Color("e8c779")); _orders.add_child(title)
	var contacts_result: Dictionary = _battle.visible_contacts(_viewer_faction_id); var contacts: Array = contacts_result.get("contacts", [])
	if contacts.is_empty():
		var none := Label.new(); none.text = "공개된 적 접촉 없음"; _orders.add_child(none)
	for value in contacts:
		var contact: Dictionary = value; var state := String(contact.get("state", "unknown"))
		if state in ["unknown", "undetected"]: continue
		var contact_label := Label.new(); contact_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if state in ["estimated", "lost"]:
			contact_label.text = _estimated_contact_text(contact)
		else: contact_label.text = "● 확인 접촉 · 현재 위치 재확인"
		_orders.add_child(contact_label)
	var events_result: Dictionary = _battle.visible_tactical_events(_viewer_faction_id); var events: Array = events_result.get("events", [])
	for index in range(events.size()):
		var event: Dictionary = events[index]; var event_label := Label.new(); event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var kind := String(event.get("event_type", event.get("type", "전술 이벤트")))
		if kind == "resource_consumed":
			event_label.text = "자원 소모 · %s · 비용 %s\n%s" % [_weapon_name(String(event.get("weapon_id", ""))), _resource_cost_text(event.get("cost", {})), _resource_transition_text(event.get("before", {}), event.get("after", {}), String(event.get("weapon_id", "")))]
		elif kind == "fire_suppressed":
			event_label.text = "사격 억제 · %s · %s" % [_weapon_name(String(event.get("weapon_id", ""))), String(event.get("reason_label", "코어 자원 조건 미충족"))]
		elif kind == "resource_recovered":
			event_label.name = "CombatResourceRecovery"
			event_label.text = "턴 %d 판정 시작 회복 · %s" % [int(event.get("resolution_turn", 0)), _resource_recovery_text(event.get("before", {}), event.get("after", {}))]
		elif kind.contains("fire") or String(event.get("outcome", "")) == "shot_authorized":
			var modifier: Dictionary = event.get("formation_modifier", {})
			if String(event.get("own_role", "")) == "target":
				if modifier.is_empty():
					event_label.text = "피격 경보 %d · 적 접촉 상세 비공개 · 명중/피해 판정 후속" % [index + 1]
				else:
					event_label.text = "피격 경보 %d · %s · 내 진형 방어 %s · sector 방어 %s · 합계 %s · 명중/피해 판정 후속" % [index + 1, _sector_label(String(modifier.get("incoming_sector", "indeterminate"))), _signed_percent(int(modifier.get("own_defense_percent", 0))), _signed_percent(int(modifier.get("own_sector_defense_percent", 0))), _signed_percent(int(modifier.get("own_total_defense_percent", 0)))]
			else:
				var fire_control: Dictionary = event.get("fire_control_snapshot", {})
				var eligibility: Dictionary = fire_control.get("eligibility", {})
				var weapon_summary := "내 무기 정보 없음"
				if not fire_control.is_empty():
					weapon_summary = "%s · 배분 %s · 코어 적격 사거리 %.1f / 사격각 %.1f°" % [_weapon_name(String(fire_control.get("selected_weapon_id", ""))), _bps_text(int(fire_control.get("selected_allocation_basis_points", 0))), float(eligibility.get("range", 0)), float(eligibility.get("arc_deg", 0))]
				event_label.text = "사격 %d · 승인 · 거리 %.1f/사거리 %.1f · 방위 %.1f° · 사격각 %.1f° · %s · 표적 %s · 내 화력 %s · 명중/피해 판정 후속" % [index + 1, float(event.get("distance", 0)), float(event.get("range", 0)), float(event.get("bearing_deg", 0)), float(event.get("arc_deg", 0)), weapon_summary, _sector_label(String(modifier.get("target_sector", "indeterminate"))), _signed_percent(int(modifier.get("own_fire_percent", 0)))]
		else: event_label.text = "%d. %s · 코어 판정" % [index + 1, kind]
		_orders.add_child(event_label)


func _add_formation_editor() -> void:
	if not _battle.has_method("formation_order") or not _battle.has_method("viewer_snapshot"): return
	var viewer: Dictionary = _battle.viewer_snapshot(_viewer_faction_id); var allowed: Array = viewer.get("allowed_formations", [])
	var current: Dictionary = viewer.get("own_formation_state", {}).get(_selected_squadron_id, {})
	var draft_result: Dictionary = _battle.formation_order(_selected_squadron_id); var draft: Dictionary = draft_result.get("order", {})
	var current_id := String(current.get("formation_id", "")); var draft_id := String(draft.get("formation_id", current_id))
	var heading := Label.new(); heading.text = "진형 · 현재 %s / 변경 초안 %s" % [_formation_name(allowed, current_id), _formation_name(allowed, draft_id)]; heading.add_theme_color_override("font_color", Color("9fd4e2")); _orders.add_child(heading)
	var picker := OptionButton.new(); picker.name = "FormationOrderPicker"; picker.custom_minimum_size = Vector2(340,44); picker.focus_mode = Control.FOCUS_ALL
	var selected_index := 0
	for index in range(allowed.size()):
		var row: Dictionary = allowed[index]; picker.add_item("%s · %s" % [String(row.get("name", row.get("formation_id", ""))), String(row.get("role", ""))]); picker.set_item_metadata(index, String(row.get("formation_id", "")))
		if String(row.get("formation_id", "")) == draft_id: selected_index = index
	picker.select(selected_index); picker.item_selected.connect(_on_formation_selected.bind(picker)); _orders.add_child(picker)
	var selected_row := _formation_row(allowed, draft_id); var modifiers: Dictionary = selected_row.get("modifiers", {})
	var detail := Label.new(); detail.name = "FormationModifierSnapshot"; detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; detail.text = "코어 profile · 기동 %s · 탐지 %s · 화력 %s · 방어 %s" % [_signed_percent(int(modifiers.get("mobility_percent",0))), _signed_percent(int(modifiers.get("detection_percent",0))), _signed_percent(int(modifiers.get("fire_percent",0))), _signed_percent(int(modifiers.get("defense_percent",0)))]; _orders.add_child(detail)


func _on_formation_selected(index: int, picker: OptionButton) -> void:
	if _selected_squadron_id.is_empty() or index < 0: return
	_set_receipt(_battle.set_formation_order(_selected_squadron_id, String(picker.get_item_metadata(index)))); _refresh()


func _formation_row(rows: Array, formation_id: String) -> Dictionary:
	for row in rows:
		if String(row.get("formation_id", "")) == formation_id: return row
	return {}


func _formation_name(rows: Array, formation_id: String) -> String:
	return String(_formation_row(rows, formation_id).get("name", formation_id))


func _sector_label(sector: String) -> String:
	return {"front":"정면", "flank":"측면", "rear":"후면", "indeterminate":"방향 불명(동일 좌표)"}.get(sector, "방향 불명")


func _estimated_contact_text(contact: Dictionary) -> String:
	var position: Array = contact.get("last_known_position", [0, 0])
	return "△ %s · 마지막 확인 (%.1f, %.1f) T%d · 경과 %d턴 · 신뢰 %d bp · 오차 반경 %d · T%d 뒤 만료 · 실제 위치와 다를 수 있음" % ["소실 접촉(stale)" if String(contact.get("state", "")) == "lost" else "추정 접촉", float(position[0]), float(position[1]), int(contact.get("last_seen_turn", 0)), int(contact.get("staleness_turns", 0)), int(contact.get("confidence_basis_points", 0)), int(contact.get("error_radius", 0)), int(contact.get("expires_after_turn", 0))]


func _add_estimated_fire_editor() -> void:
	if not _battle.has_method("estimated_fire_order") or _selected_squadron_id.is_empty(): return
	var contacts: Array = _battle.visible_contacts(_viewer_faction_id).get("contacts", []); var estimated: Array = []
	for value in contacts:
		if String(value.get("state", "")) == "estimated": estimated.append(value)
	var title := Label.new(); title.text = "추정 사격 · 마지막 확인 좌표 기준"; title.add_theme_color_override("font_color", Color("e8c779")); _orders.add_child(title)
	if estimated.is_empty():
		var none := Label.new(); none.text = "현재 선택 가능한 추정 접촉 없음"; _orders.add_child(none); return
	for index in range(estimated.size()):
		var contact: Dictionary = estimated[index]; var contact_id := String(contact.get("contact_id", "")); var select := _button(("● " if contact_id == _selected_contact_id else "○ ") + "추정 접촉 %d 선택" % (index + 1), "SelectEstimatedContact%d" % (index + 1), 340); select.pressed.connect(_on_map_contact_selected.bind(contact_id)); _orders.add_child(select)
	if not _selected_contact_id.is_empty():
		var selected := Label.new(); selected.name = "SelectedEstimatedContact"; selected.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; selected.text = _estimated_contact_text(_viewer_contact(_selected_contact_id)); _orders.add_child(selected)
	var order_result: Dictionary = _battle.estimated_fire_order(_selected_squadron_id); var order: Dictionary = order_result.get("order", {})
	if not order.is_empty():
		var aim: Array = order.get("aim_position", [0, 0]); var offset: Array = order.get("error_offset", [0, 0]); var order_label := Label.new(); order_label.name = "EstimatedFireDraft"; order_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; order_label.text = "추정 사격 초안 · 코어 조준 (%.1f, %.1f) · 오차 (%.1f, %.1f) / 반경 %d · 신뢰 %d bp · 명중/피해 pending" % [float(aim[0]), float(aim[1]), float(offset[0]), float(offset[1]), int(order.get("error_radius", 0)), int(order.get("confidence_basis_points", 0))]; _orders.add_child(order_label)
	var actions := HBoxContainer.new(); _orders.add_child(actions)
	var stage := _button("추정 사격", "SetEstimatedFire", 165); stage.disabled = _selected_contact_id.is_empty(); stage.pressed.connect(_on_set_estimated_fire); actions.add_child(stage)
	var clear := _button("추정 사격 취소", "ClearEstimatedFire", 165); clear.disabled = order.is_empty(); clear.pressed.connect(_on_clear_estimated_fire); actions.add_child(clear)


func _viewer_contact(contact_id: String) -> Dictionary:
	if _battle == null or not _battle.has_method("visible_contacts"): return {}
	for value in _battle.visible_contacts(_viewer_faction_id).get("contacts", []):
		if String(value.get("contact_id", "")) == contact_id: return value
	return {}


func _on_set_estimated_fire() -> void:
	if _selected_squadron_id.is_empty() or _selected_contact_id.is_empty(): return
	_set_receipt(_battle.set_estimated_fire(_selected_squadron_id, _selected_contact_id)); _refresh()


func _on_clear_estimated_fire() -> void:
	if _selected_squadron_id.is_empty(): return
	_set_receipt(_battle.clear_estimated_fire(_selected_squadron_id)); _refresh()


func _signed_percent(value: int) -> String:
	return "%+d%%" % value


func _add_weapon_editor() -> void:
	if not _battle.has_method("weapon_allocation_order") or not _battle.has_method("viewer_snapshot"): return
	var viewer: Dictionary = _battle.viewer_snapshot(_viewer_faction_id); var categories: Array = viewer.get("weapon_categories", []); var presets: Array = viewer.get("weapon_presets", [])
	var live: Dictionary = viewer.get("own_weapon_allocation_state", {}).get(_selected_squadron_id, {})
	var order_result: Dictionary = _battle.weapon_allocation_order(_selected_squadron_id); var order: Dictionary = order_result.get("order", {})
	var title := Label.new(); title.text = "무기 운용 초안 · %s" % ("공격 보류" if bool(order.get("hold_fire", false)) else "사격 재개"); title.add_theme_color_override("font_color", Color("e8c779")); _orders.add_child(title)
	var fire_row := HBoxContainer.new(); _orders.add_child(fire_row)
	var hold := _button("공격 보류", "HoldFire", 165); hold.disabled = bool(order.get("hold_fire", false)); hold.pressed.connect(_on_hold_fire.bind(true)); fire_row.add_child(hold)
	var resume := _button("사격 재개", "ResumeFire", 165); resume.disabled = not bool(order.get("hold_fire", false)) or live.get("available_categories", []).is_empty(); resume.pressed.connect(_on_hold_fire.bind(false)); fire_row.add_child(resume)
	var preset_row := HBoxContainer.new(); _orders.add_child(preset_row)
	var preset_picker := OptionButton.new(); preset_picker.name = "WeaponPresetPicker"; preset_picker.custom_minimum_size = Vector2(225,44); preset_picker.focus_mode = Control.FOCUS_ALL
	for index in range(presets.size()): preset_picker.add_item(String(presets[index].get("name", presets[index].get("preset_id", "")))); preset_picker.set_item_metadata(index, String(presets[index].get("preset_id", "")))
	preset_row.add_child(preset_picker)
	var apply := _button("프리셋 적용", "ApplyWeaponPreset", 110); apply.disabled = presets.is_empty(); apply.pressed.connect(_on_weapon_preset.bind(preset_picker)); preset_row.add_child(apply)
	var available: Array = live.get("available_categories", []); var allocations: Dictionary = order.get("allocations", {})
	for category in categories:
		var weapon_id := String(category.get("weapon_id", "")); var row := HBoxContainer.new(); _orders.add_child(row)
		var label := Label.new(); label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; label.text = "%s · %s" % [String(category.get("name", weapon_id)), _bps_text(int(allocations.get(weapon_id, 0))) if available.has(weapon_id) else "사용 불가 · 0.00%"] ; row.add_child(label)
		var spin := SpinBox.new(); spin.name = "WeaponBps_%s" % weapon_id; spin.min_value = 0; spin.max_value = 10000; spin.step = 1; spin.value = int(allocations.get(weapon_id, 0)); spin.suffix = " bp"; spin.custom_minimum_size = Vector2(125,44); spin.editable = available.has(weapon_id); spin.focus_mode = Control.FOCUS_ALL if spin.editable else Control.FOCUS_NONE; spin.value_changed.connect(_on_weapon_basis_points.bind(weapon_id)); row.add_child(spin)
	var total := Label.new(); total.name = "WeaponAllocationTotal"; total.text = "정규화 합계 · %s" % (_bps_text(int(order_result.get("total_basis_points", -1))) if order_result.has("total_basis_points") else "코어 합계 대기"); total.add_theme_color_override("font_color", Color("a8d9bd")); _orders.add_child(total)


func _on_weapon_basis_points(value: float, weapon_id: String) -> void:
	_set_receipt(_battle.set_weapon_basis_points(_selected_squadron_id, weapon_id, int(value))); _refresh()


func _on_weapon_preset(picker: OptionButton) -> void:
	if picker.item_count <= 0: return
	_set_receipt(_battle.apply_weapon_preset(_selected_squadron_id, String(picker.get_item_metadata(picker.selected)))); _refresh()


func _on_hold_fire(enabled: bool) -> void:
	_set_receipt(_battle.set_hold_fire(_selected_squadron_id, enabled)); _refresh()


func _add_combat_resource_panel(squadron_id: String = "") -> void:
	if not _battle.has_method("viewer_snapshot"): return
	if squadron_id.is_empty(): squadron_id = _selected_squadron_id
	var viewer: Dictionary = _battle.viewer_snapshot(_viewer_faction_id)
	var own_resources: Dictionary = viewer.get("own_combat_resources", {})
	if not own_resources.has(squadron_id): return
	var resources: Dictionary = own_resources[squadron_id]
	var shared: Dictionary = resources.get("shared", {})
	var title := Label.new(); title.name = "CombatResourceTitle"; title.text = "제한 전투 자원 · 내 전대만"; title.add_theme_color_override("font_color", Color("9fd4e2")); _orders.add_child(title)
	var shared_label := Label.new(); shared_label.name = "CombatResourceShared"; shared_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shared_label.text = "에너지 %d/%d · 열 %d/%d" % [int(shared.get("energy", 0)), int(shared.get("energy_capacity", 0)), int(shared.get("heat", 0)), int(shared.get("heat_capacity", 0))]; _orders.add_child(shared_label)
	var weapons: Dictionary = resources.get("weapons", {})
	for category in viewer.get("weapon_categories", []):
		var weapon_id := String(category.get("weapon_id", ""))
		if not weapons.has(weapon_id): continue
		var weapon: Dictionary = weapons[weapon_id]; var row := Label.new(); row.name = "CombatResource_%s" % weapon_id; row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.text = "%s · 탄약 %d/%d · 함재기 %d/%d · 특수 %d/%d" % [String(category.get("name", weapon_id)), int(weapon.get("ammo", 0)), int(weapon.get("ammo_capacity", 0)), int(weapon.get("carrier_ready", 0)), int(weapon.get("carrier_capacity", 0)), int(weapon.get("special", 0)), int(weapon.get("special_capacity", 0))]
		_orders.add_child(row)
	var note := Label.new(); note.text = "부족·과열·미복귀에 따른 사격 억제와 턴 소모/회복은 코어 이벤트로만 표시됩니다."; note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; note.add_theme_color_override("font_color", Color("92aab4")); _orders.add_child(note)


func _bps_text(value: int) -> String:
	if value < 0: return "코어 값 없음"
	return "%d bp · %.2f%%" % [value, float(value) / 100.0]


func _weapon_name(weapon_id: String) -> String:
	if weapon_id.is_empty(): return "무기 미선택"
	for value in _battle.weapon_categories():
		var category: Dictionary = value
		if String(category.get("weapon_id", "")) == weapon_id:
			return String(category.get("name", weapon_id))
	return weapon_id


func _resource_cost_text(cost: Dictionary) -> String:
	return "탄약 %d · 에너지 %d · 열 +%d · 함재기 %d · 특수 %d" % [int(cost.get("ammo", 0)), int(cost.get("energy", 0)), int(cost.get("heat", 0)), int(cost.get("carrier_sorties", 0)), int(cost.get("special", 0))]


func _resource_transition_text(before: Dictionary, after: Dictionary, weapon_id: String) -> String:
	var before_shared: Dictionary = before.get("shared", {}); var after_shared: Dictionary = after.get("shared", {})
	var before_weapon: Dictionary = before.get("weapons", {}).get(weapon_id, {}); var after_weapon: Dictionary = after.get("weapons", {}).get(weapon_id, {})
	return "전→후 · 에너지 %d→%d · 열 %d→%d · 탄약 %d→%d · 함재기 %d→%d · 특수 %d→%d" % [int(before_shared.get("energy", 0)), int(after_shared.get("energy", 0)), int(before_shared.get("heat", 0)), int(after_shared.get("heat", 0)), int(before_weapon.get("ammo", 0)), int(after_weapon.get("ammo", 0)), int(before_weapon.get("carrier_ready", 0)), int(after_weapon.get("carrier_ready", 0)), int(before_weapon.get("special", 0)), int(after_weapon.get("special", 0))]


func _resource_recovery_text(before: Dictionary, after: Dictionary) -> String:
	var before_shared: Dictionary = before.get("shared", {}); var after_shared: Dictionary = after.get("shared", {})
	var parts: Array[String] = ["에너지 %d→%d" % [int(before_shared.get("energy", 0)), int(after_shared.get("energy", 0))], "열 %d→%d" % [int(before_shared.get("heat", 0)), int(after_shared.get("heat", 0))]]
	var weapon_ids: Array = before.get("weapons", {}).keys(); weapon_ids.sort()
	for weapon_id in weapon_ids:
		var before_weapon: Dictionary = before.weapons[weapon_id]; var after_weapon: Dictionary = after.get("weapons", {}).get(weapon_id, {})
		parts.append("%s 함재기 %d→%d" % [_weapon_name(String(weapon_id)), int(before_weapon.get("carrier_ready", 0)), int(after_weapon.get("carrier_ready", 0))])
	return " · ".join(parts)


func _add_phase_ledger() -> void:
	if not _battle.has_method("viewer_phase_summary") or not _battle.has_method("viewer_phase"): return
	var divider := HSeparator.new(); _orders.add_child(divider)
	var heading := Label.new(); heading.name = "FivePhaseLedgerTitle"; heading.text = "턴 전투 5단계 판정 원장"; heading.add_theme_color_override("font_color", Color("e8c779")); _orders.add_child(heading)
	var summary: Dictionary = _battle.viewer_phase_summary(_viewer_faction_id)
	if not bool(summary.get("ok", false)):
		var unavailable := Label.new(); unavailable.name = "FivePhaseLedgerPending"; unavailable.text = "판정 완료 후 viewer 원장이 공개됩니다."; unavailable.add_theme_color_override("font_color", Color("92aab4")); _orders.add_child(unavailable); return
	var digest := Label.new(); digest.name = "FivePhaseTurnDigest"; digest.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY; digest.text = "턴 %d digest · %s" % [int(summary.get("turn", 0)), String(summary.get("turn_digest", ""))]; digest.add_theme_color_override("font_color", Color("92aab4")); _orders.add_child(digest)
	var mode_row := HBoxContainer.new(); mode_row.add_theme_constant_override("separation", 5); _orders.add_child(mode_row)
	var automatic := _button("자동 전체", "LedgerPhaseAuto", 105); automatic.disabled = _ledger_phase_filter.is_empty(); automatic.pressed.connect(_on_ledger_phase.bind("")); mode_row.add_child(automatic)
	var phase_picker := OptionButton.new(); phase_picker.name = "LedgerPhasePicker"; phase_picker.custom_minimum_size = Vector2(225, 44); phase_picker.focus_mode = Control.FOCUS_ALL; phase_picker.add_item("단계별 보기")
	for index in range(summary.get("phases", []).size()):
		var row: Dictionary = summary.phases[index]; phase_picker.add_item("%d %s" % [index + 1, String(row.get("phase_name", ""))]); phase_picker.set_item_metadata(index + 1, String(row.get("phase_id", "")))
		if String(row.get("phase_id", "")) == _ledger_phase_filter: phase_picker.select(index + 1)
	phase_picker.item_selected.connect(_on_ledger_picker.bind(phase_picker)); mode_row.add_child(phase_picker)
	var timeline := GridContainer.new(); timeline.name = "FivePhaseTimeline"; timeline.columns = 3; timeline.add_theme_constant_override("h_separation", 4); timeline.add_theme_constant_override("v_separation", 4); _orders.add_child(timeline)
	for index in range(summary.get("phases", []).size()):
		var row: Dictionary = summary.phases[index]; var phase_id := String(row.get("phase_id", ""))
		var button := _button("%d %s\n%s" % [index + 1, String(row.get("phase_name", "")), _ledger_compact_status(row)], "LedgerPhase_%s" % phase_id, 108); button.custom_minimum_size.y = 54; button.clip_text = true; button.tooltip_text = _ledger_status_text(row); button.pressed.connect(_on_ledger_phase.bind(phase_id)); timeline.add_child(button)
	var shown: Array = []
	if _ledger_phase_filter.is_empty():
		for row in summary.get("phases", []): shown.append(String(row.get("phase_id", "")))
	else: shown.append(_ledger_phase_filter)
	for phase_id in shown:
		var result: Dictionary = _battle.viewer_phase(_viewer_faction_id, phase_id)
		if not bool(result.get("ok", false)): continue
		var phase: Dictionary = result.get("phase", {}); var phase_label := Label.new(); phase_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var lines: Array[String] = ["%d. %s · %s" % [int(phase.get("order", 0)), String(phase.get("phase_name", "")), _ledger_status_text({"status": phase.get("status", ""), "event_count": phase.get("events", []).size(), "pending_count": phase.get("pending", []).size()})]]
		for value in phase.get("events", []):
			var event: Dictionary = value; lines.append("  • %s · %s" % [String(event.get("event_type", "event")), String(event.get("ledger_event_id", ""))])
		for pending in phase.get("pending", []): lines.append("  ◌ pending · %s" % String(pending))
		phase_label.text = "\n".join(lines); _orders.add_child(phase_label)


func _ledger_status_text(row: Dictionary) -> String:
	var status := String(row.get("status", "")); var events := int(row.get("event_count", 0)); var pending := int(row.get("pending_count", 0))
	if status == "no_visible_events": return "가시 이벤트 없음%s" % (" · pending %d" % pending if pending > 0 else "")
	if status == "recorded": return "실제 이벤트 %d" % events
	if status == "partial": return "실제 %d · pending %d" % [events, pending]
	if status == "pending": return "pending %d" % pending
	return status


func _ledger_compact_status(row: Dictionary) -> String:
	var status := String(row.get("status", "")); var events := int(row.get("event_count", 0)); var pending := int(row.get("pending_count", 0))
	if status == "no_visible_events": return "가시 없음%s" % (" · P%d" % pending if pending > 0 else "")
	if status == "recorded": return "실제 %d" % events
	if status == "partial": return "실제 %d · P%d" % [events, pending]
	if status == "pending": return "P%d" % pending
	return status


func _on_ledger_phase(phase_id: String) -> void:
	_ledger_phase_filter = phase_id; _refresh()


func _on_ledger_picker(index: int, picker: OptionButton) -> void:
	if index <= 0: return
	_on_ledger_phase(String(picker.get_item_metadata(index)))


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _battle != null and _battle.phase() == "sun_control_prompt":
			_last_error = "손권군 제어 방식을 선택해야 합니다. Esc로 닫을 수 없습니다."; _refresh()
		else: close_requested.emit()
		get_viewport().set_input_as_handled()


func _panel(title_text: String, width: float) -> PanelContainer:
	var panel := PanelContainer.new(); panel.custom_minimum_size.x = width; panel.add_theme_stylebox_override("panel", _style(Color("08151e"), Color("466978")))
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 10)
	panel.add_child(margin)
	var stack := VBoxContainer.new(); stack.add_theme_constant_override("separation", 7); margin.add_child(stack)
	var title := Label.new(); title.text = title_text; title.add_theme_font_size_override("font_size", 17); title.add_theme_color_override("font_color", Color("9bd8e7")); stack.add_child(title); panel.set_meta("stack", stack); return panel


func _button(text: String, node_name: String, width: float) -> Button:
	var button := Button.new(); button.name = node_name; button.text = text; button.custom_minimum_size = Vector2(width, 44); button.focus_mode = Control.FOCUS_ALL; button.add_theme_stylebox_override("normal", _style(Color("13232d"), Color("557584"))); button.add_theme_stylebox_override("hover", _style(Color("203743"), Color("d0ad61"))); button.add_theme_stylebox_override("focus", _style(Color("192d38"), Color("f0d17b"))); button.add_theme_stylebox_override("disabled", _style(Color("091116"), Color("34434a"))); return button


func _spin(node_name: String, minimum: float, maximum: float) -> SpinBox:
	var spin := SpinBox.new(); spin.name = node_name; spin.min_value = minimum; spin.max_value = maximum; spin.step = 1; spin.custom_minimum_size = Vector2(105, 44); spin.focus_mode = Control.FOCUS_ALL; return spin


func _style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new(); style.bg_color = background; style.border_color = border; style.set_border_width_all(1); style.set_corner_radius_all(4); style.content_margin_left = 10; style.content_margin_right = 10; style.content_margin_top = 6; style.content_margin_bottom = 6; return style


func _clear(parent: Node) -> void:
	for child in parent.get_children(): parent.remove_child(child); child.queue_free()
