class_name TacticalRouteView
extends Control

## 선택한 함대의 실제 이동 상태를 읽어 보여 주는 항로 관측 컴포넌트.
## 명령과 시간은 호스트가 소유하며, 이 화면은 FleetRouteContext를 표시만 한다.
signal closed(fleet_id: int)
signal detail_requested(fleet_id: int)
signal speed_requested

const BG: Texture2D = preload("res://assets/ui-mockups/seonghanji-fleet-encounter-background.png")
const ASSAULT_CARRIER: Texture2D = preload("res://assets/ships/assault-carrier.png")
const LINE_SHIP: Texture2D = preload("res://assets/ships/line-ship.png")
const ARTILLERY_SHIP: Texture2D = preload("res://assets/ships/artillery-ship.png")
const SIEGE_SHIP: Texture2D = preload("res://assets/ships/siege-ship.png")
const ELECTRONIC_SHIP: Texture2D = preload("res://assets/ships/electronic-ship.png")
const INTERCEPTOR_FIGHTER: Texture2D = preload("res://assets/ships/interceptor-fighter.png")
const SUPPLY_SHIP: Texture2D = preload("res://assets/ships/supply-ship.png")
const CONTEXT_PATH := "res://app/views/fleet_route_context.gd"
const SHIP_TEXTURES := {
	"전열": preload("res://assets/ships/line-ship.png"),
	"포격": preload("res://assets/ships/artillery-ship.png"),
	"강습": preload("res://assets/ships/assault-carrier.png"),
	"전자": preload("res://assets/ships/electronic-ship.png"),
	"공성": preload("res://assets/ships/siege-ship.png"),
	"보급": preload("res://assets/ships/supply-ship.png"),
}

var data
var campaign

var _fleet_id := -1
var _fleet
var _pending_context: Dictionary = {}
var _context: Dictionary = {}
var _close_rect := Rect2()
var _fleet_interaction_rect := Rect2()
var _playback_rect := Rect2()
var _fleet_formation_art: Array[TextureRect] = []
var _ship_sprites: Array[TextureRect] = []
var _display_progress := 0.0
var _has_display_progress := false


func setup(p_data, p_campaign) -> void:
	data = p_data
	campaign = p_campaign
	refresh()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_fleet_formation_art()
	_build_ship_sprites()
	resized.connect(_on_resized)


func _build_fleet_formation_art() -> void:
	# 전대는 아이콘이 아니라 개별 함선 시안으로 렌더한다. 실제 함대의 세부 함종
	# 편제 데이터는 아직 없으므로 이 배열은 전력 수치가 아닌 시네마틱 대표 편성이다.
	var ships: Array[Dictionary] = [
		{"name": "Interceptor", "texture": INTERCEPTOR_FIGHTER, "layer": 0},
		{"name": "Electronic", "texture": ELECTRONIC_SHIP, "layer": 1},
		{"name": "Artillery", "texture": ARTILLERY_SHIP, "layer": 1},
		{"name": "Line", "texture": LINE_SHIP, "layer": 2},
		{"name": "Siege", "texture": SIEGE_SHIP, "layer": 2},
		{"name": "Supply", "texture": SUPPLY_SHIP, "layer": 2},
		{"name": "Flagship", "texture": ASSAULT_CARRIER, "layer": 3},
	]
	for definition in ships:
		var art := TextureRect.new()
		art.name = "FleetShip%s" % String(definition["name"])
		art.texture = definition["texture"]
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.z_index = int(definition["layer"])
		add_child(art)
		_fleet_formation_art.append(art)
	_layout_fleet_formation_art()


func _on_resized() -> void:
	_layout_fleet_formation_art()
	_layout_ship_sprites()
	queue_redraw()


