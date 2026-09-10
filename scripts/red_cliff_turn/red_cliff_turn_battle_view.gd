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

var _battle
var _applied_revision := 0
var _applied_digest := ""
var _busy := false
var _last_error := ""
var _header: Label
var _phase_text: Label
var _steps: VBoxContainer
var _map: Control
var _orders: VBoxContainer
var _log: RichTextLabel
var _status: Label
var _primary: Button
var _prompt: PanelContainer
var _reenable_prompt: Button


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
	var step_panel := _panel("진행 단계", 235); body.add_child(step_panel); _steps = VBoxContainer.new(); _steps.name = "PhaseSteps"; _steps.add_theme_constant_override("separation", 7); step_panel.get_meta("stack").add_child(_steps)
	var map_panel := _panel("2D 전술 배치 · 읽기 전용", 760); map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL; body.add_child(map_panel)
	_map = Control.new(); _map.name = "AppliedSquadronMap"; _map.custom_minimum_size = Vector2(720, 465); _map.size_flags_vertical = Control.SIZE_EXPAND_FILL; _map.clip_contents = true; map_panel.get_meta("stack").add_child(_map)
	var order_panel := _panel("현재 명령", 350); body.add_child(order_panel); _orders = VBoxContainer.new(); _orders.name = "CurrentFactionOrders"; _orders.size_flags_vertical = Control.SIZE_EXPAND_FILL; _orders.add_theme_constant_override("separation", 7); order_panel.get_meta("stack").add_child(_orders)
	var footer := HBoxContainer.new(); footer.custom_minimum_size.y = 185; footer.add_theme_constant_override("separation", 10); root_box.add_child(footer)
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
	_rebuild_steps(phase); _rebuild_map(snapshot); _rebuild_orders(snapshot, phase); _rebuild_log()
	_prompt.visible = phase == "sun_control_prompt"
	if _prompt.visible:
		var first: Button = _prompt.find_child("SunManualThisTurn", true, false); if first != null: first.grab_focus()
	var policy_enabled := bool(_battle.prompt_policy().get("enabled", true))
	_reenable_prompt.disabled = _busy or policy_enabled or phase == "sun_control_prompt"
	_primary.disabled = _busy or not ["liu_command", "sun_command", "victory_check"].has(phase)
	_primary.text = {"liu_command": "유비 HOLD 확정", "sun_command": "손권 HOLD 확정", "victory_check": "다음 턴"}.get(phase, "처리 대기")
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
	_clear(_map)
	var setup: Dictionary = snapshot.get("applied_setup", {}); var bounds: Array = setup.get("battlefield_bounds", [0, 0, 1600, 900])
	var width := maxf(1.0, float(bounds[2])); var height := maxf(1.0, float(bounds[3]))
	var faction_counts := {}
	for value in setup.get("squadrons", []):
		var squad: Dictionary = value; var position: Array = squad.get("initial_position", [0, 0]); var marker := Button.new(); var faction_id := String(squad.get("faction_id", "")); var faction_index := int(faction_counts.get(faction_id, 0)); faction_counts[faction_id] = faction_index + 1
		var display_offset: Vector2 = {"liu_bei": Vector2(-75, -38 + faction_index * 62), "sun_quan": Vector2(70, -30 + faction_index * 62), "cao_cao": Vector2(0, 0)}.get(faction_id, Vector2.ZERO)
		marker.name = "MapMarker_%s" % String(squad.get("id", "")); marker.text = "%s%s\n%s" % ["◆ " if bool(squad.get("flagship", false)) else "", FACTION_NAMES.get(faction_id, ""), squad.get("name", "")]; marker.disabled = true; marker.custom_minimum_size = Vector2(135, 48); marker.position = Vector2(clampf(float(position[0]) / width, 0.0, 1.0) * 570.0 + 30.0, clampf(float(position[1]) / height, 0.0, 1.0) * 350.0 + 25.0) + display_offset; marker.add_theme_color_override("font_disabled_color", FACTION_COLORS.get(faction_id, Color.WHITE)); _map.add_child(marker)


