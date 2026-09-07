extends Node

signal battle_entry_requested(battle_id: String)

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
var ui_layer: CanvasLayer
var stage_badges: Array[PanelContainer] = []
var menu_buttons: Dictionary = {}
var top_route_buttons: Dictionary = {}
var red_cliff_banner: PanelContainer
var red_cliff_banner_action: Button
var red_cliff_banner_headline: Label
var battle_screen: PanelContainer
var battle_screen_state: Label
var battle_screen_battle_id := ""
var active_menu_id := "overview"
var map_context_menu_id := "overview"
var submenu: Control
var map_input_blocker: Control
var fleet_move_panel: Control
var tactical_route_view: Control
var fleet_voyage_view: Control
var projected_systems: Array = []
var data
var campaign
var playback_speeds := [1, 2, 4, 16, 64]
var playback_speed_index := 0
var pause_button: Button
var speed_button: Button
var resource_value_labels: Dictionary = {}
var resource_delta_labels: Dictionary = {}
var status_rows_container: VBoxContainer
var _terrain_data: Dictionary = {}
var _map_fleets: Array = []
var _route_payload: Dictionary = {}
var _selection_data: Dictionary = {}
var _fleet_navigation_state: Dictionary = {}
var _tactical_route_context: Dictionary = {}
var _refresh_count := 0
var stage_title_labels: Array[Label] = []
var stage_caption_labels: Array[Label] = []
var stage_previews: Array[TextureRect] = []

const WORLD_SIZE := Vector2(3200.0, 1800.0)
const CANONICAL_WORLD_SIZE := Vector2(37312.0, 30000.0)
const GameDataScript = preload("res://core/data/game_data.gd")
const CampaignScript = preload("res://core/campaign.gd")
const HomeMapSnapshotScript = preload("res://app/home_map_snapshot.gd")
const HOME_SUBMENU_PATH := "res://scripts/HomeSubmenu.gd"
const FLEET_MOVE_PANEL_PATH := "res://scripts/FleetMovePanel.gd"
const TACTICAL_ROUTE_VIEW_PATH := "res://app/views/tactical_route_view.gd"
const FLEET_VOYAGE_3D_PATH := "res://app/views/fleet_voyage_3d.gd"
var hud_safe_rect := Rect2(184.0, 70.0, 1116.0, 620.0)
var home_state: Dictionary = {}
var home_snapshot

func _ready() -> void:
    RenderingServer.set_default_clear_color(Color("#020a12"))
    var galaxy_data: Dictionary = _load_json("res://data/galaxy.json")
    _terrain_data = _load_json("res://data/terrain.json")
    data = GameDataScript.load_all()
    campaign = CampaignScript.scenario_03(data, 20803)
    campaign.world.player_faction = "손권"
    campaign.world.clock.speed = 1
    campaign.world.clock.paused = false
    playback_speed_index = 0
    home_snapshot = HomeMapSnapshotScript.from_campaign(campaign, 208,
        {"viewer_faction": "손권"})
    home_state = home_snapshot.snapshot()
    var systems: Array = _project_systems(home_state, campaign)
    projected_systems = systems
    var regions: Array = _project_regions(home_state)
    var bodies: Array = _project_body_rows(home_snapshot.visible_bodies(2))
    var routes: Array = _project_routes(home_state)
    _map_fleets = _adapt_observed_fleets(home_state, systems, regions)

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

    map.setup(cam, systems, _map_fleets, _terrain_data, regions, routes, bodies,
        home_state.get("active_battles", []), home_state.get("external_powers", []))
    map.set_input_safe_rect(hud_safe_rect)
    var continent: ConnectedContinent = ConnectedContinent.new()
    continent.name = "ConnectedContinent"
    map.add_child(continent)
    continent.build(_terrain_data)



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
    battle_entry_requested.connect(_open_red_cliff_battle_entry_shell)

    _build_ui(galaxy_data, systems)

func _process(delta: float) -> void:
    if campaign == null or campaign.ended or campaign.world.clock.paused:
        return
    if campaign.advance(int(delta * 1000.0)) > 0:
        _refresh_home_snapshot()

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


func _snapshot_runtime_context() -> Dictionary:
    var runtime := {"viewer_faction": "손권"}
    var provenance: Dictionary = home_state.get("provenance", {})
    for key in ["active_battles", "red_cliff_conditions", "news"]:
        var value = home_state.get(key)
        if key == "news":
            if value is Array:
                var safe_news: Array = []
                for item in value:
                    if not item is Dictionary:
                        continue
                    var row: Dictionary = (item as Dictionary).duplicate(true)
                    var battle_id := String(row.get("battle_id", ""))
                    var news_id := String(row.get("news_id", ""))
                    var action_battle_id := String(row.get("action_battle_id", ""))
                    if battle_id == Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID \
                            or news_id.begins_with(Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID + ":") \
                            or action_battle_id == Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID:
                        continue
                    safe_news.append(row)
                if not safe_news.is_empty() or String(provenance.get("news", "")) == "runtime_fixture":
                    runtime[key] = safe_news.duplicate(true)
            continue
        if (value is Array or value is Dictionary) and (not value.is_empty() \
                or String(provenance.get(key, "")) == "runtime_fixture"):
            runtime[key] = home_state[key].duplicate(true)
    return runtime


