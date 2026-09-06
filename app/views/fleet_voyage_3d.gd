class_name FleetVoyage3D
extends Control

## 전략 항로에서 선택한 함대의 근접 3D 항행 관측.
## 함종별 GLB와 실제 Fleet.plan 비율을 사용하며, 연출 시간은 월드 시계 배속을 따른다.
signal closed(fleet_id: int)

## 가까운 관측의 초점은 고밀도 선도함으로 잡고, 나머지는 저비용 함선으로
## 유지한다. 160척 함대의 수적 인상과 성능을 동시에 보존하는 LOD 전환점이다.
## V2 경량 프로토타입 대신 Blender 원본에서 만든 고밀도 영웅 자산을 쓴다.
## 원거리 함대는 이 씬을 인스턴스화하지 않고 LOD/MultiMesh 경로를 유지한다.
## GLB는 임포트 캐시가 없는 CI에서도 열 수 있도록 런타임 glTF 문서로 읽는다.
const HAE_MU_HERO_GLB_PATH := "res://assets/models/ships/haemu_line_ship_lod0_v3_final.glb"
const HAE_MU_HERO_FALLBACK_SCENE: PackedScene = preload("res://assets/models/ships/haemu_line_ship_lod0_v2.glb")
const STARFIELD: Texture2D = preload("res://assets/ui-mockups/fleet-voyage-starfield-v1.png")
## 상용 HDRI가 라이선스 대장에 등록되면 이 위치에 둔다. 파일이 없는 개발·CI 환경에서는
## 기존 별 배경으로 안전하게 폴백한다.
const HERO_HDRI_PATH := "res://assets/environments/hero_ship_reflection_4k.hdr"
## 이 관측 시나리오의 정본 편성은 해무급 전열함 한 척이다. 호위함이나
## 축약 편대는 별도의 함대 편성 데이터가 생기기 전까지 표시하지 않는다.
const OBSERVATION_SHIP_COUNT := 1

var campaign
var _fleet_id := -1
var _viewport: SubViewport
var _formation: Node3D
var _camera: Camera3D
var _environment: Environment
var _title: Label
var _quality_caption: Label
var _close: Button
var _elapsed := 0.0
var _fleet_total := 0
var _orbit_yaw := .40
var _orbit_pitch := .24
var _orbit_distance := 14.0
var _orbit_dragging := false
var _orbit_target := Vector3(0, 0, -6.0)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_viewport()
	_build_hud()
	visible = false


func setup(campaign_ref) -> void:
	campaign = campaign_ref


func open_fleet(fleet_id: int) -> void:
	_fleet_id = fleet_id
	visible = true
	_rebuild_formation()


func _build_viewport() -> void:
	var container := SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	_viewport = SubViewport.new()
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(_viewport)
	var world := Node3D.new()
	_viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	_environment = environment.environment
	_environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var panorama := PanoramaSkyMaterial.new()
	panorama.panorama = STARFIELD
	sky.sky_material = panorama
	_environment.sky = sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color("8ab3d2")
	_environment.ambient_light_energy = .32
	_environment.glow_enabled = true
	_environment.glow_intensity = .72
	_environment.glow_strength = .85
	_environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	_environment.tonemap_exposure = 1.05
	var physical_camera := CameraAttributesPhysical.new()
	physical_camera.exposure_sensitivity = 100.0
	physical_camera.exposure_aperture = 5.6
	physical_camera.exposure_shutter_speed = 0.008
	_apply_hero_quality_features()
	world.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -35, 0)
	key.light_color = Color("a7dffd")
	key.light_energy = 2.2
	world.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-5, 2, 5)
	rim.light_color = Color("24bbff")
	rim.light_energy = 9.0
	rim.omni_range = 46.0
	world.add_child(rim)
	_formation = Node3D.new()
	world.add_child(_formation)
	_camera = Camera3D.new()
	_camera.attributes = physical_camera
	# 함대 전체를 멀리서 보는 전략도가 아니라, 호위함 사이로 진입한 관측 카메라다.
	world.add_child(_camera)
	_apply_orbit_camera()


func _build_hud() -> void:
	_title = Label.new()
	_title.position = Vector2(28, 24)
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color("e8f7ff"))
	add_child(_title)
	_quality_caption = Label.new()
	_quality_caption.text = "3D 항행 관측 · 전략 시계 배속 동기화 · " + _quality_mode_label()
	_quality_caption.position = Vector2(30, 55)
	_quality_caption.add_theme_color_override("font_color", Color("8fc5db"))
	add_child(_quality_caption)
	_close = Button.new()
	_close.text = "전략 항로로 돌아가기"
	_close.position = Vector2(28, 84)
	_close.pressed.connect(_close_view)
	add_child(_close)
	var controls := Label.new()
	controls.text = "좌클릭 드래그: 360° 관측 · 휠: 줌 확대/축소"
	controls.position = Vector2(30, 145)
	controls.add_theme_color_override("font_color", Color("86b9cf"))
	add_child(controls)


func _rebuild_formation() -> void:
	for child in _formation.get_children():
		child.queue_free()
	var fleet = _find_fleet()
	if fleet == null:
		return
	_fleet_total = OBSERVATION_SHIP_COUNT
	_title.text = "제%d함대 · 3D 항행 관측 · 전열함 1척" % _fleet_id
	var ship := _instantiate_hero_ship()
	ship.set_meta("fleet_ship_kind", "전열")
	ship.position = Vector3.ZERO
	ship.rotation_degrees = Vector3(0, -8.0, 0)
	ship.scale = Vector3.ONE * .36
	_formation.add_child(ship)
	_orbit_target = Vector3.ZERO
	_orbit_distance = 8.0
	var caption := get_node_or_null("FleetCount") as Label
	if caption == null:
		caption = Label.new()
		caption.name = "FleetCount"
		caption.position = Vector2(30, 116)
		caption.add_theme_color_override("font_color", Color("9acde2"))
		add_child(caption)
	caption.text = "전열함 1척 · 단독 항행 중"
	_apply_orbit_camera()


