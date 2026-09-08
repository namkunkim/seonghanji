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
		var font:=get_theme_default_font(); var c:=Vector2(size.x*.55,size.y*.54); draw_rect(Rect2(Vector2.ZERO,size),Color("08131e")); draw_rect(Rect2(Vector2.ZERO,size),Color("415968"),false,1.5)
		for i in 55: draw_circle(Vector2(fposmod(i*73.0,size.x-20)+10,fposmod(i*41.0,size.y-46)+42),.6+float(i%3)*.25,Color("6a8797",.55))
		for radius in [70.0,135.0,205.0,285.0]: draw_arc(c,radius,0,TAU,96,Color("315064",.48),1)
		for x in range(0,int(size.x),55): draw_line(Vector2(x,42),Vector2(x,size.y),Color("1e3544",.35),.6)
		for y in range(42,int(size.y),55): draw_line(Vector2(0,y),Vector2(size.x,y),Color("1e3544",.35),.6)
		draw_circle(Vector2(-45,size.y*.46),size.y*.67,Color("0e2433")); draw_arc(Vector2(-45,size.y*.46),size.y*.67,-1.1,1.1,64,Color("52839d",.8),2)
		draw_rect(Rect2(0,0,size.x,40),Color("0b1924",.94)); draw_line(Vector2(0,40),Vector2(size.x,40),Color("3d596a")); draw_string(font,Vector2(16,26),"전술 지휘도",HORIZONTAL_ALIGNMENT_LEFT,-1,19,Color("ebf3f4")); draw_string(font,Vector2(size.x-155,26),"PHASE %d · %s" % [phase,phase_name],HORIZONTAL_ALIGNMENT_RIGHT,140,13,Color("e6c271"))
		_route(PackedVector2Array([Vector2(size.x*.18,size.y*.37),Vector2(size.x*.34,size.y*.40),c]),Color("dc5b52")); _route(PackedVector2Array([Vector2(size.x*.83,size.y*.34),Vector2(size.x*.71,size.y*.40),c]),Color("55baf0")); _route(PackedVector2Array([Vector2(size.x*.79,size.y*.72),Vector2(size.x*.67,size.y*.66),c]),Color("55baf0"))
		draw_circle(c,23,Color("d5ad57",.14)); draw_arc(c,23,0,TAU,24,Color("f3d380"),1.4); draw_circle(c,7,Color("f3d380")); draw_string(font,c+Vector2(-48,45),"구지 궤도 거점",HORIZONTAL_ALIGNMENT_CENTER,96,14,Color("f4ead2"))
		_fleet(Vector2(size.x*.25,size.y*.42),Color("e75f55"),12,"우비군",phase%2); _fleet(Vector2(size.x*.23,size.y*.69),Color("e75f55"),9,"손권 본대",1); _fleet(Vector2(size.x*.76,size.y*.36),Color("67c4fa"),13,"위군 본대",2); _fleet(Vector2(size.x*.73,size.y*.68),Color("67c4fa"),10,"장료 기동대",3)
		draw_string(font,Vector2(18,size.y-17),"적군(오·유)  %d척 · 사기 %d" % [d,dm],HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("ee9389")); draw_string(font,Vector2(size.x-258,size.y-17),"위군  %d척 · 사기 %d" % [a,am],HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("88d4fb"))
	func _route(points:PackedVector2Array,color:Color)->void:
		for i in points.size()-1: draw_dashed_line(points[i],points[i+1],color,1.8,7); var tip:=points[points.size()-1]; var dir:=(tip-points[points.size()-2]).normalized(); var side:=Vector2(-dir.y,dir.x); draw_colored_polygon(PackedVector2Array([tip,tip-dir*10+side*5,tip-dir*10-side*5]),color)
	func _fleet(pos:Vector2,color:Color,count:int,label:String,style:int)->void:
		for i in count: var col:=i%4; var row:=i/4; var off:=Vector2((col-1.5)*13+row*4,(row-1)*13+(col%2)*3); if style==1: off=Vector2((col-1.5)*16,(row-1)*10+abs(col-1.5)*7); draw_colored_polygon(PackedVector2Array([pos+off+Vector2(7,0),pos+off+Vector2(-5,-4),pos+off+Vector2(-3,4)]),color)
		draw_circle(pos,10,Color(color,.12)); draw_arc(pos,10,0,TAU,16,color,1); draw_string(get_theme_default_font(),pos+Vector2(-48,-26),label,HORIZONTAL_ALIGNMENT_CENTER,96,13,Color("e8f2f6"))

