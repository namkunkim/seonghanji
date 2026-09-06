class_name FleetMovePanel
extends PanelContainer

## 아군 주둔 함대의 이동 목적지를 고르는 비차단 요청 패널.
##
## 경로·회랑·지형·소요는 전부 `Orders.resolve_move`의 결과만 표시한다.
## 이 패널은 캠페인을 변경하지 않으며, 실제 발행은 호스트가 signal을 받아 맡는다.

signal move_requested(fleet_id: int, destination_region: String, preview: Dictionary)
signal closed

var data: GameData
var campaign: Campaign

var _fleet_id: int = -1
var _selected_region: String = ""
var _candidate_previews: Array[Dictionary] = []

var _heading: Label
var _content: VBoxContainer


func _ready() -> void:
	custom_minimum_size = Vector2(620.0, 420.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	add_theme_stylebox_override("panel", _panel_style())
	visibility_changed.connect(_on_visibility_changed)
	_build_shell()
	visible = _fleet_id >= 0
	set_process_unhandled_key_input(visible)


func setup(data_ref: GameData, campaign_ref: Campaign) -> void:
	data = data_ref
	campaign = campaign_ref
	if is_node_ready() and visible:
		refresh()


func open_fleet(fleet_id: int) -> void:
	_fleet_id = fleet_id
	_selected_region = ""
	visible = true
	if is_node_ready():
		refresh()
		grab_focus()


func close_panel() -> void:
	if not visible:
		return
	visible = false
	_selected_region = ""
	closed.emit()


## 현재 갱신에서 판정한 후보의 깊은 복사본. 시험과 호스트 미리보기에 쓴다.
func candidate_previews() -> Array:
	return _candidate_previews.duplicate(true)


func refresh() -> void:
	if not is_node_ready() or _content == null:
		return
	_clear(_content)
	_candidate_previews.clear()

	if data == null or campaign == null or campaign.world == null:
		_heading.text = "함대 이동"
		_add_notice("이동 정보를 불러올 수 없습니다.", "캠페인 또는 정본 데이터가 없습니다.")
		return

	var fleet = _find_fleet(_fleet_id)
	if fleet == null or not fleet.is_alive():
		_heading.text = "함대 이동"
		_add_notice("함대를 찾을 수 없습니다.", "소실되었거나 존재하지 않는 함대입니다.")
		return
	if String(fleet.owner) != String(campaign.world.player_faction):
		_heading.text = "제%d함대 이동" % _fleet_id
		_add_notice("이동 명령을 내릴 수 없습니다.", "플레이어 세력의 함대가 아닙니다.")
		return

	_heading.text = "제%d함대 이동" % _fleet_id
	_add_pair("출발", _system_label(String(fleet.at_system)))
	_add_pair("현재 진형", String(fleet.formation))

	if fleet.is_moving():
		_render_moving(fleet)
		return

	_build_candidates(fleet)
	if _candidate_previews.is_empty():
		_add_notice("이동 가능한 목적지가 없습니다.", Orders.UNREACHABLE_REASON)
		return

	_add_section("목적 권역")
	for preview in _candidate_previews:
		_add_candidate_button(preview)

	if _selected_region != "":
		var selected := _preview_for(_selected_region)
		if not selected.is_empty():
			_render_preview(selected)


func _build_shell() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 9)
	add_child(root)

	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 52.0
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)
	_heading = Label.new()
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_heading.add_theme_font_size_override("font_size", 22)
	_heading.add_theme_color_override("font_color", Color("effaff"))
	header.add_child(_heading)
	var close_button := Button.new()
	close_button.text = "닫기  ×"
	close_button.tooltip_text = "함대 이동 패널 닫기 (Esc)"
	close_button.pressed.connect(close_panel)
	header.add_child(close_button)

	var separator := HSeparator.new()
	root.add_child(separator)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 7)
	scroll.add_child(_content)


