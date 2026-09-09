class_name RedCliffBattleView
extends Control

## Read-only presentation boundary: Campaign retains authority for all combat facts.
signal return_requested
var campaign = null
var battle_id := ""
var _state: Label
var _feedback: Label
var _map: TacticalMap
var _feed: BattleStillImage
var _deck: CommandDeck
var _report: BattleReport
var _formation: OptionButton
var _phase_alert: Label
var _history_backdrop: ColorRect
var _history_panel: PanelContainer
var _history_text: Label
var _comparison_panel: PanelContainer
var _comparison_grid: GridContainer
var _comparison_summary: Label
var _buttons: Array[Button] = []
var _synced_formation_id := ""
var _current_formation_name := ""
var _comparison_signature := ""
var _last_phase := -1
var _phase_alert_time := 0.0
var _modal_opener: Control
var _pending_command_kind := ""
var _pending_command_label := ""
var _applied_command_count := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_once()
	set_process(true)

func configure(campaign_ref, canonical_battle_id: String) -> void:
	campaign = campaign_ref; battle_id = canonical_battle_id; _refresh()

func _process(delta: float) -> void:
	_refresh()
	if _phase_alert_time > 0.0:
		_phase_alert_time = maxf(0.0,_phase_alert_time-delta)
		_phase_alert.modulate.a = clampf(_phase_alert_time/.45,0.0,1.0) if _phase_alert_time < .45 else 1.0
		if _phase_alert_time <= 0.0: _phase_alert.visible = false

func _build_once() -> void:
	if _state != null: return
	var bg := ColorRect.new(); bg.color = Color("050b12"); bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(bg)
	var margins := MarginContainer.new(); margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right"]: margins.add_theme_constant_override(side, 18)
	margins.add_theme_constant_override("margin_top", 13); margins.add_theme_constant_override("margin_bottom", 12); add_child(margins)
	_phase_alert = Label.new(); _phase_alert.name="PhaseTransitionAlert"; _phase_alert.visible=false; _phase_alert.z_index=20; _phase_alert.mouse_filter=Control.MOUSE_FILTER_IGNORE; _phase_alert.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; _phase_alert.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; _phase_alert.add_theme_font_size_override("font_size",17); _phase_alert.add_theme_color_override("font_color",Color("fff0bd")); _phase_alert.set_anchors_preset(Control.PRESET_CENTER_TOP); _phase_alert.position=Vector2(-210,166); _phase_alert.size=Vector2(420,42)
	var alert_box:=StyleBoxFlat.new(); alert_box.bg_color=Color("332813",.94); alert_box.border_color=Color("e3b956"); alert_box.set_border_width_all(1); alert_box.set_corner_radius_all(2); _phase_alert.add_theme_stylebox_override("normal",alert_box); add_child(_phase_alert)
	_build_history_panel()
	_build_comparison_panel()
	var stack := VBoxContainer.new(); stack.add_theme_constant_override("separation", 8); margins.add_child(stack)
	var title_row := HBoxContainer.new(); title_row.custom_minimum_size = Vector2(0, 48); stack.add_child(title_row)
	var title := Label.new(); title.text = "적 벽 대 전"; title.add_theme_font_size_override("font_size", 31); title.add_theme_color_override("font_color", Color("e8d5a2")); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; title_row.add_child(title)
	var loc := Label.new(); loc.text = "구지 궤도 전역  ·  208년 10월 23일"; loc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; loc.add_theme_font_size_override("font_size", 15); loc.add_theme_color_override("font_color", Color("9fb0bc")); title_row.add_child(loc)
	_deck = CommandDeck.new(); _deck.custom_minimum_size = Vector2(0, 86); stack.add_child(_deck)
	_state = Label.new(); _state.visible = false; _state.custom_minimum_size = Vector2(0,42); _state.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; _state.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; _state.add_theme_font_size_override("font_size",18)
	var result_box := StyleBoxFlat.new(); result_box.bg_color=Color("111b22"); result_box.border_color=Color("c8a451"); result_box.set_border_width_all(1); result_box.set_corner_radius_all(2); _state.add_theme_stylebox_override("normal",result_box); stack.add_child(_state)
	var split := HBoxContainer.new(); split.custom_minimum_size = Vector2(0, 480); split.size_flags_vertical = Control.SIZE_EXPAND_FILL; split.add_theme_constant_override("separation", 10); stack.add_child(split)
	_map = TacticalMap.new(); _map.name = "TacticalMapTwoThirds"; _map.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _map.size_flags_stretch_ratio = 2.0; split.add_child(_map)
	_feed = BattleStillImage.new(); _feed.name = "BattleStillImageOneThird"; _feed.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _feed.size_flags_stretch_ratio = 1.0; split.add_child(_feed)
	_report = BattleReport.new(); _report.name = "PhaseBattleReport"; _report.custom_minimum_size = Vector2(0, 56); stack.add_child(_report)
	var controls := HBoxContainer.new(); controls.custom_minimum_size = Vector2(0, 60); controls.add_theme_constant_override("separation", 8); stack.add_child(controls)
	controls.add_child(_button("진형 유지", "hold_formation"))
	_formation = OptionButton.new(); _formation.custom_minimum_size = Vector2(144, 46)
	for row in Formations.rows(): _formation.add_item(String(row.get("name", "")))
	_formation.item_selected.connect(_on_formation_preview)
	_style_control_button(_formation, Color("c89f4d"), false)
	controls.add_child(_formation)
	var compare:=Button.new(); compare.name="FormationComparisonButton"; compare.text="진형 비교"; compare.custom_minimum_size=Vector2(106,46); _style_control_button(compare,Color("7896a5"),false); compare.pressed.connect(func(): _toggle_comparison(compare)); controls.add_child(compare)
	controls.add_child(_button("다음 진형 적용", "change_formation")); controls.add_child(_button("다음 페이즈  ›", "advance_phase")); controls.add_child(_button("AI에 위임", "delegate_ai"))
	var history := Button.new(); history.name="BattleHistoryButton"; history.text="전투 기록"; history.custom_minimum_size=Vector2(106,46); _style_control_button(history,Color("7896a5"),false); history.pressed.connect(func(): _toggle_history(history)); controls.add_child(history)
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; controls.add_child(spacer)
	var home := Button.new(); home.text = "홈으로"; home.custom_minimum_size = Vector2(92, 46); _style_control_button(home,Color("607684"),false); home.pressed.connect(func(): return_requested.emit()); controls.add_child(home)
	_feedback = Label.new(); _feedback.custom_minimum_size = Vector2(0, 18); _feedback.add_theme_font_size_override("font_size", 13); _feedback.add_theme_color_override("font_color", Color("e3bd70")); stack.add_child(_feedback)

func _button(label: String, action: String) -> Button:
	var b := Button.new(); b.text = label; b.custom_minimum_size = Vector2(126, 46); b.set_meta("action", action)
	var accents := {"hold_formation":Color("607b8a"),"change_formation":Color("c89f4d"),"advance_phase":Color("e1b64f"),"delegate_ai":Color("708b9a")}
	_style_control_button(b,accents.get(action,Color("607684")),action=="advance_phase")
	b.pressed.connect(func(): _issue(String(b.get_meta("action")))); _buttons.append(b); return b

func _build_history_panel() -> void:
	_history_backdrop=ColorRect.new(); _history_backdrop.name="BattleHistoryBackdrop"; _history_backdrop.visible=false; _history_backdrop.z_index=39; _history_backdrop.color=Color(0,0,0,.52); _history_backdrop.mouse_filter=Control.MOUSE_FILTER_STOP; _history_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _history_backdrop.gui_input.connect(_on_modal_backdrop_input); add_child(_history_backdrop)
	_history_panel=PanelContainer.new(); _history_panel.name="BattleHistoryPanel"; _history_panel.visible=false; _history_panel.z_index=40; _history_panel.focus_mode=Control.FOCUS_ALL; _history_panel.set_anchors_preset(Control.PRESET_CENTER); _history_panel.position=Vector2(-370,-210); _history_panel.size=Vector2(740,420)
	var panel_style:=StyleBoxFlat.new(); panel_style.bg_color=Color("07121b",.985); panel_style.border_color=Color("b9954d"); panel_style.set_border_width_all(2); panel_style.set_corner_radius_all(3); panel_style.content_margin_left=22; panel_style.content_margin_right=22; panel_style.content_margin_top=18; panel_style.content_margin_bottom=18; _history_panel.add_theme_stylebox_override("panel",panel_style); add_child(_history_panel)
	var stack:=VBoxContainer.new(); stack.add_theme_constant_override("separation",10); _history_panel.add_child(stack)
	var heading:=HBoxContainer.new(); stack.add_child(heading)
	var title:=Label.new(); title.text="적벽대전 전투 기록"; title.add_theme_font_size_override("font_size",22); title.add_theme_color_override("font_color",Color("ebd59e")); title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; heading.add_child(title)
	var close:=Button.new(); close.text="닫기"; close.custom_minimum_size=Vector2(76,38); _style_control_button(close,Color("7896a5"),false); close.pressed.connect(_close_modal); heading.add_child(close)
	var rule:=HSeparator.new(); stack.add_child(rule)
	_history_text=Label.new(); _history_text.name="BattleHistoryText"; _history_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; _history_text.vertical_alignment=VERTICAL_ALIGNMENT_TOP; _history_text.size_flags_vertical=Control.SIZE_EXPAND_FILL; _history_text.add_theme_font_size_override("font_size",16); _history_text.add_theme_color_override("font_color",Color("dce7e9")); stack.add_child(_history_text)

