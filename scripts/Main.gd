extends Node

var map: GalaxyMap
var cam: Camera2D
var inspector_body: VBoxContainer
var zoom_label: Label
var minimap: GalaxyMinimap
var stage_buttons: Array[Button] = []
var ui_root: Control
var top_panel: PanelContainer
var left_panel: PanelContainer
var right_panel: PanelContainer
var bottom_panel: PanelContainer
var stage_badges: Array[PanelContainer] = []
var menu_buttons: Dictionary = {}
var top_route_buttons: Dictionary = {}
var active_menu_id := "overview"
var map_context_menu_id := "overview"
var submenu: Control
var map_input_blocker: Control
var projected_systems: Array = []
var playback_speeds := [1.0, 2.0, 4.0]
var playback_speed_index := 0
var pause_button: Button
var speed_button: Button
var _initial_tree_paused := false
var _initial_time_scale := 1.0

const WORLD_SIZE := Vector2(3200.0, 1800.0)
const CANONICAL_WORLD_SIZE := Vector2(37312.0, 30000.0)
const GameDataScript = preload("res://core/data/game_data.gd")
const CampaignScript = preload("res://core/campaign.gd")
const HomeMapSnapshotScript = preload("res://app/home_map_snapshot.gd")
const HOME_SUBMENU_PATH := "res://scripts/HomeSubmenu.gd"
var hud_safe_rect := Rect2(184.0, 70.0, 1116.0, 620.0)
var home_state: Dictionary = {}
var home_snapshot

func _ready() -> void:
    _initial_tree_paused = get_tree().paused
    _initial_time_scale = Engine.time_scale
    playback_speed_index = _closest_playback_speed_index(_initial_time_scale)
    RenderingServer.set_default_clear_color(Color("#020a12"))
    var galaxy_data: Dictionary = _load_json("res://data/galaxy.json")
    var terrain_data: Dictionary = _load_json("res://data/terrain.json")
    var game_data = GameDataScript.load_all()
    var campaign = CampaignScript.scenario_03(game_data, 20803)
    home_snapshot = HomeMapSnapshotScript.from_campaign(campaign, 208)
    home_state = home_snapshot.snapshot()
    var systems: Array = _project_systems(home_state, campaign)
    projected_systems = systems
    var regions: Array = _project_regions(home_state)
    var bodies: Array = _project_body_rows(home_snapshot.visible_bodies(2))
    var routes: Array = _project_routes(home_state)

    map = GalaxyMap.new()
    map.name = "GalaxyMap"
    add_child(map)

    cam = Camera2D.new()
    cam.position = WORLD_SIZE * 0.5
    cam.zoom = Vector2(0.50,0.50)
    # GalaxyMap owns safe-area-aware clamping. Native Camera2D limits force a
    # zoomed-out world against the bottom-right edge when the viewport is larger
    # than the world, breaking the centered overview composition.
    cam.limit_left = -100000
    cam.limit_top = -100000
    cam.limit_right = 100000
    cam.limit_bottom = 100000
    cam.position_smoothing_enabled = true
    cam.position_smoothing_speed = 8.0
    map.add_child(cam)
    cam.make_current()

    map.setup(cam, systems, [], terrain_data, regions, routes, bodies,
        home_state.get("active_battles", []), home_state.get("external_powers", []))
    map.set_input_safe_rect(hud_safe_rect)
    var continent: ConnectedContinent = ConnectedContinent.new()
    continent.name = "ConnectedContinent"
    map.add_child(continent)
    continent.build(terrain_data)



    var star_clusters: StarClusterLayer = StarClusterLayer.new()
    star_clusters.name = "StarClusterLayer"
    map.add_child(star_clusters)
    star_clusters.build()

    var debris: StrategicDebrisLayer = StrategicDebrisLayer.new()
    debris.name = "StrategicDebrisLayer"
    map.add_child(debris)
    debris.build()



    map.object_selected.connect(_on_selected)
    map.zoom_level_changed.connect(_on_zoom_level_changed)

    _build_ui(galaxy_data, systems)

func _exit_tree() -> void:
    Engine.time_scale = _initial_time_scale
    var tree := get_tree()
    if tree != null:
        tree.paused = _initial_tree_paused

func _project_point(raw) -> Array:
    if not raw is Array or raw.size() < 2:
        return [0.0, 0.0]
    return [float(raw[0]) / CANONICAL_WORLD_SIZE.x * WORLD_SIZE.x,
        float(raw[1]) / CANONICAL_WORLD_SIZE.y * WORLD_SIZE.y]

func _project_systems(state: Dictionary, campaign) -> Array:
    var owners: Dictionary = state.get("region_owner", {})
    var capitals := {}
    for faction_id in campaign.faction_ids:
        capitals[String(campaign.factions[faction_id].capital_system)] = String(faction_id)
    var out: Array = []
    for source in state.get("canonical_systems", []):
        var counts := {}
        for rid in source.get("regions", []):
            var owner := String(owners.get(String(rid), "neutral"))
            counts[owner] = int(counts.get(owner, 0)) + 1
        var owner := "neutral"
        var best := 0
        for fid in counts:
            if int(counts[fid]) > best:
                owner = String(fid)
                best = int(counts[fid])
        var grade := String(source.get("grade", ""))
        out.append({
            "id": String(source.get("id", "")), "name": String(source.get("name", "")),
            "display_name": String(source.get("display_name", "")),
            "pos": _project_point(source.get("position", [])),
            "canonical_position": source.get("position", []).duplicate(true),
            "region_ids": source.get("regions", []).duplicate(true), "faction": owner,
            "type": "capital" if capitals.has(String(source.get("id", ""))) else ("fortress" if grade == "1급" else "strategic"),
            "grade": grade,
        })
    return out

