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
	func fleet_icon_counts()->Vector2i: return Vector2i(mini(d,20),mini(a,20))
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
			_route_curve(Vector2(size.x*.18,size.y*.37),Vector2(size.x*.39,size.y*.30),hub,Color("e66b5f"),true)
			_fleet_wedge(Vector2(size.x*.22,size.y*.39),Color("eb685c"),"우비 돌격단",allied_first,0.0,true)
			if allied_second > 0:
				_route_curve(Vector2(size.x*.21,size.y*.72),Vector2(size.x*.36,size.y*.70),hub,Color("e66b5f"),true)
				_fleet_wedge(Vector2(size.x*.23,size.y*.70),Color("d94f50"),"손권 주력",allied_second,-.28,true)
		if a > 0:
			var wei_icons := fleet_icon_counts().y; var wei_first := ceili(float(wei_icons)*.55); var wei_second := wei_icons-wei_first
			_route_curve(Vector2(size.x*.82,size.y*.31),Vector2(size.x*.70,size.y*.31),hub,Color("63bef1"),false)
			_fleet_wedge(Vector2(size.x*.79,size.y*.34),Color("6bcafa"),"위군 본대",wei_first,PI,true)
			if wei_second > 0:
				_route_curve(Vector2(size.x*.78,size.y*.70),Vector2(size.x*.67,size.y*.69),hub,Color("63bef1"),false)
				_fleet_wedge(Vector2(size.x*.76,size.y*.69),Color("53aee1"),"장료 기동대",wei_second,2.72,true)
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