func _toggle_history(opener: Control = null) -> void:
	if _history_panel == null: return
	if _history_panel.visible: _close_modal(); return
	if opener != null: _modal_opener=opener
	if _comparison_panel != null: _comparison_panel.visible=false
	_history_panel.visible=true; _history_backdrop.visible=true; _history_panel.grab_focus()

func _build_comparison_panel() -> void:
	_comparison_panel=PanelContainer.new(); _comparison_panel.name="FormationComparisonPanel"; _comparison_panel.visible=false; _comparison_panel.z_index=40; _comparison_panel.focus_mode=Control.FOCUS_ALL; _comparison_panel.set_anchors_preset(Control.PRESET_CENTER); _comparison_panel.position=Vector2(-410,-210); _comparison_panel.size=Vector2(820,420)
	var panel_style:=StyleBoxFlat.new(); panel_style.bg_color=Color("07121b",.985); panel_style.border_color=Color("b9954d"); panel_style.set_border_width_all(2); panel_style.set_corner_radius_all(3); panel_style.content_margin_left=24; panel_style.content_margin_right=24; panel_style.content_margin_top=18; panel_style.content_margin_bottom=18; _comparison_panel.add_theme_stylebox_override("panel",panel_style); add_child(_comparison_panel)
	var stack:=VBoxContainer.new(); stack.add_theme_constant_override("separation",10); _comparison_panel.add_child(stack)
	var heading:=HBoxContainer.new(); stack.add_child(heading)
	var title:=Label.new(); title.text="진형 전술 비교"; title.add_theme_font_size_override("font_size",22); title.add_theme_color_override("font_color",Color("ebd59e")); title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; heading.add_child(title)
	var close:=Button.new(); close.text="닫기"; close.custom_minimum_size=Vector2(76,38); _style_control_button(close,Color("7896a5"),false); close.pressed.connect(_close_modal); heading.add_child(close)
	stack.add_child(HSeparator.new())
	_comparison_summary=Label.new(); _comparison_summary.name="FormationComparisonSummary"; _comparison_summary.add_theme_font_size_override("font_size",15); _comparison_summary.add_theme_color_override("font_color",Color("c9d8dc")); stack.add_child(_comparison_summary)
	_comparison_grid=GridContainer.new(); _comparison_grid.name="FormationComparisonGrid"; _comparison_grid.columns=4; _comparison_grid.size_flags_vertical=Control.SIZE_EXPAND_FILL; _comparison_grid.add_theme_constant_override("h_separation",22); _comparison_grid.add_theme_constant_override("v_separation",8); stack.add_child(_comparison_grid)
	var note:=Label.new(); note.text="※ 계수는 코어 진형 데이터의 페이즈 보정값입니다. 승률 예측이 아니며 적용 전 전투 상태는 변하지 않습니다."; note.add_theme_font_size_override("font_size",12); note.add_theme_color_override("font_color",Color("879ba5")); stack.add_child(note)

func _toggle_comparison(opener: Control = null) -> void:
	if _comparison_panel == null: return
	if _comparison_panel.visible: _close_modal(); return
	if opener != null: _modal_opener=opener
	if _history_panel != null: _history_panel.visible=false
	_comparison_panel.visible=true; _history_backdrop.visible=true
	_refresh_comparison(_current_formation_name,_formation.get_item_text(_formation.selected),_last_phase)
	_comparison_panel.grab_focus()

func _close_modal() -> void:
	if _history_panel != null: _history_panel.visible=false
	if _comparison_panel != null: _comparison_panel.visible=false
	if _history_backdrop != null: _history_backdrop.visible=false
	if is_instance_valid(_modal_opener): _modal_opener.call_deferred("grab_focus")
	_modal_opener=null

func _on_modal_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		_close_modal(); get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE \
			and ((_history_panel != null and _history_panel.visible) or (_comparison_panel != null and _comparison_panel.visible)):
		_close_modal(); get_viewport().set_input_as_handled()

func _formation_comparison(current_name:String,candidate_name:String,current_phase:int)->Dictionary:
	var current_coefficients:=Formations.coefficients(current_name); var candidate_coefficients:=Formations.coefficients(candidate_name)
	var phase_labels:=["접적","포화","교전","강습","결착"]; var rows:Array[Dictionary]=[]
	for index in Formations.PHASE_KEYS.size():
		var key:String=Formations.PHASE_KEYS[index]; var current_value:=float(current_coefficients.get(key,1.0)); var candidate_value:=float(candidate_coefficients.get(key,1.0))
		rows.append({"phase":index+1,"name":phase_labels[index],"current":current_value,"candidate":candidate_value,"delta":candidate_value-current_value,"active":index+1==current_phase})
	return {"current_name":current_name,"candidate_name":candidate_name,"current_width":Formations.width_class(current_name),"candidate_width":Formations.width_class(candidate_name),"current_command":Formations.required_command(current_name),"candidate_command":Formations.required_command(candidate_name),"rows":rows}

func _refresh_comparison(current_name:String,candidate_name:String,current_phase:int)->void:
	if _comparison_grid == null or current_name.is_empty() or candidate_name.is_empty(): return
	var signature:="%s|%s|%d" % [current_name,candidate_name,current_phase]
	if signature==_comparison_signature: return
	_comparison_signature=signature
	var data:=_formation_comparison(current_name,candidate_name,current_phase)
	_comparison_summary.text="현재  %s · 전개폭 %s · 통솔 %d      후보  %s · 전개폭 %s · 통솔 %d" % [data.current_name,data.current_width,data.current_command,data.candidate_name,data.candidate_width,data.candidate_command]
	for child in _comparison_grid.get_children(): _comparison_grid.remove_child(child); child.queue_free()
	for heading in ["페이즈","현재 · %s" % current_name,"후보 · %s" % candidate_name,"변화"]: _comparison_grid.add_child(_comparison_cell(heading,Color("e6cf91"),true))
	for row:Dictionary in data.rows:
		var delta:=float(row.delta); var delta_text:="유지" if is_zero_approx(delta) else ("▲  +%.1f" % delta if delta>0.0 else "▼  %.1f" % delta); var delta_color:=Color("75d7a0") if delta>0.0 else (Color("ef8177") if delta<0.0 else Color("9eb0b8"))
		_comparison_grid.add_child(_comparison_cell(("◆ " if bool(row.active) else "   ")+"%d · %s" % [row.phase,row.name],Color("f0ca73") if bool(row.active) else Color("c5d2d6")))
		_comparison_grid.add_child(_comparison_cell("×%.1f" % float(row.current),Color("b9cbd1")))
		_comparison_grid.add_child(_comparison_cell("×%.1f" % float(row.candidate),Color("e8f0f2")))
		_comparison_grid.add_child(_comparison_cell(delta_text,delta_color))

func _comparison_cell(text:String,color:Color,heading:=false)->Label:
	var label:=Label.new(); label.text=text; label.custom_minimum_size=Vector2(155 if heading else 150,27); label.add_theme_font_size_override("font_size",14 if heading else 15); label.add_theme_color_override("font_color",color); return label

func _refresh_history(results: Array[Dictionary], battle) -> void:
	if _history_text == null: return
	var lines: Array[String] = []
	var allied_total_loss:=0; var wei_total_loss:=0
	for record in results:
		allied_total_loss+=int(record.get("defender_loss",0)); wei_total_loss+=int(record.get("attacker_loss",0))
	lines.append("완료 %d / 5     연합 누적 손실 %d척     위군 누적 손실 %d척\n────────────────────────────────" % [results.size(),allied_total_loss,wei_total_loss])
	if results.is_empty(): lines.append("아직 완료된 페이즈가 없습니다. 접적 판정을 기다리는 중입니다.")
	for record in results:
		var phase_index:=clampi(int(record.get("phase",1)),1,Battle.PHASE_NAMES.size())
		var schemes: Array=record.get("schemes",[]); var scheme_names: Array[String]=[]
		for scheme in schemes:
			var scheme_name:=String((scheme as Dictionary).get("name","")); if not scheme_name.is_empty(): scheme_names.append(scheme_name)
		var scheme_text:="없음" if scheme_names.is_empty() else "·".join(scheme_names)
		lines.append("%d단계  %s\n  연합  -%d척 / 사기 %+d     위군  -%d척 / 사기 %+d     계략  %s" % [phase_index,Battle.PHASE_NAMES[phase_index-1],int(record.get("defender_loss",0)),int(record.get("defender_morale_delta",0)),int(record.get("attacker_loss",0)),int(record.get("attacker_morale_delta",0)),scheme_text])
	if battle != null and String(battle.status)==ActiveBattle.STATUS_RESOLVED:
		var winner_name:="손권·유비 연합" if String(battle.result.get("winner_faction_id",""))=="sun_liu_side" else "위군"
		var decision:Dictionary=battle.result.get("decision",{}); var attacker:Dictionary=decision.get("attacker",{}); var defender:Dictionary=decision.get("defender",{})
		var score_line:="" if decision.is_empty() else "\n판정 근거  잔존 함선×1,000 + 사기×10  ·  위군 %d / 연합 %d" % [int(attacker.get("score",0)),int(defender.get("score",0))]
		lines.append("────────────────────────────────\n결착 결과  ◆  %s 승전%s" % [winner_name,score_line])
	_history_text.text="\n\n".join(lines)