func _project_regions(state: Dictionary) -> Array:
    var owners: Dictionary = state.get("region_owner", {})
    var out: Array = []
    for source in state.get("canonical_regions", []):
        var row: Dictionary = source.duplicate(true)
        row["canonical_position"] = source.get("position", []).duplicate(true)
        row["position"] = _project_point(source.get("position", []))
        var boundary: Array = []
        for point in source.get("boundary", []):
            boundary.append(_project_point(point))
        row["boundary"] = boundary
        row["owner"] = String(owners.get(String(source.get("id", "")), "neutral"))
        out.append(row)
    return out

func _project_bodies(state: Dictionary) -> Array:
    return _project_body_rows(state.get("canonical_bodies", []))

func _project_body_rows(source_rows: Array) -> Array:
    var out: Array = []
    for source in source_rows:
        var row: Dictionary = source.duplicate(true)
        row["canonical_position"] = source.get("position", []).duplicate(true)
        row["position"] = _project_point(source.get("position", []))
        out.append(row)
    return out

func _project_routes(state: Dictionary) -> Array:
    var out: Array = []
    for source in state.get("canonical_routes", []):
        var row: Dictionary = source.duplicate(true)
        var line: Array = []
        for point in source.get("line", []):
            line.append(_project_point(point))
        row["line"] = line
        out.append(row)
    return out

func _find_projected(rows: Array, key: String, value: String, fallback: Vector2) -> Vector2:
    for row in rows:
        if String(row.get(key, "")) == value:
            var p: Array = row.get("position", row.get("pos", []))
            if p.size() >= 2:
                return Vector2(float(p[0]), float(p[1]))
    return fallback

