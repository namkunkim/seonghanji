extends Control
class_name GalaxyMinimap

var camera_ref: Camera2D
var home_state: Dictionary = {}
var systems: Array = []
var world_size := Vector2(3200, 1800)
var canonical_world_size := Vector2(37312, 30000)
var map_screen_rect := Rect2(220.0,76.0,1070.0,634.0)
var semantic_level := 1

const COLORS := {
    "조조": Color("#1E91FF"), "손권": Color("#F24E3E"),
    "유종": Color("#A875E8"), "유장": Color("#19E082"),
    "장로": Color("#45C8D8"), "마등한수": Color("#D8A144"),
    "사섭": Color("#ED8B52"), "공손강": Color("#70E4FF"),
    "neutral": Color("#D8A144"),
}

func setup(cam: Camera2D, snapshot: Dictionary, system_data: Array, safe_rect: Rect2) -> void:
    camera_ref = cam
    home_state = snapshot
    systems = system_data
    map_screen_rect = safe_rect
    queue_redraw()

func set_semantic_level(level: int) -> void:
    semantic_level = clampi(level, 1, 5)
    queue_redraw()

func set_map_screen_rect(rect: Rect2) -> void:
    map_screen_rect = rect
    queue_redraw()

func _process(_delta: float) -> void:
    queue_redraw()

func _map(world: Vector2) -> Vector2:
    return Vector2(world.x / world_size.x * size.x, world.y / world_size.y * _map_height())

func _map_height() -> float:
    return maxf(80.0, size.y - 58.0)

func _canonical_to_world(raw: Array) -> Vector2:
    return Vector2(float(raw[0]) / canonical_world_size.x * world_size.x,
        float(raw[1]) / canonical_world_size.y * world_size.y)

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO,size), Color("030a12"), true)
    draw_rect(Rect2(Vector2(4,4), size-Vector2(8,8)), Color(0.04,0.12,0.18,0.65), false, 1.0)
    draw_line(Vector2(5,_map_height()), Vector2(size.x-5,_map_height()), Color(0.24,0.55,0.70,0.45), 1.0)
    var owners: Dictionary = home_state.get("region_owner", {})
    for region in home_state.get("canonical_regions", []):
        var polygon := PackedVector2Array()
        for raw in region.get("boundary", []):
            polygon.append(_map(_canonical_to_world(raw)))
        if polygon.size() < 3:
            continue
        var color: Color = COLORS.get(String(owners.get(String(region.get("id", "")), "neutral")), Color.GRAY)
        draw_colored_polygon(polygon, Color(color.r,color.g,color.b,0.25))
        draw_polyline(polygon, Color(color.r,color.g,color.b,0.55), 0.8, true)
    for route in home_state.get("canonical_routes", []):
        if String(route.get("display_policy", "")) != "persistent-strategic":
            continue
        var line := PackedVector2Array()
        for raw in route.get("line", []):
            line.append(_map(_canonical_to_world(raw)))
        if line.size() > 1:
            draw_polyline(line, Color(0.60,0.84,1.0,0.35), 0.75, true)
    for system in systems:
        var raw: Array = system.get("pos", [])
        var point := _map(Vector2(float(raw[0]),float(raw[1])))
        var color: Color = COLORS.get(String(system.get("faction", "neutral")), Color.WHITE)
        draw_circle(point, 1.8, color)
    _draw_external_edges()
    _draw_legend()
    if camera_ref != null:
        var viewport_size := get_viewport().get_visible_rect().size
        var safe_center_screen := map_screen_rect.position + map_screen_rect.size * 0.5
        var camera_screen_offset := (safe_center_screen - viewport_size * 0.5) / camera_ref.zoom
        var visible_center := camera_ref.position + camera_screen_offset
        var visible_world := map_screen_rect.size / camera_ref.zoom
        var rect_pos := _map(visible_center-visible_world*.5)
        var rect_size := Vector2(visible_world.x/world_size.x*size.x,visible_world.y/world_size.y*_map_height())
        var lod_colors := [Color.WHITE, Color("8fd7ff"), Color("72e5c0"), Color("ffd27a"), Color("ff947d")]
        draw_rect(Rect2(rect_pos,rect_size),Color(0.0,0.0,0.0,0.28),true)
        draw_rect(Rect2(rect_pos,rect_size),lod_colors[semantic_level - 1],false,1.7)

func _draw_external_edges() -> void:
    var placements := {
        "EXT-DONGYI": Vector2(0.96,0.12), "EXT-DAEYUEZHI": Vector2(0.03,0.23),
        "EXT-ROME": Vector2(0.04,0.84), "EXT-SASSANID": Vector2(0.19,0.90),
    }
    for power in home_state.get("external_powers", []):
        if power.has("visible_as_current") and not bool(power.get("visible_as_current", false)):
            continue
        var unit: Vector2 = placements.get(String(power.get("id", "")), Vector2.ZERO)
        var color := Color("D8B66A")
        if String(power.get("status", "")) == "background": color = Color("8EA5B5")
        elif String(power.get("status", "")) == "future": color = Color("697783")
        draw_circle(Vector2(unit.x * size.x, unit.y * _map_height()), 2.6, color)

func _draw_legend() -> void:
    var entries := ["조조", "공손강", "유장", "장로", "손권", "유종", "마등한수", "사섭"]
    var font := ThemeDB.fallback_font
    var top := _map_height() + 15.0
    for index in range(entries.size()):
        var column := index % 2
        var row := index / 2
        var raw: String = entries[index]
        var label := "마등·한수" if raw == "마등한수" else raw
        var x := 13.0 + float(column) * size.x * 0.50
        var y := top + float(row) * 11.5
        draw_circle(Vector2(x,y-3.0), 3.2, COLORS[raw])
        draw_string(font, Vector2(x+8.0,y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("DCEBF2"))