func _on_formation_preview(index: int) -> void:
	if _formation == null or index < 0 or index >= _formation.item_count: return
	_feedback.text = _formation_brief(_formation.get_item_text(index))
	_refresh_comparison(_current_formation_name,_formation.get_item_text(index),_last_phase)

func _formation_brief(formation_name: String) -> String:
	var coefficients := Formations.coefficients(formation_name)
	var phase_labels := {"contact":"접적","barrage":"포화","engagement":"교전","assault":"강습","resolution":"결착"}
	var strongest := 0.0
	for key in Formations.PHASE_KEYS: strongest = maxf(strongest,float(coefficients.get(key,1.0)))
	var strong_phases: Array[String] = []
	for key in Formations.PHASE_KEYS:
		if is_equal_approx(float(coefficients.get(key,1.0)),strongest): strong_phases.append(String(phase_labels[key]))
	var required_trait := Formations.requires_trait(formation_name)
	var trait_note := " · 특성 %s" % required_trait if not required_trait.is_empty() else ""
	return "진형 검토 · %s · 강점 %s ×%.1f · 전개폭 %s · 필요 통솔 %d%s" % [formation_name,"·".join(strong_phases),strongest,Formations.width_class(formation_name),Formations.required_command(formation_name),trait_note]

func _style_control_button(control: Control, accent: Color, primary: bool) -> void:
	var normal := _button_box(Color("3d321d") if primary else Color("101d27"),accent,.82,1 if not primary else 2)
	var hover := _button_box(Color("5a4724") if primary else Color("182a36"),accent.lightened(.16),1.0,2)
	var pressed := _button_box(Color("2e2618") if primary else Color("0b151d"),accent.darkened(.08),1.0,2)
	var focus := _button_box(Color("4a3a20") if primary else Color("142530"),Color("f1d27c"),1.0,2)
	var disabled := _button_box(Color("0a1117"),Color("273943"),.45,1)
	control.add_theme_stylebox_override("normal",normal); control.add_theme_stylebox_override("hover",hover); control.add_theme_stylebox_override("pressed",pressed); control.add_theme_stylebox_override("focus",focus); control.add_theme_stylebox_override("disabled",disabled)
	control.add_theme_color_override("font_color",Color("f5e4b0") if primary else Color("dbe5e8")); control.add_theme_color_override("font_hover_color",Color("fff0c6")); control.add_theme_color_override("font_focus_color",Color("fff0c6")); control.add_theme_color_override("font_disabled_color",Color("53636c"))