func _load_json(path: String) -> Dictionary:
    var f: FileAccess = FileAccess.open(path, FileAccess.READ)
    if f == null: return {}
    var parsed: Variant = JSON.parse_string(f.get_as_text())
    return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func _build_ui(galaxy: Dictionary, systems: Array) -> void:
    menu_buttons.clear()
    top_route_buttons.clear()
    active_menu_id = "overview"
    submenu = null
    map_input_blocker = null
    var ui: CanvasLayer = CanvasLayer.new()
    ui.layer = 20
    add_child(ui)

    ui_root = Control.new()
    ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    ui_root.process_mode = Node.PROCESS_MODE_ALWAYS
    ui.add_child(ui_root)

    # Top bar
    top_panel = PanelContainer.new()
    ui_root.add_child(top_panel)
    top_panel.add_theme_stylebox_override("panel", HudStyle.panel_style(0.94))

    var top_h: HBoxContainer = HBoxContainer.new()
    top_h.add_theme_constant_override("separation",10)
    top_panel.add_child(top_h)

    var brand: HBoxContainer = HBoxContainer.new()
    brand.custom_minimum_size = Vector2(350,58)
    brand.add_theme_constant_override("separation", 14)
    brand.alignment = BoxContainer.ALIGNMENT_CENTER
    top_h.add_child(brand)

    var title: Label = Label.new()
    title.text = "성한지"
    title.add_theme_font_size_override("font_size",42)
    title.add_theme_color_override("font_color", Color("f1fbff"))
    title.add_theme_color_override("font_outline_color", Color(0.08, 0.42, 0.62, 0.72))
    title.add_theme_constant_override("outline_size", 2)
    brand.add_child(title)

    var sub: Label = Label.new()
    sub.text = "STARS AND HEROES\n천하를 품은 우주, 다시 쓰는 삼국의 전설"
    sub.add_theme_color_override("font_color", Color("b8d6e6"))
    sub.add_theme_font_size_override("font_size",13)
    brand.add_child(sub)

    var spacer: Control = Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    top_h.add_child(spacer)

    var resources = [
        ["resource:calendar", "◷", "건안 13년 · 208", "", Color("75d989"), 126, "달력과 캠페인 시점을 확인합니다.", "연대"],
        ["resource:funds", "◆", "12.4M", "+24", Color("8fe98f"), 98, "자금 보유량과 증감 정보를 확인합니다.", "자금"],
        ["resource:supply", "◇", "8.7M", "+317", Color("8edfff"), 98, "군량 보유량과 보급 정보를 확인합니다.", "군량"],
        ["resource:influence", "✦", "3.1M", "+92", Color("d4a9ff"), 98, "영향력 현황을 확인합니다.", "영향력"],
        ["resource:intel", "●", "421K", "+11", Color("ffd875"), 92, "정보 자원과 관측 현황을 확인합니다.", "정보"],
        ["resource:capacity", "▲", "98/120", "", Color("9edfff"), 92, "지휘 수용력과 현재 사용량을 확인합니다.", "함대 수용력"]
    ]
    for resource in resources:
        var b: Button = Button.new()
        b.text = ""
        b.custom_minimum_size = Vector2(float(resource[5]),36)
        b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        b.add_theme_stylebox_override("normal", HudStyle.resource_style())
        b.add_theme_stylebox_override("hover", HudStyle.resource_hover_style())
        b.add_theme_stylebox_override("pressed", HudStyle.resource_pressed_style())
        b.add_theme_stylebox_override("disabled", HudStyle.resource_disabled_style())
        b.add_theme_stylebox_override("focus", HudStyle.resource_focus_style())
        b.tooltip_text = String(resource[6])
        b.set_meta("route_id", String(resource[0]))
        var resource_row := HBoxContainer.new()
        resource_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        resource_row.alignment = BoxContainer.ALIGNMENT_CENTER
        resource_row.add_theme_constant_override("separation", 5)
        resource_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var resource_icon := Label.new()
        resource_icon.text = String(resource[1])
        resource_icon.add_theme_font_size_override("font_size", 13)
        resource_icon.add_theme_color_override("font_color", resource[4])
        resource_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
        resource_row.add_child(resource_icon)
        var resource_value := Label.new()
        resource_value.text = String(resource[2])
        resource_value.add_theme_font_size_override("font_size", 13)
        resource_value.add_theme_color_override("font_color", Color("e8f7ff"))
        resource_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
        resource_row.add_child(resource_value)
        if not String(resource[3]).is_empty():
            var resource_delta := Label.new()
            resource_delta.text = String(resource[3])
            resource_delta.add_theme_font_size_override("font_size", 10)
            resource_delta.add_theme_color_override("font_color", Color(resource[4], 0.82))
            resource_delta.mouse_filter = Control.MOUSE_FILTER_IGNORE
            resource_row.add_child(resource_delta)
        b.add_child(resource_row)
        b.pressed.connect(_route_home_action.bind(String(resource[0]), String(resource[7]), String(resource[1]), {
            "display_value": String(resource[2]),
            "display_delta": String(resource[3]),
        }))
        top_route_buttons[String(resource[0])] = b
        top_h.add_child(b)

    for utility_data in [
        ["pause", "II", "시간 진행을 일시정지하거나 재개합니다.", "시간"],
        ["speed", "1x", "시간 배속을 1배·2배·4배로 전환합니다.", "배속"],
        ["mail", "✉", "도착한 우편과 소식을 엽니다.", "우편"],
        ["settings", "⚙", "홈 지도 설정을 엽니다.", "설정"],
    ]:
        var utility := Button.new()
        utility.text = String(utility_data[1])
        utility.custom_minimum_size = Vector2(44,36)
        utility.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        utility.add_theme_font_size_override("font_size",13)
        utility.add_theme_color_override("font_color", Color("cce9f7"))
        utility.add_theme_color_override("font_hover_color", Color("ffffff"))
        utility.add_theme_stylebox_override("normal", HudStyle.resource_style())
        utility.add_theme_stylebox_override("hover", HudStyle.resource_hover_style())
        utility.add_theme_stylebox_override("pressed", HudStyle.resource_pressed_style())
        utility.add_theme_stylebox_override("disabled", HudStyle.resource_disabled_style())
        utility.add_theme_stylebox_override("focus", HudStyle.resource_focus_style())
        utility.tooltip_text = String(utility_data[2])
        utility.set_meta("route_id", String(utility_data[0]))
        utility.pressed.connect(_route_home_action.bind(String(utility_data[0]), String(utility_data[3]), String(utility_data[1]), {}))
        top_route_buttons[String(utility_data[0])] = utility
        if String(utility_data[0]) == "pause":
            pause_button = utility
        elif String(utility_data[0]) == "speed":
            speed_button = utility
        top_h.add_child(utility)
    # Left menu
    left_panel = PanelContainer.new()
    ui_root.add_child(left_panel)
    left_panel.add_theme_stylebox_override("panel", HudStyle.panel_style(0.88))
    var menu: VBoxContainer = VBoxContainer.new()
    menu.add_theme_constant_override("separation",5)
    left_panel.add_child(menu)

    var items = [
        ["overview", "◎", "01  천하도", Color("65ccff")],
        ["systems", "◇", "02  성역", Color("8fcfff")],
        ["fleets", "▲", "03  함대", Color("80dfff")],
        ["domestic", "▣", "04  내정", Color("ffd06a")],
        ["talent", "◆", "05  인재", Color("b8e8ff")],
        ["diplomacy", "◈", "06  외교", Color("c7a6ff")],
        ["tech", "✦", "07  기술", Color("76f0dc")],
        ["records", "≡", "08  기록", Color("9db8c8")]
    ]
    for item in items:
        var b: Button = Button.new()
        b.text = "      %s" % String(item[2])
        b.custom_minimum_size = Vector2(0,49)
        b.alignment = HORIZONTAL_ALIGNMENT_LEFT
        b.add_theme_font_size_override("font_size", 16)
        b.add_theme_color_override("font_color", Color("c7e2ef"))
        b.add_theme_color_override("font_hover_color", Color("ffffff"))
        b.add_theme_stylebox_override("normal", HudStyle.button_style(String(item[0]) == active_menu_id))
        b.add_theme_stylebox_override("hover", HudStyle.button_hover_style())
        b.add_theme_stylebox_override("pressed", HudStyle.button_pressed_style())
        b.add_theme_stylebox_override("disabled", HudStyle.button_disabled_style())
        b.add_theme_stylebox_override("focus", HudStyle.button_focus_style())
        var menu_icon := Label.new()
        menu_icon.text = String(item[1])
        menu_icon.position = Vector2(14, 12)
        menu_icon.custom_minimum_size = Vector2(22, 24)
        menu_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        menu_icon.add_theme_font_size_override("font_size", 17)
        menu_icon.add_theme_color_override("font_color", item[3])
        menu_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
        b.add_child(menu_icon)
        var route_id := String(item[0])
        b.set_meta("route_id", route_id)
        b.tooltip_text = "%s 열기" % String(item[2]).substr(4)
        menu_buttons[route_id] = b
        b.pressed.connect(_route_home_action.bind(route_id, String(item[2]).substr(4), String(item[1]), {}))
        menu.add_child(b)

    # Right panel
    right_panel = PanelContainer.new()
    ui_root.add_child(right_panel)
    right_panel.add_theme_stylebox_override("panel", HudStyle.panel_style(0.92))

    var right_v: VBoxContainer = VBoxContainer.new()
    right_v.add_theme_constant_override("separation",8)
    right_panel.add_child(right_v)

    var mini_title: Label = Label.new()
    mini_title.text = "천하도 (전체 은하)"
    mini_title.add_theme_font_size_override("font_size",16)
    mini_title.add_theme_color_override("font_color", Color("f0faff"))
    mini_title.add_theme_stylebox_override("normal", HudStyle.section_style())
    mini_title.custom_minimum_size = Vector2(0, 30)
    right_v.add_child(mini_title)

    minimap = GalaxyMinimap.new()
    minimap.custom_minimum_size = Vector2(260,170)
    minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
    minimap.setup(cam, home_state, systems, hud_safe_rect)
    right_v.add_child(minimap)

    # Selection data remains wired, but the home rail is reserved for minimap and news.
    inspector_body = VBoxContainer.new()
    inspector_body.visible = false
    right_v.add_child(inspector_body)

    var news_header := PanelContainer.new()
    news_header.custom_minimum_size = Vector2(0, 30)
    news_header.add_theme_stylebox_override("panel", HudStyle.section_style())
    var news_header_row := HBoxContainer.new()
    news_header.add_child(news_header_row)
    var news_title := Label.new()
    news_title.text = "주요 소식 · 현재 상태"
    news_title.add_theme_font_size_override("font_size",16)
    news_title.add_theme_color_override("font_color", Color("f0faff"))
    news_header_row.add_child(news_title)
    var news_spacer := Control.new()
    news_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    news_header_row.add_child(news_spacer)
    var more_news := Button.new()
    more_news.text = "더보기 >"
    more_news.add_theme_font_size_override("font_size",12)
    more_news.add_theme_color_override("font_color", Color("8fc9e4"))
    more_news.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
    more_news.add_theme_stylebox_override("hover", HudStyle.button_hover_style())
    more_news.add_theme_stylebox_override("pressed", HudStyle.button_pressed_style())
    more_news.add_theme_stylebox_override("focus", HudStyle.button_focus_style())
    more_news.add_theme_stylebox_override("disabled", HudStyle.button_disabled_style())
    more_news.tooltip_text = "전체 기록과 소식을 엽니다."
    more_news.set_meta("route_id", "records")
    more_news.pressed.connect(_route_home_action.bind("records", "기록", "≡", {}))
    news_header_row.add_child(more_news)
    right_v.add_child(news_header)

    var news_rows: Array = []
    for item in home_state.get("news", []):
        news_rows.append([String(item.get("icon", "•")), Color(String(item.get("color", "99caff"))),
            String(item.get("headline", item.get("title", ""))), String(item.get("date", "건안 13년"))])
    if news_rows.is_empty():
        news_rows = _current_status_rows()
    for n in news_rows:
        var row := PanelContainer.new()
        row.custom_minimum_size = Vector2(260,52)
        row.add_theme_stylebox_override("panel", HudStyle.news_style())
        var news_row := HBoxContainer.new()
        news_row.add_theme_constant_override("separation", 8)
        row.add_child(news_row)
        var news_icon := Label.new()
        news_icon.text = String(n[0])
        news_icon.custom_minimum_size = Vector2(20, 0)
        news_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        news_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        news_icon.add_theme_font_size_override("font_size", 19)
        news_icon.add_theme_color_override("font_color", n[1])
        news_row.add_child(news_icon)
        var row_body := VBoxContainer.new()
        row_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        news_row.add_child(row_body)
        var headline := Label.new()
        headline.text = String(n[2])
        headline.add_theme_font_size_override("font_size",14)
        headline.add_theme_color_override("font_color", Color("f0f9ff"))
        headline.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
        row_body.add_child(headline)
        var date := Label.new()
        date.text = String(n[3])
        date.add_theme_font_size_override("font_size",12)
        date.add_theme_color_override("font_color",Color("b2cfdd"))
        row_body.add_child(date)
        right_v.add_child(row)

    # Bottom semantic zoom strip
    bottom_panel = PanelContainer.new()
    ui_root.add_child(bottom_panel)
    bottom_panel.add_theme_stylebox_override("panel", HudStyle.panel_style(0.94))

    var bottom_h: HBoxContainer = HBoxContainer.new()
    bottom_h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    bottom_h.add_theme_constant_override("separation",6)
    bottom_panel.add_child(bottom_h)

    var desc: Label = Label.new()
    desc.text = "시맨틱 줌\n1  →  5"
    desc.custom_minimum_size = Vector2(96,0)
    desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    desc.add_theme_font_size_override("font_size", 13)
    desc.add_theme_color_override("font_color", Color("9eb9c9"))
    bottom_h.add_child(desc)

    var region_rows: Array = _project_regions(home_state)
    var body_rows: Array = _project_body_rows(home_snapshot.visible_bodies(2))
    var jingzhou_pos := _find_projected(systems, "id", "SYS-13", Vector2(1600, 980))
    var solar_pos := _find_projected(region_rows, "name", "태양계권", jingzhou_pos)
    var guji_pos := _find_projected(body_rows, "name", "구지", solar_pos)
    var battle_active := _has_active_red_cliff_battle(home_state.get("active_battles", []))
    var stages = [
        ["천하도","19성역 · 45권역 · 37항로","res://assets/ui-mockups/seonghanji-galaxy-map-background.png",Vector2(1600,900),map.overview_zoom],
        ["형주성역","북부·중부·남부·태양계권","res://assets/ui-mockups/seonghanji-mandate-jingzhou-sanctuary-1600x900.png",jingzhou_pos,0.80],
        ["태양계권","형주 제4권역 · 특수 표식","res://assets/ui-mockups/seonghanji-jingzhou-operational-detail-1600x900.png",solar_pos,1.00],
        ["구지 궤도","구지·형혹·태음","res://assets/ui-mockups/seonghanji-fleet-encounter-background.png",guji_pos,1.25],
        ["적벽","교전 활성" if battle_active else "전투 조건 미충족","res://assets/ui-mockups/seonghanji-red-cliffs-guji-battle-key-art-16x9.png",guji_pos,1.65]
    ]
    stage_buttons.clear()
    stage_badges.clear()
    for stage_index in range(stages.size()):
        var s: Array = stages[stage_index]
        var b := Button.new()
        var is_locked_red_cliff := stage_index == 4 and not battle_active
        b.text = ""
        b.custom_minimum_size = Vector2(186,0)
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        b.size_flags_vertical = Control.SIZE_EXPAND_FILL
        b.add_theme_stylebox_override("normal", HudStyle.card_disabled_style() if is_locked_red_cliff else HudStyle.card_selected_style() if stage_index == 0 else HudStyle.card_style())
        b.add_theme_stylebox_override("hover", HudStyle.card_hover_style())
        b.add_theme_stylebox_override("pressed", HudStyle.card_pressed_style())
        b.add_theme_stylebox_override("disabled", HudStyle.card_disabled_style())
        b.add_theme_stylebox_override("focus", HudStyle.card_focus_style())
        var preview := TextureRect.new()
        var source_texture: Texture2D = load(String(s[2]))
        if stage_index in [1, 2]:
            var crop := AtlasTexture.new()
            crop.atlas = source_texture
            var source_size := source_texture.get_size()
            crop.region = Rect2(
                source_size * Vector2(0.20, 0.16),
                source_size * Vector2(0.60, 0.54)
            )
            preview.texture = crop
        else:
            preview.texture = source_texture
        preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        preview.offset_left = 5
        preview.offset_top = 31
        preview.offset_right = -5
        preview.offset_bottom = -36
        preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
        preview.self_modulate = Color(0.34, 0.40, 0.46, 0.68) if stage_index == 4 and not battle_active else Color(0.78, 0.90, 1.0, 0.92)
        preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
        b.add_child(preview)
        var number_badge := PanelContainer.new()
        number_badge.position = Vector2(8, 5)
        number_badge.custom_minimum_size = Vector2(25, 23)
        number_badge.add_theme_stylebox_override("panel", HudStyle.badge_style(stage_index == 0))
        number_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var number_label := Label.new()
        number_label.text = str(stage_index + 1)
        number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        number_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        number_label.add_theme_font_size_override("font_size", 14)
        number_label.add_theme_color_override("font_color", Color("ecfaff"))
        number_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        number_badge.add_child(number_label)
        b.add_child(number_badge)
        stage_badges.append(number_badge)
        var title_label := Label.new()
        title_label.text = "🔒 %s" % String(s[0]) if is_locked_red_cliff else String(s[0])
        title_label.position = Vector2(40,5)
        title_label.add_theme_font_size_override("font_size",15)
        title_label.add_theme_color_override("font_color", Color("8799a3") if stage_index == 4 and not battle_active else Color("eff9ff"))
        title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        b.add_child(title_label)
        var caption_panel := PanelContainer.new()
        caption_panel.anchor_top = 1.0
        caption_panel.anchor_right = 1.0
        caption_panel.anchor_bottom = 1.0
        caption_panel.offset_left = 5
        caption_panel.offset_top = -36
        caption_panel.offset_right = -5
        caption_panel.offset_bottom = -5
        caption_panel.add_theme_stylebox_override("panel", HudStyle.caption_style())
        caption_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var caption := Label.new()
        caption.text = String(s[1])
        caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        caption.add_theme_font_size_override("font_size",13)
        caption.add_theme_color_override("font_color", Color("9babb3") if stage_index == 4 and not battle_active else Color("e8f7ff"))
        caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
        caption_panel.add_child(caption)
        b.add_child(caption_panel)
        var stage_route := "stage:%d" % (stage_index + 1)
        if is_locked_red_cliff:
            stage_route = "red_cliff_lock"
            b.tooltip_text = "적벽 개전 조건이 아직 충족되지 않았습니다. 눌러 조건을 확인합니다."
        else:
            b.tooltip_text = "%s 단계로 이동합니다." % String(s[0])
        b.set_meta("route_id", stage_route)
        b.pressed.connect(_route_home_action.bind(stage_route, "적벽 개전 조건" if is_locked_red_cliff else String(s[0]), "🔒" if is_locked_red_cliff else str(stage_index + 1), {
            "position": s[3], "zoom": s[4], "battle_active": battle_active,
        }))
        bottom_h.add_child(b)
        stage_buttons.append(b)

    var zoom_panel: VBoxContainer = VBoxContainer.new()
    zoom_panel.custom_minimum_size = Vector2(128,0)
    bottom_h.add_child(zoom_panel)
    zoom_label = Label.new()
    zoom_label.text = "역사는\n별들 위에서도\n이어진다."
    zoom_label.add_theme_font_size_override("font_size",14)
    zoom_label.add_theme_color_override("font_color",Color("c2d7e1"))
    zoom_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    zoom_panel.add_child(zoom_label)
    get_viewport().size_changed.connect(_layout_ui)
    _ensure_submenu()
    _layout_ui()
    _on_zoom_level_changed(map.semantic_level)
    if pause_button:
        pause_button.text = "▶" if get_tree().paused else "II"
    if speed_button:
        speed_button.text = "%dx" % int(playback_speeds[playback_speed_index])
    _refresh_menu_styles()