func _refresh_home_snapshot() -> void:
    if campaign == null:
        return
    var camera_position := cam.position
    var camera_zoom := cam.zoom
    var semantic := map.semantic_level
    var preserved_active_menu := active_menu_id
    var preserved_map_context := map_context_menu_id
    var submenu_was_visible := submenu != null and submenu.visible
    var selected := _resolve_selection(_selection_data)

    var next_snapshot = HomeMapSnapshotScript.from_campaign(
        campaign, 208, _snapshot_runtime_context())
    var next_state: Dictionary = next_snapshot.snapshot()
    var next_systems: Array = _project_systems(next_state, campaign)
    var next_regions: Array = _project_regions(next_state)
    var next_bodies: Array = _project_body_rows(next_snapshot.visible_bodies(2))
    var next_routes: Array = _project_routes(next_state)
    var next_fleets: Array = _adapt_observed_fleets(next_state, next_systems, next_regions)

    home_snapshot = next_snapshot
    home_state = next_state
    projected_systems = next_systems
    _map_fleets = next_fleets
    if not selected.is_empty():
        _selection_data = _resolve_selection(selected)
    map.setup(cam, projected_systems, _map_fleets, _terrain_data,
        next_regions, next_routes, next_bodies,
        home_state.get("active_battles", []), home_state.get("external_powers", []))
    map.semantic_level = semantic
    cam.position = camera_position
    cam.zoom = camera_zoom
    cam.reset_smoothing()
    if minimap:
        minimap.setup(cam, home_state, projected_systems, hud_safe_rect)
        minimap.set_semantic_level(semantic)
    _refresh_resource_labels()
    _refresh_status_rows()
    _refresh_red_cliff_banner()
    _refresh_battle_entry_shell()
    _refresh_stage_five()
    if submenu != null and submenu_was_visible:
        var submenu_state := home_state.duplicate(true)
        if not _route_payload.is_empty():
            submenu_state["route_payload"] = _route_payload.duplicate(true)
        if String(submenu.get("current_route")) == "selection" and not _selection_data.is_empty():
            submenu_state["selection"] = _selection_data.duplicate(true)
        submenu.call("setup", submenu_state, home_snapshot)
    active_menu_id = preserved_active_menu
    map_context_menu_id = preserved_map_context
    _refresh_menu_styles()
    if fleet_move_panel != null and fleet_move_panel.visible and fleet_move_panel.has_method("refresh"):
        fleet_move_panel.call("refresh")
    if tactical_route_view != null and tactical_route_view.visible and tactical_route_view.has_method("refresh"):
        tactical_route_view.call("refresh")
    _refresh_count += 1


func _resolve_selection(previous: Dictionary) -> Dictionary:
    if previous.is_empty():
        return {}
    var wanted := String(previous.get("id", ""))
    if wanted != "":
        for row in projected_systems:
            if String(row.get("id", "")) == wanted:
                return row.duplicate(true)
        for key in ["canonical_regions", "external_powers", "active_battles"]:
            for row in home_state.get(key, []):
                if String(row.get("id", "")) == wanted:
                    return row.duplicate(true)
    var fleet_id := str(previous.get("fleet_id", ""))
    if fleet_id != "":
        for row in home_state.get("observed_fleets", []):
            if str(row.get("fleet_id", "")) == fleet_id:
                return row.duplicate(true)
    return previous.duplicate(true)


## GalaxyMap의 legacy fleet renderer는 정확한 함선 수와 path를 요구한다. 안전
## snapshot에 정확한 ships가 있는 관측만 연결하며, 코어에 없는 항로/속도를 만들지
## 않는다. 이동 중에는 현재 성역→목적 권역 직선만 정적으로 그리고, 주둔은 같은 점
## 두 개를 사용한다.
func _adapt_observed_fleets(state: Dictionary, systems: Array, regions: Array) -> Array:
    var out: Array = []
    for observed in state.get("observed_fleets", []):
        if not observed is Dictionary or not observed.has("ships"):
            continue
        var start := _find_projected(systems, "id", str(observed.get("system_id", "")), Vector2(-1, -1))
        if start.x < 0.0:
            continue
        var finish := start
        var progress := 0.0
        if str(observed.get("status", "")) == "moving":
            var destination_id := str(observed.get("dest_region", ""))
            if destination_id != "":
                finish = _find_projected(regions, "id", destination_id, start)
            var fleet = _player_fleet(int(observed.get("fleet_id", -1)))
            if fleet != null and fleet.departure_tick >= 0 and fleet.arrival_tick > fleet.departure_tick:
                progress = clampf(float(campaign.world.clock.tick - fleet.departure_tick) \
                    / float(fleet.arrival_tick - fleet.departure_tick), 0.0, 1.0)
        var selection: Dictionary = observed.duplicate(true)
        selection["type"] = "fleet"
        out.append({
            "fleet_id": str(observed.get("fleet_id", "")),
            "name": str(observed.get("display_name", "관측 함대")),
            "faction": str(observed.get("faction", "")),
            "size": int(observed.ships),
            "path": [[start.x, start.y], [finish.x, finish.y]],
            # GalaxyMap의 과거 어댑터 계약. 실제 위치는 아래 progress 정본으로 읽는다.
            "speed": 0.0,
            "progress": progress,
            "selection": selection,
        })
    return out


