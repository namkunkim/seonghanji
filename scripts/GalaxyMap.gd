extends Node2D
class_name GalaxyMap

signal object_selected(data: Dictionary)
signal zoom_level_changed(level: int)

var world_size: Vector2 = Vector2(3200, 1800)
var camera: Camera2D
var input_safe_rect: Rect2 = Rect2(220.0,76.0,1070.0,634.0)
var systems: Array = []
var fleets: Array = []
var terrain_data: Dictionary = {}
var scenario_regions: Array = []
var canonical_routes: Array = []
var canonical_bodies: Array = []
var active_battles: Array = []
var external_powers: Array = []
var faction_colors: Dictionary = {
    "조조": Color("#1E91FF"), "손권": Color("#F24E3E"),
    "유종": Color("#A875E8"), "유장": Color("#19E082"),
    "장로": Color("#45C8D8"), "마등한수": Color("#D8A144"),
    "사섭": Color("#ED8B52"), "공손강": Color("#70E4FF"),
    "neutral": Color("#D8A144")
}

var dragging: bool = false
var last_mouse: Vector2 = Vector2.ZERO
var fleet_time: float = 0.0
var semantic_level: int = 1
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _minor_systems: Array[Dictionary] = []
var _local_routes: Array[PackedVector2Array] = []
var _dust_motes: Array[Dictionary] = []
var _asteroids: Array[Dictionary] = []
var _stars: Array[Dictionary] = []

const MIN_ZOOM := 0.20
const MAX_ZOOM := 1.80
const OVERVIEW_PADDING := 0.97
var overview_zoom: float = 0.35
const OVERVIEW_SYSTEM_NAMES := {}
const CAPITAL_LABEL_OFFSETS := {
    "SYS-01": Vector2(-86,-58), "SYS-09": Vector2(-100,-38),
    "SYS-11": Vector2(-110,48), "SYS-12": Vector2(-92,-42),
    "SYS-13": Vector2(44,52), "SYS-15": Vector2(42,48),
    "SYS-17": Vector2(-82,-34), "SYS-18": Vector2(-112,46),
}
const FACTION_LABEL_OFFSETS := {
    "조조": Vector2(150,-125), "손권": Vector2(120,90),
    "유종": Vector2(85,100), "유장": Vector2(-145,82),
    "장로": Vector2(-250,-210), "마등한수": Vector2(-145,-72),
    "사섭": Vector2(90,72), "공손강": Vector2(-280,220),
}
const SOLAR_BODY_SCREEN_OFFSETS := {
    "구지": Vector2.ZERO,
    "형혹": Vector2(120,-58),
    "태음": Vector2(-100,62),
}

func setup(cam: Camera2D, systems_data: Array, fleet_data: Array, terrain: Dictionary,
        regions: Array = [], routes: Array = [], bodies: Array = [], battles: Array = [],
        powers: Array = []) -> void:
    camera = cam
    systems = systems_data
    fleets = fleet_data
    terrain_data = terrain
    scenario_regions = regions
    canonical_routes = routes
    canonical_bodies = bodies
    active_battles = battles
    external_powers = powers
    _prepare_static_geometry()
    queue_redraw()

func set_input_safe_rect(rect: Rect2) -> void:
    input_safe_rect = rect
    var previous_overview := overview_zoom
    var was_overview := semantic_level == 1
    if camera != null:
        was_overview = was_overview or camera.zoom.x <= previous_overview + 0.02
    overview_zoom = maxf(MIN_ZOOM, minf(rect.size.x / world_size.x,
        rect.size.y / world_size.y) * OVERVIEW_PADDING)
    if camera == null:
        return
    # A resize can move the semantic thresholds. Re-evaluate with the new
    # overview zoom so the selected card and the actual camera never disagree.
    if was_overview or _semantic_level_for_zoom(camera.zoom.x) == 1:
        focus_overview()
    else:
        _clamp_camera_position()

func focus_overview() -> void:
    if camera == null:
        return
    camera.zoom = Vector2(overview_zoom, overview_zoom)
    var viewport_center := get_viewport().get_visible_rect().size * 0.5
    var safe_center := input_safe_rect.get_center()
    camera.position = world_size * 0.5 - (safe_center - viewport_center) / overview_zoom
    # Layout and stage-card jumps must land on the safe-area composition in the
    # same frame. Otherwise Camera2D smoothing briefly exposes the clear color.
    camera.reset_smoothing()
    semantic_level = 1
    zoom_level_changed.emit(semantic_level)

func _prepare_static_geometry() -> void:
    _rng.seed = 20260905

    # StarClusterLayer is the single active owner of background stars. Keep this
    # legacy cache empty so GalaxyMap cannot accidentally duplicate that layer.
    _stars.clear()

    # Fine dust layer
    _dust_motes.clear()
    for i in range(420):
        _dust_motes.append({
            "p": Vector2(_rng.randf_range(0.0, world_size.x), _rng.randf_range(0.0, world_size.y)),
            "r": _rng.randf_range(1.0, 5.5),
            "a": _rng.randf_range(0.012, 0.06)
        })

    # The home map does not invent decorative gameplay nodes. All selectable
    # systems and routes come from the canonical snapshot.
    _minor_systems.clear()
    _local_routes.clear()

    # StrategicDebrisLayer is the single active owner of debris fields.
    _asteroids.clear()