func _build_candidates(fleet) -> void:
	var region_ids: Array[String] = data.region_ids.duplicate()
	region_ids.sort()
	for region_id in region_ids:
		var preview := _resolve_preview(fleet, region_id)
		if bool(preview.get("ok", false)):
			_candidate_previews.append(preview)
	if _selected_region != "" and _preview_for(_selected_region).is_empty():
		_selected_region = ""


func _resolve_preview(fleet, destination_region: String) -> Dictionary:
	var result: Dictionary = Orders.resolve_move(
		campaign.world.graph, data, String(fleet.at_system), destination_region)
	var preview := {
		"ok": bool(result.get("ok", false)),
		"status": "preview",
		"error": String(result.get("reason", "")),
		"fleet_id": int(fleet.id),
		"from_system": String(fleet.at_system),
		"origin_system": String(fleet.at_system),
		"destination_region": destination_region,
		"dest_region": destination_region,
		"destination_system": String(result.get("dest_system", "")),
		"path": (result.get("path", []) as Array).duplicate(true),
		"corridors": (result.get("corridor_ids", []) as Array).duplicate(true),
		"corridor_ids": (result.get("corridor_ids", []) as Array).duplicate(true),
		"terrain": String(result.get("terrain", "")),
		"travel_ticks": int(result.get("travel_ticks", -1)),
		"formation": String(fleet.formation),
		"forced_formation": String(result.get("forced_formation", "")),
		"allowed_formations": (result.get("allowed_formations", []) as Array).duplicate(true),
	}
	return preview


func _render_moving(fleet) -> void:
	_add_section("이동 중 · 읽기 전용")
	var destination_region := String(fleet.target_region)
	var preview := _resolve_preview(fleet, destination_region)
	if not bool(preview.get("ok", false)):
		_add_notice("현재 항로를 판독할 수 없습니다.", String(preview.get("error", "")))
		return
	_add_pair("목적", _region_label(destination_region))
	_add_pair("경로", _path_label(preview.get("path", [])))
	_add_pair("회랑", _corridor_label(preview.get("corridors", [])))
	_add_pair("지형", _terrain_label(preview))
	_add_pair("도착", "틱 %d · 남은 %s" % [
		int(fleet.arrival_tick), _duration(maxi(0,
			int(fleet.arrival_tick) - int(campaign.world.clock.tick)))])
	_add_notice("이미 이동 중입니다.", "도착할 때까지 목적지를 다시 지정할 수 없습니다.")


func _add_candidate_button(preview: Dictionary) -> void:
	var region_id := String(preview.get("destination_region", ""))
	var button := Button.new()
	button.toggle_mode = true
	button.button_pressed = region_id == _selected_region
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 44.0
	button.focus_mode = Control.FOCUS_ALL
	button.text = "%s  ·  %s  ·  %s" % [
		_region_label(region_id),
		_duration(int(preview.get("travel_ticks", -1))),
		String(preview.get("terrain", "개활"))]
	button.tooltip_text = "%s → %s" % [
		_path_label(preview.get("path", [])),
		_corridor_label(preview.get("corridors", []))]
	button.pressed.connect(_select_region.bind(region_id))
	_content.add_child(button)


func _select_region(region_id: String) -> void:
	_selected_region = region_id
	refresh()


func _render_preview(preview: Dictionary) -> void:
	_content.add_child(HSeparator.new())
	_add_section("이동 미리보기")
	_add_pair("출발", _system_label(String(preview.get("from_system", ""))))
	_add_pair("목적", _region_label(String(preview.get("destination_region", ""))))
	_add_pair("경로", _path_label(preview.get("path", [])))
	_add_pair("회랑", _corridor_label(preview.get("corridors", [])))
	_add_pair("지형", _terrain_label(preview))
	_add_pair("소요", _duration(int(preview.get("travel_ticks", -1))))
	var forced := String(preview.get("forced_formation", ""))
	if forced != "":
		_add_notice("진형 제한", "%s으로 고정되는 항로입니다." % forced)

	var request_button := Button.new()
	request_button.text = "이동 요청"
	request_button.custom_minimum_size.y = 48.0
	request_button.tooltip_text = "호스트에 이동 명령 발행을 요청합니다."
	request_button.pressed.connect(_emit_move_request.bind(
		String(preview.get("destination_region", ""))))
	_content.add_child(request_button)


