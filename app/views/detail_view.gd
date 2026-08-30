class_name DetailView
extends Control

## **`SC-L3` 세부 뷰** — S3.4 (`screens.md` §3)
##
## > 권역 내부 4층 · 함대 아이콘 · 진형. 요구 B6 의 「진형 갖춘 함대」가 여기다.
##
## ```
## ┌──────────────────────────────────────────────┐
## │ ◀ 형주성역        중부권 ★           [편성]  │   ← 시각 바는 부모(main.gd)의 것
## ├──────────────────────────────────────────────┤
## │  외곽 / 궤도권 / 식민지 / 지구형 행성  (LayerStrip)
## ├──────────────────────────────────────────────┤
## │  ▣ 제3함대 …  ◤◥ 어린   사기 ███░ 72   (FleetRow × n · 스크롤)
## └──────────────────────────────────────────────┘
## ```
##
## §0.2 — 세부 뷰는 **전체 화면**이다(하프 시트와 달리 지도를 겹치지 않는다).
## L2(StarmapView) 위에 꽉 차게 덮고, ◀ 로 닫으면 L2 로 돌아간다. 깊이는 L1→L2→L3.
##
## §1 다섯 조항을 지킨다.
##   ① 화면은 시뮬레이션을 멈추지 않는다 — `refresh()` 가 매 틱 불린다
##   ② 값은 구독이다 — 열어 둔 채 바뀌면 그 자리에서 (FleetRow·LayerStrip 각자)
##   ③ 확정하지 않은 조작은 세계에 없다 — 진형 미리보기에 **발행 단추가 없다**
##   ④ 발행 ○월 → 도달 △월 — 이 화면에 발행이 없으므로 이동 함대의 「도달」만 표시
##   ⑤ 취소도 명령이다 — 취소 대상 조작이 이 화면엔 아직 없다 (SC-F2·SC-F3 소관)

signal closed()

var data: GameData
var campaign: Campaign
var start_year: int = 208
var rid: String = ""

var _title: Label
var _sub: Label
var _btn_back: Button
var _btn_form: Button
var _layers: LayerStrip
var _fleet_box: VBoxContainer
var _fleet_rows: Array[FleetRow] = []
var _preview_center: CenterContainer
var _preview: PanelContainer
var _preview_body: VBoxContainer


func setup(d: GameData, c: Campaign) -> void:
	data = d
	campaign = c
	_build()
	visible = false


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = UiPalette.BG
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 10)
	add_child(col)

	# ---- 머리줄
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	head.custom_minimum_size = Vector2(0, 58)
	col.add_child(head)
	_btn_back = _button(head, "◀ 성역 뷰", 170)
	_btn_back.pressed.connect(close)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 26)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_sub = Label.new()
	_sub.add_theme_font_size_override("font_size", 18)
	_sub.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	_sub.custom_minimum_size = Vector2(220, 0)
	head.add_child(_sub)
	_btn_form = _button(head, "편성 ▸", 130)
	_btn_form.disabled = true            # SC-F1/F2/F3 은 S3.6 이다
	_btn_form.tooltip_text = "함대 편성 UI (SC-F1/F2/F3) — S3.6 미구현"

	col.add_child(HSeparator.new())

	# ---- 4층
	_layers = LayerStrip.new()
	col.add_child(_layers)

	col.add_child(HSeparator.new())

	# ---- 함대 목록 (스크롤 — 함대가 5 이상이면)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	_fleet_box = VBoxContainer.new()
	_fleet_box.add_theme_constant_override("separation", 6)
	_fleet_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_fleet_box)

	# ---- 진형 미리보기 (§3.4 — 발행 없음 · 조회만)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_STOP     # 뒤 조작을 막는다 (조회 모달 아님 — 시뮬레이션은 계속 돈다)
	center.name = "PreviewCenter"
	add_child(center)
	_preview_center = center
	center.visible = false
	_preview = PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = UiPalette.PANEL_HI
	psb.border_color = UiPalette.ACCENT
	psb.set_border_width_all(2)
	psb.set_corner_radius_all(8)
	psb.content_margin_left = 22
	psb.content_margin_right = 22
	psb.content_margin_top = 16
	psb.content_margin_bottom = 16
	_preview.add_theme_stylebox_override("panel", psb)
	center.add_child(_preview)
	_preview_body = VBoxContainer.new()
	_preview_body.add_theme_constant_override("separation", 8)
	_preview.add_child(_preview_body)