func _ensure_submenu() -> void:
    if submenu != null or not ResourceLoader.exists(HOME_SUBMENU_PATH):
        return
    var submenu_script: Script = load(HOME_SUBMENU_PATH)
    if submenu_script == null:
        return
    var instance = submenu_script.new()
    if not instance is Control:
        instance.queue_free()
        return

    map_input_blocker = ColorRect.new()
    map_input_blocker.name = "MapInputBlocker"
    map_input_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
    map_input_blocker.color = Color(0.0, 0.025, 0.055, 0.22)
    map_input_blocker.visible = false
    map_input_blocker.gui_input.connect(_on_map_blocker_gui_input)
    ui_root.add_child(map_input_blocker)

    submenu = instance as Control
    submenu.name = "HomeSubmenu"
    submenu.visible = false
    submenu.mouse_filter = Control.MOUSE_FILTER_STOP
    ui_root.add_child(submenu)
    submenu.call("setup", home_state, home_snapshot)
    if submenu.has_signal("closed"):
        submenu.connect("closed", _on_submenu_closed)
    if submenu.has_signal("action_requested"):
        submenu.connect("action_requested", _on_submenu_action_requested)

func _route_home_action(route_id: String, title: String = "", icon: String = "", payload: Dictionary = {}) -> void:
    match route_id:
        "pause":
            get_tree().paused = not get_tree().paused
            if pause_button:
                pause_button.text = "▶" if get_tree().paused else "II"
            _refresh_menu_styles()
            return
        "speed":
            playback_speed_index = (playback_speed_index + 1) % playback_speeds.size()
            Engine.time_scale = playback_speeds[playback_speed_index]
            if speed_button:
                speed_button.text = "%dx" % int(playback_speeds[playback_speed_index])
            _refresh_menu_styles()
            return
        "overview", "stage:1":
            _close_home_submenu()
            active_menu_id = "overview"
            map_context_menu_id = "overview"
            _refresh_menu_styles()
            map.focus_overview()
            return
        "systems":
            var jingzhou_pos := _find_projected(projected_systems, "id", "SYS-13", WORLD_SIZE * 0.5)
            map.focus_world(jingzhou_pos, 0.80)
            map_context_menu_id = "systems"
            _open_home_submenu(route_id, title, icon)
            return
        "stage:2", "stage:3", "stage:4", "stage:5":
            _close_home_submenu()
            map_context_menu_id = "systems" if route_id == "stage:2" else ""
            map.focus_world(payload.get("position", WORLD_SIZE * 0.5), float(payload.get("zoom", map.overview_zoom)))
            return
        "focus_system":
            var system_id := String(payload.get("system_id", ""))
            map.focus_world(_find_projected(projected_systems, "id", system_id, WORLD_SIZE * 0.5), 0.80)
            return
        "focus_region":
            var region_id := String(payload.get("region_id", ""))
            var regions: Array = _project_regions(home_state)
            map.focus_world(_find_projected(regions, "id", region_id, WORLD_SIZE * 0.5), 1.25)
            _open_related_selection(regions, "id", region_id, "권역")
            return
        "selection":
            _open_home_submenu(route_id, title, icon, payload)
        _:
            _open_home_submenu(route_id, title, icon, payload)

