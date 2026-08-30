class_name StarmapView
extends Control

## **`SC-L2` 성역 뷰** — S3.3 (`screens.md` §2)
##
## > 전략 지도 · 권역 소유 · 함대 위치. L1 에서 성역 노드를 탭하면 들어온다.
##
## ```
## ┌──────────────────────────────────────────────┐
## │ ◀ 성도        형주성역        [일괄] [필터]  │
## ├──────────────────────────────────────────────┤
## │  상단 — 권역 관계도 (RegionGraph)            │
## ├──────────────────────────────────────────────┤
## │  하단 — 권역 카드 (RegionCard × 2~4)         │
## └──────────────────────────────────────────────┘
## ```
##
## **상단은 관계도, 하단은 카드다.** 권역은 2~4개뿐이므로 한 화면에 전부 들어간다 —
## **스크롤을 만들지 않는다** (§2.1).
##
## 시각 바는 이 화면의 것이 아니다. **소유는 S3.2 게임 루프**이고 여기는 참조만 한다 (§1.2).

signal system_changed(system_id: String)

var data: GameData
var campaign: Campaign
var system_id: String = ""
var start_year: int = 208

var _title: Label
var _flags: Label
var _btn_back: Button
var _btn_batch: Button
var _btn_filter: Button
var _filter_bar: HBoxContainer
var _graph: RegionGraph
var _cards_box: VBoxContainer
var _sheet: HalfSheet
var _detail: DetailView                          # SC-L3 세부 뷰 (S3.4) — 전체 화면 오버레이
var _fleet: FleetScreens                         # SC-F1~F3 함대 편성 UI (S3.6) — 전체 화면 오버레이
var _btn_fleet: Button
var _cards: Array[RegionCard] = []

## 필터 (§2.4 — 국력순 · 위험순 · 미개발순 · 직할만)
var _sort_mode: String = "기본"
var _own_only: bool = false


func setup(d: GameData, c: Campaign, sid: String) -> void:
	data = d
	campaign = c
	_build()
	set_system(sid)


func _build() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 10)
	add_child(col)

	# ---- 머리줄
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	head.custom_minimum_size = Vector2(0, 60)
	col.add_child(head)

	_btn_back = _button(head, "◀ 성도", 150)
	_btn_back.disabled = true                      # L1 성도는 아직 없다
	_btn_back.tooltip_text = "L1 성도 — 미구현"

	_title = Label.new()
	_title.theme_type_variation = &"Title"   # FNT-002 (wght 700) · UiPalette.make_theme
	_title.add_theme_font_size_override("font_size", 26)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)

	_flags = Label.new()
	_flags.add_theme_font_size_override("font_size", 19)
	_flags.add_theme_color_override("font_color", UiPalette.DANGER)
	_flags.custom_minimum_size = Vector2(200, 0)
	head.add_child(_flags)

	_btn_batch = _button(head, "일괄", 120)
	_btn_batch.disabled = true                     # 성역 단위 명령은 S3.5 다
	_btn_batch.tooltip_text = "성역 단위 일괄 명령 — 명령 메뉴(S3.5) 미구현"
	# L1 성도(§4.3 「◀ 손권」의 자리)가 없어 여기에 둔다 — SC-F1 함대 목록 진입점.
	_btn_fleet = _button(head, "함대", 120)
	_btn_fleet.tooltip_text = "함대 목록 SC-F1 — 규모 · 배치 · 유지점/지휘 한도"
	_btn_fleet.pressed.connect(func(): _fleet.open_list(campaign.world.player_faction))
	_btn_filter = _button(head, "필터", 120)
	_btn_filter.pressed.connect(func(): _filter_bar.visible = not _filter_bar.visible)

	# ---- 필터 줄 (비차단 — 팝업이 아니라 제자리에서 열린다)
	_filter_bar = HBoxContainer.new()
	_filter_bar.add_theme_constant_override("separation", 10)
	_filter_bar.visible = false
	col.add_child(_filter_bar)
	for mode in ["기본", "국력순", "위험순", "미개발순"]:
		var b := _button(_filter_bar, mode, 130)
		b.pressed.connect(_set_sort.bind(mode))
	var own := _button(_filter_bar, "직할만", 140)
	own.toggle_mode = true
	own.toggled.connect(func(on: bool):
		_own_only = on
		_rebuild_cards())

	# ---- 상단 관계도
	_graph = RegionGraph.new()
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph.size_flags_stretch_ratio = 1.15
	_graph.start_year = start_year
	_graph.region_tapped.connect(_on_region_tapped)
	_graph.region_long_pressed.connect(_on_region_long_pressed)
	_graph.fleet_tapped.connect(_on_fleet_tapped)
	_graph.swiped.connect(_on_swiped)
	col.add_child(_graph)

	var sep := HSeparator.new()
	col.add_child(sep)

	# ---- 하단 권역 카드
	_cards_box = VBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 8)
	_cards_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_cards_box)

	# ---- 하프 시트 (카드 영역만 덮는다. **관계도는 계속 보인다**)
	_sheet = HalfSheet.new()
	_sheet.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_sheet.anchor_top = 0.62                       # 카드만 덮는다 — 지도는 계속 보인다
	_sheet.anchor_bottom = 1.0
	_sheet.offset_top = 0
	_sheet.offset_bottom = 0
	_sheet.start_year = start_year
	_sheet.setup(data, campaign)
	_sheet.detail_requested.connect(_open_detail)
	_sheet.compose_requested.connect(func(fid: int): _open_fleet_screen("compose", fid))
	_sheet.appoint_requested.connect(func(fid: int): _open_fleet_screen("appoint", fid))
	add_child(_sheet)

	# ---- 세부 뷰 SC-L3 (S3.4). **전체 화면** — 지도를 겹치지 않고 덮는다 (§0.2).
	# 시각 바는 이 뷰 밖(main.gd `$Root/TimeBar`)이라 계속 보인다.
	_detail = DetailView.new()
	_detail.set_anchors_preset(Control.PRESET_FULL_RECT)
	_detail.start_year = start_year
	_detail.setup(data, campaign)
	_detail.closed.connect(func(): refresh())
	add_child(_detail)

	# ---- 함대 편성 UI SC-F1~F3 (S3.6). **전체 화면 오버레이** — L2 위에 얹힌다 (§4.1).
	_fleet = FleetScreens.new()
	_fleet.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fleet.setup(data, campaign, start_year)
	_fleet.closed.connect(func(): refresh())
	add_child(_fleet)


