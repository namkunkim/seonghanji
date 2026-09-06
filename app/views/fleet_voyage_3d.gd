class_name FleetVoyage3D
extends Control

## 전략 항로에서 선택한 함대의 근접 3D 항행 관측.
## 함종별 GLB와 실제 Fleet.plan 비율을 사용하며, 연출 시간은 월드 시계 배속을 따른다.
signal closed(fleet_id: int)

## 가까운 관측의 초점은 고밀도 선도함으로 잡고, 나머지는 저비용 함선으로
## 유지한다. 160척 함대의 수적 인상과 성능을 동시에 보존하는 LOD 전환점이다.
## 이동 상세 화면은 함대 편성에서 가장 많은 함종을 영웅 자산으로 쓴다.
## 원거리 함대는 이 씬을 인스턴스화하지 않고 LOD/MultiMesh 경로를 유지한다.
## GLB는 임포트 캐시가 없는 CI에서도 열 수 있도록 런타임 glTF 문서로 읽는다.
const HAE_MU_HERO_GLB_PATH := "res://assets/models/iron-vanguard-space-battleship.glb"
const VOYAGE_LOD_ROOT := "res://assets/models/ships/voyage_lod/"
const HAE_MU_HERO_FALLBACK_SCENE: PackedScene = preload("res://assets/models/ships/haemu_line_ship_lod0_v2.glb")
const STARFIELD: Texture2D = preload("res://assets/ui-mockups/fleet-voyage-starfield-v1.png")
## 상용 HDRI가 라이선스 대장에 등록되면 이 위치에 둔다. 파일이 없는 개발·CI 환경에서는
## 기존 별 배경으로 안전하게 폴백한다.
const HERO_HDRI_PATH := "res://assets/environments/hero_ship_reflection_4k.hdr"
## 상세 항행 관측은 함대 전체 비율을 전대 1개(28척)로 축약해 보여 준다.
const OBSERVATION_SHIP_COUNT := Battle.SQUADRON_SHIPS

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
var _orbit_yaw := 0.0
var _orbit_pitch := .48
var _orbit_distance := 14.0
var _orbit_dragging := false
var _orbit_target := Vector3(0, 0, -6.0)
var _hero_kind := "전열"
var _ship_prototypes: Dictionary = {}
var _travel_stars: Array[MeshInstance3D] = []
var _travel_star_rng := RandomNumberGenerator.new()
var _engine_core_material: StandardMaterial3D
var _engine_plume_material: StandardMaterial3D


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
	key.light_energy = 3.2
	world.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-5, 2, 5)
	rim.light_color = Color("24bbff")
	rim.light_energy = 9.0
	rim.omni_range = 46.0
	world.add_child(rim)
	_formation = Node3D.new()
	world.add_child(_formation)
	_build_travel_starfield(world)
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
	var squadron_kinds := _squadron_ship_kinds(fleet)
	var formation_positions := _formation_positions_by_role(squadron_kinds, fleet.formation)
	_fleet_total = squadron_kinds.size()
	_title.text = "제%d함대 · 3D 항행 관측 · 전대 1개 · %d척" % [_fleet_id, _fleet_total]
	for index in range(squadron_kinds.size()):
		var ship_kind: String = squadron_kinds[index]
		var ship := _instantiate_hero_ship(ship_kind)
		ship.set_meta("fleet_ship_kind", ship_kind)
		ship.position = formation_positions[index]
		ship.rotation_degrees = Vector3(0, -8.0, 0)
		# Shared GLB meshes keep the 28-ship squadron affordable while retaining silhouettes.
		ship.scale = Vector3.ONE * .42
		_formation.add_child(ship)
	_orbit_target = Vector3(0, 0, -2.7)
	_orbit_distance = 10.0
	var caption := get_node_or_null("FleetCount") as Label
	if caption == null:
		caption = Label.new()
		caption.name = "FleetCount"
		caption.position = Vector2(30, 116)
		caption.add_theme_color_override("font_color", Color("9acde2"))
		add_child(caption)
	caption.text = "전대 1개 · %s · %s" % [fleet.formation, _squadron_composition_label(squadron_kinds)]
	_apply_orbit_camera()