func _layout_fleet_formation_art() -> void:
	if _fleet_formation_art.is_empty():
		return
	var scale := minf(size.x / 1116.0, size.y / 620.0)
	var origin := Vector2(size.x * .18, 80.0)
	# 각 함선의 방향은 리소스 원본의 추진부(좌하) → 선수(우상) 축을 따른다.
	# 목표 게이트 쪽으로 올라가는 V자 전대 구도를 만든다.
	var layout: Array[Dictionary] = [
		{"at": Vector2(10, 222), "extent": Vector2(104, 104)},
		{"at": Vector2(96, 108), "extent": Vector2(144, 144)},
		{"at": Vector2(322, 6), "extent": Vector2(132, 132)},
		{"at": Vector2(0, 14), "extent": Vector2(154, 154)},
		{"at": Vector2(450, 154), "extent": Vector2(132, 132)},
		{"at": Vector2(276, 238), "extent": Vector2(126, 126)},
		{"at": Vector2(182, 116), "extent": Vector2(300, 300)},
	]
	for index in range(mini(_fleet_formation_art.size(), layout.size())):
		var definition: Dictionary = layout[index]
		var art := _fleet_formation_art[index]
		art.position = origin + (definition["at"] as Vector2) * scale
		art.size = (definition["extent"] as Vector2) * scale


## 함대 전체 연출 아래에 실제 편성안의 함종 스프라이트를 둔다. 개별 함선 수나
## 위치를 꾸미지 않고, 전략 코어의 plan 비율만 그대로 읽는다.
func _build_ship_sprites() -> void:
	for _kind in Economy.SHIP_KINDS:
		var sprite := TextureRect.new()
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(sprite)
		_ship_sprites.append(sprite)
	_layout_ship_sprites()


func _layout_ship_sprites() -> void:
	if _ship_sprites.is_empty():
		return
	var edge := minf(88.0, size.x / 13.0)
	var start_x := size.x * .5 - edge * 3.0
	var y := minf(size.y - 278.0, 470.0)
	for index in _ship_sprites.size():
		_ship_sprites[index].position = Vector2(start_x + edge * index, y)
		_ship_sprites[index].size = Vector2.ONE * edge


func _refresh_ship_sprites() -> void:
	# 전략 항로는 개별 함선을 크게 보여 주지 않는다. 상세 3D 관측에서만 함종
	# 메시를 렌더하며, 여기서는 실제 함정 수를 점 편대로 축약한다.
	for art in _fleet_formation_art:
		art.visible = false
	if _fleet == null:
		for sprite in _ship_sprites:
			sprite.visible = false
		return
	var plan := String(_fleet.plan)
	var ratio: Array = Economy.PLANS.get(plan, Economy.PLANS[Economy.PLAN_DEFAULT])
	for index in _ship_sprites.size():
		var kind: String = Economy.SHIP_KINDS[index]
		_ship_sprites[index].texture = SHIP_TEXTURES[kind]
		_ship_sprites[index].visible = false


func open_fleet(fleet_id: int, pending_context = {}) -> void:
	_fleet_id = fleet_id
	_pending_context = _as_dictionary(pending_context)
	_has_display_progress = false
	visible = true
	refresh()


func refresh() -> void:
	_fleet = _find_fleet(_fleet_id)
	_context = _build_context()
	_refresh_ship_sprites()
	if not _has_display_progress:
		_display_progress = _canonical_progress()
		_has_display_progress = true
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	# tick은 배속에 따라 불연속적으로 진행한다. 화면은 정본 목표 진행률만 향해
	# 보간해, 특히 x16/x64에서 점 편대가 끊기지 않고 항로를 항행하게 한다.
	_display_progress = move_toward(_display_progress, _canonical_progress(),
		delta * .18 * float(_clock_speed()))
	queue_redraw()