func _emit_move_request(destination_region: String) -> void:
	var fleet = _find_fleet(_fleet_id)
	if fleet == null or not fleet.is_alive() or fleet.is_moving():
		refresh()
		return
	if String(fleet.owner) != String(campaign.world.player_faction):
		refresh()
		return
	# 클릭 뒤 세계가 변했을 수 있으므로 signal 직전에 코어 판정을 다시 낸다.
	var preview := _resolve_preview(fleet, destination_region)
	if not bool(preview.get("ok", false)):
		refresh()
		return
	move_requested.emit(_fleet_id, destination_region, preview.duplicate(true))


func _preview_for(region_id: String) -> Dictionary:
	for preview in _candidate_previews:
		if String(preview.get("destination_region", "")) == region_id:
			return preview
	return {}


func _find_fleet(fleet_id: int):
	if campaign == null:
		return null
	for fleet in campaign.fleets:
		if fleet != null and int(fleet.id) == fleet_id:
			return fleet
	return null


func _system_label(system_id: String) -> String:
	if system_id == "":
		return "정보 없음"
	return "%s성역 (%s)" % [data.system_name(system_id), system_id]


func _region_label(region_id: String) -> String:
	if region_id == "" or not data.regions.has(region_id):
		return "정보 없음"
	return "%s · %s성역" % [
		String(data.regions[region_id].get("name", region_id)),
		data.system_name(data.system_of(region_id))]


func _path_label(path) -> String:
	if not path is Array or path.is_empty():
		return "—"
	var names: Array[String] = []
	for system_id in path:
		names.append(data.system_name(String(system_id)))
	return " → ".join(names)


func _corridor_label(corridors) -> String:
	if not corridors is Array or corridors.is_empty():
		return "없음"
	var names: Array[String] = []
	for corridor_id in corridors:
		var cid := String(corridor_id)
		if data.corridors.has(cid):
			names.append(String(data.corridors[cid].get("name", cid)))
		else:
			names.append(cid)
	return " · ".join(names)


func _terrain_label(preview: Dictionary) -> String:
	var terrain := String(preview.get("terrain", "개활"))
	var forced := String(preview.get("forced_formation", ""))
	return "%s · %s 고정" % [terrain, forced] if forced != "" else terrain


static func _duration(ticks: int) -> String:
	if ticks < 0:
		return "닿지 않음"
	if ticks == 0:
		return "즉시"
	return "%.1fh" % (ticks / 60.0)


func _add_section(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color("8ee7fa"))
	_content.add_child(label)


func _add_pair(key: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_content.add_child(row)
	var key_label := Label.new()
	key_label.text = key
	key_label.custom_minimum_size.x = 84.0
	key_label.add_theme_color_override("font_color", Color("8faebd"))
	row.add_child(key_label)
	var value_label := Label.new()
	value_label.text = value
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value_label.add_theme_color_override("font_color", Color("e8f5fa"))
	row.add_child(value_label)


func _add_notice(title: String, detail: String) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	_content.add_child(box)
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_color_override("font_color", Color("ffd38a"))
	box.add_child(title_label)
	var detail_label := Label.new()
	detail_label.text = detail
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.add_theme_color_override("font_color", Color("abc3cf"))
	box.add_child(detail_label)


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()


func _on_visibility_changed() -> void:
	set_process_unhandled_key_input(visible)


static func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.055, 0.085, 0.97)
	style.border_color = Color(0.35, 0.70, 0.84, 0.82)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 16.0
	return style