func _instantiate_hero_ship(ship_kind: String) -> Node3D:
	if _ship_prototypes.has(ship_kind):
		var cached = _ship_prototypes[ship_kind] as Node3D
		if cached != null:
			return cached.duplicate() as Node3D
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var glb_path := _hero_glb_path(ship_kind)
	if document.append_from_file(glb_path, state) == OK:
		var hero := document.generate_scene(state) as Node3D
		if hero != null:
			# The concept-render GLB already owns its panel, recess, and cyan engine
			# materials. Preserve the source material language for the formation.
			_add_ship_engine_effects(hero)
			_ship_prototypes[ship_kind] = hero
			return hero.duplicate() as Node3D
	push_warning("%s 영웅 GLB를 읽지 못해 전열함 관측용 폴백을 사용합니다" % ship_kind)
	var fallback := HAE_MU_HERO_FALLBACK_SCENE.instantiate() as Node3D
	_add_ship_engine_effects(fallback)
	return fallback


func _add_ship_engine_effects(ship: Node3D) -> void:
	if ship == null or ship.get_node_or_null("IonDriveEffects") != null:
		return
	var bounds := _ship_mesh_bounds(ship)
	var span := bounds.size
	var engine_plane := bounds.end.x + maxf(span.x * .018, .035)
	var engine_y := bounds.get_center().y - span.y * .14
	var engine_radius := clampf(maxf(span.z * .045, span.y * .055), .035, .22)
	var plume_length := clampf(span.x * .16, .18, 1.3)
	var effects := Node3D.new()
	effects.name = "IonDriveEffects"
	ship.add_child(effects)
	_ensure_engine_materials()
	for lateral in [-.28, 0.0, .28]:
		var nozzle := MeshInstance3D.new()
		var nozzle_mesh := CylinderMesh.new()
		nozzle_mesh.top_radius = engine_radius * .75
		nozzle_mesh.bottom_radius = engine_radius
		nozzle_mesh.height = plume_length
		nozzle_mesh.material = _engine_plume_material
		nozzle.mesh = nozzle_mesh
		nozzle.position = Vector3(engine_plane + plume_length * .5, engine_y, bounds.get_center().z + span.z * lateral)
		nozzle.rotation_degrees = Vector3(0, 0, -90)
		effects.add_child(nozzle)
		var core := MeshInstance3D.new()
		var core_mesh := SphereMesh.new()
		core_mesh.radius = engine_radius * .72
		core_mesh.height = engine_radius * 1.44
		core_mesh.material = _engine_core_material
		core.mesh = core_mesh
		core.position = Vector3(engine_plane + .015, engine_y, bounds.get_center().z + span.z * lateral)
		effects.add_child(core)
	var engine_light := OmniLight3D.new()
	engine_light.name = "IonDriveGlow"
	engine_light.position = Vector3(engine_plane + plume_length * .55, engine_y, bounds.get_center().z)
	engine_light.light_color = Color("5bdcff")
	engine_light.light_energy = 3.6
	engine_light.omni_range = maxf(span.x * .36, .9)
	effects.add_child(engine_light)


func _ensure_engine_materials() -> void:
	if _engine_core_material == null:
		_engine_core_material = StandardMaterial3D.new()
		_engine_core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_engine_core_material.albedo_color = Color("efffff")
		_engine_core_material.emission_enabled = true
		_engine_core_material.emission = Color("d5f8ff")
		_engine_core_material.emission_energy_multiplier = 8.0
	if _engine_plume_material == null:
		_engine_plume_material = StandardMaterial3D.new()
		_engine_plume_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_engine_plume_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_engine_plume_material.albedo_color = Color("168dff", .86)
		_engine_plume_material.emission_enabled = true
		_engine_plume_material.emission = Color("0b8dff")
		_engine_plume_material.emission_energy_multiplier = 5.5


func _ship_mesh_bounds(root: Node3D) -> AABB:
	var points: Array[Vector3] = []
	for child in root.get_children():
		_collect_ship_mesh_points(child, Transform3D.IDENTITY, points)
	if points.is_empty():
		return AABB(Vector3(-1.0, -.35, -.7), Vector3(2.0, .7, 1.4))
	var minimum := points[0]
	var maximum := points[0]
	for point in points:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return AABB(minimum, maximum - minimum)


func _collect_ship_mesh_points(node: Node, parent_transform: Transform3D, points: Array[Vector3]) -> void:
	var local_transform := parent_transform
	if node is Node3D:
		local_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			var aabb := mesh_instance.mesh.get_aabb()
			for x in [aabb.position.x, aabb.end.x]:
				for y in [aabb.position.y, aabb.end.y]:
					for z in [aabb.position.z, aabb.end.z]:
						points.append(local_transform * Vector3(x, y, z))
	for child in node.get_children():
		_collect_ship_mesh_points(child, local_transform, points)