func _draw() -> void:
	draw_texture_rect(BG, Rect2(Vector2.ZERO, size), false)
	# 홈 HUD의 안전 영역 안에서 보이는 독립적인 관측 창이다. 배경은 남기되,
	# 레퍼런스처럼 함대와 게이트에 시선이 모이도록 주변부를 어둡게 눌러 준다.
	draw_rect(Rect2(Vector2.ZERO, size), Color("020914", .64))
	draw_rect(Rect2(0, 0, size.x, 92), Color("040914", .96))
	draw_rect(Rect2(0, size.y - 174, size.x, 174), Color("020914", .42))

	_close_rect = Rect2(size.x - 132, 21, 92, 48)
	draw_style_box(_style(Color("8ab7c8", .72)), _close_rect)
	draw_string(get_theme_default_font(), _close_rect.position + Vector2(24, 31),
		"닫기", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("e7f6fb"))

	var status := String(_context.get("status", "unavailable"))
	if _fleet == null or status == "unavailable":
		_draw_state_message("항로 관측 불가",
			String(_context.get("error", "대상이 소멸했거나 현재 캠페인에 존재하지 않습니다.")))
		return
	if status == "rejected":
		_draw_state_message("출항 명령 거부",
			String(_context.get("error", "이동 명령이 적용되지 않았습니다.")))
		return

	var title := "제%d함대 · 항로 관측" % _fleet_id
	var origin_name := String(_context.get("origin_name", "미확인 성계"))
	var destination_name := String(_context.get("destination_name", ""))
	var subtitle := "%s → %s" % [origin_name, destination_name] \
		if destination_name != "" else "%s · 주둔" % origin_name
	draw_string(get_theme_default_font(), Vector2(38, 39), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("ffe09a"))
	draw_string(get_theme_default_font(), Vector2(39, 67), subtitle,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("d9eef5"))

	_draw_operation_panel()
	_draw_route()
	_draw_fleet_cinematic()
	_draw_status_panel()
	_draw_playback_readout()
	_draw_command_readout()
	if _has_battle_data():
		_draw_battle_panel()


func _draw_state_message(heading: String, detail: String) -> void:
	var panel := Rect2(size.x * .5 - 260, size.y * .5 - 70, 520, 140)
	draw_style_box(_style(Color("b86f68", .85)), panel)
	draw_string(get_theme_default_font(), panel.position + Vector2(28, 47),
		heading, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("ffd1c9"))
	draw_string(get_theme_default_font(), panel.position + Vector2(28, 83),
		detail, HORIZONTAL_ALIGNMENT_LEFT, 464, 14, Color("d7e1e5"))


func _draw_operation_panel() -> void:
	var panel := Rect2(22, 96, 222, 96)
	draw_style_box(_style(Color("4c9eb7", .74)), panel)
	draw_string(get_theme_default_font(), panel.position + Vector2(14, 25),
		"작전 목표", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("8fe7fb"))
	var destination := String(_context.get("destination_name", "목적지 미지정"))
	draw_string(get_theme_default_font(), panel.position + Vector2(14, 52),
		"◇  %s 성계로 이동" % destination,
		HORIZONTAL_ALIGNMENT_LEFT, 192, 13, Color("e8f5fa"))
	draw_string(get_theme_default_font(), panel.position + Vector2(14, 77),
		_arrival_text(), HORIZONTAL_ALIGNMENT_LEFT, 192, 12, Color("b7cfd9"))