func _open_home_submenu(route_id: String, title: String, icon: String, route_payload: Dictionary = {}) -> void:
    _ensure_submenu()
    active_menu_id = route_id
    _refresh_menu_styles()
    if submenu == null:
        return
    var submenu_state: Dictionary = home_state
    if not route_payload.is_empty():
        submenu_state = home_state.duplicate(true)
        submenu_state["route_payload"] = route_payload.duplicate(true)
    if route_id == "selection":
        if submenu_state == home_state:
            submenu_state = home_state.duplicate(true)
        submenu_state["selection"] = route_payload.duplicate(true)
    submenu.call("setup", submenu_state, home_snapshot)
    submenu.call("open_route", route_id, title, icon)
    submenu.visible = true
    if map_input_blocker:
        map_input_blocker.visible = true
    _layout_submenu()

func _close_home_submenu() -> void:
    if submenu != null:
        submenu.call("close_panel")
        submenu.visible = false
    if map_input_blocker:
        map_input_blocker.visible = false

func _on_submenu_closed() -> void:
    if submenu:
        submenu.visible = false
    if map_input_blocker:
        map_input_blocker.visible = false
    active_menu_id = map_context_menu_id
    _refresh_menu_styles()

func _on_submenu_action_requested(action_id: String = "", payload: Dictionary = {}) -> void:
    if action_id.is_empty():
        return
    if action_id == "route_opened":
        active_menu_id = String(payload.get("route_id", ""))
        _refresh_menu_styles()
        return
    match action_id:
        "system_selected":
            _route_home_action("focus_system", "", "", payload)
        "region_selected":
            _route_home_action("focus_region", "", "", payload)
        "fleet_selected":
            _open_related_selection(home_state.get("observed_fleets", []), "fleet_id", String(payload.get("fleet_id", "")), "함대")
        "external_power_selected":
            _open_related_selection(home_state.get("external_powers", []), "id", String(payload.get("external_power_id", "")), "외부 세력")
        "news_selected":
            var item = payload.get("item", {})
            if item is Dictionary:
                _route_home_action("selection", String(item.get("headline", item.get("title", "소식"))), "≡", item)
        "battle_selected":
            _open_related_selection(home_state.get("active_battles", []), "id", String(payload.get("battle_id", "")), "전투")

