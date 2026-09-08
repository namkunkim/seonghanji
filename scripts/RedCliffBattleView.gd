class_name RedCliffBattleView
extends Control

## Read-only presentation boundary: Campaign retains authority for all combat facts.
signal return_requested
var campaign = null
var battle_id := ""
var _state: Label
var _feedback: Label
var _map: TacticalMap
var _feed: Evidence3D
var _deck: CommandDeck
var _formation: OptionButton
var _buttons: Array[Button] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_once()
	set_process(true)

func configure(campaign_ref, canonical_battle_id: String) -> void:
	campaign = campaign_ref; battle_id = canonical_battle_id; _refresh()

func _process(_delta: float) -> void: _refresh()

func _build_once() -> void:
	if _state != null: return
	var bg := ColorRect.new(); bg.color = Color("050b12"); bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(bg)
	var margins := MarginContainer.new(); margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right"]: margins.add_theme_constant_override(side, 18)
	margins.add_theme_constant_override("margin_top", 13); margins.add_theme_constant_override("margin_bottom", 12); add_child(margins)
	var stack := VBoxContainer.new(); stack.add_theme_constant_override("separation", 8); margins.add_child(stack)
	var title_row := HBoxContainer.new(); title_row.custom_minimum_size = Vector2(0, 48); stack.add_child(title_row)
	var title := Label.new(); title.text = "적 벽 대 전"; title.add_theme_font_size_override("font_size", 31); title.add_theme_color_override("font_color", Color("e8d5a2")); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; title_row.add_child(title)
	var loc := Label.new(); loc.text = "구지 궤도 전역  ·  208년 10월 23일"; loc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; loc.add_theme_font_size_override("font_size", 15); loc.add_theme_color_override("font_color", Color("9fb0bc")); title_row.add_child(loc)
	_deck = CommandDeck.new(); _deck.custom_minimum_size = Vector2(0, 86); stack.add_child(_deck)
	_state = Label.new(); _state.visible = false; stack.add_child(_state)
	var split := HBoxContainer.new(); split.custom_minimum_size = Vector2(0, 480); split.size_flags_vertical = Control.SIZE_EXPAND_FILL; split.add_theme_constant_override("separation", 10); stack.add_child(split)
	_map = TacticalMap.new(); _map.name = "TacticalMapTwoThirds"; _map.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _map.size_flags_stretch_ratio = 2.0; split.add_child(_map)
	_feed = Evidence3D.new(); _feed.name = "Primitive3DEvidenceOneThird"; _feed.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _feed.size_flags_stretch_ratio = 1.0; split.add_child(_feed)
	var controls := HBoxContainer.new(); controls.custom_minimum_size = Vector2(0, 60); controls.add_theme_constant_override("separation", 8); stack.add_child(controls)
	controls.add_child(_button("진형 유지", "hold_formation"))
	_formation = OptionButton.new(); _formation.custom_minimum_size = Vector2(144, 46)
	for row in Formations.rows(): _formation.add_item(String(row.get("name", "")))
	controls.add_child(_formation); controls.add_child(_button("다음 진형 적용", "change_formation")); controls.add_child(_button("다음 페이즈  ›", "advance_phase")); controls.add_child(_button("AI에 위임", "delegate_ai"))
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; controls.add_child(spacer)
	var home := Button.new(); home.text = "홈으로"; home.custom_minimum_size = Vector2(92, 46); home.pressed.connect(func(): return_requested.emit()); controls.add_child(home)
	_feedback = Label.new(); _feedback.custom_minimum_size = Vector2(0, 18); _feedback.add_theme_font_size_override("font_size", 13); _feedback.add_theme_color_override("font_color", Color("e3bd70")); stack.add_child(_feedback)

func _button(label: String, action: String) -> Button:
	var b := Button.new(); b.text = label; b.custom_minimum_size = Vector2(126, 46); b.set_meta("action", action); b.pressed.connect(func(): _issue(String(b.get_meta("action")))); _buttons.append(b); return b

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
	_feedback.text = "명령 접수 · %s" % action if issued is Dictionary and not issued.is_empty() else "명령 거부 · 현재 조건 또는 중복 입력을 확인하세요."