class Evidence3D extends SubViewportContainer:
	var world:Node3D; var camera:Camera3D; var phase:=-1; var clock:=0.0; var label:Label
	func _ready()->void:
		custom_minimum_size=Vector2(320,400); var view:=SubViewport.new();view.size=Vector2i(640,620);view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view);world=Node3D.new();view.add_child(world)
		var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("030811");env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("29465b");env.ambient_light_energy=.7;var we:=WorldEnvironment.new();we.environment=env;world.add_child(we)
		var key:=DirectionalLight3D.new();key.light_color=Color("a9d8ff");key.light_energy=1.2;key.rotation_degrees=Vector3(-35,-30,0);world.add_child(key);var fire:=OmniLight3D.new();fire.light_color=Color("ff6a32");fire.light_energy=4.2;fire.omni_range=12;fire.position=Vector3(-1,1,-1);world.add_child(fire);camera=Camera3D.new();world.add_child(camera)
		for i in 70: _star(i)
		_build(3);var overlay:=CanvasLayer.new();view.add_child(overlay);label=Label.new();label.mouse_filter=Control.MOUSE_FILTER_IGNORE;label.position=Vector2(12,10);label.add_theme_font_size_override("font_size",15);label.add_theme_color_override("font_color",Color("e7f1f3"));overlay.add_child(label);set_process(true)
	func set_battle(p:int,name:String,a:int,d:int,_am:int,_dm:int)->void:
		if p!=phase:phase=p;_build(p)
		if label!=null:label.text="● LIVE   실시간 전장 상황\n%s  ·  위 %d / 연합 %d" % [name,a,d]
	func _process(delta:float)->void: clock+=delta;if camera!=null:camera.look_at_from_position(Vector3(sin(clock*.17)*2.4,3.0+sin(clock*.31)*.45,12.5-max(phase,1)*.45),Vector3.ZERO)
	func _build(p:int)->void:
		if world==null:return
		for child in world.get_children():if child.name.begins_with("Combat"):child.queue_free()
		for i in 9:_ship(Vector3(-4.5+(i%3)*1.15,(i%2)*.42-.3,-2.5+(i/3)*1.2),Color("d65348"),i,"CombatRed")
		for i in 10:_ship(Vector3(2.0+(i%3)*1.1,(i%2)*.4-.25,-2.0+(i/3)*1.15),Color("3d9ed9"),i+4,"CombatBlue")
		for i in 12+p*3:_beam(i)
		for i in 4+p:_debris(i)
	func _ship(pos:Vector3,color:Color,index:int,prefix:String)->void:
		var n:=Node3D.new();n.name=prefix+str(index);n.position=pos;n.rotation_degrees=Vector3((index%3)*6,22 if color.r>color.b else -22,0);world.add_child(n);var hull:=MeshInstance3D.new();var hm:=CylinderMesh.new();hm.top_radius=.16;hm.bottom_radius=.42;hm.height=1.8;hm.radial_segments=8;hull.mesh=hm;hull.rotation_degrees=Vector3(0,0,90);hull.material_override=_mat(Color("152633"),.65);n.add_child(hull);var engine:=MeshInstance3D.new();var em:=SphereMesh.new();em.radius=.22;em.height=.42;engine.mesh=em;engine.position=Vector3(-.92,0,0);engine.material_override=_mat(color,1.8);n.add_child(engine)
		for side in [-1.0,1.0]:var wing:=MeshInstance3D.new();var wm:=CylinderMesh.new();wm.top_radius=.045;wm.bottom_radius=.12;wm.height=1.05;wm.radial_segments=4;wing.mesh=wm;wing.position=Vector3(0,.05,side*.38);wing.rotation_degrees=Vector3(0,0,90);wing.material_override=_mat(Color("263d4b"),.35);n.add_child(wing)
	func _beam(i:int)->void:var b:=MeshInstance3D.new();b.name="CombatTrace"+str(i);var m:=CylinderMesh.new();m.top_radius=.018;m.bottom_radius=.018;m.height=2.0+float(i%3);m.radial_segments=6;b.mesh=m;b.position=Vector3(-3.5+(i%5)*1.5,-.5+(i%4)*.55,-1+(i%3));b.rotation_degrees=Vector3(0,90-(i%3)*9,55+(i%4)*8);b.material_override=_mat(Color("ff7545") if i%3 else Color("5cc8ff"),3);world.add_child(b)
	func _debris(i:int)->void:var rock:=MeshInstance3D.new();rock.name="CombatDebris"+str(i);var m:=SphereMesh.new();m.radius=.08+i*.018;m.height=.16+i*.036;rock.mesh=m;rock.position=Vector3(-2+(i%4)*1.2,-1.5+(i%3)*.8,-1+(i%2)*2);rock.material_override=_mat(Color("35414a"),0);world.add_child(rock)
	func _star(i:int)->void:var star:=MeshInstance3D.new();star.name="Star"+str(i);var m:=SphereMesh.new();m.radius=.012;m.height=.024;star.mesh=m;star.position=Vector3(-10+fposmod(i*2.37,20),-5+fposmod(i*1.61,10),-8-fposmod(i*3.17,12));star.material_override=_mat(Color("b8d8ee"),1);world.add_child(star)
	func _mat(c:Color,e:float)->StandardMaterial3D:var m:=StandardMaterial3D.new();m.albedo_color=c;m.metallic=.8;m.roughness=.32;m.emission_enabled=e>0;m.emission=c;m.emission_energy_multiplier=e;return m