func _open_related_selection(rows, key: String, wanted: String, fallback_title: String) -> void:
    if not rows is Array:
        return
    for value in rows:
        if value is Dictionary and String(value.get(key, value.get("id", ""))) == wanted:
            var row: Dictionary = value.duplicate(true)
            if not row.has("type"):
                row["type"] = {"함대": "fleet", "외부 세력": "external_power", "전투": "battle", "권역": "region"}.get(fallback_title, "")
            var title := String(row.get("name", row.get("headline", fallback_title)))
            _route_home_action("selection", title, "◎", row)
            return

func _closest_playback_speed_index(value: float) -> int:
    var best_index := 0
    var best_distance := INF
    for index in range(playback_speeds.size()):
        var distance := absf(float(playback_speeds[index]) - value)
        if distance < best_distance:
            best_distance = distance
            best_index = index
    return best_index

func _on_map_blocker_gui_input(_event: InputEvent) -> void:
    get_viewport().set_input_as_handled()

func _refresh_menu_styles() -> void:
    for route_id in menu_buttons:
        var button: Button = menu_buttons[route_id]
        button.add_theme_stylebox_override("normal", HudStyle.button_selected_style() if String(route_id) == active_menu_id else HudStyle.button_style())
    for route_id in top_route_buttons:
        var button: Button = top_route_buttons[route_id]
        var selected := String(route_id) == active_menu_id
        if String(route_id) == "pause":
            selected = get_tree().paused
        elif String(route_id) == "speed":
            selected = playback_speed_index != 0
        button.add_theme_stylebox_override("normal", HudStyle.resource_selected_style() if selected else HudStyle.resource_style())