func _refresh() -> void:
	if _state == null: return
	var battle = _battle()
	if battle == null: _state.text = "정본 전투를 찾을 수 없습니다."; return
	var phase := int(battle.combat_phase)
	var phase_name := Battle.PHASE_NAMES[phase - 1] if phase >= 1 and phase <= Battle.PHASE_NAMES.size() else "대기"
	var a := int(battle.attacker_ships); var d := int(battle.defender_ships); var am := int(battle.attacker_morale); var dm := int(battle.defender_morale)
	_state.text = "%d / 5 페이즈 %s · 조조측 %d척 / %d · 연합 %d척 / %d" % [phase, phase_name, a, am, d, dm]
	if String(battle.status) == ActiveBattle.STATUS_RESOLVED:
		var winner := String(battle.result.get("winner_faction_id", ""))
		_state.text = "전투 결과 · 승자: %s · " % ("손권·유비 연합" if winner == "sun_liu_side" else "조조측") + _state.text
	_deck.set_battle(phase, phase_name, a, d, am, dm); _map.set_battle(phase, phase_name, a, d, am, dm); _feed.set_battle(phase, phase_name, a, d, am, dm)
	var active := String(battle.status) == ActiveBattle.STATUS_ACTIVE
	for b in _buttons: b.disabled = not active
	if not active: _feedback.text = "전투 종료 · 이후 명령은 코어가 거부합니다."

class CommandDeck extends Control:
	var phase := 0; var phase_name := "대기"; var a := 0; var d := 0; var am := 0; var dm := 0
	func set_battle(p: int, n: String, aa: int, dd: int, aam: int, ddm: int) -> void: phase=p; phase_name=n; a=aa; d=dd; am=aam; dm=ddm; queue_redraw()
	func _draw() -> void:
		var font := get_theme_default_font(); draw_rect(Rect2(Vector2.ZERO,size),Color("09131d")); draw_rect(Rect2(Vector2.ZERO,size),Color("344958"),false,1)
		_force(Rect2(8,8,size.x*.23,67),"오 · 유 연합군","합선 %d척" % d,dm,Color("c75a52"),false)
		_force(Rect2(size.x*.70,8,size.x*.29-8,67),"위군","함선 %d척" % a,am,Color("4f9fce"),true)
		var words := ["접적","포화","교전","강습","결착"]; var start:=size.x*.30; var width:=size.x*.38; draw_line(Vector2(start,20),Vector2(start+width,20),Color("64727a"),2)
		for i in 5:
			var x:=start+width*i/4.0; var live:=i+1==phase; draw_circle(Vector2(x,20),14 if live else 11,Color("b58b3b") if live else Color("172633")); draw_arc(Vector2(x,20),14 if live else 11,0,TAU,20,Color("f2d37e") if live else Color("8d9ba4"),1.2); draw_string(font,Vector2(x-4,25),str(i+1),HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("fff4d5")); draw_string(font,Vector2(x-18,51),words[i],HORIZONTAL_ALIGNMENT_CENTER,36,13,Color("f3d27c") if live else Color("aebbc3"))
	func _force(box: Rect2, name: String, ships: String, morale: int, tint: Color, right: bool) -> void:
		var font:=get_theme_default_font(); var align:=HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT; draw_rect(box,Color("0b1924")); draw_rect(box,tint.darkened(.35),false,1); draw_string(font,box.position+Vector2(12,24),name,align,box.size.x-24,17,Color("e8eef0")); draw_string(font,box.position+Vector2(12,44),ships,align,box.size.x-24,13,Color("9fb1bb")); var bar:=Rect2(box.position+Vector2(12,53),Vector2(box.size.x-24,6)); draw_rect(bar,Color("111e29")); draw_rect(Rect2(bar.position,Vector2(bar.size.x*clamp(morale,0,100)/100.0,6)),tint)