func _button(parent: Node, text: String, w: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 52)
	b.focus_mode = Control.FOCUS_NONE
	parent.add_child(b)
	return b


# ---------------------------------------------------------------- 열기 / 닫기
func open(region_id: String) -> void:
	if not data.regions.has(region_id):
		return
	rid = region_id
	visible = true
	_preview_center.visible = false
	_layers.setup(data, campaign, rid)
	_rebuild_fleets()
	refresh()


func close() -> void:
	if _preview_center.visible:
		_preview_center.visible = false
		return
	visible = false
	rid = ""
	closed.emit()


## 이 성역에서 지금 볼 만한 함대 — 주둔 + 이 성역으로 이동 중. **성계 단위다**
## (`Fleet.at_system` — 코어에 권역별 함대 귀속이 없다. region_graph.gd 와 같은 한계).
func _relevant_fleets() -> Array[Fleet]:
	var sid := data.system_of(rid)
	var out: Array[Fleet] = []
	for fl in campaign.fleets:
		if not fl.is_alive():
			continue
		var here := fl.at_system == sid and not fl.is_moving()
		var inbound := fl.is_moving() and data.regions.has(fl.target_region) \
			and data.system_of(fl.target_region) == sid
		if here or inbound:
			out.append(fl)
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


func _rebuild_fleets() -> void:
	for c in _fleet_box.get_children():
		c.queue_free()
	_fleet_rows.clear()
	var fls := _relevant_fleets()
	if fls.is_empty():
		var empty := Label.new()
		empty.text = "이 성역에 함대가 없다."
		empty.add_theme_color_override("font_color", UiPalette.TEXT_FAINT)
		empty.add_theme_font_size_override("font_size", 18)
		_fleet_box.add_child(empty)
		return
	for fl in fls:
		var row := FleetRow.new()
		row.start_year = start_year
		_fleet_box.add_child(row)
		row.setup(data, campaign, fl.id)
		row.tapped.connect(_on_fleet_tapped)
		row.formation_tapped.connect(_on_formation_tapped)
		row.log_requested.connect(_on_log_requested)
		_fleet_rows.append(row)


## **조항 ② — 값은 구독이다.** 게임 루프가 틱을 넘길 때마다 부모가 부른다.
## 함대가 새로 들어오거나 빠지면 목록을 다시 세운다 (손가락 아래 순서 안정은
## FleetRow 가 아니라 여기서 — 함대 집합이 바뀔 때만 재구성).
func refresh() -> void:
	if not visible or rid == "":
		return
	var r: Dictionary = data.regions[rid]
	var sid := data.system_of(rid)
	_title.text = "%s  %s" % [String(r["name"]),
		"★" if bool(r.get("is_seat", false)) else ""]
	var st: RegionState = campaign.world.region_states[rid]
	_sub.text = "%s성역 · %s · %s" % [data.system_name(sid),
		st.owner if st.owner != "" else "중립",
		"위임" if st.delegated else "직할"]
	_btn_back.text = "◀ %s성역" % data.system_name(sid)

	var want := _relevant_fleets()
	var have: Array[int] = []
	for row in _fleet_rows:
		if row != null:
			have.append(row.fleet_id)
	var want_ids: Array[int] = []
	for fl in want:
		want_ids.append(fl.id)
	if want_ids != have:
		_rebuild_fleets()
	else:
		for row in _fleet_rows:
			if row != null:
				row.refresh()
	_layers.refresh()


# ---------------------------------------------------------------- 조작 (§3.4)
func _on_fleet_tapped(fleet_id: int) -> void:
	# 함대 시트(진형 변경·편성·임명)는 SC-F2/F3(S3.6). 그때까지 미리보기로 안내.
	_on_formation_tapped(fleet_id)


