class_name GalaxyMapView
extends Control

signal system_selected(system_id: String)
signal tactical_requested
const MAP_BACKGROUND: Texture2D = preload("res://assets/ui-mockups/seonghanji-galaxy-map-background.png")
const POS := {"SYS-10":Vector2(.10,.31),"SYS-11":Vector2(.18,.66),"SYS-19":Vector2(.24,.82),"SYS-12":Vector2(.32,.51),"SYS-09":Vector2(.34,.35),"SYS-08":Vector2(.49,.22),"SYS-01":Vector2(.50,.39),"SYS-13":Vector2(.50,.63),"SYS-14":Vector2(.43,.52),"SYS-06":Vector2(.62,.31),"SYS-07":Vector2(.70,.14),"SYS-18":Vector2(.82,.10),"SYS-03":Vector2(.66,.42),"SYS-02":Vector2(.62,.53),"SYS-16":Vector2(.70,.61),"SYS-04":Vector2(.79,.37),"SYS-05":Vector2(.80,.51),"SYS-15":Vector2(.79,.69),"SYS-17":Vector2(.61,.83)}
const TERRAIN := {"SYS-10":"서량 별들판","SYS-11":"성운림 분지","SYS-19":"암흑 성운림","SYS-12":"진령 먼지협곡","SYS-09":"관중 성운고원","SYS-08":"태행 성간산맥","SYS-01":"황하 항성류","SYS-13":"장강 항성류","SYS-14":"한수 항성류","SYS-06":"화북 별들판","SYS-07":"북방 성계고원","SYS-18":"노룡 이온협곡","SYS-03":"황하 범람성운","SYS-02":"중원 별들판","SYS-16":"회수 항성류","SYS-04":"해안 성운평야","SYS-05":"회수 성운평야","SYS-15":"강동 항성류","SYS-17":"남방 성운림"}
var data: GameData
var selected := ""
var _terrain_rng := RandomNumberGenerator.new()
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
func setup(d: GameData, c: Campaign) -> void:
	data = d
	selected = c.factions[c.world.player_faction].capital_system
	queue_redraw()
func p(sid:String) -> Vector2:
	var q:Vector2 = POS[sid]
	return Vector2(q.x * size.x, q.y * size.y)
func _draw() -> void:
	if data == null: return
	draw_texture_rect(MAP_BACKGROUND, Rect2(Vector2.ZERO, size), false)
	_draw_galactic_geography()

	var font:=get_theme_default_font()
	draw_string(font,Vector2(size.x*.5-140,42),"성한지 · 은하 성계도",HORIZONTAL_ALIGNMENT_CENTER,280,27,Color("f4d681"))
	draw_string(font,Vector2(size.x*.5-190,66),"건안 십삼년 · 성간 항로 작전도",HORIZONTAL_ALIGNMENT_CENTER,380,12,Color("b4c6d7"))
	for rt in data.routes:
		var cs:Array=rt["connects"]
		if cs.size()!=2 or not POS.has(String(cs[0])) or not POS.has(String(cs[1])): continue
		_draw_route(p(String(cs[0])), p(String(cs[1])), String(rt["kind"]), rt.get("corridor") != null)
	for sid in POS:
		if not data.systems.has(sid): continue
		var at:=p(sid);var sys:Dictionary=data.systems[sid];var major:=String(sys["grade"])=="특급";var rr:=27.5 if major else 17.5;var c:=Color("72d8f0") if sid==selected else Color("eac969")
		draw_circle(at,rr+32,Color(c.r,c.g,c.b,.055));draw_circle(at,rr+18,Color(c.r,c.g,c.b,.10));draw_circle(at,rr,Color("07101b"));draw_arc(at,rr,0,TAU,48,c,3.8,true);draw_circle(at,7.5,Color("fff0bb"))
		if sid==selected: draw_arc(at,rr+18,0,TAU,48,Color("fff0a0"),2.7,true)
		draw_string(font,at+Vector2(-135,-rr-17),String(sys["name"]),HORIZONTAL_ALIGNMENT_CENTER,270,37 if major else 32,Color("fff4d8"))
		draw_string(font,at+Vector2(-82,rr+24),String(TERRAIN.get(sid,"성간 평야")),HORIZONTAL_ALIGNMENT_CENTER,164,11,Color("b3cfdb"))
	draw_string(font,Vector2(size.x*.10,size.y*.14),"청운 세력권",HORIZONTAL_ALIGNMENT_LEFT,160,15,Color("75d9f0"));draw_string(font,Vector2(size.x*.79,size.y*.18),"적대 세력권",HORIZONTAL_ALIGNMENT_LEFT,160,15,Color("f28b96"))
	var demo_fleet:=p("SYS-13").lerp(p("SYS-15"),.52)
	draw_circle(demo_fleet,20,Color("071a29",.94));draw_arc(demo_fleet,20,0,TAU,24,Color("8deaff"),2,true);draw_string(font,demo_fleet+Vector2(-12,7),"▲",HORIZONTAL_ALIGNMENT_CENTER,24,19,Color("eaffff"));draw_string(font,demo_fleet+Vector2(26,5),"제8 전대",HORIZONTAL_ALIGNMENT_LEFT,90,12,Color("d5f4ff"))
	_draw_hud(font)