## 함대 시트 [편성 ▸] / [임명 ▸] 에서 온다 (§2.6 · §3.4 전이도). 시트를 닫고 전체 화면으로.
func _open_fleet_screen(which: String, fleet_id: int) -> void:
	if _sheet.visible:
		_sheet.close()
	if which == "compose":
		_fleet.open_compose(fleet_id, false)
	else:
		_fleet.open_appoint(fleet_id, false)


func _button(parent: Node, text: String, w: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 52)         # 손가락 크기 (ui-design.md)
	b.focus_mode = Control.FOCUS_NONE
	parent.add_child(b)
	return b


func _set_sort(mode: String) -> void:
	_sort_mode = mode
	_rebuild_cards()


# ---------------------------------------------------------------- 성역 전환
func set_system(sid: String) -> void:
	if sid == "" or not data.systems.has(sid):
		return
	system_id = sid
	if _sheet.visible:
		_sheet.close()
	if _detail != null and _detail.visible:
		_detail.close()
	if _fleet != null and _fleet.visible:
		_fleet.close_screen()
	_graph.set_context(data, campaign, sid)
	_rebuild_cards()
	refresh()
	system_changed.emit(sid)


## 좌우 스와이프 — **L1 을 거치지 않는다** (§2.5).
##
## ⚠ `screens.md` 검토 8 은 **성역 19개의 순서가 정의되어 있지 않다**고 적었다.
## 여기서는 **인접 성역을 ID 순으로 순환**한다. 「인접 성역 우선인지 ID 순인지」의
## 답을 정한 것이 아니라, 둘 다 만족하는 가장 좁은 해석을 택한 것이다 —
## 정본이 생기면 이 함수만 바꾼다.
func _on_swiped(dir: int) -> void:
	var nbs: Array = data.neighbors.get(system_id, [])
	if nbs.is_empty():
		return
	var idx := 0 if dir > 0 else nbs.size() - 1
	set_system(String(nbs[idx]))


