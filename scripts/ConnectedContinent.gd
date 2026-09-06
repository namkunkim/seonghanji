extends Node2D
class_name ConnectedContinent

const WORLD_SIZE: Vector2 = Vector2(3200.0, 1800.0)
const TERRAIN_VIEWPORT_SIZE: Vector2i = Vector2i(1600, 900)

var debug_magenta: bool = false
var _fallbacks: Array[Polygon2D] = []
var _viewports: Array[SubViewport] = []

func build(terrain: Dictionary) -> void:
    z_index = -60
    _build_base_galactic_terrain(terrain)
    # The base shader owns both soft political colour and the shared distorted
    # silhouette. A second Polygon2D tint produced hard elliptical cut lines.
    # The unified terrain shader owns dust, Qinling and Yangtze in one world UV.
    # The retired segmented layers created a visible purple band and repeated
    # cellular noise instead of one continuous strategic geography.
    _build_debug_fallbacks()

func _build_base_galactic_terrain(terrain: Dictionary) -> void:
    var viewport: SubViewport = _make_viewport(TERRAIN_VIEWPORT_SIZE, false)
    var rect: ColorRect = _make_shader_rect(
        TERRAIN_VIEWPORT_SIZE,
        "res://shaders/BaseGalacticTerrain.gdshader"
    )
    var material := rect.material as ShaderMaterial
    for region_id in ["wei", "shu", "wu", "neutral"]:
        material.set_shader_parameter("%s_region" % region_id, _region_uniform(terrain, region_id))
    material.set_shader_parameter("qinling_points", _feature_uniform(terrain.get("qinling", {})))
    material.set_shader_parameter("yangtze_points", _feature_uniform(terrain.get("yangtze", {})))
    viewport.add_child(rect)
    _add_world_sprite(viewport.get_texture(), WORLD_SIZE * 0.5, WORLD_SIZE, -58)

func _region_uniform(terrain: Dictionary, region_id: String) -> Vector4:
    for region in terrain.get("regions", []):
        if str(region.get("id", "")) != region_id:
            continue
        var center := Vector2(float(region.center[0]), float(region.center[1])) / WORLD_SIZE
        var radius := Vector2(float(region.radius[0]), float(region.radius[1])) / WORLD_SIZE
        return Vector4(center.x, center.y, radius.x, radius.y)
    return Vector4(0.5, 0.5, 0.01, 0.01)

func _feature_uniform(feature: Dictionary) -> PackedVector2Array:
    var normalized := PackedVector2Array()
    for raw_point in feature.get("points", []):
        normalized.append(Vector2(float(raw_point[0]), float(raw_point[1])) / WORLD_SIZE)
    while normalized.size() < 7:
        normalized.append(normalized[-1] if not normalized.is_empty() else Vector2.ZERO)
    return normalized

func _build_strategic_dust() -> void:
    var zones: Array[Dictionary] = [
        {"center":Vector2(860.0, 1210.0), "size":Vector2(760.0, 390.0), "seed":2.0, "color":Color("#316E55"), "intensity":0.42},
        {"center":Vector2(1460.0, 980.0), "size":Vector2(1050.0, 430.0), "seed":5.0, "color":Color("#416D87"), "intensity":0.50},
        {"center":Vector2(1960.0, 1110.0), "size":Vector2(1180.0, 430.0), "seed":8.0, "color":Color("#5A8292"), "intensity":0.54},
        {"center":Vector2(2500.0, 1120.0), "size":Vector2(880.0, 430.0), "seed":11.0, "color":Color("#8B554D"), "intensity":0.60},
        {"center":Vector2(1810.0, 510.0), "size":Vector2(1560.0, 450.0), "seed":14.0, "color":Color("#496D8A"), "intensity":0.28}
    ]
    for zone in zones:
        var zone_data: Dictionary = zone
        var viewport: SubViewport = _make_viewport(Vector2i(720, 420), true)
        var rect: ColorRect = _make_shader_rect(Vector2i(720, 420), "res://shaders/StrategicDust.gdshader")
        var material: ShaderMaterial = rect.material as ShaderMaterial
        material.set_shader_parameter("seed", float(zone_data["seed"]))
        material.set_shader_parameter("glow_color", zone_data["color"])
        material.set_shader_parameter("intensity", float(zone_data["intensity"]))
        viewport.add_child(rect)
        _add_world_sprite(viewport.get_texture(), zone_data["center"], zone_data["size"], -34)