func _process(delta: float) -> void:
    fleet_time += delta
    if dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
        dragging = false
    if camera:
        _clamp_camera_position()
        var new_level: int = _semantic_level_for_zoom(camera.zoom.x)
        if new_level != semantic_level:
            semantic_level = new_level
            zoom_level_changed.emit(semantic_level)
    queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
        var was_dragging := dragging
        dragging = false
        if was_dragging and input_safe_rect.has_point(event.position):
            _try_select(event.position)
        return
    if event is InputEventMouseButton and not input_safe_rect.has_point(event.position):
        return
    if event is InputEventMouseMotion and not dragging and not input_safe_rect.has_point(event.position):
        return
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
            _zoom_at(1.14, event.position)
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
            _zoom_at(0.88, event.position)
        elif event.button_index == MOUSE_BUTTON_LEFT:
            dragging = true
            last_mouse = event.position
    elif event is InputEventMouseMotion and dragging:
        var delta: Vector2 = event.position - last_mouse
        camera.position -= delta / camera.zoom.x
        _clamp_camera_position()
        last_mouse = event.position

func _zoom_at(factor: float, screen_pos: Vector2) -> void:
    if camera == null: return
    var before: Vector2 = get_canvas_transform().affine_inverse() * screen_pos
    camera.zoom *= Vector2(factor, factor)
    camera.zoom.x = clamp(camera.zoom.x, overview_zoom, MAX_ZOOM)
    camera.zoom.y = camera.zoom.x
    var after: Vector2 = get_canvas_transform().affine_inverse() * screen_pos
    camera.position += before - after
    _clamp_camera_position()

func focus_world(pos: Vector2, zoom_value: float) -> void:
    if camera == null: return
    var clamped_zoom := clampf(zoom_value, overview_zoom, MAX_ZOOM)
    camera.zoom = Vector2(clamped_zoom, clamped_zoom)
    var viewport_center := get_viewport().get_visible_rect().size * 0.5
    var safe_center := input_safe_rect.position + input_safe_rect.size * 0.5
    camera.position = pos - (safe_center - viewport_center) / clamped_zoom
    _clamp_camera_position()

func _try_select(screen_pos: Vector2) -> void:
    var world_pos: Vector2 = get_canvas_transform().affine_inverse() * screen_pos
    var best: Dictionary = {}
    var best_d: float = 50.0
    for s in systems:
        var p: Vector2 = Vector2(float(s.pos[0]), float(s.pos[1]))
        var d: float = p.distance_to(world_pos)
        if d < best_d:
            best_d = d
            best = s
    if not best.is_empty():
        object_selected.emit(best)
        focus_world(Vector2(float(best.pos[0]), float(best.pos[1])), 0.9)

func _draw() -> void:
    # ConnectedContinent owns the continuous geography. Low-resolution polygon
    # clouds must not cover the sculpted shader terrain at the home-map zoom.
    _draw_scenario_regions()
    _draw_geography_labels()
    _draw_minor_routes()
    _draw_regional_routes()
    _draw_major_routes()
    _draw_minor_systems()
    _draw_major_systems()
    _draw_hierarchy_markers()
    _draw_external_gateways()
    _draw_fleets()
    _draw_faction_labels()
    _draw_contested_arrows()
    if semantic_level >= 5:
        _draw_ship_silhouette()

func _draw_background_stars() -> void:
    for s in _stars:
        var p: Vector2 = s["p"]
        var r: float = float(s["r"])
        var a: float = float(s["a"])
        var col: Color = Color(0.65,0.82,1.0,a)
        if bool(s["warm"]):
            col = Color(1.0,0.82,0.55,a)
        draw_circle(p,r,col)

func _draw_dust() -> void:
    for d in _dust_motes:
        var p: Vector2 = d["p"]
        var r: float = float(d["r"])
        var a: float = float(d["a"])
        draw_circle(p,r,Color(0.70,0.78,0.88,a))

func _draw_macro_nebulae() -> void:
    var regions: Array = terrain_data.get("regions",[])
    for region in regions:
        var center: Vector2 = Vector2(float(region.center[0]),float(region.center[1]))
        var radius: Vector2 = Vector2(float(region.radius[0]),float(region.radius[1]))
        var base: Color = Color("#"+str(region.color))
        var seed: int = int(center.x*3.0 + center.y*7.0)

        # Broad diffuse base
        _draw_irregular_cloud_field(center,radius,base,42,seed,0.035,0.085)

        # Dark internal cavities: "valleys" and molecular clouds
        var dark: Color = Color(0.01,0.02,0.035,1.0)
        _draw_irregular_cloud_field(center,radius*0.88,dark,14,seed+941,0.025,0.060)

        # Brighter ridges around navigable clusters
        _draw_luminous_ridges(center,radius,base,seed+77)

func _draw_irregular_cloud_field(center: Vector2, radius: Vector2, color: Color, count: int, seed_value: int, alpha_min: float, alpha_max: float) -> void:
    _rng.seed = seed_value
    for i in range(count):
        var ang: float = _rng.randf_range(0.0,TAU)
        var rr: float = sqrt(_rng.randf())
        var p: Vector2 = center + Vector2(cos(ang)*radius.x*rr,sin(ang)*radius.y*rr)
        var cloud_r: float = _rng.randf_range(90.0,230.0)
        var sx: float = _rng.randf_range(0.75,1.65)
        var sy: float = _rng.randf_range(0.55,1.30)
        var pts: PackedVector2Array = []
        var n: int = 28
        for k in range(n):
            var a: float = TAU*float(k)/float(n)
            var wobble: float = 0.84 + _rng.randf()*0.26
            pts.append(p + Vector2(cos(a)*cloud_r*sx*wobble,sin(a)*cloud_r*sy*wobble))
        var alpha: float = _rng.randf_range(alpha_min,alpha_max)
        draw_colored_polygon(pts,Color(color.r,color.g,color.b,alpha))