func _draw_galactic_geography() -> void:
	# v10 — the map reads as sculpted geography before it reads as colored territory.
	_terrain_rng.seed = 2280312
	_draw_blob_field(Vector2(size.x * .56, size.y * .28), Vector2(size.x * .42, size.y * .20), Color("174d72", .17), 38, .72, .42)
	_draw_blob_field(Vector2(size.x * .20, size.y * .68), Vector2(size.x * .20, size.y * .18), Color("0b6b4c", .22), 29, .78, .58)
	_draw_blob_field(Vector2(size.x * .79, size.y * .66), Vector2(size.x * .22, size.y * .18), Color("70232b", .20), 27, .76, .56)
	_draw_basin(Vector2(size.x * .20, size.y * .69), Vector2(size.x * .17, size.y * .14), Color("071c18", .42), Color("29b77d", .12))
	_draw_qinling_chain()
	_draw_strategic_valley()
	_draw_wu_delta()

func _draw_blob_field(center: Vector2, radius: Vector2, tint: Color, count: int, stretch_x: float, stretch_y: float) -> void:
	for i in count:
		var angle := _terrain_rng.randf_range(0.0, TAU)
		var distance := sqrt(_terrain_rng.randf())
		var point := center + Vector2(cos(angle) * radius.x * distance, sin(angle) * radius.y * distance)
		var blob_radius := _terrain_rng.randf_range(size.x * .018, size.x * .066)
		var color := Color(tint.r, tint.g, tint.b, tint.a * _terrain_rng.randf_range(.35, 1.0))
		draw_colored_polygon(_terrain_blob(point, blob_radius, stretch_x, stretch_y), color)

func _draw_basin(center: Vector2, radius: Vector2, shadow: Color, glow: Color) -> void:
	for ring in range(7, 0, -1):
		var scale := float(ring) / 7.0
		draw_ellipse(center, radius * scale, Color(shadow.r, shadow.g, shadow.b, shadow.a * (.22 + scale * .10)))
	_draw_blob_field(center, radius * .82, glow, 18, .70, .48)

func _draw_qinling_chain() -> void:
	# Heavy western mass → narrow Hanzhong pass → fragmented eastern ridges.
	var west := PackedVector2Array([p("SYS-09"), p("SYS-12") + Vector2(-26, -6)])
	var east := PackedVector2Array([p("SYS-12") + Vector2(31, 12), p("SYS-14") + Vector2(0, -16), p("SYS-13") + Vector2(13, -42)])
	_draw_ridge(west, 82.0, Color("160f29", .74), Color("9a75d2", .19), 44)
	_draw_ridge(east, 48.0, Color("171126", .61), Color("8066bd", .16), 27)
	var pass := p("SYS-12")
	draw_circle(pass, 39.0, Color("050a12", .58))
	draw_arc(pass, 39.0, -.65, .72, 18, Color("d8b070", .48), 2.0, true)

func _draw_ridge(points: PackedVector2Array, half_width: float, core: Color, ridge: Color, pieces: int) -> void:
	for i in pieces:
		var t := _terrain_rng.randf()
		var segment := mini(int(t * float(points.size() - 1)), points.size() - 2)
		var local_t := t * float(points.size() - 1) - float(segment)
		var a := points[segment]
		var b := points[segment + 1]
		var tangent := (b - a).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var point := a.lerp(b, local_t) + normal * _terrain_rng.randf_range(-half_width, half_width)
		var scale := _terrain_rng.randf_range(.45, 1.15)
		draw_colored_polygon(_terrain_blob(point, half_width * scale, 1.30, .52), Color(core.r, core.g, core.b, core.a * _terrain_rng.randf_range(.35, .90)))
	for offset in [-half_width * .58, -half_width * .18, half_width * .30]:
		var line := PackedVector2Array()
		for index in points.size():
			var tangent := (points[mini(index + 1, points.size() - 1)] - points[maxi(index - 1, 0)]).normalized()
			line.append(points[index] + Vector2(-tangent.y, tangent.x) * offset)
		draw_polyline(line, ridge, 2.0, true)