func _draw_route() -> void:
	# 이 선은 성계 간 확정 경로를 보여 준다. Fleet에는 항로 위 좌표/출발 tick이
	# 없으므로 함대의 진행률이나 중간 위치는 절대 추정하지 않는다.
	var from := Vector2(size.x * .25, size.y * .61)
	var to := Vector2(size.x * .82, size.y * .27)
	var path: Array = _context.get("path", [])
	var points := PackedVector2Array()
	var segment_count := maxi(path.size() - 1, 1)
	for index in range(segment_count + 1):
		var ratio := float(index) / float(segment_count)
		var point := from.lerp(to, ratio)
		if index > 0 and index < segment_count:
			point.y += sin(float(index) * 1.7) * minf(72.0, size.y * .08)
		points.append(point)

	draw_polyline(points, Color("65d9ef", .12), 24, true)
	draw_polyline(points, Color("dcefa2", .62), 2, true)
	_draw_route_direction_marks(points)
	_draw_system_gate(from, String(_context.get("origin_name", "미확인 성계")),
		"출발", Color("75ddf2"), -1)
	_draw_system_gate(to, String(_context.get("destination_name", "목적지 미지정")),
		"목적지", Color("f0b77c"), 1)

	var status := String(_context.get("status", ""))
	var marker_text: String = {
		"pending": "출항 명령 처리 중",
		"moving": "이동 중 · 시간 배속 동기화",
		"arrived": "도착 완료",
		"stationed": "주둔",
	}.get(status, "상태 미확인")
	draw_string(get_theme_default_font(), Vector2(size.x * .5 - 150, 116),
		marker_text, HORIZONTAL_ALIGNMENT_CENTER, 300, 13, Color("fff0c4"))

	for index in range(1, points.size() - 1):
		var label := _system_name(String(path[index])) if index < path.size() else "경유"
		draw_circle(points[index], 8, Color("dcefa2"))
		draw_string(get_theme_default_font(), points[index] + Vector2(-55, -18),
			label, HORIZONTAL_ALIGNMENT_CENTER, 110, 12, Color("d9eef5"))


func _draw_route_direction_marks(points: PackedVector2Array) -> void:
	if points.size() < 2:
		return
	for index in range(points.size() - 1):
		var start := points[index]
		var end := points[index + 1]
		var direction := (end - start).normalized()
		var center := start.lerp(end, .68)
		var normal := Vector2(-direction.y, direction.x)
		var arrow := PackedVector2Array([
			center + direction * 12.0,
			center - direction * 8.0 + normal * 6.0,
			center - direction * 8.0 - normal * 6.0,
		])
		draw_colored_polygon(arrow, Color("cfeea7", .72))


func _draw_fleet_cinematic() -> void:
	# 전략 화면에서는 실제 함정 수만큼의 점 편대를 그린다. `Fleet.formation`이
	# 정한 전개 형상과 항로의 진행 방향을 함께 적용한다.
	var ships := maxi(0, int(_fleet.ships)) if _fleet != null else 0
	var formation := String(_context.get("formation", "미확인"))
	var center := _strategic_fleet_position()
	_fleet_interaction_rect = Rect2(center - Vector2(155, 92), Vector2(310, 184))
	var dot_count := clampi(ships, 12, 180)
	var forward := (Vector2(size.x * .82, size.y * .27) - Vector2(size.x * .25, size.y * .61)).normalized()
	var lateral := Vector2(-forward.y, forward.x)
	for index in range(dot_count):
		var local := _formation_offset(index, formation)
		var position := center + forward * local.x + lateral * local.y
		draw_circle(position, 1.8, Color("86edf8"))
		draw_line(position - forward * 8.0, position - forward * 2.0,
			Color("3ba9d2", .45), 1.0, true)
	draw_arc(center, 32, 0, TAU, 24, Color("ffe69b", .82), 1.5, true)
	draw_string(get_theme_default_font(), center + Vector2(-128, 108),
		"제%d함대 · %s · %d척" % [_fleet_id, formation, ships],
		HORIZONTAL_ALIGNMENT_CENTER, 256, 15, Color("f7fbff"))
	draw_string(get_theme_default_font(), center + Vector2(-128, 130),
		"클릭하여 3D 항행 관측", HORIZONTAL_ALIGNMENT_CENTER, 256, 12, Color("8fe7fb"))


func _strategic_fleet_position() -> Vector2:
	var fallback := Vector2(size.x * .50, size.y * .48)
	var departure := int(_context.get("departure_tick", -1))
	var arrival := int(_context.get("arrival_tick", -1))
	if campaign == null or campaign.world == null or departure < 0 or arrival <= departure:
		return fallback
	var from := Vector2(size.x * .25, size.y * .61)
	var to := Vector2(size.x * .82, size.y * .27)
	return from.lerp(to, _display_progress)