func _hero_glb_path(ship_kind: String) -> String:
	match ship_kind:
		"포격": return VOYAGE_LOD_ROOT + "artillery_ship.glb"
		"강습": return VOYAGE_LOD_ROOT + "assault_carrier.glb"
		"전자": return VOYAGE_LOD_ROOT + "electronic_ship.glb"
		"공성": return VOYAGE_LOD_ROOT + "siege_ship.glb"
		"보급": return VOYAGE_LOD_ROOT + "supply_ship.glb"
		_: return VOYAGE_LOD_ROOT + "line_ship.glb"


func _ship_kind_label(ship_kind: String) -> String:
	match ship_kind:
		"포격": return "포격함"
		"강습": return "강습항모"
		"전자": return "전자전함"
		"공성": return "공성함"
		"보급": return "보급함"
		_: return "전열함"


func _squadron_ship_kinds(fleet) -> Array[String]:
	var weights: Array = Economy.PLANS.get(String(fleet.plan), Economy.PLANS[Economy.PLAN_DEFAULT])
	var total_weight := 0
	for weight in weights:
		total_weight += maxi(int(weight), 0)
	var counts: Dictionary = {}
	var remainders: Array = []
	var assigned := 0
	for index in range(Economy.SHIP_KINDS.size()):
		var kind: String = Economy.SHIP_KINDS[index]
		var weighted := OBSERVATION_SHIP_COUNT * maxi(int(weights[index]), 0)
		var count := int(weighted / total_weight) if total_weight > 0 else 0
		counts[kind] = count
		assigned += count
		remainders.append({"kind": kind, "remainder": weighted % total_weight, "index": index})
	remainders.sort_custom(func(a, b):
		if int(a["remainder"]) == int(b["remainder"]):
			return int(a["index"]) < int(b["index"])
		return int(a["remainder"]) > int(b["remainder"]))
	for index in range(OBSERVATION_SHIP_COUNT - assigned):
		var kind: String = String(remainders[index]["kind"])
		counts[kind] = int(counts[kind]) + 1
	var result: Array[String] = []
	for kind in Economy.SHIP_KINDS:
		for _ship_index in range(int(counts.get(kind, 0))):
			result.append(kind)
	return _role_ordered_squadron_kinds(result)


func _squadron_composition_label(ship_kinds: Array[String]) -> String:
	var counts: Dictionary = {}
	for kind in ship_kinds:
		counts[kind] = int(counts.get(kind, 0)) + 1
	var parts: Array[String] = []
	for kind in Economy.SHIP_KINDS:
		var count := int(counts.get(kind, 0))
		if count > 0:
			parts.append("%s %d" % [_ship_kind_label(kind), count])
	return " · ".join(parts)


func _formation_positions_by_role(ship_kinds: Array[String], formation: String) -> Array[Vector3]:
	# 사용자가 지정한 어린진: 전열함이 선두·양익을 감싸고, 중앙에 포격·강습·전자전을
	# 두며 공성·보급은 후방 열에서 지원한다. 같은 역할의 배치 좌표는 항상 같다.
	var layout: Array[Vector3] = [
		Vector3(0.0, .12, 0.0),
		Vector3(-.72, .0, -.78),
		Vector3(-4.0, -.08, -1.58), Vector3(-2.4, .08, -1.58), Vector3(-.8, .0, -1.58),
		Vector3(.8, .0, -1.58), Vector3(2.4, .08, -1.58), Vector3(4.0, -.08, -1.58),
		Vector3(-4.0, .08, -2.65), Vector3(-2.4, -.04, -2.65), Vector3(-.8, .04, -2.65),
		Vector3(.8, .04, -2.65), Vector3(2.4, -.04, -2.65), Vector3(4.0, .08, -2.65),
		Vector3(-4.0, -.08, -3.72), Vector3(-2.4, .04, -3.72), Vector3(-.8, .0, -3.72),
		Vector3(.8, .0, -3.72), Vector3(2.4, .04, -3.72), Vector3(4.0, -.08, -3.72),
		Vector3(-4.5, .05, -4.79), Vector3(-3.0, -.05, -4.79), Vector3(-1.5, .04, -4.79),
		Vector3(0.0, 0.0, -4.79), Vector3(1.5, .04, -4.79), Vector3(3.0, -.05, -4.79),
		Vector3(4.5, .05, -4.79), Vector3(0.0, .1, -5.86),
	]
	if formation != "어린진" or ship_kinds.size() != layout.size():
		var original: Array[Vector3] = []
		for index in ship_kinds.size():
			original.append(_formation_position(index, formation))
		return original
	return layout