class TacticalMap extends Control:
	var phase:=0; var phase_name:="대기"; var a:=0; var d:=0; var am:=0; var dm:=0
	func _ready() -> void: custom_minimum_size=Vector2(650,400); queue_redraw()
	func set_battle(p:int,n:String,aa:int,dd:int,aam:int,ddm:int)->void: phase=p;phase_name=n;a=aa;d=dd;am=aam;dm=ddm;queue_redraw()
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
		_route_curve(Vector2(size.x*.18,size.y*.37),Vector2(size.x*.39,size.y*.30),hub,Color("e66b5f"),true)
		_route_curve(Vector2(size.x*.21,size.y*.72),Vector2(size.x*.36,size.y*.70),hub,Color("e66b5f"),true)
		_route_curve(Vector2(size.x*.82,size.y*.31),Vector2(size.x*.70,size.y*.31),hub,Color("63bef1"),false)
		_route_curve(Vector2(size.x*.78,size.y*.70),Vector2(size.x*.67,size.y*.69),hub,Color("63bef1"),false)
		_fleet_wedge(Vector2(size.x*.22,size.y*.39),Color("eb685c"),"우비 돌격단",12,0.0,true)
		_fleet_wedge(Vector2(size.x*.23,size.y*.70),Color("d94f50"),"손권 주력",9,-.28,true)
		_fleet_wedge(Vector2(size.x*.79,size.y*.34),Color("6bcafa"),"위군 본대",13,PI,true)
		_fleet_wedge(Vector2(size.x*.76,size.y*.69),Color("53aee1"),"장료 기동대",10,2.72,true)
		_card(Rect2(14,54,160,54),"연합 전력", "%d척  ·  사기 %d" % [d,dm],Color("df6158"))
		_card(Rect2(size.x-174,54,160,54),"위군 전력", "%d척  ·  사기 %d" % [a,am],Color("62bdf1"))
		draw_rect(Rect2(0,size.y-30,size.x,30),Color("07111a",.94)); draw_string(font,Vector2(14,size.y-10),"◆ 주요 합선   ─ ─ 이동 경로   ◌ 교전 구역   △ 함대 전열",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("a7bac4"))
	func _station(pos:Vector2)->void:
		var font:=get_theme_default_font(); draw_circle(pos,11,Color("f2d280",.85)); draw_circle(pos,6,Color("09131d"));
		for angle in [0.0,PI*.5,PI,PI*1.5]: draw_line(pos+Vector2(12,0).rotated(angle),pos+Vector2(23,0).rotated(angle),Color("d9b464"),3)
		draw_string(font,pos+Vector2(-56,80),"구지 거점\n점령 목표",HORIZONTAL_ALIGNMENT_CENTER,112,13,Color("f3e2b7"))
	func _route_curve(from:Vector2,control:Vector2,to:Vector2,color:Color,_red:bool)->void:
		var points:=PackedVector2Array(); for i in 17: var t:=float(i)/16.0; points.append(from.lerp(control,t).lerp(control.lerp(to,t),t))
		for i in points.size()-1: draw_dashed_line(points[i],points[i+1],color,1.8,7.0)
		var tip:=points[points.size()-1]; var direction:=(tip-points[points.size()-2]).normalized(); var side:=Vector2(-direction.y,direction.x); draw_colored_polygon(PackedVector2Array([tip,tip-direction*10+side*5,tip-direction*10-side*5]),color)
	func _fleet_wedge(pos:Vector2,color:Color,label:String,count:int,angle:float,_active:bool)->void:
		var font:=get_theme_default_font(); draw_circle(pos,33,Color(color,.055)); draw_arc(pos,33,0,TAU,32,Color(color,.55),1)
		for i in count:
			var row:=int(sqrt(float(i))); var within:=i-row*row; var off:=Vector2(13.0+row*11.0,(within-row*.5)*12.0).rotated(angle)
			var tip:=pos+off; var forward:=Vector2(6,0).rotated(angle); var side:=Vector2(0,4).rotated(angle)
			draw_colored_polygon(PackedVector2Array([tip+forward,tip-forward*.65+side,tip-forward*.65-side]),color)
		draw_circle(pos,4,Color("f4e3ba")); draw_string(font,pos+Vector2(-57,-43),label,HORIZONTAL_ALIGNMENT_CENTER,114,13,Color("edf4f5"))
	func _card(rect:Rect2,title:String,value:String,tint:Color)->void:
		var font:=get_theme_default_font(); draw_rect(rect,Color("08151f",.93)); draw_rect(rect,tint.darkened(.28),false,1); draw_rect(Rect2(rect.position,Vector2(3,rect.size.y)),tint); draw_string(font,rect.position+Vector2(12,20),title,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("aebfc8")); draw_string(font,rect.position+Vector2(12,41),value,HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("eff6f7"))

class Evidence3D extends SubViewportContainer:
	## Keeps the legacy node identity and one-viewport contract while presenting authored combat art.
	var phase := 0
	var canvas: CinematicBattleCanvas
	func _ready() -> void:
		custom_minimum_size = Vector2(320,400)
		stretch = true
		# Keep the render surface below the panel's minimum height. A 700px child
		# forced the whole VBox past 900px and clipped the command deck.
		var view := SubViewport.new(); view.size = Vector2i(512,400); view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(view)
		canvas = CinematicBattleCanvas.new(); canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); view.add_child(canvas)
	func set_battle(p:int,name:String,a:int,d:int,am:int,dm:int)->void:
		phase=p
		if canvas != null: canvas.set_battle(p,name,a,d,am,dm)