func _draw_luminous_ridges(center: Vector2, radius: Vector2, base: Color, seed_value: int) -> void:
    _rng.seed = seed_value
    for i in range(17):
        var pts: PackedVector2Array = []
        var start_ang: float = _rng.randf_range(0.0,TAU)
        var base_rr: float = _rng.randf_range(0.25,0.88)
        for k in range(7):
            var a: float = start_ang + float(k)*_rng.randf_range(0.07,0.17)
            var rr: float = base_rr + sin(float(k)*1.7 + float(i))*0.06
            pts.append(center + Vector2(cos(a)*radius.x*rr,sin(a)*radius.y*rr))
        draw_polyline(pts,Color(base.r*1.18,base.g*1.18,base.b*1.18,0.13),_rng.randf_range(2.0,7.0),true)

func _draw_dark_clouds() -> void:
    # Large star-poor voids and cloud lanes
    _rng.seed = 558812
    for i in range(34):
        var p: Vector2 = Vector2(_rng.randf_range(800,3050),_rng.randf_range(120,1550))
        var rad: float = _rng.randf_range(70,210)
        draw_circle(p,rad,Color(0.0,0.01,0.02,_rng.randf_range(0.03,0.10)))

func _draw_qinling() -> void:
    var data: Dictionary = terrain_data.get("qinling",{})
    var base_pts: PackedVector2Array = []
    for a in data.get("points",[]):
        base_pts.append(Vector2(float(a[0]),float(a[1])))
    if base_pts.size() < 2: return

    # Mountain body: hundreds of irregular cloud masses around polyline
    _rng.seed = 99110
    for i in range(120):
        var t: float = _rng.randf()
        var p: Vector2 = _point_on_path(base_pts,t)
        var tangent: Vector2 = _path_tangent(base_pts,t)
        var normal: Vector2 = Vector2(-tangent.y,tangent.x).normalized()
        p += normal * _rng.randf_range(-95.0,95.0)
        var rad: float = _rng.randf_range(35.0,115.0)
        var pts: PackedVector2Array = _noisy_blob(p,rad,_rng.randf_range(0.70,1.45),_rng.randf_range(0.60,1.18),18)
        var col: Color = Color(0.22,0.15,0.29,_rng.randf_range(0.008,0.025))
        if i % 4 == 0:
            col = Color(0.55,0.38,0.72,_rng.randf_range(0.015,0.035))
        draw_colored_polygon(pts,col)

    # Dark mountain core
    for i in range(55):
        var t2: float = _rng.randf()
        var p2: Vector2 = _point_on_path(base_pts,t2)
        p2 += Vector2(_rng.randf_range(-80,80),_rng.randf_range(-65,65))
        draw_colored_polygon(_noisy_blob(p2,_rng.randf_range(28,78),1.2,.8,16),Color(0.015,0.01,0.025,_rng.randf_range(.015,.04)))

    # luminous ridges
    for offset in [-58.0,-18.0,26.0,66.0]:
        var ridge: PackedVector2Array = []
        for j in range(40):
            var t3: float = float(j)/39.0
            var pp: Vector2 = _point_on_path(base_pts,t3)
            var tan: Vector2 = _path_tangent(base_pts,t3)
            var nor: Vector2 = Vector2(-tan.y,tan.x).normalized()
            pp += nor*(offset + sin(t3*18.0+offset)*9.0)
            ridge.append(pp)
        draw_polyline(ridge,Color(0.72,0.57,0.92,0.12 if offset!=26.0 else 0.28),3.0 if offset!=26.0 else 5.0,true)


func _draw_yangtze() -> void:
    var data: Dictionary = terrain_data.get("yangtze",{})
    var pts: PackedVector2Array = []
    for a in data.get("points",[]):
        pts.append(Vector2(float(a[0]),float(a[1])))
    if pts.size() < 2: return

    # Broad gas valley: many offset flow strands, not one thick line
    _rng.seed = 33321
    for strand in range(26):
        var strand_pts: PackedVector2Array = []
        var offset: float = _rng.randf_range(-115.0,115.0)
        for j in range(48):
            var t: float = float(j)/47.0
            var p: Vector2 = _point_on_path(pts,t)
            var tan: Vector2 = _path_tangent(pts,t)
            var nor: Vector2 = Vector2(-tan.y,tan.x).normalized()
            var wave: float = sin(t*18.0+float(strand))*_rng.randf_range(3.0,14.0)
            strand_pts.append(p+nor*(offset+wave))
        var a_col: float = _rng.randf_range(0.025,0.09)
        draw_polyline(strand_pts,Color(0.38,0.82,1.0,a_col*0.35),_rng.randf_range(3.0,14.0),true)

    # Main route threads
    for off in [-72.0,-28.0,18.0,61.0]:
        var lane: PackedVector2Array = []
        for k in range(42):
            var t2: float = float(k)/41.0
            var pp: Vector2 = _point_on_path(pts,t2)
            var tan2: Vector2 = _path_tangent(pts,t2)
            var nor2: Vector2 = Vector2(-tan2.y,tan2.x).normalized()
            lane.append(pp+nor2*off)
        draw_polyline(lane,Color(0.76,0.95,1.0,0.23),2.2,true)

    # asteroid islands inside the river
    for i in range(95):
        var t3: float = _rng.randf()
        var cp: Vector2 = _point_on_path(pts,t3)
        var tn: Vector2 = _path_tangent(pts,t3)
        var nr: Vector2 = Vector2(-tn.y,tn.x).normalized()
        cp += nr*_rng.randf_range(-110,110)
        draw_circle(cp,_rng.randf_range(2.0,7.5),Color(0.36,0.42,0.50,_rng.randf_range(.18,.55)))


func _draw_minor_routes() -> void:
    return

func _draw_regional_routes() -> void:
    return