func _role_ordered_squadron_kinds(ship_kinds: Array[String]) -> Array[String]:
	# 도식의 각 칸: 전열 11 · 포격 6 · 강습 4 · 전자 3 · 공성 1 · 보급 3.
	var layout_roles: Array[String] = [
		"전열", "전열",
		"전열", "포격", "강습", "전자", "전열", "전열",
		"전열", "포격", "강습", "전자", "공성", "전열",
		"전열", "포격", "강습", "포격", "보급", "전열",
		"보급", "포격", "강습", "전자", "포격", "보급", "전열", "전열",
	]
	var remaining: Dictionary = {}
	for kind in ship_kinds:
		remaining[kind] = int(remaining.get(kind, 0)) + 1
	var ordered: Array[String] = []
	for role in layout_roles:
		if int(remaining.get(role, 0)) > 0:
			ordered.append(role)
			remaining[role] = int(remaining[role]) - 1
		else:
			for fallback in Economy.SHIP_KINDS:
				if int(remaining.get(fallback, 0)) > 0:
					ordered.append(fallback)
					remaining[fallback] = int(remaining[fallback]) - 1
					break
	return ordered


func _representative_ship_kind(fleet) -> String:
	if fleet == null or not fleet.has_method("ships_by_kind"):
		return "전열"
	# 봉쇄 유지의 전술 정체성은 전자전 지휘·교란이다. 함대 편제에서 전열함이
	# 수적으로 많더라도 상세 관측의 영웅함은 전자전함을 우선해 보여 준다.
	if String(fleet.plan) == "봉쇄 유지":
		return "전자"
	var by_kind: Dictionary = fleet.ships_by_kind()
	var best_kind := "전열"
	var best_count := -1
	# Stable ordering keeps ties deterministic and favors the line ship by default.
	for kind in Economy.SHIP_KINDS:
		var count := int(by_kind.get(kind, 0))
		if count > best_count:
			best_kind = kind
			best_count = count
	return best_kind


## 제공받은 GLB는 한 장의 백색 재질이라 외곽 실루엣만 읽힌다. 선체 좌표를
## 기준으로 선수 장갑·중앙 지휘부·측면 모듈·후방 추진부를 분리해, 단일 메시도
## 전함의 구획과 방향을 즉시 판독할 수 있게 한다.
func _apply_iron_vanguard_materials(root: Node) -> void:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

varying vec3 ship_position;

void vertex() {
	ship_position = VERTEX;
}