class CinematicBattleCanvas extends Control:
	var phase:=0; var phase_name:="접적"; var wei:=0; var allied:=0; var wei_morale:=0; var allied_morale:=0; var time:=0.0
	var artwork:Texture2D = preload("res://assets/ui-mockups/red-cliffs-live-battle-v1.png")
	func _ready()->void: set_process(true); queue_redraw()
	func set_battle(p:int,n:String,a:int,d:int,am:int,dm:int)->void: phase=p;phase_name=n;wei=a;allied=d;wei_morale=am;allied_morale=dm;queue_redraw()
	func _process(delta:float)->void: time+=delta; queue_redraw()
	func _draw()->void:
		var font:=get_theme_default_font(); var full:=Rect2(Vector2.ZERO,size)
		# Authored battle plate is cropped like a live tactical camera, never stretched into a UI texture.
		var source := Rect2(Vector2.ZERO,artwork.get_size())
		var target_ratio: float = size.x / max(size.y, 1.0); var source_ratio: float = source.size.x / source.size.y
		if source_ratio > target_ratio:
			var crop_width: float = source.size.y * target_ratio; source.position.x += (source.size.x-crop_width)*.5; source.size.x = crop_width
		else:
			var crop_height: float = source.size.x / target_ratio; source.position.y += (source.size.y-crop_height)*.5; source.size.y = crop_height
		draw_texture_rect_region(artwork,full,source,Color.WHITE)
		draw_rect(full,Color("06101a",.14))
		draw_rect(Rect2(0,0,size.x,45),Color("07121c",.88)); draw_line(Vector2(0,45),Vector2(size.x,45),Color("79a4b5",.62),1)
		draw_circle(Vector2(21,22),4+sin(time*4.0)*1.2,Color("ff6545")); draw_string(font,Vector2(33,28),"LIVE  ·  실시간 전장 상황",HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("f0f6f5"))
		draw_string(font,Vector2(size.x-155,28),"구지 궤도 · 교전 영상",HORIZONTAL_ALIGNMENT_RIGHT,140,12,Color("a9c2cc"))
		# Signal tags sit on the image instead of covering its cinematic center.
		_tag(Rect2(14,size.y*.16,128,35),"위군 기함",Color("61c5fb"),false)
		_tag(Rect2(size.x-145,size.y*.40,132,35),"연합 화공대",Color("f06a55"),true)
		var ticker:=Rect2(0,size.y-94,size.x,35); draw_rect(ticker,Color("06121c",.9)); draw_line(ticker.position, ticker.position+Vector2(size.x,0),Color("537686",.7),1)
		draw_string(font,ticker.position+Vector2(13,23),"전황 보고  ·  %s / 연합군이 위군 전열에 압박을 가하고 있습니다." % phase_name,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("d7e3e5"))
		var stats:=Rect2(0,size.y-59,size.x,59); draw_rect(stats,Color("08141e",.96)); draw_line(stats.position,stats.position+Vector2(size.x,0),Color("678795",.65),1)
		_stat(Vector2(14,size.y-37),"연합",allied,allied_morale,Color("e46a5e")); _stat(Vector2(size.x*.52,size.y-37),"위군",wei,wei_morale,Color("65c7fa"))
	func _tag(rect:Rect2,text:String,tint:Color,right:bool)->void:
		var font:=get_theme_default_font(); draw_rect(rect,Color("07131d",.86)); draw_rect(rect,tint.darkened(.28),false,1); draw_rect(Rect2(rect.position,Vector2(3,rect.size.y)),tint); draw_string(font,rect.position+Vector2(10,23),text,HORIZONTAL_ALIGNMENT_LEFT,rect.size.x-16,13,Color("edf5f5")); var anchor:=Vector2(rect.end.x if right else rect.position.x,rect.get_center().y); draw_line(anchor,anchor+Vector2(-22 if right else 22,18),tint,1)
	func _stat(pos:Vector2,title:String,ships:int,morale:int,tint:Color)->void:
		var font:=get_theme_default_font(); draw_string(font,pos,title+"  %d척" % ships,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("eaf2f4")); draw_string(font,pos+Vector2(93,0),"사기 %d" % morale,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("a9c0c9")); draw_rect(Rect2(pos+Vector2(0,9),Vector2(170,5)),Color("142633")); draw_rect(Rect2(pos+Vector2(0,9),Vector2(170*clamp(morale,0,100)/100.0,5)),tint)