func _resource_specs() -> Array:
    var scenario: Dictionary = home_state.get("scenario", {})
    var player: Dictionary = home_state.get("player_state", {})
    var year := int(scenario.get("year", 208))
    var month := int(scenario.get("month", 1))
    var era_year := 13 + (year - 208)
    var budget: Dictionary = player.get("budget", {})
    var net := int(budget.get("net", 0))
    var net_text := "%+d" % net if player.has("treasury") else ""
    return [
        ["resource:calendar", "◷", "건안 %d년 %d월" % [era_year, month], "", Color("75d989"), 126, "현재 캠페인 시점을 확인합니다.", "연대"],
        ["resource:funds", "◆", str(player.get("treasury", "—")), net_text, Color("8fe98f"), 98, "손권 세력의 실제 자금과 순변동을 확인합니다.", "자금"],
        ["resource:mandate", "◇", str(player.get("mandate", "—")), "", Color("8edfff"), 98, "손권 세력의 천명을 확인합니다.", "천명"],
        ["resource:hegemony", "✦", str(player.get("hegemony", "—")), "", Color("d4a9ff"), 98, "손권 세력의 패권 압력을 확인합니다.", "패권 압력"],
        ["resource:mobilized", "●", str(player.get("mobilized", "—")), "", Color("ffd875"), 92, "손권 세력의 실제 동원력을 확인합니다.", "동원력"],
        ["resource:capacity", "▲", "%s/%s" % [str(player.get("fleet_used_milli", "—")), str(player.get("fleet_capacity_milli", "—"))], "", Color("9edfff"), 106, "실제 함대 사용량과 수용량을 확인합니다.", "함대 수용량"],
    ]


func _resource_payload(route_id: String) -> Dictionary:
    for resource in _resource_specs():
        if String(resource[0]) == route_id:
            return {"display_value": String(resource[2]), "display_delta": String(resource[3])}
    return {}


func _refresh_resource_labels() -> void:
    for resource in _resource_specs():
        var route_id := String(resource[0])
        if resource_value_labels.has(route_id):
            (resource_value_labels[route_id] as Label).text = String(resource[2])
        if resource_delta_labels.has(route_id):
            (resource_delta_labels[route_id] as Label).text = String(resource[3])
    if submenu != null and submenu.visible and String(submenu.get("current_route")).begins_with("resource:"):
        _route_payload = _resource_payload(String(submenu.get("current_route")))


func _refresh_stage_five() -> void:
    if stage_buttons.size() < 5:
        return
    var active := _has_active_red_cliff_battle(home_state.get("active_battles", []))
    var button := stage_buttons[4]
    button.set_meta("route_id", "stage:5" if active else "red_cliff_lock")
    button.tooltip_text = "적벽 단계로 이동합니다." if active else "적벽 개전 조건이 아직 충족되지 않았습니다. 눌러 조건을 확인합니다."
    button.add_theme_stylebox_override("normal", HudStyle.card_style() if active else HudStyle.card_disabled_style())
    if stage_title_labels.size() >= 5:
        stage_title_labels[4].text = "적벽" if active else "🔒 적벽"
        stage_title_labels[4].add_theme_color_override("font_color", Color("eff9ff") if active else Color("8799a3"))
    if stage_caption_labels.size() >= 5:
        stage_caption_labels[4].text = "교전 활성" if active else "전투 조건 미충족"
        stage_caption_labels[4].add_theme_color_override("font_color", Color("e8f7ff") if active else Color("9babb3"))
    if stage_previews.size() >= 5:
        stage_previews[4].self_modulate = Color(0.78, 0.90, 1.0, 0.92) if active else Color(0.34, 0.40, 0.46, 0.68)
    _on_zoom_level_changed(map.semantic_level)