void fragment() {
	vec3 p = ship_position;
	vec3 color = vec3(0.095, 0.145, 0.190); // 기본 선체: 청회색 건메탈

	if (p.x < -0.42) {
		color = vec3(0.34, 0.42, 0.48); // 선수 장갑판
	} else if (p.x > 0.54) {
		color = vec3(0.035, 0.070, 0.105); // 후방 기관·추진부
	} else if (p.y > 0.16) {
		color = vec3(0.17, 0.25, 0.32); // 상부 지휘·포탑 구획
	}

	if (abs(p.z) > 0.26 && p.x > -0.25 && p.x < 0.62) {
		color = vec3(0.21, 0.29, 0.35); // 좌·우 외부 모듈
	}

	// 판넬 격자와 중앙 지휘 레일: 원본에 없는 텍스처 없이도 외장 구획을 판독한다.
	float longitudinal_seam = 1.0 - smoothstep(0.0, 0.026, abs(fract((p.x + 1.0) * 3.15) - 0.5));
	float lateral_seam = 1.0 - smoothstep(0.0, 0.020, abs(fract((p.z + 0.5) * 4.6) - 0.5));
	color *= 1.0 - max(longitudinal_seam, lateral_seam) * 0.42;
	if (p.y > 0.11 && abs(p.z) < 0.075 && p.x > -0.34 && p.x < 0.55) {
		color = vec3(0.025, 0.060, 0.090); // 중앙 지휘 레일
	}
	if (abs(abs(p.z) - 0.32) < 0.018 && p.y > -0.02 && p.x > -0.58 && p.x < 0.46) {
		color = vec3(0.02, 0.52, 0.78); // 현측 항법등
	}

	ALBEDO = color;
	METALLIC = 0.72;
	ROUGHNESS = 0.38;
	if (p.x > 0.74 && p.y < 0.03) {
		EMISSION = vec3(0.0, 0.53, 1.32); // 이온 추진기 청색 발광
	}
}
"""
	var armor := ShaderMaterial.new()
	armor.shader = shader
	_apply_iron_vanguard_material_to_meshes(root, armor)


func _apply_iron_vanguard_material_to_meshes(root: Node, armor: Material) -> void:
	for child in root.get_children():
		_apply_iron_vanguard_material_to_meshes(child, armor)
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface in mesh_instance.mesh.get_surface_count():
				mesh_instance.set_surface_override_material(surface, armor)


## 단일 메시의 패널 정보를 게임 안에서 읽을 수 있게 하는 영웅 관측용 외장.
## 원본 함체의 윤곽을 가리지 않으며, 각 모듈은 독립된 금속/발광 재질을 쓴다.
func _attach_iron_vanguard_exterior_modules(ship: Node3D) -> void:
	var hull := _iron_vanguard_mesh_root(ship)
	if hull == null:
		return
	var dark_machinery := _vanguard_metal(Color("101d29"), .82, .42)
	var cyan_engine := _vanguard_emissive(Color("20c9ff"), 4.0)

	# 후방 삼연 이온 추진기: 검은 노즐과 청색 발광 코어를 분리한다.
	for side in [-.22, 0.0, .22]:
		_add_vanguard_cylinder(hull, "Ion engine housing", Vector3(.91, -.06, side),
			.087, .12, dark_machinery, Vector3(0, 0, 90))
		_add_vanguard_cylinder(hull, "Ion engine core", Vector3(.975, -.06, side),
			.060, .018, cyan_engine, Vector3(0, 0, 90))


func _iron_vanguard_mesh_root(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root as MeshInstance3D
	for child in root.get_children():
		var mesh_root := _iron_vanguard_mesh_root(child)
		if mesh_root != null:
			return mesh_root
	return null


func _vanguard_metal(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _vanguard_emissive(color: Color, energy: float) -> StandardMaterial3D:
	var material := _vanguard_metal(color, .25, .18)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


func _add_vanguard_cylinder(parent: Node3D, label: String, position: Vector3,
		radius: float, height: float, material: Material, rotation: Vector3) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
	var module := MeshInstance3D.new()
	module.name = label
	module.mesh = mesh
	module.material_override = material
	module.position = position
	module.rotation_degrees = rotation
	parent.add_child(module)


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
	# 함께 항행하는 관점으로 고정된 성운 위를 별 입자가 뒤로 흘러간다.
	_formation.position = Vector3.ZERO
	_formation.rotation = Vector3.ZERO
	_advance_travel_starfield(delta)
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
	# 성운 파노라마는 고정한다. 전진감은 별 입자의 원근 이동으로만 표현한다.
	if _environment != null:
		_environment.sky_rotation = Vector3.ZERO


func _build_travel_starfield(world: Node3D) -> void:
	_travel_star_rng.seed = 3103
	var field := Node3D.new()
	field.name = "ForwardTravelStarfield"
	world.add_child(field)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(.055, .055)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = Color("c9efff", .7)
	material.emission_enabled = true
	material.emission = Color("83dcff")
	material.emission_energy_multiplier = 1.4
	mesh.material = material
	for index in 72:
		var star := MeshInstance3D.new()
		star.name = "TravelStar%d" % index
		star.mesh = mesh
		star.position = _new_travel_star_position()
		star.set_meta("travel_speed", _travel_star_rng.randf_range(3.2, 6.4))
		star.scale = Vector3.ONE * _travel_star_rng.randf_range(.55, 1.45)
		field.add_child(star)
		_travel_stars.append(star)


func _new_travel_star_position() -> Vector3:
	return Vector3(
		_travel_star_rng.randf_range(-11.0, 11.0),
		_travel_star_rng.randf_range(-6.0, 8.0),
		_travel_star_rng.randf_range(-34.0, -10.0))


func _advance_travel_starfield(delta: float) -> void:
	var clock_speed := float(campaign.world.clock.speed)
	for star in _travel_stars:
		var position := star.position
		var step := float(star.get_meta("travel_speed", 4.0)) * clock_speed * delta
		# 원근상 화면 바깥으로 퍼지며 카메라 쪽으로 다가오는 별: 함대는 정지해도
		# 우주가 후방으로 밀려나는 전진 감각을 만든다.
		position.x += position.x * step * .055
		position.y += position.y * step * .055
		position.z += step
		if position.z > -7.0 or abs(position.x) > 18.0 or abs(position.y) > 12.0:
			position = _new_travel_star_position()
		star.position = position


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