# ---------------------------------------------------------------- 카드
func _rebuild_cards() -> void:
	for c in _cards:
		c.queue_free()
	_cards.clear()
	var rids := _ordered_regions()
	for rid in rids:
		var card := RegionCard.new()
		_cards_box.add_child(card)
		card.setup(data, campaign, rid)
		card.tapped.connect(_on_region_tapped)
		card.long_pressed.connect(_on_region_long_pressed)
		_cards.append(card)


## 정렬·필터. **틱마다 다시 세우지 않는다** —
## 순서가 손가락 아래에서 바뀌면 잘못 누르게 된다. 필터를 만질 때만 다시 센다.
func _ordered_regions() -> Array[String]:
	var out: Array[String] = []
	var player := campaign.world.player_faction
	for rid in data.regions_of.get(system_id, []):
		var st: RegionState = campaign.world.region_states[rid]
		# 「직할만」 — 플레이어 소유이면서 위임하지 않은 권역
		if _own_only and (st.owner != player or st.delegated):
			continue
		out.append(String(rid))
	match _sort_mode:
		"국력순":
			out.sort_custom(func(a, b): return data.region_power(a) > data.region_power(b))
		"위험순":
			out.sort_custom(func(a, b):
				return RegionFlags.danger(data, campaign, a) \
					> RegionFlags.danger(data, campaign, b))
		"미개발순":
			out.sort_custom(func(a, b): return _dev_left(a) > _dev_left(b))
	return out


func _dev_left(rid: String) -> int:
	var st: RegionState = campaign.world.region_states[rid]
	return data.region_dev_slots(rid) - st.development


# ---------------------------------------------------------------- 조작 (§2.5)
func _on_region_tapped(rid: String) -> void:
	_sheet.open_region(rid)


func _on_region_long_pressed(rid: String) -> void:
	# 롱탭 → 세부 뷰 `SC-L3` 직행 (§2.5)
	_open_detail(rid)


## 하프 시트 [세부 ▸] · 카드 롱탭 두 경로가 여기로 온다 (§2.6 전이도).
func _open_detail(rid: String) -> void:
	if rid == "":
		return
	if _sheet.visible:
		_sheet.close()
	_detail.open(rid)


func _on_fleet_tapped(fleet_id: int) -> void:
	_sheet.open_fleet(fleet_id)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not (event as InputEventKey).echo):
		return
	# 태블릿에는 없는 입력이다. **검증용**으로만 둔다 (스와이프와 같은 일을 한다)
	var busy := _detail.visible or _fleet.visible
	match (event as InputEventKey).keycode:
		KEY_LEFT:
			if not busy:
				_on_swiped(-1)
		KEY_RIGHT:
			if not busy:
				_on_swiped(1)
		KEY_ESCAPE:
			if _fleet.visible:
				_fleet.close_screen()
			elif _detail.visible:
				_detail.close()
			elif _sheet.visible:
				_sheet.close()


# ---------------------------------------------------------------- 갱신
## **조항 ② — 화면이 읽는 값은 스냅샷이 아니라 구독이다.**
## 게임 루프가 틱을 넘길 때마다 불린다. 시트가 열려 있어도 계속 갱신된다.
func refresh() -> void:
	if data == null or system_id == "":
		return
	# 화면 이름은 **성역으로 통일한다** (§0.1). 공식 명칭(`display_name`)이
	# 통칭과 다를 때만 괄호로 덧붙인다 — 사예성역(중앙성역)이 그 경우다.
	var sys: Dictionary = data.systems[system_id]
	_title.text = "%s성역" % String(sys["name"])
	var official := String(sys.get("display_name", ""))
	if official != "" and official != _title.text:
		_title.text += "   (%s)" % official
	_flags.text = "⚔ 분쟁" if _split() else ""
	_graph.refresh()
	for c in _cards:
		c.refresh()
	_sheet.refresh()
	_detail.refresh()          # 열려 있으면 매 틱 구독 갱신 (조항 ②)
	_fleet.refresh()           # 편성/임명 화면도 값이 흐른다 (§1.1 ①②)


## 이 성역이 두 세력 이상에 나뉘어 있는가 (§2.2 분쟁).
func _split() -> bool:
	var seen := {}
	for rid in data.regions_of.get(system_id, []):
		var st: RegionState = campaign.world.region_states[rid]
		if st.owner != "":
			seen[st.owner] = true
	return seen.size() >= 2