func _canonical_progress() -> float:
	var departure := int(_context.get("departure_tick", -1))
	var arrival := int(_context.get("arrival_tick", -1))
	if campaign == null or campaign.world == null or departure < 0 or arrival <= departure:
		return 0.0
	return clampf(float(campaign.world.clock.tick - departure) / float(arrival - departure), 0.0, 1.0)


func _clock_speed() -> int:
	return int(campaign.world.clock.speed) if campaign != null and campaign.world != null else 1


func _formation_offset(index: int, formation: String) -> Vector2:
	var row := int(floor(sqrt(float(index))))
	var column := index - row * row
	var centered := float(column) - float(row)
	match formation:
		"학익진": # 양익 포위: 전방을 비우고 두 날개를 넓게 편다.
			var wing := -1.0 if index % 2 == 0 else 1.0
			return Vector2(-float(row) * 5.0, wing * (18.0 + float(row) * 8.0))
		"방원진": # 종심 방어: 중심을 둘러싼 방형 고리.
			var side := index % 4
			var ring := int(index / 4) + 1
			return [Vector2(ring * 7.0, centered * 6.0), Vector2(centered * 6.0, ring * 7.0),
				Vector2(-ring * 7.0, centered * 6.0), Vector2(centered * 6.0, -ring * 7.0)][side]
		"안행진": # 사격 전개: 넓고 얕은 횡열.
			return Vector2(-float(row) * 8.0, centered * 13.0)
		"봉시진": # 축차 투입: 좁은 선두에서 뒤로 열리는 V.
			return Vector2(-float(row) * 11.0, centered * 7.0)
		"장사진": # 회랑 종렬 항진.
			return Vector2(-float(index) * 5.5, 0.0)
		"팔진": # 여덟 방위의 가변 방진.
			var angle := TAU * float(index % 8) / 8.0
			var radius := 12.0 + float(index / 8) * 8.0
			return Vector2(cos(angle) * radius, sin(angle) * radius)
		_: # 어린진: 중앙 돌파용 쐐기.
			return Vector2(-float(row) * 9.0, centered * 8.0)


func _draw_status_panel() -> void:
	var panel := Rect2(22, size.y - 144, 292, 120)
	draw_style_box(_style(Color("c6a75d", .82)), panel)
	draw_string(get_theme_default_font(), panel.position + Vector2(18, 28),
		"제%d함대 · 기함 편성" % _fleet_id,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("8fe7fb"))

	var formation := String(_context.get("formation", "미확인"))
	var terrain := String(_context.get("terrain", "미확인"))
	var ships := maxi(0, int(_fleet.ships)) if _fleet != null else 0
	draw_string(get_theme_default_font(), panel.position + Vector2(18, 57),
		"%s · %s · %s" % [_status_label(), formation, terrain],
		HORIZONTAL_ALIGNMENT_LEFT, 256, 13, Color("eef7fb"))
	draw_string(get_theme_default_font(), panel.position + Vector2(18, 82),
		"가용 함정  %d척" % ships, HORIZONTAL_ALIGNMENT_LEFT, 256, 13, Color("c7dce4"))
	draw_string(get_theme_default_font(), panel.position + Vector2(18, 108),
		_arrival_text(), HORIZONTAL_ALIGNMENT_LEFT, 256, 12, Color("ffe2a0"))


func _draw_playback_readout() -> void:
	_playback_rect = Rect2(size.x * .47, size.y - 58, 170, 34)
	draw_style_box(_style(Color("5f9dad", .72)), _playback_rect)
	var speed := _clock_speed()
	draw_string(get_theme_default_font(), _playback_rect.position + Vector2(14, 22),
		"시간 배속  ·  %dx" % speed,
		HORIZONTAL_ALIGNMENT_CENTER, _playback_rect.size.x - 28, 13, Color("cdebf2"))