func _button_box(background: Color, border: Color, border_alpha: float, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new(); box.bg_color=background; box.border_color=Color(border,border_alpha)
	box.set_border_width_all(width); box.set_corner_radius_all(2); box.content_margin_left=12; box.content_margin_right=12
	return box

func _battle():
	if campaign == null: return null
	for entry in campaign.active_battles:
		if String(entry.battle_id) == battle_id: return entry
	return null

func _issue(action: String) -> void:
	var battle = _battle()
	if battle == null or String(battle.status) != ActiveBattle.STATUS_ACTIVE: _feedback.text = "전투가 활성 상태가 아니므로 명령이 거부되었습니다."; return
	if not campaign.has_method("issue_red_cliff_player_command"): _feedback.text = "전투 코어 명령 API를 기다리는 중입니다."; return
	var payload := {}
	if action == "change_formation": payload["target_formation_id"] = Formations.id_for_name(_formation.get_item_text(_formation.selected))
	var issued = campaign.call("issue_red_cliff_player_command", battle_id, action, payload)
	if issued is Dictionary and not issued.is_empty():
		var action_labels := {"hold_formation":"현재 진형 유지", "change_formation":"%s 적용" % _formation.get_item_text(_formation.selected), "advance_phase":"다음 페이즈 진행", "delegate_ai":"AI 전술 위임"}
		_pending_command_kind=action; _pending_command_label=String(action_labels.get(action, action))
		_feedback.text = "◆ 명령 접수 · %s · 대기 중 · 다음 전역 틱에 적용됩니다." % _pending_command_label
	else:
		var state:Dictionary=campaign.call("red_cliff_command_state",battle_id,action,payload)
		var requested:Dictionary=state.get("requested_command",{})
		_feedback.text = "명령 거부 · %s" % _command_reason_text(String(requested.get("reason_code","rejected_by_reducer")))

func _command_reason_text(reason_code:String)->String:
	var reasons:={"unknown_battle":"전투 식별자를 찾을 수 없습니다.","resolved":"이미 결착된 전투입니다.","battle_not_active":"현재 활성 전투가 아닙니다.","invalid_payload":"진형 또는 명령 정보가 유효하지 않습니다.","ai_delegated":"AI 위임 중에는 플레이어 명령을 내릴 수 없습니다.","phase_not_ready":"자동 접적 판정이 끝난 뒤 다음 페이즈를 진행할 수 있습니다.","duplicate_command":"같은 페이즈에 이미 동일 명령을 접수했습니다.","insufficient_command":"함대 통솔 수치가 명령 요구치를 충족하지 못합니다.","invalid_origin":"플레이어 명령 경로가 아닙니다.","rejected_by_reducer":"현재 전투 상태에서 적용할 수 없는 명령입니다."}
	return String(reasons.get(reason_code,"명령을 적용할 수 없습니다. (%s)" % reason_code))

func _refresh() -> void:
	if _state == null: return
	var battle = _battle()
	if battle == null: _state.text = "정본 전투를 찾을 수 없습니다."; return
	var phase := int(battle.combat_phase)
	var phase_name := Battle.PHASE_NAMES[phase - 1] if phase >= 1 and phase <= Battle.PHASE_NAMES.size() else "대기"
	if phase != _last_phase:
		_last_phase = phase
		_show_phase_alert(phase,phase_name)
	var a := int(battle.attacker_ships); var d := int(battle.defender_ships); var am := int(battle.attacker_morale); var dm := int(battle.defender_morale)
	_state.visible = false
	_state.text = "%d / 5 페이즈 %s · 조조측 %d척 / %d · 연합 %d척 / %d" % [phase, phase_name, a, am, d, dm]
	if String(battle.status) == ActiveBattle.STATUS_RESOLVED:
		var winner := String(battle.result.get("winner_faction_id", ""))
		var winner_name := "손권·유비 연합" if winner == "sun_liu_side" else "위군"
		_state.text = "결착 완료  ◆  %s 승전  ·  위군 %d척 / 사기 %d  ·  연합 %d척 / 사기 %d" % [winner_name,a,am,d,dm]
		_state.add_theme_color_override("font_color",Color("ef8478") if winner == "sun_liu_side" else Color("7bcdf5"))
		_state.visible = true
		_phase_alert_time=0.0; _phase_alert.visible=false
	var attacker_formation_id := String(battle.attacker_formation_id)
	var attacker_formation_name := Formations.name_for_id(attacker_formation_id)
	_current_formation_name=attacker_formation_name
	var defender_formation_name := Formations.name_for_id(String(battle.defender_formation_id))
	if attacker_formation_id != _synced_formation_id:
		_synced_formation_id = attacker_formation_id
		for index in _formation.item_count:
			if _formation.get_item_text(index) == attacker_formation_name:
				_formation.select(index)
				break
	_formation.tooltip_text = "현재 위군 진형: %s" % attacker_formation_name
	if _feedback.text.is_empty(): _feedback.text = _formation_brief(attacker_formation_name)
	_deck.set_battle(phase, phase_name, a, d, am, dm, attacker_formation_name); _map.set_battle(phase, phase_name, a, d, am, dm, attacker_formation_name, defender_formation_name); _map.set_results(battle.phase_results); _feed.set_battle(phase, phase_name, a, d, am, dm); _report.set_results(battle.phase_results)
	var active := String(battle.status) == ActiveBattle.STATUS_ACTIVE
	var command_state: Dictionary = campaign.call("red_cliff_command_state", battle_id) if campaign != null and campaign.has_method("red_cliff_command_state") else {}
	var delegated := bool(command_state.get("ai_delegated", false))
	var player_commands: Array = command_state.get("player_commands", [])
	var reducer_feedback:Dictionary=command_state.get("last_command_feedback",{})
	if not _pending_command_kind.is_empty() and not reducer_feedback.is_empty() \
			and String(reducer_feedback.get("kind",""))==_pending_command_kind \
			and not bool(reducer_feedback.get("accepted",false)):
		_feedback.text="명령 거부 · %s" % _command_reason_text(String(reducer_feedback.get("reason_code","rejected_by_reducer")))
		_pending_command_kind=""; _pending_command_label=""
	if player_commands.size() != _applied_command_count:
		_applied_command_count=player_commands.size()
		if not _pending_command_kind.is_empty():
			var applied := false
			for row in player_commands:
				if String((row as Dictionary).get("kind", "")) == _pending_command_kind: applied=true
			if applied:
				_feedback.text="✓ 명령 적용 · %s · 현재 %d단계 %s" % [_pending_command_label,phase,phase_name]
				_pending_command_kind=""; _pending_command_label=""
	if not _pending_command_kind.is_empty(): _report.set_command_status("명령 접수 · %s · 대기 중" % _pending_command_label)
	elif _applied_command_count>0: _report.set_command_status("마지막 명령 적용 · %d건 기록" % _applied_command_count)
	else: _report.set_command_status("명령 대기 · 다음 전역 틱에 정본 판정")
	_report.set_phase(phase, phase_name, delegated)
	_refresh_history(battle.phase_results,battle)
	if _comparison_panel.visible: _refresh_comparison(attacker_formation_name,_formation.get_item_text(_formation.selected),phase)
	for b in _buttons:
		var action := String(b.get_meta("action", ""))
		if action == "advance_phase": b.disabled = not bool(command_state.get("can_advance", false))
		elif action == "change_formation": b.disabled = not bool(command_state.get("can_change_formation", false))
		else: b.disabled = not active or delegated
	_formation.disabled = not bool(command_state.get("can_change_formation", false))
	if delegated and active: _feedback.text = "AI 전술 위임 중 · 플레이어 명령은 잠겼으며 페이즈는 자동 진행됩니다."
	if not active:
		var decision:Dictionary=battle.result.get("decision",{}); var attacker_evidence:Dictionary=decision.get("attacker",{}); var defender_evidence:Dictionary=decision.get("defender",{})
		_feedback.text = "판정 근거 · 잔존 함선×1,000 + 사기×10 · 위군 %d / 연합 %d" % [int(attacker_evidence.get("score",0)),int(defender_evidence.get("score",0))] if not decision.is_empty() else "전투 종료 · 이후 명령은 코어가 거부합니다."

func _show_phase_alert(phase: int, phase_name: String) -> void:
	if _phase_alert == null: return
	var cues := ["교전권 진입","장거리 포화 개시","주력 전열 충돌","거점 강습 개시","최종 결착 판정"]
	var index:=clampi(phase-1,0,cues.size()-1)
	_phase_alert.text="PHASE %d · %s  ◆  %s" % [phase,phase_name,cues[index]]
	_phase_alert.modulate.a=1.0; _phase_alert.visible=true; _phase_alert_time=1.8

class CommandDeck extends Control:
	var phase := 0; var phase_name := "대기"; var a := 0; var d := 0; var am := 0; var dm := 0
	var attacker_formation_name := ""
	func set_battle(p: int, n: String, aa: int, dd: int, aam: int, ddm: int, formation_name: String) -> void: phase=p; phase_name=n; a=aa; d=dd; am=aam; dm=ddm; attacker_formation_name=formation_name; queue_redraw()
	func _draw() -> void:
		var font := get_theme_default_font(); draw_rect(Rect2(Vector2.ZERO,size),Color("09131d")); draw_rect(Rect2(Vector2.ZERO,size),Color("344958"),false,1)
		_force(Rect2(8,8,size.x*.23,67),"오 · 유 연합군","합선 %d척" % d,dm,Color("c75a52"),false)
		_force(Rect2(size.x*.70,8,size.x*.29-8,67),"위군 · %s" % attacker_formation_name,"함선 %d척" % a,am,Color("4f9fce"),true)
		var words := ["접적","포화","교전","강습","결착"]; var start:=size.x*.30; var width:=size.x*.38; draw_line(Vector2(start,20),Vector2(start+width,20),Color("64727a"),2)
		for i in 5:
			var x:=start+width*i/4.0; var live:=i+1==phase; draw_circle(Vector2(x,20),14 if live else 11,Color("b58b3b") if live else Color("172633")); draw_arc(Vector2(x,20),14 if live else 11,0,TAU,20,Color("f2d37e") if live else Color("8d9ba4"),1.2); draw_string(font,Vector2(x-4,25),str(i+1),HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("fff4d5")); draw_string(font,Vector2(x-18,51),words[i],HORIZONTAL_ALIGNMENT_CENTER,36,13,Color("f3d27c") if live else Color("aebbc3"))
	func _force(box: Rect2, name: String, ships: String, morale: int, tint: Color, right: bool) -> void:
		var font:=get_theme_default_font(); var align:=HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT; draw_rect(box,Color("0b1924")); draw_rect(box,tint.darkened(.35),false,1); draw_string(font,box.position+Vector2(12,24),name,align,box.size.x-24,17,Color("e8eef0")); draw_string(font,box.position+Vector2(12,44),ships,align,box.size.x-24,13,Color("9fb1bb")); var bar:=Rect2(box.position+Vector2(12,53),Vector2(box.size.x-24,6)); draw_rect(bar,Color("111e29")); draw_rect(Rect2(bar.position,Vector2(bar.size.x*clamp(morale,0,100)/100.0,6)),tint)

class BattleReport extends Control:
	var summary := "전투 판정 대기 · 명령을 선택하면 다음 전역 틱에 결과가 반영됩니다."
	var command_status := "명령 대기 · 다음 전역 틱에 정본 판정"
	var current_directive := "접적 좌표 확인 · 전열과 교전권 진입 경로를 점검하십시오."
	var allied_loss := 0
	var wei_loss := 0
	var allied_morale_delta := 0
	var wei_morale_delta := 0
	var scheme_summary := "계략 없음"
	func set_results(results: Array[Dictionary]) -> void:
		if results.is_empty():
			summary = "전투 판정 대기 · 명령을 선택하면 다음 전역 틱에 결과가 반영됩니다."
			allied_loss = 0; wei_loss = 0; allied_morale_delta = 0; wei_morale_delta = 0; scheme_summary = "계략 없음"
		else:
			var latest: Dictionary = results.back()
			var resolved_phase := clampi(int(latest.get("phase", 1)), 1, Battle.PHASE_NAMES.size())
			wei_loss = int(latest.get("attacker_loss", 0)); allied_loss = int(latest.get("defender_loss", 0))
			wei_morale_delta = int(latest.get("attacker_morale_delta", 0)); allied_morale_delta = int(latest.get("defender_morale_delta", 0))
			var schemes: Array = latest.get("schemes", [])
			var scheme_names: Array[String] = []
			for scheme in schemes:
				var scheme_name:=String((scheme as Dictionary).get("name",""))
				if not scheme_name.is_empty(): scheme_names.append(scheme_name)
			scheme_summary = "계략 없음" if scheme_names.is_empty() else "계략 발동: %s" % "·".join(scheme_names)
			summary = "직전 전과 · %d단계 %s · %s" % [resolved_phase, Battle.PHASE_NAMES[resolved_phase-1], scheme_summary]
		queue_redraw()
	func set_phase(current_phase: int, current_name: String, delegated: bool) -> void:
		var directives := [
			"접적 좌표 확인 · 전열과 교전권 진입 경로를 점검하십시오.",
			"장거리 포화 · 적 사기와 전열을 먼저 흔드십시오.",
			"주력 교전 · 진형 상성과 잔존 전력을 확인하십시오.",
			"거점 강습 · 붕괴한 측면과 지휘선을 압박하십시오.",
			"결착 · 잔존 전력을 집중해 승패를 확정하십시오.",
		]
		var index := clampi(current_phase-1,0,directives.size()-1)
		current_directive = "%d단계 %s · %s" % [current_phase,current_name,directives[index]]
		if delegated: current_directive += "  [AI 지휘 중]"
		queue_redraw()
	func set_command_status(status: String) -> void:
		if command_status != status: command_status=status; queue_redraw()
	func _draw() -> void:
		var font := get_theme_default_font()
		draw_rect(Rect2(Vector2.ZERO,size),Color("08131c",.96)); draw_rect(Rect2(Vector2.ZERO,size),Color("314958"),false,1)
		draw_string(font,Vector2(14,22),summary,HORIZONTAL_ALIGNMENT_LEFT,size.x*.48,13,Color("c6d3d8"))
		var allied := "연합 손실 %d척  ·  사기 %+d" % [allied_loss,allied_morale_delta]
		var wei := "위군 손실 %d척  ·  사기 %+d" % [wei_loss,wei_morale_delta]
		draw_string(font,Vector2(size.x*.51,22),allied,HORIZONTAL_ALIGNMENT_LEFT,size.x*.23,13,Color("ee7b72"))
		draw_string(font,Vector2(size.x*.76,22),wei,HORIZONTAL_ALIGNMENT_LEFT,size.x*.22,13,Color("69c4f4"))
		draw_line(Vector2(12,31),Vector2(size.x-12,31),Color("263b49"),1)
		draw_string(font,Vector2(14,49),"현재 지침 · "+current_directive,HORIZONTAL_ALIGNMENT_LEFT,size.x*.67,12,Color("e4bd6b"))
		draw_string(font,Vector2(size.x*.70,49),command_status,HORIZONTAL_ALIGNMENT_LEFT,size.x*.29,12,Color("9fd0da"))

class TacticalMap extends Control:
	var phase:=0; var phase_name:="대기"; var a:=0; var d:=0; var am:=0; var dm:=0
	var attacker_formation_name:="미확인"; var defender_formation_name:="미확인"
	var selected_fleet := ""
	var hover_fleet := ""
	var keyboard_fleet_index := -1
	var latest_result: Dictionary = {}
	var latest_result_signature := ""
	var result_flash := 0.0
	var clock := 0.0
	func _ready() -> void: custom_minimum_size=Vector2(650,400); mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND; focus_mode=Control.FOCUS_ALL; tooltip_text="전술 지도. 화살표 키로 함대를 순회하고 Enter 또는 Space로 선택합니다."; set_process(true); set_process_unhandled_key_input(true); queue_redraw()
	func _process(delta: float) -> void: clock = fmod(clock + delta, 120.0); result_flash=maxf(0.0,result_flash-delta); queue_redraw()
	func set_battle(p:int,n:String,aa:int,dd:int,aam:int,ddm:int,attacker_formation:="미확인",defender_formation:="미확인")->void:
		phase=p; phase_name=n; a=aa; d=dd; am=aam; dm=ddm; attacker_formation_name=attacker_formation; defender_formation_name=defender_formation
		if (selected_fleet.begins_with("allied") and d<=0) or (selected_fleet.begins_with("wei") and a<=0): selected_fleet=""
		queue_redraw()
	func set_results(results: Array[Dictionary]) -> void:
		if results.is_empty(): latest_result={}; latest_result_signature=""; return
		var record: Dictionary=results.back(); var schemes: Array=record.get("schemes",[]); var names:Array[String]=[]
		for scheme in schemes:
			var scheme_name:=String((scheme as Dictionary).get("name","")); if not scheme_name.is_empty(): names.append(scheme_name)
		var signature:="%d|%d|%d|%d|%d|%d|%s" % [int(record.get("phase",0)),int(record.get("attacker_loss",0)),int(record.get("defender_loss",0)),int(record.get("attacker_morale_delta",0)),int(record.get("defender_morale_delta",0)),results.size(),"·".join(names)]
		if signature != latest_result_signature: latest_result_signature=signature; result_flash=1.65
		latest_result=record.duplicate(true); latest_result["scheme_names"]=names
	func fleet_icon_counts()->Vector2i: return Vector2i(mini(d,20),mini(a,20))
	func route_progress() -> float: return clampf(.10 + float(maxi(phase, 1) - 1) * .17, .10, .82)
	func fleet_anchor_points() -> Dictionary:
		var hub := Vector2(size.x*.52,size.y*.55)
		var progress := route_progress()
		return {
			"allied_primary": _route_point(Vector2(size.x*.18,size.y*.37),Vector2(size.x*.39,size.y*.30),hub,progress),
			"allied_secondary": _route_point(Vector2(size.x*.21,size.y*.72),Vector2(size.x*.36,size.y*.70),hub,progress),
			"wei_primary": _route_point(Vector2(size.x*.82,size.y*.31),Vector2(size.x*.70,size.y*.31),hub,progress),
			"wei_secondary": _route_point(Vector2(size.x*.78,size.y*.70),Vector2(size.x*.67,size.y*.69),hub,progress),
		}
	func select_fleet(fleet_id:String)->void:
		if fleet_id in ["allied_primary","allied_secondary"] and d <= 0: selected_fleet=""
		elif fleet_id in ["wei_primary","wei_secondary"] and a <= 0: selected_fleet=""
		elif fleet_id in fleet_anchor_points(): selected_fleet=fleet_id
		else: selected_fleet=""
		queue_redraw()
	func selection_snapshot()->Dictionary:
		return selection_snapshot_for(selected_fleet)
	func selection_snapshot_for(fleet_id:String)->Dictionary:
		if fleet_id.is_empty(): return {}
		var allied:=fleet_id.begins_with("allied")
		var names:={"allied_primary":"우비 돌격단","allied_secondary":"손권 주력","wei_primary":"위군 본대","wei_secondary":"장료 기동대"}
		return {"id":fleet_id,"name":String(names.get(fleet_id,"미확인 함대")),"faction":"손권·유비 연합" if allied else "위군","ships":d if allied else a,"morale":dm if allied else am,"formation":defender_formation_name if allied else attacker_formation_name,"objective":_phase_objective(),"engagement":_engagement_state()}
	func _gui_input(event:InputEvent)->void:
		if event is InputEventMouseMotion: _hover_at(event.position)
		elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed: grab_focus(); _select_at(event.position)
		elif event is InputEventScreenTouch and event.pressed: _select_at(event.position)
	func _unhandled_key_input(event: InputEvent) -> void:
		if not has_focus() or not event.pressed or event.echo: return
		if event.keycode in [KEY_LEFT,KEY_UP,KEY_RIGHT,KEY_DOWN]:
			var ids:=_available_fleet_ids(); if ids.is_empty(): return
			var step:=-1 if event.keycode in [KEY_LEFT,KEY_UP] else 1
			keyboard_fleet_index=posmod(keyboard_fleet_index+step,ids.size()); hover_fleet=String(ids[keyboard_fleet_index]); tooltip_text="전술 지도 · %s. Enter 또는 Space로 선택" % String(selection_snapshot_for(hover_fleet).get("name","함대")); get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_ENTER,KEY_SPACE] and not hover_fleet.is_empty(): select_fleet(hover_fleet); get_viewport().set_input_as_handled()
	func _available_fleet_ids()->Array[String]:
		var ids:Array[String]=[]
		if d>0: ids.append_array(["allied_primary","allied_secondary"])
		if a>0: ids.append_array(["wei_primary","wei_secondary"])
		return ids
	func _hover_at(point:Vector2)->void:
		var nearest:=""; var nearest_distance:=48.0
		for fleet_id in fleet_anchor_points():
			var distance:=point.distance_to(fleet_anchor_points()[fleet_id]); if distance<nearest_distance: nearest=fleet_id; nearest_distance=distance
		if hover_fleet!=nearest: hover_fleet=nearest; tooltip_text="전술 지도" if nearest.is_empty() else "함대 %s · 클릭하여 상세 표시" % String(selection_snapshot_for(nearest).get("name","")); queue_redraw()
	func _select_at(point:Vector2)->void:
		var nearest:=""; var nearest_distance:=48.0
		for fleet_id in fleet_anchor_points():
			var distance:=point.distance_to(fleet_anchor_points()[fleet_id])
			if distance < nearest_distance: nearest=fleet_id; nearest_distance=distance
		select_fleet(nearest)
	func _phase_objective()->String:
		return ["교전권 진입","적 전열 압박","주력 전열 충돌","구지 거점 돌파","잔존 전력 격멸"][clampi(phase-1,0,4)]
	func _engagement_state()->String:
		return ["접근 중","장거리 교전","근접 교전","강습 중","결착 진행"][clampi(phase-1,0,4)]
	func _draw() -> void:
		var font:=get_theme_default_font(); var hub:=Vector2(size.x*.52,size.y*.55)
		# A painted, layered board gives the battlefield depth before tactical marks land on it.
		draw_rect(Rect2(Vector2.ZERO,size),Color("050b12"))
		for i in 8: draw_circle(Vector2(size.x*.76,size.y*.18),250.0-i*27.0,Color(0.04,0.15,0.23,0.018+i*.004))
		for i in 96:
			var star:=Vector2(fposmod(i*97.0+31.0,size.x),42.0+fposmod(i*53.0,size.y-66.0)); draw_circle(star,.35+float(i%4)*.22,Color("9ec8dd",.22+float(i%3)*.14))
		var planet:=Vector2(-size.y*.16,size.y*.66)
		for radius in range(int(size.y*.78),20,-14): draw_circle(planet,radius,Color(0.015+radius/30000.0,0.07+radius/9000.0,0.11+radius/7000.0,.12))
		draw_arc(planet,size.y*.78,-1.22,0.22,100,Color("5b99b5",.8),2.0)
		for radius in [72.0,138.0,212.0,290.0]: draw_arc(hub,radius,-.22,TAU-.22,100,Color("406579",.43),1.0)
		for x in range(0,int(size.x),64): draw_line(Vector2(x,41),Vector2(x,size.y-31),Color("254151",.28),.6)
		for y in range(42,int(size.y-31),64): draw_line(Vector2(0,y),Vector2(size.x,y),Color("254151",.28),.6)
		# Sector header and compact operational legend.
		draw_rect(Rect2(0,0,size.x,41),Color("08131e",.96)); draw_line(Vector2(0,41),Vector2(size.x,41),Color("587384",.8),1)
		draw_string(font,Vector2(16,27),"구지 궤도  ·  전술 지휘도",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("e8f1f2"))
		draw_string(font,Vector2(size.x-194,26),"제 %d 국면  /  %s" % [phase,phase_name],HORIZONTAL_ALIGNMENT_RIGHT,178,13,Color("f0cb76"))
		# Engagement zone and objective are readable at a glance.
		draw_circle(hub,52,Color("d7ad57",.055)); draw_arc(hub,52,0,TAU,48,Color("d8b66d",.8),1.4); draw_arc(hub,32,0,TAU,32,Color("a77a35",.5),.8)
		_station(hub)
		# Abstract icon counts are capped for legibility but never exceed the
		# canonical live count. A zero-ship faction leaves no current route or fleet.
		if d > 0:
			var allied_icons := fleet_icon_counts().x; var allied_first := ceili(float(allied_icons)*.55); var allied_second := allied_icons-allied_first
			var allied_from := Vector2(size.x*.18,size.y*.37); var allied_control := Vector2(size.x*.39,size.y*.30)
			_route_curve(allied_from,allied_control,hub,Color("e66b5f"),true)
			var allied_t := clampf(route_progress()+sin(clock*.9)*.008,.0,.9)
			_fleet_wedge(_route_point(allied_from,allied_control,hub,allied_t),Color("eb685c"),"우비 돌격단",allied_first,_route_tangent(allied_from,allied_control,hub,allied_t).angle(),"allied_primary")
			if allied_second > 0:
				var allied_two_from := Vector2(size.x*.21,size.y*.72); var allied_two_control := Vector2(size.x*.36,size.y*.70)
				_route_curve(allied_two_from,allied_two_control,hub,Color("e66b5f"),true)
				var allied_two_t := clampf(route_progress()*.92+sin(clock*.82+1.4)*.007,.0,.9)
				_fleet_wedge(_route_point(allied_two_from,allied_two_control,hub,allied_two_t),Color("d94f50"),"손권 주력",allied_second,_route_tangent(allied_two_from,allied_two_control,hub,allied_two_t).angle(),"allied_secondary")
		if a > 0:
			var wei_icons := fleet_icon_counts().y; var wei_first := ceili(float(wei_icons)*.55); var wei_second := wei_icons-wei_first
			var wei_from := Vector2(size.x*.82,size.y*.31); var wei_control := Vector2(size.x*.70,size.y*.31)
			_route_curve(wei_from,wei_control,hub,Color("63bef1"),false)
			var wei_t := clampf(route_progress()*.96+sin(clock*.88+.7)*.008,.0,.9)
			_fleet_wedge(_route_point(wei_from,wei_control,hub,wei_t),Color("6bcafa"),"위군 본대",wei_first,_route_tangent(wei_from,wei_control,hub,wei_t).angle(),"wei_primary")
			if wei_second > 0:
				var wei_two_from := Vector2(size.x*.78,size.y*.70); var wei_two_control := Vector2(size.x*.67,size.y*.69)
				_route_curve(wei_two_from,wei_two_control,hub,Color("63bef1"),false)
				var wei_two_t := clampf(route_progress()*.88+sin(clock*.78+2.1)*.007,.0,.9)
				_fleet_wedge(_route_point(wei_two_from,wei_two_control,hub,wei_two_t),Color("53aee1"),"장료 기동대",wei_second,_route_tangent(wei_two_from,wei_two_control,hub,wei_two_t).angle(),"wei_secondary")
		_engagement_fx(hub)
		_force_card(Rect2(14,54,180,62),"연합 전력",d,dm,int(d+int(latest_result.get("defender_loss",0))),int(dm-int(latest_result.get("defender_morale_delta",0))),Color("df6158"))
		_force_card(Rect2(size.x-194,54,180,62),"위군 전력",a,am,int(a+int(latest_result.get("attacker_loss",0))),int(am-int(latest_result.get("attacker_morale_delta",0))),Color("62bdf1"))
		if not selected_fleet.is_empty(): _selection_card()
		_result_overlay(hub)
		draw_rect(Rect2(0,size.y-30,size.x,30),Color("07111a",.94)); draw_string(font,Vector2(14,size.y-10),"◆ 주요 합선   ─ ─ 이동 경로   ◌ 교전 구역   △ 함대 전열   ·   함대 표식 클릭: 상세",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("a7bac4"))
	func _station(pos:Vector2)->void:
		var font:=get_theme_default_font(); draw_circle(pos,11,Color("f2d280",.85)); draw_circle(pos,6,Color("09131d"));
		for angle in [0.0,PI*.5,PI,PI*1.5]: draw_line(pos+Vector2(12,0).rotated(angle),pos+Vector2(23,0).rotated(angle),Color("d9b464"),3)
		draw_string(font,pos+Vector2(-56,80),"구지 거점\n점령 목표",HORIZONTAL_ALIGNMENT_CENTER,112,13,Color("f3e2b7"))
	func _route_curve(from:Vector2,control:Vector2,to:Vector2,color:Color,_red:bool)->void:
		var points:=PackedVector2Array(); for i in 17: var t:=float(i)/16.0; points.append(_route_point(from,control,to,t))
		for i in points.size()-1: draw_dashed_line(points[i],points[i+1],color,1.8,7.0)
		var tip:=points[points.size()-1]; var direction:=(tip-points[points.size()-2]).normalized(); var side:=Vector2(-direction.y,direction.x); draw_colored_polygon(PackedVector2Array([tip,tip-direction*10+side*5,tip-direction*10-side*5]),color)
		for marker in 4:
			var marker_t := fposmod(clock*.075+float(marker)*.25,1.0)
			draw_circle(_route_point(from,control,to,marker_t),2.2,color.lightened(.35))
	func _route_point(from:Vector2,control:Vector2,to:Vector2,t:float)->Vector2:
		return from.lerp(control,t).lerp(control.lerp(to,t),t)
	func _route_tangent(from:Vector2,control:Vector2,to:Vector2,t:float)->Vector2:
		return ((control-from)*(2.0*(1.0-t))+(to-control)*(2.0*t)).normalized()
	func _engagement_fx(hub:Vector2)->void:
		if phase < 2 or a <= 0 or d <= 0: return
		var pulse := .5+.5*sin(clock*3.2)
		draw_arc(hub,58.0+pulse*9.0,0,TAU,48,Color(1.0,.62,.25,.22+.28*pulse),2.0)
		var salvo_count := mini(phase+1,6)
		for i in salvo_count:
			var angle := clock*.38+float(i)*TAU/float(salvo_count)
			var outer := hub+Vector2(36.0+float(i%2)*16.0,0).rotated(angle)
			var inner := hub+Vector2(9,0).rotated(angle+PI)
			draw_line(outer,inner,Color("ffbd68",.42+.35*abs(sin(clock*4.0+i))),1.4)
		if phase >= 3:
			for i in phase-1:
				var burst := hub+Vector2(18.0+float(i)*11.0,0).rotated(float(i)*2.1+clock*.12)
				draw_circle(burst,3.0+2.2*abs(sin(clock*3.8+i)),Color("ff7a49",.72))
	func _fleet_wedge(pos:Vector2,color:Color,label:String,count:int,angle:float,fleet_id:String)->void:
		var font:=get_theme_default_font(); draw_circle(pos,33,Color(color,.055)); draw_arc(pos,33,0,TAU,32,Color(color,.55),1)
		if selected_fleet==fleet_id or hover_fleet==fleet_id:
			var pulse:=2.0+1.2*(.5+.5*sin(clock*4.0)); draw_arc(pos,39,0,TAU,40,Color("ffe39a"),pulse); draw_circle(pos,45,Color("e9bd58",.045))
		for i in count:
			var row:=int(sqrt(float(i))); var within:=i-row*row; var off:=Vector2(13.0+row*11.0,(within-row*.5)*12.0).rotated(angle)
			var tip:=pos+off; var forward:=Vector2(6,0).rotated(angle); var side:=Vector2(0,4).rotated(angle)
			draw_colored_polygon(PackedVector2Array([tip+forward,tip-forward*.65+side,tip-forward*.65-side]),color)
		draw_circle(pos,4,Color("f4e3ba")); draw_string(font,pos+Vector2(-57,-43),label,HORIZONTAL_ALIGNMENT_CENTER,114,13,Color("edf4f5"))
	func _selection_card()->void:
		var data:=selection_snapshot(); if data.is_empty(): return
		var allied:=String(data.faction)=="손권·유비 연합"; var tint:=Color("e96c61") if allied else Color("65c5f4"); var faction_short:="연합" if allied else "위군"
		var rect:=Rect2(14,118,240,142); var font:=get_theme_default_font()
		draw_rect(rect,Color("07131d",.97)); draw_rect(rect,tint,false,1.5); draw_rect(Rect2(rect.position,Vector2(4,rect.size.y)),tint)
		draw_string(font,rect.position+Vector2(16,25),"선택 함대  ◆  %s" % data.name,HORIZONTAL_ALIGNMENT_LEFT,208,16,Color("f5e4b4"))
		draw_line(rect.position+Vector2(14,34),rect.position+Vector2(rect.size.x-14,34),Color("39515e"),1)
		draw_string(font,rect.position+Vector2(16,57),"%s  ·  전체 %d척  ·  사기 %d" % [faction_short,data.ships,data.morale],HORIZONTAL_ALIGNMENT_LEFT,208,13,Color("dce8eb"))
		draw_string(font,rect.position+Vector2(16,79),"현재 진형  %s" % data.formation,HORIZONTAL_ALIGNMENT_LEFT,208,13,Color("bcd0d7"))
		draw_string(font,rect.position+Vector2(16,101),"작전 목표  %s" % data.objective,HORIZONTAL_ALIGNMENT_LEFT,208,13,Color("e4bd6b"))
		draw_string(font,rect.position+Vector2(16,123),"교전 상태  %s" % data.engagement,HORIZONTAL_ALIGNMENT_LEFT,208,13,tint.lightened(.18))
	func _force_card(rect:Rect2,title:String,ships:int,morale:int,previous_ships:int,previous_morale:int,tint:Color)->void:
		var font:=get_theme_default_font(); draw_rect(rect,Color("08151f",.93)); draw_rect(rect,tint.darkened(.28),false,1); draw_rect(Rect2(rect.position,Vector2(3,rect.size.y)),tint); draw_string(font,rect.position+Vector2(12,19),title,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("aebfc8")); draw_string(font,rect.position+Vector2(12,39),"현재  %d척 · 사기 %d" % [ships,morale],HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("eff6f7")); var prior:="직전  %d척 · 사기 %d" % [previous_ships,previous_morale] if not latest_result.is_empty() else "직전 전과 없음"; draw_string(font,rect.position+Vector2(12,55),prior,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("9fb7c0"))
	func _result_overlay(hub:Vector2)->void:
		if latest_result.is_empty(): return
		var font:=get_theme_default_font(); var phase_done:=int(latest_result.get("phase",0)); var allied_loss:=int(latest_result.get("defender_loss",0)); var wei_loss:=int(latest_result.get("attacker_loss",0)); var allied_morale:=int(latest_result.get("defender_morale_delta",0)); var wei_morale:=int(latest_result.get("attacker_morale_delta",0)); var names:Array=latest_result.get("scheme_names",[]); var scheme_text:="계략 없음" if names.is_empty() else "계략 발동 · "+" · ".join(names)
		var rect:=Rect2(size.x*.31,size.y-112,size.x*.38,70); draw_rect(rect,Color("07131d",.92)); draw_rect(rect,Color("d6ac5a",.9),false,1)
		draw_string(font,rect.position+Vector2(12,19),"PHASE %d 결과 적용  ·  %s" % [phase_done,scheme_text],HORIZONTAL_ALIGNMENT_LEFT,rect.size.x-24,13,Color("f0d18a")); draw_string(font,rect.position+Vector2(12,40),"연합  -%d척 / 사기 %+d     위군  -%d척 / 사기 %+d" % [allied_loss,allied_morale,wei_loss,wei_morale],HORIZONTAL_ALIGNMENT_LEFT,rect.size.x-24,13,Color("dde8ea")); draw_string(font,rect.position+Vector2(12,58),"현재 전력은 상단 카드, 직전 전력은 이 결과 전 상태입니다.",HORIZONTAL_ALIGNMENT_LEFT,rect.size.x-24,11,Color("9eb6be"))
		if result_flash>0.0:
			var alpha:=clampf(result_flash/1.65,0.0,1.0); draw_arc(hub,65+(1.0-alpha)*32,0,TAU,48,Color("ffe09a",alpha*.75),2.4); draw_string(font,hub+Vector2(-80,-78),"전과 반영",HORIZONTAL_ALIGNMENT_CENTER,160,15,Color(1,0.88,.62,alpha))