func _load_json(path: String) -> Dictionary:
    var f: FileAccess = FileAccess.open(path, FileAccess.READ)
    if f == null: return {}
    var parsed: Variant = JSON.parse_string(f.get_as_text())
    return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func _build_ui(galaxy: Dictionary, systems: Array) -> void:
    # The home HUD is rebuilt by state/viewport regression paths.  Keep a single
    # owned canvas layer so reconstructed UI cannot leave an earlier interrupt
    # banner (and its button signal) active underneath the new HUD.
    if is_instance_valid(ui_layer):
        ui_layer.free()
    ui_layer = null
    menu_buttons.clear()
    top_route_buttons.clear()
    active_menu_id = "overview"
    submenu = null
    map_input_blocker = null
    battle_screen = null
    battle_screen_state = null
    battle_screen_battle_id = ""
    if map != null:
        map.visible = true
    ui_layer = CanvasLayer.new()
    ui_layer.layer = 20
    add_child(ui_layer)

    ui_root = Control.new()
    ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    ui_root.process_mode = Node.PROCESS_MODE_ALWAYS
    ui_layer.add_child(ui_root)

    # Top bar
    top_panel = PanelContainer.new()
    ui_root.add_child(top_panel)
    top_panel.add_theme_stylebox_override("panel", HudStyle.panel_style(0.94))

    _build_red_cliff_banner()

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

    resource_value_labels.clear()
    resource_delta_labels.clear()
    var resources := _resource_specs()
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
        var resource_delta: Label = null
        if not String(resource[3]).is_empty():
            resource_delta = Label.new()
            resource_delta.text = String(resource[3])
            resource_delta.add_theme_font_size_override("font_size", 10)
            resource_delta.add_theme_color_override("font_color", Color(resource[4], 0.82))
            resource_delta.mouse_filter = Control.MOUSE_FILTER_IGNORE
            resource_row.add_child(resource_delta)
        b.add_child(resource_row)
        b.pressed.connect(_open_resource_route.bind(
            String(resource[0]), String(resource[7]), String(resource[1])))
        top_route_buttons[String(resource[0])] = b
        resource_value_labels[String(resource[0])] = resource_value
        if resource_delta != null:
            resource_delta_labels[String(resource[0])] = resource_delta
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

    status_rows_container = VBoxContainer.new()
    status_rows_container.add_theme_constant_override("separation", 5)
    right_v.add_child(status_rows_container)
    _refresh_status_rows()

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
    stage_title_labels.clear()
    stage_caption_labels.clear()
    stage_previews.clear()
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
        stage_previews.append(preview)
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
        stage_title_labels.append(title_label)
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
        stage_caption_labels.append(caption)
        b.add_child(caption_panel)
        var stage_route := "stage:%d" % (stage_index + 1)
        if is_locked_red_cliff:
            stage_route = "red_cliff_lock"
            b.tooltip_text = "적벽 개전 조건이 아직 충족되지 않았습니다. 눌러 조건을 확인합니다."
        else:
            b.tooltip_text = "%s 단계로 이동합니다." % String(s[0])
        b.set_meta("route_id", stage_route)
        b.pressed.connect(_on_stage_pressed.bind(stage_index, String(s[0]), s[3], float(s[4])))
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
    if not get_viewport().size_changed.is_connected(_layout_ui):
        get_viewport().size_changed.connect(_layout_ui)
    _ensure_submenu()
    _ensure_fleet_overlays()
    _layout_ui()
    _on_zoom_level_changed(map.semantic_level)
    if pause_button:
        pause_button.text = "▶" if campaign.world.clock.paused else "II"
    if speed_button:
        speed_button.text = "%dx" % int(playback_speeds[playback_speed_index])
    _refresh_menu_styles()
    _refresh_red_cliff_banner()


func _build_red_cliff_banner() -> void:
    red_cliff_banner = PanelContainer.new()
    red_cliff_banner.name = "RedCliffInterruptBanner"
    red_cliff_banner.visible = false
    red_cliff_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
    red_cliff_banner.add_theme_stylebox_override("panel", HudStyle.news_style())
    ui_root.add_child(red_cliff_banner)

    var row := HBoxContainer.new()
    row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_theme_constant_override("separation", 10)
    red_cliff_banner.add_child(row)

    var marker := Label.new()
    marker.text = "×"
    marker.custom_minimum_size = Vector2(24, 0)
    marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    marker.add_theme_font_size_override("font_size", 20)
    marker.add_theme_color_override("font_color", Color("ff5b7f"))
    marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(marker)

    red_cliff_banner_headline = Label.new()
    red_cliff_banner_headline.name = "Headline"
    red_cliff_banner_headline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    red_cliff_banner_headline.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    red_cliff_banner_headline.add_theme_font_size_override("font_size", 15)
    red_cliff_banner_headline.add_theme_color_override("font_color", Color("f5fbff"))
    red_cliff_banner_headline.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(red_cliff_banner_headline)

    red_cliff_banner_action = Button.new()
    red_cliff_banner_action.name = "OpenActiveBattle"
    red_cliff_banner_action.text = "전투 진입"
    red_cliff_banner_action.custom_minimum_size = Vector2(100, 32)
    red_cliff_banner_action.add_theme_font_size_override("font_size", 13)
    red_cliff_banner_action.add_theme_stylebox_override("normal", HudStyle.resource_style())
    red_cliff_banner_action.add_theme_stylebox_override("hover", HudStyle.resource_hover_style())
    red_cliff_banner_action.add_theme_stylebox_override("pressed", HudStyle.resource_pressed_style())
    red_cliff_banner_action.add_theme_stylebox_override("disabled", HudStyle.resource_disabled_style())
    red_cliff_banner_action.add_theme_stylebox_override("focus", HudStyle.resource_focus_style())
    red_cliff_banner_action.pressed.connect(_on_red_cliff_banner_pressed)
    row.add_child(red_cliff_banner_action)


func _refresh_red_cliff_banner() -> void:
    if red_cliff_banner == null:
        return
    var banner_item := _red_cliff_interrupt_banner_item()
    red_cliff_banner.visible = not banner_item.is_empty()
    if banner_item.is_empty():
        return
    if red_cliff_banner_headline != null:
        red_cliff_banner_headline.text = String(banner_item.get("headline", "적벽 전투 개전"))
    var action_battle_id := String(banner_item.get("action_battle_id", ""))
    red_cliff_banner_action.set_meta("action_id", String(banner_item.get("action_id", "")))
    red_cliff_banner_action.set_meta("action_battle_id", action_battle_id)
    red_cliff_banner_action.disabled = not bool(banner_item.get("can_open", false))
    red_cliff_banner_action.tooltip_text = "전투 진입은 아직 준비되지 않았습니다." \
        if red_cliff_banner_action.disabled else "적벽 전투 진입 요청을 보냅니다."