func _instantiate_hero_ship() -> Node3D:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(HAE_MU_HERO_GLB_PATH, state) == OK:
		var hero := document.generate_scene(state) as Node3D
		if hero != null:
			return hero
	push_warning("해무급 V3 GLB를 읽지 못해 V2 관측용 폴백을 사용합니다")
	return HAE_MU_HERO_FALLBACK_SCENE.instantiate() as Node3D


func _apply_hero_quality_features() -> void:
	# SSR·SSIL은 Forward+ 전용이다. Compatibility에서는 같은 씬과 재질을 쓰되,
	# 지원하지 않는 화면공간 효과를 켜지 않아 모바일 폴백을 보존한다.
	var forward_plus := _is_forward_plus_renderer()
	_environment.ssao_enabled = forward_plus
	_environment.ssao_radius = 1.35
	_environment.ssao_intensity = 1.15
	_environment.ssil_enabled = forward_plus
	_environment.ssil_radius = 3.0
	_environment.ssil_intensity = .65
	_environment.ssr_enabled = forward_plus
	_environment.ssr_max_steps = 64
	var panorama := _environment.sky.sky_material as PanoramaSkyMaterial
	if ResourceLoader.exists(HERO_HDRI_PATH):
		var hdri := load(HERO_HDRI_PATH) as Texture2D
		if hdri != null and panorama != null:
			panorama.panorama = hdri


func _is_forward_plus_renderer() -> bool:
	# 프로젝트 설정이 아니라 실제로 실행 중인 렌더러를 읽는다. 이렇게 해야
	# `renderer/rendering_method.mobile` 및 명령행 폴백도 정확히 반영된다.
	return RenderingServer.get_current_rendering_method() == "forward_plus"


func _quality_mode_label() -> String:
	return "Forward+ 영웅 품질" if _is_forward_plus_renderer() else "Compatibility 폴백"


func _formation_position(index: int, formation: String) -> Vector3:
	var row := int(floor(sqrt(float(index))))
	var column := index - row * row
	var centered := float(column) - float(row)
	var x := 0.0
	var y := (float((index * 5) % 9) - 4.0) * .18
	var z := 0.0
	match formation:
		"학익진":
			var wing := -1.0 if index % 2 == 0 else 1.0
			x = wing * (2.2 + float(row) * 1.35)
			z = -float(row) * 1.15
		"방원진":
			var side := index % 4
			var ring := float(index / 4 + 1)
			var span := 1.4 + ring * .65
			match side:
				0: x = span; z = centered * .45
				1: x = centered * .45; z = span
				2: x = -span; z = centered * .45
				_: x = centered * .45; z = -span
		"안행진":
			x = centered * 1.25
			z = -float(row) * .72
		"봉시진":
			x = centered * .56
			z = -float(row) * 1.28
		"장사진":
			x = (float((index % 3) - 1)) * .28
			z = -float(index) * .58
		"팔진":
			var angle := TAU * float(index % 8) / 8.0
			var radius := 1.7 + float(index / 8) * .72
			x = cos(angle) * radius
			z = sin(angle) * radius - float(index / 8) * .4
		_:
			x = centered * .72
			z = -float(row) * 1.08
	return Vector3(x, y, z)


func _process(delta: float) -> void:
	if not visible or campaign == null or campaign.world == null:
		return
	_elapsed += delta * float(campaign.world.clock.speed)
	# 함대는 선택된 진형을 유지한다. 함선을 흘려 보내지 않고, 카메라가 함대와
	# 함께 항행하는 관점으로 성운·별 배경만 시간 배속에 맞춰 이동시킨다.
	_formation.position = Vector3.ZERO
	_formation.rotation = Vector3.ZERO
	_update_sky_motion()


func _apply_orbit_camera() -> void:
	if _camera == null:
		return
	var horizontal := cos(_orbit_pitch) * _orbit_distance
	var offset := Vector3(
		sin(_orbit_yaw) * horizontal,
		sin(_orbit_pitch) * _orbit_distance,
		cos(_orbit_yaw) * horizontal)
	_camera.position = _orbit_target + offset
	_camera.look_at(_orbit_target, Vector3.UP)
	_update_sky_motion()


func _update_sky_motion() -> void:
	# PanoramaSkyMaterial은 카메라 회전에 따라 시야가 바뀐다. 시간 배속에
	# 비례한 저속 회전을 더해, 함대는 고정되어도 배경이 흐르는 항행감을 만든다.
	if _environment != null:
		_environment.sky_rotation = Vector3(
			_orbit_pitch * .18 + sin(_elapsed * .025) * .035,
			_orbit_yaw * .18 + _elapsed * .012,
			0.0)


func _find_fleet():
	if campaign == null:
		return null
	for fleet in campaign.fleets:
		if fleet != null and int(fleet.id) == _fleet_id:
			return fleet
	return null


func _close_view() -> void:
	var id := _fleet_id
	visible = false
	closed.emit(id)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_orbit_distance = maxf(4.5, _orbit_distance - 1.0)
			_apply_orbit_camera()
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_orbit_distance = minf(42.0, _orbit_distance + 1.0)
			_apply_orbit_camera()
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			_orbit_dragging = event.pressed
			accept_event()
			return
	if event is InputEventMouseMotion and _orbit_dragging:
		_orbit_yaw -= event.relative.x * .010
		_orbit_pitch = clampf(_orbit_pitch - event.relative.y * .008, -.78, .78)
		_apply_orbit_camera()
		accept_event()