func _layout_submenu() -> void:
    if map_input_blocker:
        map_input_blocker.position = hud_safe_rect.position
        map_input_blocker.size = hud_safe_rect.size
    if submenu == null:
        return
    var panel_size := Vector2(
        minf(760.0, hud_safe_rect.size.x * 0.72),
        minf(float(submenu.call("preferred_height")) if submenu.has_method("preferred_height") else 540.0,
            hud_safe_rect.size.y - 36.0)
    )
    submenu.set_anchors_preset(Control.PRESET_TOP_LEFT)
    submenu.position = hud_safe_rect.get_center() - panel_size * 0.5
    submenu.size = panel_size

func _layout_ui() -> void:
    if ui_root == null:
        return
    var viewport_size := get_viewport().get_visible_rect().size
    var top_height := clampf(viewport_size.y * 0.078, 58.0, 70.0)
    var bottom_height := clampf(viewport_size.y * 0.225, 174.0, 210.0)
    var left_width := clampf(viewport_size.x * 0.115, 168.0, 184.0)
    var right_width := clampf(viewport_size.x * 0.188, 272.0, 302.0)
    var content_height := viewport_size.y - top_height - bottom_height

    top_panel.position = Vector2.ZERO
    top_panel.size = Vector2(viewport_size.x, top_height)
    left_panel.position = Vector2(0.0, top_height)
    left_panel.size = Vector2(left_width, content_height)
    right_panel.position = Vector2(viewport_size.x - right_width, top_height)
    right_panel.size = Vector2(right_width, content_height)
    bottom_panel.position = Vector2(0.0, viewport_size.y - bottom_height)
    bottom_panel.size = Vector2(viewport_size.x, bottom_height)

    hud_safe_rect = Rect2(left_width, top_height, viewport_size.x - left_width - right_width, content_height)
    map.set_input_safe_rect(hud_safe_rect)
    if minimap:
        minimap.set_map_screen_rect(hud_safe_rect)
    _layout_submenu()