func _red_cliff_interrupt_banner_item() -> Dictionary:
    for value in home_state.get("news", []):
        if not value is Dictionary:
            continue
        var row: Dictionary = value
        if bool(row.get("is_interrupt_banner", false)) \
                and String(row.get("news_id", "")).begins_with(
                    Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID + ":") \
                and String(row.get("battle_id", "")) == Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID \
                and String(row.get("action_id", "")) == "open_active_battle" \
                and String(row.get("action_battle_id", "")) == Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID:
            return row.duplicate(true)
    return {}


func _on_red_cliff_banner_pressed() -> void:
    if red_cliff_banner_action == null:
        return
    _request_red_cliff_battle_entry(
        String(red_cliff_banner_action.get_meta("action_battle_id", "")))


func _request_red_cliff_battle_entry(battle_id: String) -> bool:
    # The display route ID (BATTLE-RED-CLIFF) is deliberately not accepted here.
    # This boundary receives and emits only the canonical Campaign battle identity.
    if battle_id != Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID or campaign == null:
        return false
    var banner_item := _red_cliff_interrupt_banner_item()
    if banner_item.is_empty() or not bool(banner_item.get("can_open", false)):
        return false
    for battle in campaign.active_battles:
        if String(battle.battle_id) == battle_id \
                and String(battle.status) == ActiveBattle.STATUS_ACTIVE \
                and int(battle.combat_phase) == 1 and bool(battle.entry_available):
            battle_entry_requested.emit(battle_id)
            return true
    return false


## This is deliberately a read-only entry shell, not the battle simulation.  The
## signal may be emitted by UI code, so repeat the canonical identity and active
## record checks at the receiving boundary rather than trusting a display route.
func _open_red_cliff_battle_entry_shell(battle_id: String) -> bool:
    if battle_id != Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID:
        return false
    var battle = _canonical_active_red_cliff_battle()
    if battle == null:
        return false
    _ensure_red_cliff_battle_entry_shell()
    if not is_instance_valid(battle_screen):
        return false
    battle_screen_battle_id = battle_id
    _set_home_ui_visible(false)
    map.visible = false
    battle_screen.visible = true
    _render_red_cliff_battle_state(battle)
    return true


func _canonical_active_red_cliff_battle():
    if campaign == null:
        return null
    for battle in campaign.active_battles:
        if String(battle.battle_id) == Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID \
                and String(battle.status) == ActiveBattle.STATUS_ACTIVE:
            return battle
    return null


func _ensure_red_cliff_battle_entry_shell() -> void:
    if is_instance_valid(battle_screen):
        return
    if ui_root == null:
        return
    battle_screen = PanelContainer.new()
    battle_screen.name = "RedCliffBattleEntryShell"
    battle_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    battle_screen.add_theme_stylebox_override("panel", HudStyle.panel_style(0.98))
    battle_screen.visible = false
    ui_root.add_child(battle_screen)

    var content := VBoxContainer.new()
    content.name = "Content"
    content.set_anchors_preset(Control.PRESET_CENTER)
    content.position = Vector2(-280.0, -150.0)
    content.size = Vector2(560.0, 300.0)
    content.add_theme_constant_override("separation", 16)
    battle_screen.add_child(content)

    var heading := Label.new()
    heading.name = "BattleTitle"
    heading.text = "적벽 전투"
    heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    heading.add_theme_font_size_override("font_size", 30)
    heading.add_theme_color_override("font_color", Color("f5fbff"))
    content.add_child(heading)

    var subtitle := Label.new()
    subtitle.name = "BattleLocation"
    subtitle.text = "구지 궤도 · 현재 전투 상태"
    subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    subtitle.add_theme_font_size_override("font_size", 16)
    subtitle.add_theme_color_override("font_color", Color("9fc6dc"))
    content.add_child(subtitle)

    battle_screen_state = Label.new()
    battle_screen_state.name = "State"
    battle_screen_state.size_flags_vertical = Control.SIZE_EXPAND_FILL
    battle_screen_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    battle_screen_state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    battle_screen_state.add_theme_font_size_override("font_size", 18)
    battle_screen_state.add_theme_color_override("font_color", Color("e8f7ff"))
    content.add_child(battle_screen_state)

    var close := Button.new()
    close.name = "ReturnHome"
    close.text = "천하도로 돌아가기"
    close.custom_minimum_size = Vector2(180.0, 38.0)
    close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    close.add_theme_stylebox_override("normal", HudStyle.resource_style())
    close.add_theme_stylebox_override("hover", HudStyle.resource_hover_style())
    close.add_theme_stylebox_override("pressed", HudStyle.resource_pressed_style())
    close.pressed.connect(_close_red_cliff_battle_entry_shell)
    content.add_child(close)