class BattleStillImage extends Control:
	var phase_label: Label
	var allied_label: Label
	var wei_label: Label
	var allied_bar: ProgressBar
	var wei_bar: ProgressBar

	func _ready() -> void:
		custom_minimum_size = Vector2(320, 400)
		clip_contents = true
		var image := TextureRect.new()
		image.name = "BattleConceptStill"
		image.texture = load("res://assets/ui-mockups/red-cliffs-live-battle-v1.png")
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(image)

		var top_scrim := ColorRect.new()
		top_scrim.color = Color("06101a", .82)
		top_scrim.set_anchors_preset(Control.PRESET_TOP_WIDE)
		top_scrim.offset_bottom = 64
		top_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(top_scrim)
		var bottom_scrim := ColorRect.new()
		bottom_scrim.color = Color("06101a", .88)
		bottom_scrim.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		bottom_scrim.offset_top = -74
		bottom_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bottom_scrim)

		phase_label = Label.new()
		phase_label.position = Vector2(14, 12)
		phase_label.add_theme_font_size_override("font_size", 16)
		phase_label.add_theme_color_override("font_color", Color("edf6f4"))
		add_child(phase_label)
		allied_label = Label.new()
		allied_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		allied_label.position = Vector2(14, -60)
		allied_label.add_theme_font_size_override("font_size", 13)
		allied_label.add_theme_color_override("font_color", Color("f08d82"))
		add_child(allied_label)
		allied_bar = ProgressBar.new()
		allied_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		allied_bar.position = Vector2(14, -32)
		allied_bar.size = Vector2(132, 6)
		allied_bar.max_value = 100
		allied_bar.show_percentage = false
		_style_bar(allied_bar, Color("d85e55"))
		add_child(allied_bar)
		wei_label = Label.new()
		wei_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		wei_label.position = Vector2(-146, -60)
		wei_label.add_theme_font_size_override("font_size", 13)
		wei_label.add_theme_color_override("font_color", Color("80d4ff"))
		add_child(wei_label)
		wei_bar = ProgressBar.new()
		wei_bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		wei_bar.position = Vector2(-146, -32)
		wei_bar.size = Vector2(132, 6)
		wei_bar.max_value = 100
		wei_bar.show_percentage = false
		_style_bar(wei_bar, Color("4db9ef"))
		add_child(wei_bar)

	func set_battle(p: int, phase_name: String, a: int, d: int, am: int, dm: int) -> void:
		if phase_label == null:
			return
		phase_label.text = "전장 기록 이미지\nPHASE %d · %s" % [p, phase_name]
		allied_label.text = "연합군  %d척 · 사기 %d" % [d, dm]
		allied_bar.value = clamp(dm, 0, 100)
		wei_label.text = "위군  %d척 · 사기 %d" % [a, am]
		wei_bar.value = clamp(am, 0, 100)

	func _style_bar(bar: ProgressBar, tint: Color) -> void:
		var background := StyleBoxFlat.new()
		background.bg_color = Color("142633")
		var fill := StyleBoxFlat.new()
		fill.bg_color = tint
		bar.add_theme_stylebox_override("background", background)
		bar.add_theme_stylebox_override("fill", fill)