func _draw_major_routes() -> void:
    for route in canonical_routes:
        var line := PackedVector2Array()
        for raw in route.get("line", []):
            line.append(Vector2(float(raw[0]), float(raw[1])))
        if line.size() < 2:
            continue
        var strategic := String(route.get("display_policy", "")) == "persistent-strategic"
        var alpha := 0.34 if strategic else (0.11 if semantic_level == 1 else 0.22)
        var width := 2.0 if strategic else 1.0
        var color := Color("8EDCFF")
        var connects: Array = route.get("connects", [])
        if not connects.is_empty() and String(connects[0]).begins_with("EXT:"):
            color = Color("D8B66A")
        draw_polyline(line, Color(color.r, color.g, color.b, alpha), width, true)

func _semantic_level_for_zoom(zoom_value: float) -> int:
    var level_two := maxf(overview_zoom + 0.14, 0.52)
    if zoom_value < level_two:
        return 1
    if zoom_value < 0.82:
        return 2
    if zoom_value < 1.08:
        return 3
    if zoom_value < 1.42:
        return 4
    return 5

func _clamp_camera_position() -> void:
    if camera == null:
        return
    if camera.zoom.x <= overview_zoom + 0.0001:
        var viewport_center := get_viewport().get_visible_rect().size * 0.5
        camera.position = world_size * 0.5 - (input_safe_rect.get_center() - viewport_center) / overview_zoom
        return
    var viewport_size := get_viewport().get_visible_rect().size
    var viewport_center := viewport_size * 0.5
    # canvas screen = viewport_center + (world - camera) * zoom.
    # These bounds place the four world edges exactly on the corresponding
    # map-safe edges, independent of the HUD widths or current zoom.
    var min_position := (viewport_center - input_safe_rect.position) / camera.zoom.x
    var max_position := world_size - (input_safe_rect.end - viewport_center) / camera.zoom.x
    if min_position.x > max_position.x:
        min_position.x = world_size.x * 0.5
        max_position.x = min_position.x
    if min_position.y > max_position.y:
        min_position.y = world_size.y * 0.5
        max_position.y = min_position.y
    camera.position = camera.position.clamp(min_position, max_position)

func _draw_asteroid_fields() -> void:
    if semantic_level < 3: return
    for a in _asteroids:
        var p: Vector2 = a["p"]
        var r: float = float(a["r"])
        var alpha: float = float(a["a"])
        var pts: PackedVector2Array = _noisy_blob(p,r,1.35,0.85,7)
        draw_colored_polygon(pts,Color(0.32,0.37,0.43,alpha))

func _draw_minor_systems() -> void:
    if semantic_level < 2: return
    for s in _minor_systems:
        var p: Vector2 = s["p"]
        var c: Color = faction_colors.get(str(s["f"]),Color.WHITE)
        draw_circle(p,2.4,Color(1.0,0.97,0.82,0.82))
        draw_circle(p,5.5,Color(c.r,c.g,c.b,0.05))

func _draw_major_systems() -> void:
    for s in systems:
        var p: Vector2 = Vector2(float(s.pos[0]),float(s.pos[1]))
        var faction: String = str(s.get("faction","neutral"))
        var c: Color = faction_colors.get(faction,Color.WHITE)
        var r: float = 9.0
        if s.type == "capital": r = 17.0
        elif s.type == "fortress": r = 13.0
        elif s.type == "strategic": r = 11.0
        elif s.type == "battle": r = 15.0
        if semantic_level == 1:
            if s.type == "capital": r *= 1.42
            else: r = 6.0

        draw_circle(p,r*5.8,Color(c.r,c.g,c.b,0.025))
        draw_circle(p,r*3.5,Color(c.r,c.g,c.b,0.055))
        draw_circle(p,r*1.8,Color(c.r,c.g,c.b,0.14))
        draw_circle(p,r,Color(1.0,0.97,0.74,1.0))
        draw_circle(p,r*0.42,Color.WHITE)
        draw_arc(p,r+6,0,TAU,48,c,3.0,true)
        if s.type == "capital":
            draw_arc(p,r+16.0,0,TAU,64,Color(c.r,c.g,c.b,0.62),2.4,true)
            draw_arc(p,r+29.0,0,TAU,64,Color(c.r,c.g,c.b,0.34),1.8,true)
            draw_arc(p,r+43.0,0,TAU,72,Color(0.82,0.94,1.0,0.18),1.3,true)
            for orbit_angle in [0.25, 2.35, 4.45]:
                var satellite := p + Vector2(cos(orbit_angle),sin(orbit_angle)) * (r+29.0)
                draw_circle(satellite,3.2,Color(1.0,0.94,0.66,0.92))
        if semantic_level >= 1:
            _draw_status_icons(p,c,str(s.type))
        if s.type == "battle":
            draw_arc(p,r+13.0,0,TAU,48,Color(1.0,0.55,0.30,0.58),3.0,true)
            draw_line(p+Vector2(-17.0,-17.0),p+Vector2(17.0,17.0),Color(1.0,0.72,0.55,0.68),2.0,true)
            draw_line(p+Vector2(-17.0,17.0),p+Vector2(17.0,-17.0),Color(1.0,0.72,0.55,0.68),2.0,true)

        if semantic_level == 1 and s.type == "capital":
            var overview_name := str(s.name)
            var overview_kind := str(s.type)
            var overview_size := _overview_label_size(overview_kind)
            var overview_width := ThemeDB.fallback_font.get_string_size(overview_name,HORIZONTAL_ALIGNMENT_LEFT,-1,overview_size).x
            var label_pos: Vector2 = p + CAPITAL_LABEL_OFFSETS.get(String(s.get("id", "")), Vector2(r+14.0,9.0))
            var node_screen := get_canvas_transform() * p
            if node_screen.x > input_safe_rect.end.x-180.0:
                label_pos.x = p.x-overview_width-r-14.0
            _draw_overview_system_label(overview_name,label_pos,overview_kind,c)
        elif semantic_level == 2:
            _draw_label(str(s.name),p+Vector2(r+12.0,7.0),22 if s.type != "capital" else 28,Color.WHITE)