func _on_log_requested(fleet_id: int) -> void:
	# 더블탭 → 3D 전투 씬(요구 B9·S5) · L1 단계에서는 전투 로그(S4.2). 둘 다 미구현.
	_show_note("제%d함대 — 전투 로그(S4.2) · 3D 씬(S5) 미구현" % fleet_id)


## 진형 도형 탭 → 진형 선택 미리보기. **발행 단추 없음** (§1.1 ③).
## 지형 필터(§3.3) 적용 · 요구 통솔 미달 시 「통솔 n < 요구 m — 실패 시 −20%」(§3.4·§5.5).
func _on_formation_tapped(fleet_id: int) -> void:
	var fl := _fleet(fleet_id)
	if fl == null:
		return
	for c in _preview_body.get_children():
		c.queue_free()

	var terrain := _terrain_of(rid)
	var cur := _fleet_formation(fl)
	var cmd: int = fl.command

	_pv_label("제%d함대 — 진형 (지형: %s · 지휘관 통솔 %d)" % [fl.id, terrain, cmd],
		UiPalette.TEXT, 20)
	_pv_label("현재: %s" % (cur if cur != "" else "미정 (코어 필드 대기 — 검토 14)"),
		UiPalette.TEXT_DIM, 17)

	for f in FormationSpec.all():
		var fname := String(f["name"])
		var req := int(f.get("required_command", 0))
		var allowed := FormationSpec.allowed_in(fname, terrain)
		var line := "%s  %s  ·  요구 통솔 %d" % [
			FormationSpec.glyph(fname), fname, req]
		var colr := UiPalette.TEXT
		if not allowed:
			line += "   ✕ " + FormationSpec.terrain_note(fname, terrain)
			colr = UiPalette.TEXT_FAINT
		elif cmd < req:
			line += "   ⚠ 통솔 %d < 요구 %d — 실패 시 이 페이즈 전 계수 −20%%" % [cmd, req]
			colr = UiPalette.WARN
		_pv_label(line, colr, 17)

	_pv_label("진형 변경은 페이즈 사이 1회이며 SC-F2(S3.6)에서 발행한다. "
		+ "여기서 고른 것은 명령이 아니다 (§1.1 ③).", UiPalette.TEXT_FAINT, 16)
	var close_b := Button.new()
	close_b.text = "닫기"
	close_b.custom_minimum_size = Vector2(120, 48)
	close_b.focus_mode = Control.FOCUS_NONE
	close_b.pressed.connect(func(): _preview_center.visible = false)
	_preview_body.add_child(close_b)
	_preview_center.visible = true


func _show_note(text: String) -> void:
	for c in _preview_body.get_children():
		c.queue_free()
	_pv_label(text, UiPalette.TEXT, 18)
	var b := Button.new()
	b.text = "닫기"
	b.custom_minimum_size = Vector2(120, 48)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): _preview_center.visible = false)
	_preview_body.add_child(b)
	_preview_center.visible = true


func _pv_label(text: String, col: Color, fs: int) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", fs)
	_preview_body.add_child(l)


# ---------------------------------------------------------------- 지형 (§3.3)
## 권역이 회랑을 끼고 있으면 그 등급이 진형을 강제한다. 회랑이 없으면 개활로 본다.
## `data/routes.json` 에 항로별 권역 귀속이 없어 **기저 항로는 가려내지 못한다**
## (검토 13) — 여기서는 회랑만 본다.
func _terrain_of(region_id: String) -> String:
	var worst := "개활"
	for h in data.regions[region_id].get("routes_hosted", []):
		var nm := String(h)
		if not data.is_corridor(nm):
			continue
		for cid in data.corridor_ids:
			if String(data.corridors[cid]["name"]) != nm:
				continue
			var scale := String(data.corridors[cid].get("scale", ""))
			if scale == "대회랑":
				return "대회랑"
			if scale == "중회랑":
				worst = "중회랑"
	return worst


func _fleet_formation(fl: Fleet) -> String:
	if "formation" in fl:
		return String(fl.formation)
	return ""


func _fleet(fleet_id: int) -> Fleet:
	for fl in campaign.fleets:
		if fl.id == fleet_id:
			return fl if fl.is_alive() else null
	return null