func _render_red_cliff_battle_state(battle) -> void:
    if battle_screen_state == null:
        return
    # These fields are copied only for display.  The shell never derives a new
    # battle from labels, faction ownership, or fleet counts.
    var formation_lines := ""
    var verdicts: Dictionary = campaign.active_battle_formation_verdicts(battle) if campaign != null else {}
    if not verdicts.is_empty():
        var attacker_verdict: Dictionary = verdicts.get("attacker", {})
        var defender_verdict: Dictionary = verdicts.get("defender", {})
        formation_lines = "\n진형: %s ×%.1f / %s ×%.1f" % [
            String(attacker_verdict.get("formation_name", "—")), float(attacker_verdict.get("combat_milli", 1000)) / 1000.0,
            String(defender_verdict.get("formation_name", "—")), float(defender_verdict.get("combat_milli", 1000)) / 1000.0,
        ]
    battle_screen_state.text = "정본 전투 ID: %s\n상태: %s\n전장: 구지 궤도 · %s / %s\n전투 단계: %d\n공격측: %s (%d척)\n방어측: %s (%d척)%s" % [
        String(battle.battle_id), String(battle.status),
        String(battle.region_id), String(battle.system_id), int(battle.combat_phase),
        String(battle.attacker_faction_id), battle.attacker_fleet_ids.size(),
        String(battle.defender_faction_id), battle.defender_fleet_ids.size(), formation_lines,
    ]


func _refresh_battle_entry_shell() -> void:
    if not is_instance_valid(battle_screen) or not battle_screen.visible:
        return
    var battle = _canonical_active_red_cliff_battle()
    if battle == null:
        # A shell already open remains an observation surface for the latest core
        # fact; it never manufactures a resolved/pending battle from UI state.
        battle_screen_state.text = "상태: 현재 활성 전투가 아닙니다."
        return
    _render_red_cliff_battle_state(battle)


func _set_home_ui_visible(visible: bool) -> void:
    for control in [top_panel, left_panel, right_panel, bottom_panel, red_cliff_banner]:
        if is_instance_valid(control):
            control.visible = visible


func _close_red_cliff_battle_entry_shell() -> void:
    if not is_instance_valid(battle_screen):
        return
    battle_screen.visible = false
    # Keep the observed canonical identity while the reusable shell is hidden.
    # Re-entry still revalidates it against Campaign, so this is not UI state
    # persistence and cannot resurrect a resolved record.
    map.visible = true
    _set_home_ui_visible(true)
    _refresh_red_cliff_banner()
    if map_input_blocker != null:
        map_input_blocker.visible = submenu != null and submenu.visible


func _refresh_status_rows() -> void:
    if status_rows_container == null:
        return
    for child in status_rows_container.get_children():
        status_rows_container.remove_child(child)
        child.queue_free()
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
        status_rows_container.add_child(row)

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


func _ensure_fleet_overlays() -> void:
    if ui_root == null:
        return
    if fleet_move_panel == null and ResourceLoader.exists(FLEET_MOVE_PANEL_PATH):
        var move_script: Script = load(FLEET_MOVE_PANEL_PATH)
        if move_script != null:
            var move_instance = move_script.new()
            if move_instance is Control:
                fleet_move_panel = move_instance as Control
                fleet_move_panel.name = "FleetMovePanel"
                fleet_move_panel.visible = false
                fleet_move_panel.mouse_filter = Control.MOUSE_FILTER_STOP
                ui_root.add_child(fleet_move_panel)
                fleet_move_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
                if fleet_move_panel.has_method("setup"):
                    fleet_move_panel.call("setup", data, campaign)
                if fleet_move_panel.has_signal("move_requested"):
                    fleet_move_panel.connect("move_requested", _on_fleet_move_requested)
                if fleet_move_panel.has_signal("closed"):
                    fleet_move_panel.connect("closed", _on_fleet_move_panel_closed)
            else:
                move_instance.queue_free()
    if tactical_route_view == null and ResourceLoader.exists(TACTICAL_ROUTE_VIEW_PATH):
        var route_script: Script = load(TACTICAL_ROUTE_VIEW_PATH)
        if route_script != null:
            var route_instance = route_script.new()
            if route_instance is Control:
                tactical_route_view = route_instance as Control
                tactical_route_view.name = "TacticalRouteView"
                tactical_route_view.visible = false
                tactical_route_view.mouse_filter = Control.MOUSE_FILTER_STOP
                ui_root.add_child(tactical_route_view)
                # TacticalRouteView의 _ready 기본값은 전체 화면이므로 호스트의
                # HUD 안전 영역 계약으로 자식 준비 완료 뒤 다시 제한한다.
                tactical_route_view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
                if tactical_route_view.has_method("setup"):
                    tactical_route_view.call("setup", data, campaign)
                if tactical_route_view.has_signal("closed"):
                    tactical_route_view.connect("closed", _on_tactical_route_closed)
                if tactical_route_view.has_signal("detail_requested"):
                    tactical_route_view.connect("detail_requested", _on_tactical_route_detail_requested)
                if tactical_route_view.has_signal("speed_requested"):
                    tactical_route_view.connect("speed_requested", _cycle_playback_speed)
            else:
                route_instance.queue_free()
    if fleet_voyage_view == null and ResourceLoader.exists(FLEET_VOYAGE_3D_PATH):
        var voyage_script: Script = load(FLEET_VOYAGE_3D_PATH)
        if voyage_script != null:
            var voyage_instance = voyage_script.new()
            if voyage_instance is Control:
                fleet_voyage_view = voyage_instance as Control
                fleet_voyage_view.name = "FleetVoyage3D"
                fleet_voyage_view.visible = false
                fleet_voyage_view.mouse_filter = Control.MOUSE_FILTER_STOP
                ui_root.add_child(fleet_voyage_view)
                fleet_voyage_view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
                if fleet_voyage_view.has_method("setup"):
                    fleet_voyage_view.call("setup", campaign)
                if fleet_voyage_view.has_signal("closed"):
                    fleet_voyage_view.connect("closed", _on_fleet_voyage_closed)
            else:
                voyage_instance.queue_free()
    _layout_fleet_overlays()