func _draw_status_icons(p: Vector2, c: Color, kind: String) -> void:
    # Compact ownership / facility / warning glyphs make systems read as game state.
    var icon_a := p + Vector2(-30.0,-28.0)
    var diamond := PackedVector2Array([icon_a+Vector2(0,-6),icon_a+Vector2(6,0),icon_a+Vector2(0,6),icon_a+Vector2(-6,0)])
    draw_colored_polygon(diamond,Color(c.r,c.g,c.b,0.78))
    draw_polyline(diamond,Color(0.92,0.98,1.0,0.90),1.2,true)
    var icon_b := p + Vector2(30.0,-28.0)
    draw_rect(Rect2(icon_b-Vector2(5,5),Vector2(10,10)),Color(0.03,0.08,0.12,0.88),true)
    draw_rect(Rect2(icon_b-Vector2(5,5),Vector2(10,10)),Color(0.72,0.90,1.0,0.80),false,1.2)
    if kind in ["fortress","battle"]:
        var warning := p + Vector2(0.0,34.0)
        draw_line(warning+Vector2(-6,5),warning+Vector2(0,-7),Color(1.0,0.58,0.27,0.86),2.0,true)
        draw_line(warning+Vector2(0,-7),warning+Vector2(6,5),Color(1.0,0.58,0.27,0.86),2.0,true)
        draw_line(warning+Vector2(6,5),warning+Vector2(-6,5),Color(1.0,0.58,0.27,0.86),2.0,true)
func _draw_fleets() -> void:
    if semantic_level < 3: return
    for f in fleets:
        var path: Array = f.path
        var pts: PackedVector2Array = []
        for a in path:
            pts.append(Vector2(float(a[0]),float(a[1])))
        draw_polyline(pts,Color(1,1,1,0.10),2.0,true)

        var t: float = fmod(fleet_time*float(f.speed),1.0)
        var p: Vector2 = _point_on_path(pts,t)
        var c: Color = faction_colors.get(str(f.faction),Color.WHITE)

        draw_circle(p,22.0,Color(c.r,c.g,c.b,0.05))
        var tri: PackedVector2Array = PackedVector2Array([
            p+Vector2(17,0),p+Vector2(-8,-7),p+Vector2(-3,0),p+Vector2(-8,7)
        ])
        draw_colored_polygon(tri,c)

        if semantic_level >= 4:
            _draw_label("%s · %s척" % [f.name,str(f.size)],p+Vector2(22,-12),16,Color.WHITE)
            _draw_fleet_formation(p,c,int(f.size))

func _draw_fleet_formation(center: Vector2, c: Color, size: int) -> void:
    var count: int = int(min(150,max(35,size/100)))
    for i in count:
        var row: int = int(i/17)
        var col: int = i%17
        var x: float = -100.0-float(row)*11.0
        var y: float = float(col-8)*6.5
        draw_circle(center+Vector2(x,y),1.5,Color(c.r,c.g,c.b,0.55))

func _draw_ship_silhouette() -> void:
    var c: Vector2 = Vector2(2860,1170)
    var poly: PackedVector2Array = PackedVector2Array([
        c+Vector2(-190,28),c+Vector2(-95,-38),c+Vector2(50,-34),
        c+Vector2(135,-10),c+Vector2(190,18),c+Vector2(120,54),c+Vector2(-90,60)
    ])
    draw_colored_polygon(poly,Color(0.34,0.42,0.50,0.88))
    draw_polyline(poly,Color(0.72,0.86,0.96,0.75),2.0,true)
    draw_circle(c+Vector2(154,18),9.0,Color(1.0,0.54,0.22,0.85))

func _noisy_blob(center: Vector2, radius: float, sx: float, sy: float, n: int) -> PackedVector2Array:
    var pts: PackedVector2Array = []
    for k in range(n):
        var a: float = TAU*float(k)/float(n)
        var wob: float = 0.72+_rng.randf()*0.50
        pts.append(center+Vector2(cos(a)*radius*sx*wob,sin(a)*radius*sy*wob))
    return pts

func _path_tangent(points: PackedVector2Array, t: float) -> Vector2:
    if points.size()<2: return Vector2.RIGHT
    var segf: float = t*float(points.size()-1)
    var idx: int = min(points.size()-2,int(floor(segf)))
    return (points[idx+1]-points[idx]).normalized()

func _point_on_path(points: PackedVector2Array, t: float) -> Vector2:
    if points.size()<2: return Vector2.ZERO
    var segf: float = t*float(points.size()-1)
    var idx: int = min(points.size()-2,int(floor(segf)))
    var u: float = segf-float(idx)
    return points[idx].lerp(points[idx+1],u)

func _draw_label(text: String, pos: Vector2, size: int, color: Color) -> void:
    var font: Font = ThemeDB.fallback_font
    var draw_size := size
    if semantic_level >= 2:
        var canvas_scale := maxf(0.001, absf(get_canvas_transform().x.x))
        draw_size = maxi(1, roundi(float(size) / canvas_scale))
    pos = _clamp_label_baseline_to_safe_screen(text,pos,draw_size,52.0)
    draw_string(font,pos+Vector2(2,2),text,HORIZONTAL_ALIGNMENT_LEFT,-1,draw_size,Color(0.0,0.0,0.0,0.92))
    draw_string(font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,draw_size,color)