func _draw_command_readout() -> void:
	var origin := Vector2(size.x - 280, size.y - 78)
	var entries := [
		["이동", "지휘 화면"], ["진형", String(_context.get("formation", "미확인"))],
		["관측", "읽기 전용"],
	]
	for index in range(entries.size()):
		var panel := Rect2(origin + Vector2(index * 88, 0), Vector2(80, 54))
		draw_style_box(_style(Color("4d8190", .60)), panel)
		draw_string(get_theme_default_font(), panel.position + Vector2(4, 21),
			String(entries[index][0]), HORIZONTAL_ALIGNMENT_CENTER, 72, 13, Color("8fe7fb"))
		draw_string(get_theme_default_font(), panel.position + Vector2(4, 41),
			String(entries[index][1]), HORIZONTAL_ALIGNMENT_CENTER, 72, 10, Color("a7c0c9"))


func _draw_battle_panel() -> void:
	var battle := _battle_dictionary()
	var panel := Rect2(size.x - 390, 116, 350, 128)
	draw_style_box(_style(Color("d6746f", .92)), panel)
	draw_string(get_theme_default_font(), panel.position + Vector2(18, 29),
		"접적 상태", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("ffaaa2"))
	var battle_name := String(battle.get("name", battle.get("title", "교전 데이터 확인")))
	var phase := String(battle.get("phase", battle.get("status", "진행 중")))
	draw_string(get_theme_default_font(), panel.position + Vector2(18, 59),
		battle_name, HORIZONTAL_ALIGNMENT_LEFT, 310, 14, Color("fff1ed"))
	draw_string(get_theme_default_font(), panel.position + Vector2(18, 84),
		"현재 단계  %s" % phase, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("ffd0c8"))
	draw_string(get_theme_default_font(), panel.position + Vector2(18, 108),
		"전투 지시는 전투 화면에서 실행합니다", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("c9d9df"))


func _build_context() -> Dictionary:
	if _fleet_id < 0:
		return {}
	# 이미 완성된 FleetRouteContext를 받은 경우 snapshot 결과를 우선한다.
	if _pending_context.has("schema_version") and _pending_context.has("fleet_id"):
		return _pending_context.duplicate(true)
	if ResourceLoader.exists(CONTEXT_PATH):
		var context_script = load(CONTEXT_PATH)
		if context_script != null and context_script.has_method("from_campaign"):
			var route_context = context_script.call("from_campaign", campaign, _fleet_id, _pending_context)
			if route_context != null and route_context.has_method("snapshot"):
				var snapshot = route_context.call("snapshot")
				if snapshot is Dictionary:
					return (snapshot as Dictionary).duplicate(true)
	return _fallback_context()


func _fallback_context() -> Dictionary:
	if _fleet == null:
		return {"fleet_id": _fleet_id, "error": "함대를 찾을 수 없습니다"}
	var destination_region := String(_pending_context.get("destination_region", _fleet.target_region))
	var destination_system := String(_pending_context.get("destination_system", ""))
	if destination_system == "" and destination_region != "" and data != null:
		destination_system = String(data.system_of(destination_region))
	return {
		"schema_version": 1,
		"status": "moving" if _fleet.is_moving() else "stationed",
		"fleet_id": _fleet.id,
		"origin_system": _fleet.at_system,
		"origin_name": _system_name(_fleet.at_system),
		"destination_region": destination_region,
		"destination_region_name": _region_name(destination_region),
		"destination_system": destination_system,
		"destination_name": _system_name(destination_system) if destination_system != "" else "",
		"arrival_tick": _fleet.arrival_tick,
		"remaining_ticks": maxi(0, _fleet.arrival_tick - campaign.world.clock.tick) if _fleet.arrival_tick >= 0 else -1,
		"path": [_fleet.at_system, destination_system] if destination_system != "" else [_fleet.at_system],
		"corridors": [],
		"terrain": "미확인",
		"formation": _fleet.formation,
		"error": "",
	}