func _on_stage_pressed(stage_index: int, title: String, position: Vector2, zoom: float) -> void:
    var battle_active := _has_active_red_cliff_battle(home_state.get("active_battles", []))
    var locked := stage_index == 4 and not battle_active
    var route_id := "red_cliff_lock" if locked else "stage:%d" % (stage_index + 1)
    _route_home_action(route_id, "적벽 개전 조건" if locked else title,
        "🔒" if locked else str(stage_index + 1), {
            "position": position, "zoom": zoom, "battle_active": battle_active,
        })


func _open_resource_route(route_id: String, title: String, icon: String) -> void:
    _route_home_action(route_id, title, icon, _resource_payload(route_id))


func _route_home_action(route_id: String, title: String = "", icon: String = "", payload: Dictionary = {}) -> void:
    match route_id:
        "pause":
            campaign.world.clock.paused = not campaign.world.clock.paused
            if pause_button:
                pause_button.text = "▶" if campaign.world.clock.paused else "II"
            _refresh_home_snapshot()
            return
        "speed":
            _cycle_playback_speed()
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
    _route_payload = route_payload.duplicate(true)
    var submenu_state: Dictionary = home_state
    if not route_payload.is_empty():
        submenu_state = home_state.duplicate(true)
        submenu_state["route_payload"] = route_payload.duplicate(true)
    if route_id == "selection":
        if submenu_state == home_state:
            submenu_state = home_state.duplicate(true)
        submenu_state["selection"] = route_payload.duplicate(true)
        _selection_data = route_payload.duplicate(true)
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
            _open_related_selection(home_state.get("observed_fleets", []), "fleet_id", str(payload.get("fleet_id", "")), "함대")
        "fleet_move_requested":
            _open_fleet_move(int(payload.get("fleet_id", -1)))
        "fleet_route_requested":
            _open_tactical_route(int(payload.get("fleet_id", -1)))
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
        if value is Dictionary and str(value.get(key, value.get("id", ""))) == wanted:
            var row: Dictionary = value.duplicate(true)
            if not row.has("type"):
                row["type"] = {"함대": "fleet", "외부 세력": "external_power", "전투": "battle", "권역": "region"}.get(fallback_title, "")
            var title := str(row.get("display_name", row.get("name", row.get("headline", fallback_title))))
            _route_home_action("selection", title, "◎", row)
            return


func _open_fleet_move(fleet_id: int) -> void:
    var fleet = _player_fleet(fleet_id)
    if fleet == null or fleet.is_moving():
        return
    _ensure_fleet_overlays()
    if fleet_move_panel == null:
        return
    _capture_fleet_navigation_state()
    _block_home_for_fleet_overlay()
    if tactical_route_view != null:
        tactical_route_view.visible = false
    fleet_move_panel.visible = true
    fleet_move_panel.call("open_fleet", fleet_id)


func _open_tactical_route(fleet_id: int, pending_context: Dictionary = {}) -> void:
    if _player_fleet(fleet_id) == null:
        return
    _ensure_fleet_overlays()
    if tactical_route_view == null:
        return
    _capture_fleet_navigation_state()
    _block_home_for_fleet_overlay()
    if fleet_move_panel != null:
        fleet_move_panel.visible = false
    _tactical_route_context = pending_context.duplicate(true)
    tactical_route_view.visible = true
    tactical_route_view.call("open_fleet", fleet_id, pending_context)


func _on_fleet_move_requested(fleet_id: int, destination_region: String,
        preview: Dictionary) -> void:
    var fleet = _player_fleet(fleet_id)
    if fleet == null or fleet.is_moving() or destination_region == "":
        return
    _ensure_fleet_overlays()
    if tactical_route_view == null:
        return
    var from_system := String(fleet.at_system)
    var receipt: Dictionary = campaign.world.issue(Domestic.CMD_FLEET_MOVE, {
        "faction": String(fleet.owner),
        "fleet": fleet_id,
        "region": destination_region,
    }, 0)
    var pending_context := receipt.duplicate(true)
    pending_context["status"] = "pending"
    pending_context["command_seq"] = int(receipt.get("seq", -1))
    pending_context["from_system"] = from_system
    pending_context["dest_region"] = destination_region
    for key in ["estimated_arrival_tick", "expected_arrival_tick", "route_arrival_tick"]:
        if preview.has(key):
            pending_context[key] = preview[key]
    if not pending_context.has("estimated_arrival_tick") and preview.has("travel_ticks"):
        pending_context["estimated_arrival_tick"] = int(receipt.get("issued_tick", 0)) \
            + maxi(int(preview.get("travel_ticks", 0)), 1)
    if fleet_move_panel != null:
        fleet_move_panel.visible = false
    _open_tactical_route(fleet_id, pending_context)


func _on_fleet_move_panel_closed() -> void:
    if fleet_move_panel != null:
        fleet_move_panel.visible = false
    _restore_fleet_navigation_state()