func _draw_strategic_valley() -> void:
	# Hanzhong → Jingzhou → Red Cliffs is one broad curved valley, not a route line.
	var valley := PackedVector2Array([p("SYS-12"), p("SYS-14") + Vector2(22, 28), p("SYS-13") + Vector2(48, 17), p("SYS-15") + Vector2(-42, -46)])
	draw_polyline(valley, Color("020d18", .66), 148.0, true)
	draw_polyline(valley, Color("145a78", .24), 96.0, true)
	for offset in [-38.0, -13.0, 17.0, 43.0]:
		var strand := PackedVector2Array()
		for i in valley.size():
			var tangent := (valley[mini(i + 1, valley.size() - 1)] - valley[maxi(i - 1, 0)]).normalized()
			strand.append(valley[i] + Vector2(-tangent.y, tangent.x) * offset)
		draw_polyline(strand, Color("7bdcff", .18), 2.2, true)
	for i in 62:
		var segment := _terrain_rng.randi_range(0, valley.size() - 2)
		var point := valley[segment].lerp(valley[segment + 1], _terrain_rng.randf())
		point += Vector2(_terrain_rng.randf_range(-52, 52), _terrain_rng.randf_range(-42, 42))
		draw_circle(point, _terrain_rng.randf_range(1.5, 5.0), Color("718292", _terrain_rng.randf_range(.16, .42)))

func _draw_wu_delta() -> void:
	var delta := p("SYS-15")
	for i in 18:
		var angle := _terrain_rng.randf_range(-2.65, -.35)
		var end := delta + Vector2(cos(angle) * _terrain_rng.randf_range(70, 175), sin(angle) * _terrain_rng.randf_range(42, 105))
		draw_line(delta, end, Color("d86358", .15), _terrain_rng.randf_range(2.0, 7.0), true)
	_draw_blob_field(delta + Vector2(34, 8), Vector2(size.x * .13, size.y * .11), Color("a83c38", .13), 16, .92, .50)

func _terrain_blob(center: Vector2, radius: float, scale_x: float, scale_y: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 12:
		var angle := TAU * float(i) / 12.0
		var wobble := _terrain_rng.randf_range(.66, 1.30)
		points.append(center + Vector2(cos(angle) * radius * scale_x * wobble, sin(angle) * radius * scale_y * wobble))
	return points

func draw_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 28:
		var angle := TAU * float(i) / 28.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)
func _draw_route(a: Vector2, b: Vector2, kind: String, corridor: bool) -> void:
	var direction := b - a
	var length := direction.length()
	if length < 1.0:
		return
	var unit := direction / length
	var normal := Vector2(-unit.y, unit.x)
	# 선형 직선 대신 지형을 따라 흐르는 항로. 항성류는 완만하게 굽고,
	# 산맥 회랑은 가장 짧고 좁은 틈을 직선으로 관통한다.
	var bend := 0.0 if corridor else (18.0 if kind.contains("고속") else 10.0)
	var sign := -1.0 if a.y < b.y else 1.0
	var mid := (a + b) * .5 + normal * bend * sign
	var curve := PackedVector2Array([a, mid, b])
	if corridor:
		# 험로/회랑: 붉은 성운 흔적, 좁은 이중 경고 궤도.
		for d in range(0, int(length), 22):
			var at := a + unit * float(d)
			draw_circle(at, 20.0, Color("a32643", .09))
			draw_circle(at, 9.0, Color("f05d6f", .11))
		draw_polyline(curve, Color("e96576"), 3.4, true)
		draw_polyline(PackedVector2Array([a + normal*4, mid + normal*4, b + normal*4]), Color("782944"), 3.4, true)
		draw_dashed_line(a, b, Color("ffd083"), 1.4, 8.0, true)
	elif kind.contains("고속"):
		# 고속항로: 넓은 푸른 발광 회랑 위로 금빛 코어가 흐른다.
		draw_polyline(curve, Color("16789f", .22), 20.0, true)
		draw_polyline(curve, Color("55cfee", .45), 7.0, true)
		draw_polyline(curve, Color("f0d37b"), 2.2, true)
		draw_dashed_line(a, b, Color("d7f9ff"), 1.2, 13.0, true)
	else:
		# 일반 항로: 안정된 잔별 띠. 눈에 띄되 고속항로와 경쟁하지 않는다.
		draw_polyline(curve, Color("87a2b9", .28), 5.0, true)
		draw_polyline(curve, Color("d1c37f", .72), 1.3, true)
		for d in range(12, int(length), 26):
			draw_circle(a + unit * float(d), 2.0, Color("dcecff", .70))