func _draw_overview_system_label(text: String, pos: Vector2, kind: String, faction_color: Color) -> void:
    var font: Font = ThemeDB.fallback_font
    var size: int = _overview_label_size(kind)
    var halo_radius: float = 2.4
    var label_color := Color(0.88,0.94,0.98,0.96)
    if kind == "capital":
        halo_radius = 4.0
        label_color = Color(1.0,0.98,0.86,1.0)
    elif kind == "fortress":
        halo_radius = 3.2
        label_color = Color(0.94,0.97,1.0,1.0)
    elif kind == "battle":
        halo_radius = 3.6
        label_color = Color(1.0,0.78,0.62,1.0)

    # Eight-way dark halo survives the 0.5 overview zoom without becoming a
    # solid nameplate, while the restrained faction tint links label and node.
    var halo_color := Color(0.005,0.012,0.025,0.96)
    for direction in [
        Vector2(-1.0,-1.0),Vector2(0.0,-1.0),Vector2(1.0,-1.0),
        Vector2(-1.0,0.0),Vector2(1.0,0.0),
        Vector2(-1.0,1.0),Vector2(0.0,1.0),Vector2(1.0,1.0)
    ]:
        draw_string(font,pos+direction*halo_radius,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,halo_color)
    draw_string(font,pos+Vector2(1.5,1.5),text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,Color(faction_color.r,faction_color.g,faction_color.b,0.48))
    draw_string(font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,label_color)

func _overview_label_size(kind: String) -> int:
    # World-space font sizes are reduced by the dynamic overview zoom. Keep the
    # resulting screen text near 12-14 px at 1600x900 instead of 8-10 px.
    if kind == "capital": return 40
    if kind == "fortress": return 40
    if kind == "battle": return 40
    return 36

func _clamp_world_point_to_safe_screen(world_pos: Vector2, margin_px: float) -> Vector2:
    var canvas_transform := get_canvas_transform()
    var screen_pos := canvas_transform * world_pos
    var safe_min := input_safe_rect.position+Vector2.ONE*margin_px
    var safe_max := input_safe_rect.end-Vector2.ONE*margin_px
    screen_pos = screen_pos.clamp(safe_min,safe_max)
    return canvas_transform.affine_inverse() * screen_pos

func _clamp_label_baseline_to_safe_screen(text: String, world_pos: Vector2, size: int, margin_px: float) -> Vector2:
    var font: Font = ThemeDB.fallback_font
    var canvas_transform := get_canvas_transform()
    var canvas_scale := maxf(0.001,absf(canvas_transform.x.x))
    var text_size := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size)*canvas_scale
    var ascent := font.get_ascent(size)*canvas_scale
    var descent := font.get_descent(size)*canvas_scale
    var screen_pos := canvas_transform * world_pos
    var min_baseline := input_safe_rect.position+Vector2(margin_px,margin_px+ascent)
    var max_baseline := input_safe_rect.end-Vector2(margin_px+text_size.x,margin_px+descent)
    screen_pos = screen_pos.clamp(min_baseline,max_baseline)
    return canvas_transform.affine_inverse() * screen_pos


func _draw_geography_labels() -> void:
    if semantic_level < 1 or semantic_level > 2:
        return
    _draw_label("진령 성운장벽",Vector2(1330,830),30,Color(0.92,0.84,1.0,0.78))
    _draw_label("장강 우주대",Vector2(1830,1280),30,Color(0.80,0.95,1.0,0.78))
    # Terrain names are deliberately lower priority than scenario state.

func _draw_faction_labels() -> void:
    if semantic_level > 2:
        return
    var sums := {}
    for region in scenario_regions:
        var owner := String(region.get("owner", "neutral"))
        if owner == "neutral":
            continue
        var raw: Array = region.get("position", [])
        if raw.size() < 2:
            continue
        if not sums.has(owner):
            sums[owner] = {"sum": Vector2.ZERO, "count": 0}
        sums[owner]["sum"] += Vector2(float(raw[0]), float(raw[1]))
        sums[owner]["count"] = int(sums[owner]["count"]) + 1
    for owner in sums:
        var center: Vector2 = sums[owner]["sum"] / float(sums[owner]["count"])
        center += FACTION_LABEL_OFFSETS.get(String(owner), Vector2.ZERO)
        _draw_overview_faction_label(_display_faction(String(owner)), center, 46 if semantic_level == 1 else 30,
            faction_colors.get(owner, Color.WHITE))
    _draw_liu_bei_marker()

func _display_faction(raw: String) -> String:
    return "마등·한수" if raw == "마등한수" else raw

func _draw_overview_faction_label(text: String, pos: Vector2, size: int, color: Color) -> void:
    var font: Font = ThemeDB.fallback_font
    pos = _clamp_label_baseline_to_safe_screen(text,pos,size,56.0)
    for offset in [Vector2(-4,0),Vector2(4,0),Vector2(0,-4),Vector2(0,4)]:
        draw_string(font,pos+offset,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,Color(0.0,0.015,0.035,0.86))
    draw_string(font,pos+Vector2(3,4),text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,Color(color.r,color.g,color.b,0.28))
    draw_string(font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,Color(color.r,color.g,color.b,0.96))


func _draw_contested_arrows() -> void:
    for battle in active_battles:
        if String(battle.get("id", "")) != "BATTLE-RED-CLIFF" or String(battle.get("status", "")) != "active":
            continue
        var raw: Array = battle.get("anchor_position", [])
        if raw.size() < 2:
            continue
        var p := Vector2(float(raw[0]) / 37312.0 * world_size.x,
            float(raw[1]) / 30000.0 * world_size.y)
        match _red_cliff_presentation_mode():
            "overview":
                _draw_screen_arc(p, 16.0, Color("FF9A72"), 2.0)
            "rally":
                _draw_screen_arc(p, 22.0, Color("F2B95D"), 3.0)
                _draw_label("적벽 집결", p + _screen_delta(Vector2(48,58)), 18, Color("FFE2A6"))
            "forecast":
                _draw_screen_arc(p, 38.0, Color("F2B95D"), 3.0)
                _draw_label("예상 교전권", p + _screen_delta(Vector2(52,34)), 18, Color("FFE2A6"))
            "approach":
                _draw_guji_approach_overlay(p)
            "battle":
                _draw_red_cliff_battle_overlay(p)