class Evidence3D extends SubViewportContainer:
	## Legacy node identity/one-viewport contract, now backed by a genuine 3D scene.
	var phase := -1
	var clock := 0.0
	var world: Node3D
	var camera: Camera3D
	var live_label: Label
	var allied_label: Label
	var wei_label: Label
	var allied_bar: ProgressBar
	var wei_bar: ProgressBar
	var phase_name := "대기"
	var wei_ships := -1
	var allied_ships := -1
	var wei_morale := 0
	var allied_morale := 0
	var ships: Array[Node3D] = []
	var beams: Array[MeshInstance3D] = []
	func _ready() -> void:
		custom_minimum_size = Vector2(320,400); stretch = true
		var view := SubViewport.new(); view.size = Vector2i(640,500); view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; view.msaa_3d = Viewport.MSAA_4X; add_child(view)
		world = Node3D.new(); view.add_child(world)
		var environment := Environment.new(); environment.background_mode = Environment.BG_COLOR; environment.background_color = Color("020711"); environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.ambient_light_color = Color("27465b"); environment.ambient_light_energy = 0.65; environment.glow_enabled = true; environment.glow_intensity = 1.15
		var world_env := WorldEnvironment.new(); world_env.environment = environment; world.add_child(world_env)
		var key := DirectionalLight3D.new(); key.light_color = Color("a8d8ff"); key.light_energy = 1.45; key.rotation_degrees = Vector3(-32,-25,0); world.add_child(key)
		var fire := OmniLight3D.new(); fire.light_color = Color("ff6338"); fire.light_energy = 5.5; fire.omni_range = 14; fire.position = Vector3(-1.5,1.0,-2.0); world.add_child(fire)
		camera = Camera3D.new(); camera.fov = 48.0; world.add_child(camera)
		_backdrop()
		for i in 90: _star(i)
		var overlay := CanvasLayer.new(); view.add_child(overlay)
		var top_scrim := ColorRect.new(); top_scrim.position = Vector2.ZERO; top_scrim.size = Vector2(640,64); top_scrim.color = Color("06101a",.78); overlay.add_child(top_scrim)
		var stat_scrim := ColorRect.new(); stat_scrim.position = Vector2(0,426); stat_scrim.size = Vector2(640,74); stat_scrim.color = Color("06101a",.88); overlay.add_child(stat_scrim)
		live_label = Label.new(); live_label.position = Vector2(14,12); live_label.add_theme_font_size_override("font_size",16); live_label.add_theme_color_override("font_color",Color("edf6f4")); overlay.add_child(live_label)
		allied_label = Label.new(); allied_label.position = Vector2(14,440); allied_label.add_theme_font_size_override("font_size",13); allied_label.add_theme_color_override("font_color",Color("f08d82")); overlay.add_child(allied_label)
		allied_bar = ProgressBar.new(); allied_bar.position = Vector2(14,462); allied_bar.size = Vector2(220,6); allied_bar.max_value = 100; allied_bar.show_percentage = false; _style_bar(allied_bar,Color("d85e55")); overlay.add_child(allied_bar)
		wei_label = Label.new(); wei_label.position = Vector2(382,440); wei_label.add_theme_font_size_override("font_size",13); wei_label.add_theme_color_override("font_color",Color("80d4ff")); overlay.add_child(wei_label)
		wei_bar = ProgressBar.new(); wei_bar.position = Vector2(382,462); wei_bar.size = Vector2(220,6); wei_bar.max_value = 100; wei_bar.show_percentage = false; _style_bar(wei_bar,Color("4db9ef")); overlay.add_child(wei_bar)
		_build(3); set_process(true)
	func set_battle(p:int,name:String,a:int,d:int,am:int,dm:int)->void:
		var changed := p != phase or a != wei_ships or d != allied_ships
		phase = p; phase_name = name; wei_ships = a; allied_ships = d; wei_morale = am; allied_morale = dm
		if changed: _build(p)
		if live_label != null:
			live_label.text = "● LIVE   실시간 전장 상황\nPHASE %d · %s" % [p,name]
			allied_label.text = "연합군  %d척   사기 %d" % [d,dm]; allied_bar.value = clamp(dm,0,100)
			wei_label.text = "위군  %d척   사기 %d" % [a,am]; wei_bar.value = clamp(am,0,100)
	func _process(delta:float)->void:
		clock += delta
		if camera != null: camera.look_at_from_position(Vector3(sin(clock*.16)*.55,1.35+sin(clock*.34)*.22,14.2),Vector3(0,0,-.8))
		for ship in ships:
			var base: Vector3 = ship.get_meta("base"); var lane: float = ship.get_meta("lane"); ship.position = base + Vector3(sin(clock*.75+lane)*.16,cos(clock*1.2+lane)*.055,sin(clock*.55+lane)*.09); ship.rotation.z = sin(clock*.8+lane)*.035
		for beam in beams: beam.scale.y = .55 + abs(sin(clock*5.0+float(beam.get_meta("seed"))))*.8
	func _build(p:int)->void:
		if world == null: return
		ships.clear(); beams.clear()
		for child in world.get_children():
			if child.name.begins_with("Combat"):
				# Detach immediately so a fleet reduced to zero cannot survive for one
				# rendered frame while queue_free waits for the frame boundary.
				world.remove_child(child)
				child.queue_free()
		var closure := float(max(p-1,0)) * .42
		_spawn_side(false, allied_ships, closure)
		_spawn_side(true, wei_ships, closure)
		if allied_ships > 0 and wei_ships > 0:
			for i in 2+p*3: _beam(i)
			for i in max(0,p-1): _explosion(i)
	func _spawn_side(is_wei:bool,count:int,closure:float)->void:
		# Visual abstraction is proportional, but zero canonical ships means zero 3D ships.
		if count <= 0: return
		var tint := Color("3d9fdb") if is_wei else Color("d34f47")
		var start := 20 if is_wei else 0
		var sign := 1.0 if is_wei else -1.0
		var capitals := 2 if count >= 16 else 1
		var escorts := clampi(ceili(float(count) / 6.0), 1, 8)
		for i in capitals:
			_ship(Vector3(sign*(3.9-closure)+sign*i*.56,(-.3 if i==0 else 1.0),-1.4-i*.9),tint,start+i,sign)
		for i in escorts:
			_ship(Vector3(sign*(3.35-closure)+sign*(i%4)*.58,(i%2)*.56-.8,-2.0+(i/4)*.72),tint,start+2+i,sign)
	func _ship(pos:Vector3,tint:Color,index:int,direction:float)->void:
		var capital := index == 0 or index == 1 or index == 20 or index == 21
		var scale := 1.45 if capital else .55
		var ship := Node3D.new(); ship.name="CombatShip"+str(index); ship.position=pos; ship.set_meta("base",pos); ship.set_meta("lane",float(index)*.67); ship.rotation_degrees=Vector3((index%3)*3,16*direction,0); world.add_child(ship); ships.append(ship)
		var hull_tint := Color("173d50") if tint.b > tint.r else Color("4a2426")
		var armor_tint := Color("245d77") if tint.b > tint.r else Color("742f31")
		_part(ship,Vector3(0,0,0),Vector3(2.55, .42, .72)*scale,hull_tint)
		_part(ship,Vector3(.10,.28,0),Vector3(1.32,.34,.42)*scale,armor_tint)
		_part(ship,Vector3(.45,.54,0),Vector3(.48,.25,.28)*scale,Color("426a7b"))
		_part(ship,Vector3(-.22,.62,0),Vector3(.38,.22,.22)*scale,Color("203c4a"))
		for side in [-1.0,1.0]:
			_part(ship,Vector3(-.05,.02,side*.56)*scale,Vector3(1.18,.10,.18)*scale,Color("203946"))
			_part(ship,Vector3(-.56,.12,side*.78)*scale,Vector3(.42,.12,.11)*scale,Color("365361"))
		var engine:=MeshInstance3D.new(); var engine_mesh:=SphereMesh.new(); engine_mesh.radius=.075*scale; engine_mesh.height=.15*scale; engine.mesh=engine_mesh; engine.position=Vector3(-1.36*scale,0,0); engine.material_override=_material(tint,1.8); ship.add_child(engine)
		var trail:=MeshInstance3D.new(); var trail_mesh:=CylinderMesh.new(); trail_mesh.top_radius=.022*scale; trail_mesh.bottom_radius=.055*scale; trail_mesh.height=.54*scale; trail.mesh=trail_mesh; trail.position=Vector3(-1.7*scale,0,0); trail.rotation_degrees=Vector3(0,0,90); trail.material_override=_material(Color(tint,.65),.75); ship.add_child(trail)
	func _part(parent:Node3D,position:Vector3,dimensions:Vector3,color:Color)->void:
		var piece:=MeshInstance3D.new(); var mesh:=BoxMesh.new(); mesh.size=dimensions; piece.mesh=mesh; piece.position=position; piece.material_override=_material(color,.04); parent.add_child(piece)
	func _beam(index:int)->void:
		var beam:=MeshInstance3D.new(); beam.name="CombatBeam"+str(index); var mesh:=CylinderMesh.new(); mesh.top_radius=.008; mesh.bottom_radius=.008; mesh.height=2.7+float(index%3)*.42; mesh.radial_segments=6; beam.mesh=mesh; beam.position=Vector3(-1.6+(index%4)*.9,-.35+(index%3)*.42,-.5+(index%2)*.8); beam.rotation_degrees=Vector3(0,90-(index%3)*7,78+(index%4)*5); beam.material_override=_material(Color("ff7545") if index%3 else Color("5cc8ff"),2.3); beam.set_meta("seed",index); world.add_child(beam); beams.append(beam)
	func _explosion(index:int)->void:
		var burst:=MeshInstance3D.new(); burst.name="CombatBurst"+str(index); var mesh:=SphereMesh.new(); mesh.radius=.055+index*.012; mesh.height=.11+index*.024; burst.mesh=mesh; burst.position=Vector3(-.8+(index%3)*.72,-.25+(index%2)*.45,-.45); burst.material_override=_material(Color("fff0ad"),4.4); world.add_child(burst)
		var halo:=MeshInstance3D.new(); halo.name="CombatHalo"+str(index); var halo_mesh:=SphereMesh.new(); halo_mesh.radius=.14+index*.025; halo_mesh.height=.28+index*.05; halo.mesh=halo_mesh; halo.position=burst.position; halo.material_override=_halo_material(Color("ff7141",.28)); world.add_child(halo)
	func _backdrop()->void:
		var plate:=MeshInstance3D.new(); plate.name="BackdropConceptPlate"; var mesh:=QuadMesh.new(); mesh.size=Vector2(36,28); plate.mesh=mesh; plate.position=Vector3(0,-1.2,-12); var material:=StandardMaterial3D.new(); material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; material.albedo_texture=load("res://assets/ui-mockups/red-cliffs-orbital-backdrop-v1.png"); material.albedo_color=Color(1,1,1,.42); material.cull_mode=BaseMaterial3D.CULL_DISABLED; plate.material_override=material; world.add_child(plate)
	func _star(index:int)->void:
		var star:=MeshInstance3D.new(); star.name="Star"+str(index); var mesh:=SphereMesh.new(); mesh.radius=.01; mesh.height=.02; star.mesh=mesh; star.position=Vector3(-11+fposmod(index*2.37,22),-6+fposmod(index*1.61,12),-9-fposmod(index*3.17,14)); star.material_override=_material(Color("b8d8ee"),1.0); world.add_child(star)
	func _material(color:Color,emission:float)->StandardMaterial3D:
		var material:=StandardMaterial3D.new(); material.albedo_color=color; material.metallic=.82; material.roughness=.28; material.emission_enabled=emission>0.0; material.emission=color; material.emission_energy_multiplier=emission; return material
	func _halo_material(color:Color)->StandardMaterial3D:
		var material:=_material(color,1.6); material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; return material
	func _style_bar(bar:ProgressBar,tint:Color)->void:
		var background:=StyleBoxFlat.new(); background.bg_color=Color("142633"); background.corner_radius_top_left=3; background.corner_radius_top_right=3; background.corner_radius_bottom_left=3; background.corner_radius_bottom_right=3
		var fill:=StyleBoxFlat.new(); fill.bg_color=tint; fill.corner_radius_top_left=3; fill.corner_radius_top_right=3; fill.corner_radius_bottom_left=3; fill.corner_radius_bottom_right=3
		bar.add_theme_stylebox_override("background",background); bar.add_theme_stylebox_override("fill",fill)