func _find_fleet(fleet_id: int):
	if campaign == null:
		return null
	for fleet in campaign.fleets:
		if fleet.id == fleet_id:
			return fleet
	return null


func _as_dictionary(value) -> Dictionary:
	if value == null:
		return {}
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Object and value.has_method("snapshot"):
		var snapshot = value.call("snapshot")
		if snapshot is Dictionary:
			return (snapshot as Dictionary).duplicate(true)
	return {}


func _status_label() -> String:
	return {
		"moving": "이동 중",
		"pending": "출항 명령 처리 중",
		"stationed": "주둔",
		"arrived": "도착 완료",
		"rejected": "출항 명령 거부",
		"unavailable": "항로 관측 불가",
	}.get(String(_context.get("status", "")), "상태 미확인")


func _arrival_text() -> String:
	var arrival_tick := int(_context.get("arrival_tick", -1))
	var remaining_ticks := int(_context.get("remaining_ticks", -1))
	if arrival_tick < 0:
		return "도착 예정  없음"
	return "도착 tick %d · 남은 %d tick" % [arrival_tick, maxi(0, remaining_ticks)]


func _system_name(system_id: String) -> String:
	if system_id == "":
		return "미확인 성계"
	if data != null and data.has_method("system_name"):
		return String(data.system_name(system_id))
	return system_id


func _region_name(region_id: String) -> String:
	if region_id == "" or data == null or not ("regions" in data) or not data.regions.has(region_id):
		return ""
	return String(data.regions[region_id].get("name", region_id))


func _corridor_label(value) -> String:
	if value is Dictionary:
		return String(value.get("name", value.get("id", "미확인 회랑")))
	return String(value)


func _has_battle_data() -> bool:
	return not _battle_dictionary().is_empty()


func _battle_dictionary() -> Dictionary:
	for key in ["battle", "encounter", "combat"]:
		var value = _pending_context.get(key)
		if value is Dictionary and not value.is_empty():
			return value
	return {}


func _draw_system_gate(at: Vector2, name: String, role: String, color: Color, direction: int) -> void:
	draw_circle(at, 43, Color(color.r, color.g, color.b, .13))
	draw_circle(at, 26, Color("07101b"))
	draw_arc(at, 26, 0, TAU, 36, color, 3.0, true)
	draw_circle(at, 8, Color("fff0b3"))
	var x := at.x - 125 if direction < 0 else at.x - 82
	draw_string(get_theme_default_font(), Vector2(x, at.y - 48),
		name, HORIZONTAL_ALIGNMENT_CENTER, 190, 20, Color("fff2ca"))
	draw_string(get_theme_default_font(), Vector2(x, at.y + 55),
		role, HORIZONTAL_ALIGNMENT_CENTER, 190, 12, color)


func _point_on_polyline(points: PackedVector2Array, ratio: float) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	if points.size() == 1:
		return points[0]
	var scaled := clampf(ratio, 0.0, 1.0) * float(points.size() - 1)
	var index := mini(int(floor(scaled)), points.size() - 2)
	return points[index].lerp(points[index + 1], scaled - float(index))


func _style(border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("07111d", .94)
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	return style


func _close() -> void:
	var closing_id := _fleet_id
	visible = false
	_fleet_id = -1
	_fleet = null
	_pending_context.clear()
	_context.clear()
	closed.emit(closing_id)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT \
				or (event.button_index == MOUSE_BUTTON_LEFT and _close_rect.has_point(event.position)):
			_close()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and _fleet_interaction_rect.has_point(event.position):
			detail_requested.emit(_fleet_id)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and _playback_rect.has_point(event.position):
			speed_requested.emit()
			accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()