func _on_tactical_route_closed(_fleet_id: int) -> void:
    if tactical_route_view != null:
        tactical_route_view.visible = false
    _tactical_route_context.clear()
    _restore_fleet_navigation_state()


func _on_tactical_route_detail_requested(fleet_id: int) -> void:
    _ensure_fleet_overlays()
    if fleet_voyage_view == null:
        return
    if tactical_route_view != null:
        tactical_route_view.visible = false
    fleet_voyage_view.visible = true
    fleet_voyage_view.call("open_fleet", fleet_id)


func _on_fleet_voyage_closed(fleet_id: int) -> void:
    if fleet_voyage_view != null:
        fleet_voyage_view.visible = false
    if tactical_route_view != null:
        tactical_route_view.visible = true
        tactical_route_view.call("open_fleet", fleet_id, _tactical_route_context)


func _capture_fleet_navigation_state() -> void:
    if not _fleet_navigation_state.is_empty():
        return
    _fleet_navigation_state = {
        "camera_position": cam.position,
        "camera_zoom": cam.zoom,
        "semantic": map.semantic_level,
        "active_menu": active_menu_id,
        "map_context": map_context_menu_id,
        "selection": _selection_data.duplicate(true),
        "route_payload": _route_payload.duplicate(true),
        "submenu_visible": submenu != null and submenu.visible,
        "submenu_route": String(submenu.get("current_route")) if submenu != null else "",
    }


func _block_home_for_fleet_overlay() -> void:
    if submenu != null:
        submenu.visible = false
    if map_input_blocker != null:
        map_input_blocker.visible = true
    if map != null:
        map.dragging = false
        map.set_process_unhandled_input(false)


func _restore_fleet_navigation_state() -> void:
    if _fleet_navigation_state.is_empty():
        if map_input_blocker != null:
            map_input_blocker.visible = false
        if map != null:
            map.set_process_unhandled_input(true)
        return
    var restored := _fleet_navigation_state.duplicate(true)
    _fleet_navigation_state.clear()
    cam.position = restored.get("camera_position", cam.position)
    cam.zoom = restored.get("camera_zoom", cam.zoom)
    cam.reset_smoothing()
    map.semantic_level = int(restored.get("semantic", map.semantic_level))
    active_menu_id = String(restored.get("active_menu", active_menu_id))
    map_context_menu_id = String(restored.get("map_context", map_context_menu_id))
    _selection_data = (restored.get("selection", {}) as Dictionary).duplicate(true)
    _route_payload = (restored.get("route_payload", {}) as Dictionary).duplicate(true)
    var restore_submenu := bool(restored.get("submenu_visible", false))
    if submenu != null:
        if restore_submenu:
            var submenu_state := home_state.duplicate(true)
            if not _route_payload.is_empty():
                submenu_state["route_payload"] = _route_payload.duplicate(true)
            if String(restored.get("submenu_route", "")) == "selection" \
                    and not _selection_data.is_empty():
                submenu_state["selection"] = _selection_data.duplicate(true)
            submenu.call("setup", submenu_state, home_snapshot)
        submenu.visible = restore_submenu
    if map_input_blocker != null:
        map_input_blocker.visible = restore_submenu
    map.set_process_unhandled_input(true)
    _refresh_menu_styles()


func _player_fleet(fleet_id: int):
    if campaign == null or fleet_id < 0:
        return null
    for fleet in campaign.fleets:
        if int(fleet.id) == fleet_id and String(fleet.owner) == String(campaign.world.player_faction) \
                and fleet.is_alive():
            return fleet
    return null

func _closest_playback_speed_index(value: float) -> int:
    var best_index := 0
    var best_distance := INF
    for index in range(playback_speeds.size()):
        var distance := absf(float(playback_speeds[index]) - value)
        if distance < best_distance:
            best_distance = distance
            best_index = index
    return best_index


func _cycle_playback_speed() -> void:
    if campaign == null or campaign.world == null:
        return
    playback_speed_index = (playback_speed_index + 1) % playback_speeds.size()
    campaign.world.clock.speed = playback_speeds[playback_speed_index]
    if speed_button:
        speed_button.text = "%dx" % int(playback_speeds[playback_speed_index])
    _refresh_home_snapshot()

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
            selected = campaign != null and campaign.world.clock.paused
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


func _layout_fleet_overlays() -> void:
    if fleet_move_panel != null:
        var move_size := Vector2(
            minf(760.0, hud_safe_rect.size.x - 36.0),
            minf(560.0, hud_safe_rect.size.y - 36.0)
        )
        fleet_move_panel.position = hud_safe_rect.get_center() - move_size * 0.5
        fleet_move_panel.size = move_size
    if tactical_route_view != null:
        tactical_route_view.position = hud_safe_rect.position
        tactical_route_view.size = hud_safe_rect.size
    if fleet_voyage_view != null:
        fleet_voyage_view.position = hud_safe_rect.position
        fleet_voyage_view.size = hud_safe_rect.size

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
    if red_cliff_banner != null:
        red_cliff_banner.position = Vector2(left_width + 12.0, top_height + 8.0)
        red_cliff_banner.size = Vector2(
            maxf(0.0, viewport_size.x - left_width - right_width - 24.0), 42.0)
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
    _layout_fleet_overlays()

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