func _build_qinling(data: Dictionary) -> void:
    var points_data: Array = data.get("points", [])
    if points_data.size() < 2:
        return
    var points: PackedVector2Array = PackedVector2Array()
    for raw_point in points_data:
        var pair: Array = raw_point
        points.append(Vector2(float(pair[0]), float(pair[1])))

    for index in range(points.size() - 1):
        var a: Vector2 = points[index]
        var b: Vector2 = points[index + 1]
        var segment_length: float = a.distance_to(b)
        var world_width: float = 420.0
        if index <= 1:
            world_width = 560.0
        elif index == 2:
            world_width = 280.0
        elif index >= 5:
            world_width = 330.0

        var viewport: SubViewport = _make_viewport(Vector2i(960, 360), true)
        var rect: ColorRect = _make_shader_rect(Vector2i(960, 360), "res://shaders/QinlingTerrain.gdshader")
        var material: ShaderMaterial = rect.material as ShaderMaterial
        material.set_shader_parameter("segment_phase", float(index) * 1.73)
        material.set_shader_parameter("pass_position", 0.50 if index == 2 else 0.36)
        material.set_shader_parameter("pass_strength", 0.96 if index == 2 else 0.34)
        material.set_shader_parameter("western_mass", 1.18 if index <= 1 else 0.82)
        material.set_shader_parameter("eastern_fracture", 0.80 if index >= 4 else 0.28)
        viewport.add_child(rect)

        var sprite: Sprite2D = _add_world_sprite(
            viewport.get_texture(),
            (a + b) * 0.5 + Vector2(0.0, 8.0),
            Vector2(segment_length * 1.44, world_width),
            -29
        )
        sprite.rotation = (b - a).angle()

func _build_yangtze(data: Dictionary) -> void:
    var points_data: Array = data.get("points", [])
    if points_data.size() < 2:
        return
    var points: PackedVector2Array = PackedVector2Array()
    for raw_point in points_data:
        var pair: Array = raw_point
        points.append(Vector2(float(pair[0]), float(pair[1])))

    for index in range(points.size() - 1):
        var a: Vector2 = points[index]
        var b: Vector2 = points[index + 1]
        var segment_length: float = a.distance_to(b)
        var basin_boost: float = 0.0
        var width: float = 360.0
        if index in [2, 3, 4]:
            basin_boost = 1.0
            width = 520.0
        elif index == 5:
            basin_boost = 0.65
            width = 470.0

        var viewport: SubViewport = _make_viewport(Vector2i(960, 360), true)
        var rect: ColorRect = _make_shader_rect(Vector2i(960, 360), "res://shaders/YangtzeVolume.gdshader")
        var material: ShaderMaterial = rect.material as ShaderMaterial
        material.set_shader_parameter("phase", float(index) * 1.21)
        material.set_shader_parameter("basin_boost", basin_boost)
        material.set_shader_parameter("valley_strength", 1.16 if index in [2, 3, 4] else 0.92)
        viewport.add_child(rect)

        var sprite: Sprite2D = _add_world_sprite(
            viewport.get_texture(),
            (a + b) * 0.5,
            Vector2(segment_length * 1.56, width),
            -25
        )
        sprite.rotation = (b - a).angle()

func _make_viewport(size: Vector2i, transparent: bool) -> SubViewport:
    var viewport: SubViewport = SubViewport.new()
    viewport.size = size
    viewport.transparent_bg = transparent
    viewport.disable_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    add_child(viewport)
    _viewports.append(viewport)
    return viewport

func _make_shader_rect(size: Vector2i, shader_path: String) -> ColorRect:
    var rect: ColorRect = ColorRect.new()
    rect.size = Vector2(size)
    rect.color = Color.WHITE
    rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var material: ShaderMaterial = ShaderMaterial.new()
    var shader_resource: Shader = load(shader_path)
    material.shader = shader_resource
    rect.material = material
    return rect

func _add_world_sprite(texture: Texture2D, center: Vector2, world_size: Vector2, layer_z: int) -> Sprite2D:
    var sprite: Sprite2D = Sprite2D.new()
    sprite.texture = texture
    sprite.position = center
    sprite.centered = true
    sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    var texture_size: Vector2 = texture.get_size()
    sprite.scale = Vector2(world_size.x / texture_size.x, world_size.y / texture_size.y)
    sprite.z_index = layer_z
    add_child(sprite)
    return sprite

func _build_debug_fallbacks() -> void:
    var specs: Array[Dictionary] = [
        {"center":WORLD_SIZE * 0.5, "size":WORLD_SIZE, "z":-57},
        {"center":Vector2(1380.0, 820.0), "size":Vector2(1850.0, 390.0), "z":-28},
        {"center":Vector2(2080.0, 1280.0), "size":Vector2(2200.0, 470.0), "z":-24}
    ]
    for spec in specs:
        var spec_data: Dictionary = spec
        var fallback: Polygon2D = Polygon2D.new()
        fallback.position = spec_data["center"]
        fallback.polygon = _rect_poly(spec_data["size"])
        fallback.color = Color(1.0, 0.0, 1.0, 0.16)
        fallback.visible = debug_magenta
        fallback.z_index = int(spec_data["z"])
        add_child(fallback)
        _fallbacks.append(fallback)

func _rect_poly(size: Vector2) -> PackedVector2Array:
    var half_width: float = size.x * 0.5
    var half_height: float = size.y * 0.5
    return PackedVector2Array([
        Vector2(-half_width, -half_height),
        Vector2(half_width, -half_height),
        Vector2(half_width, half_height),
        Vector2(-half_width, half_height)
    ])

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey:
        var key_event: InputEventKey = event as InputEventKey
        if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F9:
            debug_magenta = not debug_magenta
            for fallback in _fallbacks:
                fallback.visible = debug_magenta