func _draw_hud(font: Font) -> void:
	# 유리 패널을 직접 그려 HUD가 배경 위에서 잃지 않게 한다.
	var bar := Rect2(size.x - 450.0, 20.0, 415.0, 44.0)
	draw_style_box(_panel_style(Color("07111d"), Color("caa85b"), 12), bar)
	draw_string(font, bar.position + Vector2(22, 28), "영맥석 12,450     은량 8,912만     군공 21,870", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("f7e8bf"))
	# 좌측: 게임의 주요 층위를 한 번에 보여 주는 고정 메뉴.
	var menu := ["◎  성계도", "♜  함대", "⌂  내정", "◈  외교", "⚒  연구", "▤  연감"]
	for i in menu.size():
		var cell := Rect2(24.0, 102.0 + i * 54.0, 122.0, 42.0)
		draw_style_box(_panel_style(Color("102235") if i == 0 else Color("07101b"), Color("57b9d8") if i == 0 else Color("35516a"), 6), cell)
		draw_string(font, cell.position + Vector2(14, 27), menu[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("eaf8ff") if i == 0 else Color("a9c2d2"))
	# 우측: 현재 지도에서 기대되는 탐색·필터 도구. 프로토타입도 상품 UI처럼 읽히게 한다.
	var tools := ["⌖\n현재 위치", "▽\n지도 필터", "◉\n세력권", "⌕\n성계 검색"]
	for i in tools.size():
		var cell := Rect2(size.x - 126.0, 116.0 + i * 63.0, 94.0, 51.0)
		draw_style_box(_panel_style(Color("07101b"), Color("405e76"), 6), cell)
		var lines := String(tools[i]).split("\n")
		draw_string(font, cell.position + Vector2(13, 21), lines[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("75d9f0"))
		draw_string(font, cell.position + Vector2(13, 40), lines[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("d2e1e8"))
	var box := Rect2(28.0, size.y - 186.0, 330.0, 150.0)
	draw_style_box(_panel_style(Color("07111d"), Color("caa85b"), 12), box)
	var name := "미확인 성계"
	var grade := "—"
	if data != null and data.systems.has(selected):
		name = String(data.systems[selected]["name"]) + " 성계"
		grade = String(data.systems[selected]["grade"])
	draw_string(font, box.position + Vector2(22, 31), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color("ffe2a0"))
	draw_string(font, box.position + Vector2(22, 55), "전략 등급  " + grade + "     성계 선택됨", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("9ecde0"))
	draw_line(box.position + Vector2(20, 73), box.position + Vector2(box.size.x - 20, 73), Color("617b91"), 1.0)
	draw_string(font, box.position + Vector2(22, 99), "민심 82     수비대 6,400     영맥 Lv.3", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("eef4f7"))
	draw_rect(Rect2(box.position + Vector2(20, 114), Vector2(125, 24)), Color("17465d"), true)
	draw_rect(Rect2(box.position + Vector2(154, 114), Vector2(155, 24)), Color("5d401c"), true)
	draw_string(font, box.position + Vector2(39, 132), "성계 정보", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("e8f7ff"))
	draw_string(font, box.position + Vector2(186, 132), "함대 파견", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("fff0c6"))
	var orders := Rect2(size.x - 495.0, size.y - 76.0, 462.0, 42.0)
	draw_style_box(_panel_style(Color("07101b"), Color("415e77"), 8), orders)
	draw_string(font, orders.position + Vector2(18, 27), "작전 모드", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("82d8ed"))
	draw_string(font, orders.position + Vector2(122, 27), "정찰", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("dce7eb"))
	draw_string(font, orders.position + Vector2(191, 27), "이동", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("dce7eb"))
	draw_string(font, orders.position + Vector2(254, 27), "봉쇄", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("dce7eb"))
	draw_string(font, orders.position + Vector2(324, 27), "일시정지 Ⅱ", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("ffe29b"))

func _panel_style(fill: Color, border: Color, radius: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(int(radius))
	return style
func _gui_input(event:InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed): return
	if event.position.distance_to(p("SYS-13").lerp(p("SYS-15"),.52))<30:
		tactical_requested.emit();return
	var hit := "";var best := 42.0
	for sid in POS:
		var d: float = event.position.distance_to(p(sid))
		if d<best: best=d;hit=sid
	if hit!="": selected=hit;queue_redraw();system_selected.emit(hit)
