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
	_map = TacticalMap.new(); _map.name = "AppliedSquadronMap"; _map.size_flags_vertical = Control.SIZE_EXPAND_FILL; _map.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _map.squadron_selected.connect(_on_map_squadron_selected); _map.waypoint_requested.connect(_on_waypoint_requested); _map.interaction_rejected.connect(_on_interaction_rejected); map_panel.get_meta("stack").add_child(_map)
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
	_map.configure(setup.get("battlefield_bounds", [0, 0, 1600, 900]), setup.get("squadrons", []), _battle.live_navigation())
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
		for future in ["무기", "진형 변경", "탐지"]:
			var disabled_empty := _button("%s · 후속 기능 · 현재 사용 불가" % future, "Disabled%s" % future, 340); disabled_empty.disabled = true; _orders.add_child(disabled_empty)
		return
	var squad := _find_squad(snapshot, _selected_squadron_id)
	var selected := Label.new(); selected.text = "선택: %s" % String(squad.get("name", _selected_squadron_id)); selected.add_theme_color_override("font_color", Color("f0cf7e")); _orders.add_child(selected)
	var action_row := HBoxContainer.new(); _orders.add_child(action_row)
	var hold := _button("대기 HOLD", "SetOrderHold", 165); hold.pressed.connect(_on_set_hold); action_row.add_child(hold)
	var move := _button("이동 MOVE", "ArmOrderMove", 165); move.pressed.connect(_on_arm_move); action_row.add_child(move)
	var order_result: Dictionary = _battle.command_order(_selected_squadron_id); var order: Dictionary = order_result.get("order", {})
	var action := String(order.get("action", "hold")); var state := Label.new(); state.name = "OrderActionState"; state.text = "현재: %s%s" % [action.to_upper(), " · 첫 경유점 대기" if _move_armed and action != "move" else ""]; _orders.add_child(state)
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
	for future in ["무기", "진형 변경", "탐지"]:
		var disabled := _button("%s · 후속 기능 · 현재 사용 불가" % future, "Disabled%s" % future, 340); disabled.disabled = true; _orders.add_child(disabled)


func _rebuild_log() -> void:
	var lines: Array[String] = []
	for value in _battle.turn_log():
		var entry: Dictionary = value; var turn_number := int(entry.get("turn", 0)); var parts: Array[String] = []
		if not entry.get("liu_orders", []).is_empty(): parts.append("유비 명령 %d" % entry.liu_orders.size())
		var decision: Dictionary = entry.get("sun_control_decision", {})
		if not decision.is_empty(): parts.append("손권 %s" % ("수동" if decision.get("control") == "manual" else "AI"))
		if not entry.get("sun_orders", []).is_empty(): parts.append("손권 명령 %d" % entry.sun_orders.size())
		if not entry.get("cao_orders", []).is_empty(): parts.append("조조 AI HOLD %d" % entry.cao_orders.size())
		var resolution: Dictionary = entry.get("resolution_receipt", {})
		if not resolution.is_empty():
			var moved := 0; var partial := 0
			for event in resolution.get("movement_events", []):
				if String(event.get("action", "")) == "move": moved += 1; partial += 0 if bool(event.get("path_complete", true)) else 1
			parts.append("이동 %d · 부분 이동 %d · rules_pending" % [moved, partial])
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
	if phase == "victory_check": return "이동 판정이 확정되었습니다. 충돌/요격/무기/탐지/피해/승패는 후속 구현 대기입니다."
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