func _red_cliff_presentation_mode() -> String:
    match semantic_level:
        1: return "overview"
        2: return "rally"
        3: return "forecast"
        4: return "approach"
        5: return "battle"
    return "hidden"

func _canvas_scale() -> float:
    return maxf(0.001, absf(get_canvas_transform().x.x))

func _screen_delta(offset: Vector2) -> Vector2:
    return offset / _canvas_scale()

func _draw_screen_arc(center: Vector2, radius_px: float, color: Color, width_px: float) -> void:
    var canvas_scale := _canvas_scale()
    draw_arc(center, radius_px / canvas_scale, 0.0, TAU, 64, color,
        width_px / canvas_scale, true)

func _draw_screen_arrow(a: Vector2, b: Vector2, color: Color) -> void:
    var canvas_scale := _canvas_scale()
    var direction := (b-a).normalized()
    var normal := Vector2(-direction.y,direction.x)
    draw_line(a,b,Color(color.r,color.g,color.b,0.72),3.0/canvas_scale,true)
    var tip := PackedVector2Array([
        b,
        b-direction*(20.0/canvas_scale)+normal*(8.0/canvas_scale),
        b-direction*(20.0/canvas_scale)-normal*(8.0/canvas_scale),
    ])
    draw_colored_polygon(tip,Color(color.r,color.g,color.b,0.90))

func _draw_battle_fleet_wedge(origin: Vector2, direction: Vector2, color: Color) -> void:
    var canvas_scale := _canvas_scale()
    var forward := direction.normalized()
    var normal := Vector2(-forward.y,forward.x)
    for row in range(4):
        for column in range(row+1):
            var p := origin-forward*(float(row)*14.0/canvas_scale) \
                +normal*((float(column)-float(row)*0.5)*12.0/canvas_scale)
            draw_circle(p,3.0/canvas_scale,Color(color.r,color.g,color.b,0.92))

func _draw_guji_approach_overlay(p: Vector2) -> void:
    var left_start := p + _screen_delta(Vector2(-220,-92))
    var right_start := p + _screen_delta(Vector2(220,92))
    _draw_screen_arrow(left_start,p+_screen_delta(Vector2(-58,-25)),Color("6FC7FF"))
    _draw_screen_arrow(right_start,p+_screen_delta(Vector2(62,27)),Color("E3BD70"))
    _draw_screen_arc(p,28.0,Color("8FD7FF"),2.0)
    _draw_label("구지 궤도 · 접근축 탐색",p+_screen_delta(Vector2(-72,-108)),20,Color("CDEEFF"))

func _draw_red_cliff_battle_overlay(p: Vector2) -> void:
    var allied_start := p + _screen_delta(Vector2(-230,-105))
    var cao_start := p + _screen_delta(Vector2(230,105))
    # Preserve the strategic-map faction language: Sun Quan-led alliance is
    # red, while Cao Cao remains blue. Liu Bei is named in the label rather
    # than introducing a third tactical color without a legend.
    _draw_screen_arrow(allied_start,p+_screen_delta(Vector2(-64,-29)),Color("FF725F"))
    _draw_screen_arrow(cao_start,p+_screen_delta(Vector2(68,31)),Color("4AAEFF"))
    _draw_battle_fleet_wedge(allied_start+_screen_delta(Vector2(24,12)),Vector2(1,0.46),Color("FF725F"))
    _draw_battle_fleet_wedge(cao_start+_screen_delta(Vector2(-24,-12)),Vector2(-1,-0.46),Color("4AAEFF"))
    var canvas_scale := _canvas_scale()
    draw_line(p+_screen_delta(Vector2(-42,88)),p+_screen_delta(Vector2(42,-88)),
        Color(1.0,0.82,0.48,0.80),3.0/canvas_scale,true)
    _draw_screen_arc(p,58.0,Color("FF6757"),5.0)
    _draw_screen_arc(p,35.0,Color("FFD46F"),3.0)
    _draw_label("⚔ 적벽 대회전",p+_screen_delta(Vector2(-38,-126)),24,Color("FFD0B6"))
    _draw_label("손·유 연합 진입",allied_start+_screen_delta(Vector2(-18,-18)),16,Color("FFC0B5"))
    _draw_label("조조 함대 진입",cao_start+_screen_delta(Vector2(-84,28)),16,Color("A9D8FF"))

func _draw_scenario_regions() -> void:
    for region in scenario_regions:
        var polygon := PackedVector2Array()
        for raw in region.get("boundary", []):
            polygon.append(Vector2(float(raw[0]), float(raw[1])))
        if polygon.size() < 3:
            continue
        var color: Color = faction_colors.get(String(region.get("owner", "neutral")), Color("D8A144"))
        draw_colored_polygon(polygon, Color(color.r, color.g, color.b, 0.10))
        draw_polyline(polygon, Color(color.r, color.g, color.b, 0.20), 1.1, true)

func _draw_liu_bei_marker() -> void:
    var anchor := Vector2.ZERO
    for region in scenario_regions:
        if String(region.get("id", "")) == "RGN-02":
            var raw: Array = region.get("position", [])
            anchor = Vector2(float(raw[0]), float(raw[1])) + Vector2(-55, 42)
            break
    if anchor == Vector2.ZERO:
        return
    draw_arc(anchor, 13.0, 0.0, TAU, 28, Color("E7F2FF"), 2.0, true)
    draw_line(anchor + Vector2(-9,9), anchor + Vector2(9,-9), Color("E7F2FF"), 2.0, true)
    _draw_label("유비 · 유랑", anchor + Vector2(18,6), 18, Color("DCEBFF"))