func _on_selected(data: Dictionary) -> void:
    for c in inspector_body.get_children():
        c.queue_free()
    var title: Label = Label.new()
    title.text = str(data.get("name",""))
    title.add_theme_font_size_override("font_size",20)
    inspector_body.add_child(title)
    var body: Label = Label.new()
    body.text = "세력: %s\n유형: %s\n좌표: %s" % [
        str(data.get("faction","-")),
        str(data.get("type","-")),
        str(data.get("pos","-"))
    ]
    inspector_body.add_child(body)
    var selection_title := String(data.get("display_name", data.get("name", "선택 정보")))
    if String(data.get("type", "")) in ["capital", "fortress", "strategic"] and not selection_title.ends_with("성역"):
        selection_title += " 성역"
    _route_home_action("selection", selection_title, "◎", data)

func _on_zoom_level_changed(level: int) -> void:
    var names = ["","천하도","성역","우주 지형","함대","함선"]
    if zoom_label and level >= 0 and level < names.size():
        zoom_label.tooltip_text = names[level]
    for index in range(stage_buttons.size()):
        var route_id := String(stage_buttons[index].get_meta("route_id", ""))
        stage_buttons[index].add_theme_stylebox_override("normal",
            HudStyle.card_disabled_style() if route_id == "red_cliff_lock"
            else HudStyle.card_selected_style() if index + 1 == level
            else HudStyle.card_style())
        if index < stage_badges.size():
            stage_badges[index].add_theme_stylebox_override("panel", HudStyle.badge_style(index + 1 == level and route_id != "red_cliff_lock"))
    map_context_menu_id = "overview" if level == 1 else ("systems" if level == 2 else "")
    if submenu == null or not submenu.visible:
        active_menu_id = map_context_menu_id
        _refresh_menu_styles()
    if minimap:
        minimap.set_semantic_level(level)

func _display_faction(raw: String) -> String:
    return "마등·한수" if raw == "마등한수" else raw

func _has_active_red_cliff_battle(battles) -> bool:
    if not battles is Array:
        return false
    for battle in battles:
        if battle is Dictionary and String(battle.get("id", "")) == "BATTLE-RED-CLIFF" \
                and String(battle.get("status", "")) == "active":
            return true
    return false

func _current_status_rows() -> Array:
    var owners: Dictionary = home_state.get("region_owner", {})
    var owner_set := {}
    for owner in owners.values():
        if not String(owner).is_empty():
            owner_set[String(owner)] = true
    var present_external: Array[String] = []
    for power in home_state.get("external_powers", []):
        if String(power.get("status", "")) == "present":
            present_external.append(String(power.get("name", "")))
    var red_cliff_active := _has_active_red_cliff_battle(home_state.get("active_battles", []))
    return [
        ["◎", Color("99caff"), "건안 13년 캠페인 시작", "%d개 통치 세력 · 45개 권역" % owner_set.size()],
        ["◆", Color("6fc7ff"), "형주 북부권: %s" % _display_faction(String(owners.get("RGN-01", "미확인"))),
            "중부 %s · 남부 %s · 태양계 %s" % [_display_faction(String(owners.get("RGN-02", "미확인"))), _display_faction(String(owners.get("RGN-03", "미확인"))), _display_faction(String(owners.get("RGN-04", "미확인")))]],
        ["×", Color("ff8c78"), "적벽 전투: 교전 활성" if red_cliff_active else "적벽 전투: 미활성",
            "구지 궤도 · 전장 확인" if red_cliff_active else "5개 개전 조건 충족 전에는 전장 없음"],
        ["➜", Color("e3bd70"), "외부 관문: %s" % " · ".join(present_external), "영토가 아닌 접근축으로 표시"],
        ["◌", Color("8ea5b5"), "로마: 교역 배경", "사산조: 224년 이후 · 현재 비활성"],
    ]