func _rebuild_orders(snapshot: Dictionary, phase: String) -> void:
	_clear(_orders)
	var faction_id := "liu_bei" if phase == "liu_command" else ("sun_quan" if phase == "sun_command" else "")
	var heading := Label.new(); heading.text = "%s · %s" % [FACTION_NAMES.get(faction_id, "자동 처리"), "직접 명령" if not faction_id.is_empty() else "입력 잠김"]; heading.add_theme_font_size_override("font_size", 17); _orders.add_child(heading)
	for value in snapshot.get("applied_setup", {}).get("squadrons", []):
		var squad: Dictionary = value
		if String(squad.get("faction_id", "")) != faction_id or not bool(squad.get("operational", true)): continue
		var row := Label.new(); row.text = "✓ %s  ·  대기(HOLD)" % String(squad.get("name", "")); row.custom_minimum_size.y = 40; row.add_theme_color_override("font_color", Color("a7dbba")); _orders.add_child(row)
	for future in ["이동", "무기", "진형 변경", "탐지"]:
		var disabled := _button("%s · 후속 기능 · 현재 사용 불가" % future, "Disabled%s" % future, 315); disabled.disabled = true; _orders.add_child(disabled)


func _rebuild_log() -> void:
	var lines: Array[String] = []
	for value in _battle.turn_log():
		var entry: Dictionary = value; var turn_number := int(entry.get("turn", 0)); var parts: Array[String] = []
		if not entry.get("liu_orders", []).is_empty(): parts.append("유비 HOLD %d" % entry.liu_orders.size())
		var decision: Dictionary = entry.get("sun_control_decision", {})
		if not decision.is_empty(): parts.append("손권 %s" % ("수동" if decision.get("control") == "manual" else "AI"))
		if not entry.get("sun_orders", []).is_empty(): parts.append("손권 HOLD %d" % entry.sun_orders.size())
		if not entry.get("cao_orders", []).is_empty(): parts.append("조조 AI HOLD %d" % entry.cao_orders.size())
		if not entry.get("resolution_receipt", {}).is_empty(): parts.append("명령 원장 확정 · rules_pending")
		lines.append("[턴 %d] %s" % [turn_number, " · ".join(parts) if not parts.is_empty() else "유비 명령 대기"])
	_log.text = "\n".join(lines); _log.scroll_to_line(maxi(0, lines.size() - 1))


func _on_primary() -> void:
	if _battle == null or _busy: return
	var phase: String = _battle.phase()
	if not ["liu_command", "sun_command", "victory_check"].has(phase): return
	_busy = true
	_last_error = ""; _primary.disabled = true
	var receipt: Dictionary
	if phase == "liu_command": receipt = _battle.submit_liu_orders(_hold_orders("liu_bei"))
	elif phase == "sun_command": receipt = _battle.submit_sun_orders(_hold_orders("sun_quan"))
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


func _hold_orders(faction_id: String) -> Array:
	var orders: Array = []
	for value in _battle.snapshot().get("applied_setup", {}).get("squadrons", []):
		if value is Dictionary and String(value.get("faction_id", "")) == faction_id and bool(value.get("operational", true)):
			orders.append({"squadron_id": String(value.get("id", "")), "action": "hold"})
	return orders


func _status_for_phase(phase: String) -> String:
	if not _last_error.is_empty(): return _last_error
	if phase == "liu_command": return "모든 유비군 operational 전대에 대기(HOLD)를 제출합니다."
	if phase == "sun_control_prompt": return "손권군 제어 방식을 선택해야 계속할 수 있습니다."
	if phase == "sun_command": return "손권군 수동 명령은 이번 범위에서 대기(HOLD)만 지원합니다."
	if phase == "victory_check": return "명령 원장만 확정되었습니다. 승리 조건 판정 후속 구현 대기 · 이동/전투/피해 미실행."
	if phase == "turn_limit_reached": return "20/20 · 결과 판정 대기. 승자와 피해는 아직 계산하지 않았습니다."
	return "AI 명령 및 명령 원장을 처리하는 중입니다."


func _set_receipt(receipt: Dictionary) -> void:
	if not bool(receipt.get("ok", false)): _last_error = " · ".join(receipt.get("errors", []))


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


func _style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new(); style.bg_color = background; style.border_color = border; style.set_border_width_all(1); style.set_corner_radius_all(4); style.content_margin_left = 10; style.content_margin_right = 10; style.content_margin_top = 6; style.content_margin_bottom = 6; return style


func _clear(parent: Node) -> void:
	for child in parent.get_children(): parent.remove_child(child); child.queue_free()