func _draw_hierarchy_markers() -> void:
    if semantic_level >= 2:
        for region in scenario_regions:
            if String(region.get("name", "")) != "태양계권":
                continue
            var raw: Array = region.get("position", [])
            var p := Vector2(float(raw[0]), float(raw[1]))
            draw_arc(p, 25.0, 0.0, TAU, 48, Color("FFE08A"), 2.3, true)
            if semantic_level == 2:
                _draw_label("태양계권 진입",p+_screen_delta(Vector2(-138,-58)),18,Color("FFE8A8"))
            elif semantic_level == 3:
                _draw_label("태양계권 · 3천체",p+_screen_delta(Vector2(-98,-104)),18,Color("FFE8A8"))
    if semantic_level < 3:
        return
    var guji_display := Vector2.ZERO
    for body in canonical_bodies:
        if String(body.get("name", "")) == "구지":
            guji_display = _solar_body_display_position(body)
            break
    if guji_display != Vector2.ZERO:
        for body in canonical_bodies:
            if String(body.get("region", "")) != "RGN-04" or String(body.get("name", "")) == "구지":
                continue
            draw_line(guji_display,_solar_body_display_position(body),Color(0.72,0.88,1.0,0.28),
                1.5/_canvas_scale(),true)
    for body in canonical_bodies:
        if String(body.get("region", "")) != "RGN-04":
            continue
        var name := String(body.get("name", ""))
        var p := _solar_body_display_position(body)
        var is_guji := name == "구지"
        draw_circle(p, 7.0 if is_guji else 4.0, Color("C8E8FF") if is_guji else Color("D8BDA5"))
        var label_offset := Vector2(-18,58) if is_guji else Vector2(10,5)
        _draw_label(name, p + label_offset, 17, Color("E8F5FF"))

func _solar_body_display_position(body: Dictionary) -> Vector2:
    var raw: Array = body.get("position", [])
    if raw.size() < 2:
        return Vector2.ZERO
    var canonical_display := Vector2(float(raw[0]), float(raw[1]))
    var name := String(body.get("name", ""))
    if not SOLAR_BODY_SCREEN_OFFSETS.has(name):
        return canonical_display
    var guji_anchor := canonical_display
    for candidate in canonical_bodies:
        if String(candidate.get("name", "")) != "구지":
            continue
        var guji_raw: Array = candidate.get("position", [])
        if guji_raw.size() >= 2:
            guji_anchor = Vector2(float(guji_raw[0]), float(guji_raw[1]))
        break
    var canvas_scale := maxf(0.001, absf(get_canvas_transform().x.x))
    var screen_offset: Vector2 = SOLAR_BODY_SCREEN_OFFSETS.get(name, Vector2.ZERO)
    return guji_anchor + screen_offset / canvas_scale

func _draw_external_gateways() -> void:
    if semantic_level != 1:
        return
    var placements := {
        "EXT-DONGYI": Vector2(2900, 100), "EXT-DAEYUEZHI": Vector2(165, 370),
        "EXT-ROME": Vector2(180, 1460), "EXT-SASSANID": Vector2(620, 1540),
    }
    for power in external_powers:
        var id := String(power.get("id", ""))
        var p: Vector2 = placements.get(id, Vector2.ZERO)
        var status := String(power.get("status", ""))
        if status == "future" or not bool(power.get("visible_as_current", true)):
            continue
        p = _clamp_world_point_to_safe_screen(p, 30.0)
        var color := Color("D8B66A")
        if status == "background": color = Color("8EA5B5")
        elif status == "future": color = Color("697783")
        draw_arc(p, 15.0, -PI * 0.55, PI * 0.55, 20, color, 2.0, true)
        var suffix := ""
        if id == "EXT-ROME": suffix = " · 교역 배경"
        elif id == "EXT-SASSANID": suffix = " · 224년 이후"
        else: suffix = " · 외부 관문"
        var label_offset := Vector2(-300,55) if id == "EXT-DONGYI" else Vector2(24,8)
        var label_text := String(power.get("name", "")) + suffix
        var label_pos := _clamp_label_baseline_to_safe_screen(label_text, p + label_offset, 34, 42.0)
        draw_line(p, label_pos + Vector2(0,-8), Color(color.r,color.g,color.b,0.58), 1.8, true)
        _draw_gateway_label(label_text, label_pos, 34, color)

func _draw_gateway_label(text: String, pos: Vector2, size: int, color: Color) -> void:
    var font: Font = ThemeDB.fallback_font
    for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN,
            Vector2(-1,-1), Vector2(1,-1), Vector2(-1,1), Vector2(1,1)]:
        draw_string(font,pos+direction*3.0,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,
            Color(0.0,0.01,0.02,0.94))
    draw_string(font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,Color(color.r,color.g,color.b,1.0))

func _draw_overview_front_label(text: String, pos: Vector2) -> void:
    var font: Font = ThemeDB.fallback_font
    pos = _clamp_label_baseline_to_safe_screen(text,pos,27,52.0)
    draw_string(font,pos+Vector2(2,2),text,HORIZONTAL_ALIGNMENT_LEFT,-1,27,Color(0.0,0.0,0.0,0.94))
    draw_string(font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,27,Color(1.0,0.76,0.62,0.98))

func _draw_overview_arrow(a: Vector2, b: Vector2, c: Color) -> void:
    _draw_arrow(_clamp_world_point_to_safe_screen(a,55.0),_clamp_world_point_to_safe_screen(b,55.0),c)

func _draw_arrow(a: Vector2, b: Vector2, c: Color) -> void:
    draw_line(a,b,Color(c.r,c.g,c.b,.42),3.0,true)
    var dir: Vector2=(b-a).normalized()
    var n: Vector2=Vector2(-dir.y,dir.x)
    var tip: PackedVector2Array=PackedVector2Array([b,b-dir*22+n*8,b-dir*22-n*8])
    draw_colored_polygon(tip,Color(c.r,c.g,c.b,.72))
