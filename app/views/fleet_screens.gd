class_name FleetScreens
extends Control

## **함대 편성 UI 3종** — S3.6 (요구 B7 · `screens.md` §4)
##
## | 화면 | 질문 | 정본 |
## |---|---|---|
## | `SC-F1` 함대 목록 | 몇 개를 어디에 두는가 | §4.3 |
## | `SC-F2` 편성 시트 | 무엇을 태우는가 | §4.4·§4.5 |
## | `SC-F3` 임명 시트 | 누가 지휘하는가 | §4.6 |
##
## `HalfSheet` 처럼 **L2 위에 얹히는 오버레이**다. **모달이 아니다** —
## 시뮬레이션은 이 화면이 열려 있어도 돈다 (V-25 ④ · §1.1 ①).
## 열려 있는 동안 배속 그대로 시간이 흐른다 — ×4 면 편성 한 번에 게임 내 12개월이
## 지날 수 있다 (`screens.md` 검토 1 — 화면 쪽 완화는 **임의로 정하지 않는다**).
##
## ## 셋을 한 화면에 합치지 않는다 (§4.1)
## 합치면 스크롤이 생기고, 스크롤은 `ui-design.md` §1.1 의 12~15행 한계를 넘는다.
## 그래서 한 번에 하나의 패널만 그린다.
##
## ## 조항 ③④ 의 본무대 (§1)
##   ③ 편성안·강화 축·진형·임명을 고르는 것은 **명령이 아니다.** 「발행」을 눌러야 명령이다.
##   ④ 발행 결과에 **「발행 ○월 → 도달 △월」** 을 함께 표시한다.
##
## ## 코어와의 경계 (`screens.md` §10.4 판정 3 · 검토 14)
##   · **진형** — `Fleet.formation` 은 레인 1(SC-L3)이 세운 필드다. 값은 여기서 **초기 진형**으로
##     발행하되(§4.4·§4.5), 필드 정의·전장 배선(페이즈 계수·상성·지형 강제)은 그 레인 몫이다.
##   · **강화 축** — `Fleet` 에 축·단계를 담을 필드가 없다 (검토 신설). **미리보기까지다** —
##     발행 페이로드에는 실어 두되 apply 가 대입할 곳이 없다.
##   발행이 실제로 반영하는 것은 **① 편성안(`Fleet.plan`)** · **초기 진형(`Fleet.formation`)** ·
##   **③ 임명 4계층**이다.

signal closed()

var data: GameData
var campaign: Campaign
var start_year: int = 208

var _mode: String = ""                 # "" | "list" | "compose" | "appoint" | "move"
var _faction_id: String = ""
var _fleet_id: int = -1
var _from_list: bool = false

# ---- SC-F1 이동 명령 작업 상태 (§4.3)
var _move_dest: String = ""

# ---- SC-F1 분할 / 합류 작업 상태 (§4.3 · §13)
var _split_squadrons: int = 1
var _split_commander: String = ""      # 분견대에 곧바로 앉힐 제독 char id (선택)
var _merge_target: int = -1            # 합류할 상대 함대 id

# ---- SC-F2 작업 상태 (발행 전까지는 세계에 없다 · 조항 ③)
var _plan: String = ""
var _axis: String = ""                  # "" | "화력" | "돌파" | "지속"
var _step: int = 0                      # 0~2
var _formation: String = "어린진"
var _recommend_on: bool = true
var _rule_note: String = ""

# ---- SC-F3 작업 상태
var _ap: Dictionary = {}               # slot("제독"/"부제독"/"강습"/"공성"/"보급") -> char id
var _squad_mode: String = "자동"
var _squad_pick: Array[int] = [-1, -1, -1, -1, -1]

var _frame: VBoxContainer
var _title: Label
var _body: VBoxContainer
var _note: Label
var _portrait_popup: PopupPanel
var _portrait_popup_frame: PortraitFrame
var _portrait_popup_label: Label

const _SLOTS: Array[String] = ["제독", "부제독", "강습", "공성", "보급"]
const _SLOT_STAT := {"제독": "통솔", "부제독": "통솔", "강습": "무력",
	"공성": "지력", "보급": "정치"}
const _PLANS: Array[String] = ["균형", "회랑 돌파", "개활 결전",
	"강습 특화", "성계 공략", "봉쇄 유지"]
const _AXES: Array[String] = ["화력", "돌파", "지속"]
const _AXIS_COST := {
	"화력": "③ 교전 약화 · 유지점 상승",
	"돌파": "함대 규모 축소",
	"지속": "전투력 순감",
}
const _AXIS_TARGET := {"화력": 1, "돌파": 2, "지속": 5}   # Economy.SHIP_KINDS 인덱스


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiPalette.PANEL
	sb.border_color = UiPalette.ACCENT
	sb.set_border_width_all(2)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	_frame = VBoxContainer.new()
	_frame.add_theme_constant_override("separation", 12)
	panel.add_child(_frame)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	_frame.add_child(head)
	var back := _btn(head, "◀", 70)
	back.pressed.connect(_on_back)
	_title = Label.new()
	_title.theme_type_variation = &"Title"   # FNT-002 (wght 700) · UiPalette.make_theme
	_title.add_theme_font_size_override("font_size", 24)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := _btn(head, "닫기", 110)
	close.pressed.connect(close_screen)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_frame.add_child(_body)

	_note = Label.new()
	_note.add_theme_font_size_override("font_size", 17)
	_note.add_theme_color_override("font_color", UiPalette.WARN)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_frame.add_child(_note)
	_build_portrait_popup()


func _build_portrait_popup() -> void:
	_portrait_popup = PopupPanel.new()
	_portrait_popup.size = Vector2i(300, 410)
	add_child(_portrait_popup)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_portrait_popup.add_child(box)
	_portrait_popup_frame = PortraitFrame.new()
	box.add_child(_portrait_popup_frame)
	_portrait_popup_label = Label.new()
	_portrait_popup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portrait_popup_label.add_theme_color_override("font_color", UiPalette.TEXT_FAINT)
	box.add_child(_portrait_popup_label)


func _show_portrait(character: Dictionary) -> void:
	if character.is_empty():
		return
	_portrait_popup_frame.set_character(character)
	_portrait_popup_label.text = "%s · %s" % [String(character.get("name", "—")), _portrait_popup_frame.art_id()]
	_portrait_popup.popup_centered()


func setup(d: GameData, c: Campaign, year: int) -> void:
	data = d
	campaign = c
	start_year = year


# ---------------------------------------------------------------- 열기 / 닫기
func open_list(faction_id: String) -> void:
	_mode = "list"
	_faction_id = faction_id
	visible = true
	refresh()


func open_compose(fleet_id: int, from_list: bool) -> void:
	_mode = "compose"
	_fleet_id = fleet_id
	_from_list = from_list
	var fl := _fleet()
	if fl != null:
		_faction_id = fl.owner
		_plan = fl.plan
		_axis = ""
		_step = 0
		_formation = fl.formation
		_recommend_on = true
		_apply_recommendation()
	visible = true
	refresh()


func open_appoint(fleet_id: int, from_list: bool) -> void:
	_mode = "appoint"
	_fleet_id = fleet_id
	_from_list = from_list
	var fl := _fleet()
	if fl != null:
		_faction_id = fl.owner
		_ap = {
			"제독": fl.commander_id, "부제독": fl.vice_id, "강습": fl.assault_id,
			"공성": fl.siege_id, "보급": fl.supply_id,
		}
		_squad_mode = "자동"
		_squad_pick = [-1, -1, -1, -1, -1]
	visible = true
	refresh()


func open_move(fleet_id: int, from_list: bool) -> void:
	_mode = "move"
	_fleet_id = fleet_id
	_from_list = from_list
	_move_dest = ""
	var fl := _fleet()
	if fl != null:
		_faction_id = fl.owner
	visible = true
	refresh()


func open_reorg(fleet_id: int, from_list: bool) -> void:
	_mode = "reorg"
	_fleet_id = fleet_id
	_from_list = from_list
	_split_squadrons = 1
	_split_commander = ""
	_merge_target = -1
	var fl := _fleet()
	if fl != null:
		_faction_id = fl.owner
	visible = true
	refresh()


func close_screen() -> void:
	visible = false
	_mode = ""
	closed.emit()


func _on_back() -> void:
	match _mode:
		"list":
			close_screen()
		_:
			if _from_list:
				open_list(_faction_id)
			else:
				close_screen()


## 조항 ② — 값이 흐른다. 게임 루프가 틱을 넘길 때마다 불린다.
func refresh() -> void:
	if not visible or data == null:
		return
	var fl := _fleet()
	if _mode != "list" and fl == null:
		# §1.3 — 대상이 사라졌다. 닫기만 남는다.
		_title.text = "함대 —"
		_clear(_body)
		_note.text = "⚠ 이 함대는 사라졌다 (전멸·흡수). 닫기만 남는다 (§1.3)"
		return
	match _mode:
		"list":
			_draw_list()
		"compose":
			_draw_compose(fl)
		"appoint":
			_draw_appoint(fl)
		"move":
			_draw_move(fl)
		"reorg":
			_draw_reorg(fl)


# ================================================================ SC-F1 함대 목록
func _draw_list() -> void:
	var f: Faction = campaign.factions.get(_faction_id)
	if f == null:
		_title.text = "함대 목록 —"
		_clear(_body)
		return
	_title.text = "%s   함대 (%d)" % [_faction_id, _count_fleets(_faction_id)]
	_clear(_body)

	# ---- 유지점 예산 (§4.3 — 소비 / 실동원)
	var mob := f.mobilized(data, campaign.world.region_states, campaign.world.graph,
		campaign.world.clock.tick)
	var used_milli := _consumed_points_milli(_faction_id)
	var row := _kv(_body, "유지점", "%.1f / %d" % [used_milli / 1000.0, mob])
	var g := Gauge.new()
	g.custom_minimum_size = Vector2(360, 14)
	g.bar_color = UiPalette.ROUTE_FAST if used_milli <= mob * 1000 else UiPalette.DANGER
	g.set_value(used_milli, maxi(mob * 1000, 1), 0, -1)
	row.add_child(g)

	# ---- 지휘 재고 (§4.3 — 등급별 미배치 제독 · 미임명 자리)
	_kv(_body, "지휘", _command_stock(_faction_id))

	_body.add_child(HSeparator.new())

	# ---- 함대 행
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var ids: Array[int] = []
	for fl in campaign.fleets:
		if fl.owner == _faction_id and fl.is_alive():
			ids.append(fl.id)
	ids.sort()
	for fid in ids:
		list.add_child(_fleet_row(_fleet_by_id(fid)))

	_note.text = "행을 누르면 편성 시트(SC-F2). [임명]은 임명 시트(SC-F3). " + \
		"신설·이동·분할/합류는 명령 메뉴(S3.5)·`SC-F1` 스와이프 — 미배선."


func _fleet_row(fl: Fleet) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiPalette.PANEL_HI
	sb.border_color = UiPalette.LINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 12
	sb.content_margin_right = 8
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	pc.add_theme_stylebox_override("panel", sb)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	pc.add_child(col)

	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 14)
	col.add_child(r1)
	_lbl(r1, "제%d함대" % fl.id, UiPalette.TEXT, 20, 150)
	_lbl(r1, "%d척" % fl.ships, UiPalette.TEXT_DIM, 18, 90)
	_lbl(r1, fl.plan, UiPalette.TEXT_DIM, 18, 110)
	var where := data.system_name(fl.at_system) + "성역"
	if fl.is_moving():
		where = "→ %s · %s" % [
			String(data.regions[fl.target_region]["name"]) if data.regions.has(fl.target_region) else "—",
			UiPalette.tick_label(fl.arrival_tick, start_year)]
	_lbl(r1, where, UiPalette.TEXT_DIM, 18, 240)
	var cmd_name := fl.commander_name if fl.commander_name != "" else "무명 장교"
	_lbl(r1, cmd_name, UiPalette.TEXT, 18, 130)
	# 버튼은 자기 클릭을 삼킨다 — 행 전체 탭(gui_input)보다 먼저 잡는다.
	# §4.3 은 좌스와이프(이동)·행 탭(편성)·우스와이프(분할/합류)를 두나, 이 저장소의
	# 다른 화면들이 스와이프 대신 버튼을 쓰므로 맞춘다. 분할/합류는 미구현 (검토 24).
	var move := _btn(r1, "이동 ▸", 100)
	move.pressed.connect(open_move.bind(fl.id, true))
	var reorg := _btn(r1, "분할/합류 ▸", 140)
	reorg.pressed.connect(open_reorg.bind(fl.id, true))
	var appoint := _btn(r1, "임명 ▸", 100)
	appoint.pressed.connect(open_appoint.bind(fl.id, true))
	var edit := _btn(r1, "편성 ▸", 100)
	edit.pressed.connect(open_compose.bind(fl.id, true))

	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 12)
	col.add_child(r2)
	_lbl(r2, "유지점 %.2f" % (_fleet_points_milli(fl, fl.plan, "", 0) / 1000.0),
		UiPalette.TEXT_FAINT, 17, 150)
	_lbl(r2, "주둔 %s ×%.1f" % [fl.station, _station_mult(fl.station)],
		UiPalette.TEXT_FAINT, 17, 170)
	var warn := _fleet_warnings(fl)
	if warn != "":
		_lbl(r2, warn, UiPalette.WARN, 17, 420)

	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	pc.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and not (e as InputEventMouseButton).pressed:
			open_compose(fl.id, true))
	return pc


# ================================================================ SC-F2 편성 시트
func _draw_compose(fl: Fleet) -> void:
	_title.text = "제%d함대  편성" % fl.id
	_clear(_body)

	# ---- 모드 토글 [추천] [사용자]
	var modebar := HBoxContainer.new()
	modebar.add_theme_constant_override("separation", 8)
	_body.add_child(modebar)
	var rec := _btn(modebar, "추천", 120)
	rec.toggle_mode = true
	rec.button_pressed = _recommend_on
	rec.toggled.connect(func(on: bool):
		_recommend_on = on
		if on:
			_apply_recommendation()
		refresh())
	var man := _btn(modebar, "사용자", 120)
	man.toggle_mode = true
	man.button_pressed = not _recommend_on
	man.toggled.connect(func(on: bool):
		_recommend_on = not on
		if _recommend_on:
			_apply_recommendation()
		refresh())
	if _recommend_on and _rule_note != "":
		_lbl(modebar, "→ " + _rule_note, UiPalette.ACCENT, 17, 460)

	# ---- ① 편성안
	_body.add_child(_section("① 편성안"))
	var pbar := _wrap()
	_body.add_child(pbar)
	for p in _PLANS:
		var b := _btn(pbar, p, 130)
		b.toggle_mode = true
		b.button_pressed = (p == _plan)
		b.disabled = _recommend_on
		b.pressed.connect(func():
			_plan = p
			refresh())

	var ratio := _current_ratio()
	_kv(_body, "함종 (전열·포격·강습·전자·공성·보급)",
		"%d · %d · %d · %d · %d · %d   = %d척" % [
			ratio[0], ratio[1], ratio[2], ratio[3], ratio[4], ratio[5],
			fl.ships])

	# ---- ② 강화 축
	_body.add_child(_section("② 강화 축   (전열함을 헐어 키운다 · 1단계 = 5%p · ±2단계)"))
	var abar := _wrap()
	_body.add_child(abar)
	for ax in _AXES:
		for st in [1, 2]:
			var b := _btn(abar, "%s +%d" % [ax, st], 120)
			b.toggle_mode = true
			b.button_pressed = (_axis == ax and _step == st)
			b.disabled = _recommend_on
			b.pressed.connect(func():
				if _axis == ax and _step == st:
					_axis = ""; _step = 0
				else:
					_axis = ax; _step = st
				refresh())
	if _axis != "":
		_lbl(_body, "⚠ 대가 — %s" % _AXIS_COST.get(_axis, ""), UiPalette.WARN, 17, 620)

	# ---- ③ 초기 진형 (지형 필터 · 정본은 FormationSpec = data/formations.json)
	var terr := _terrain(fl)
	_body.add_child(_section("③ 초기 진형   (지형: %s)" % terr))
	var fbar := _wrap()
	_body.add_child(fbar)
	for row in FormationSpec.all():
		var fm := String(row["name"])
		var req: int = int(row.get("required_command", 0))
		var b := _btn(fbar, "%s (%d)" % [fm, req], 130)
		b.toggle_mode = true
		b.button_pressed = (fm == _formation)
		var ok := FormationSpec.allowed_in(fm, terr)
		# 팔진은 통솔 90 + 전용 특성. 화면에선 통솔만 본다 (특성 판정은 전투 레인)
		if row.get("requires_trait") != null and fl.command < req:
			ok = false
		b.disabled = not ok
		if not ok:
			b.tooltip_text = FormationSpec.terrain_note(fm, terr) if not FormationSpec.allowed_in(fm, terr) \
				else "통솔 90 + 전용 특성 필요 (§5.6)"
		b.pressed.connect(func():
			_formation = fm
			refresh())
	if terr == "대회랑":
		_lbl(_body, "대회랑 — 장사진 고정 · 변경 불가 · ② 포화 계수 0.6 (§3.3)",
			UiPalette.TEXT_DIM, 17, 620)
	var freq := FormationSpec.required_command(_formation)
	if fl.command < freq:
		_lbl(_body, "⚠ 통솔 %d < 요구 %d — 전투 중 변경 실패 시 해당 페이즈 전 계수 −20%% (§5.5)" % [
			fl.command, freq], UiPalette.WARN, 17, 640)

	_body.add_child(HSeparator.new())

	# ---- 즉시 표시 — 유지점 · 한도 게이지 · 대가
	var per_milli := _fleet_points_milli(fl, _plan, _axis, _step)
	var base_milli := _fleet_points_milli(fl, fl.plan, "", 0)
	_kv(_body, "유지점", "%.2f → %.2f" % [base_milli / 1000.0, per_milli / 1000.0])
	var cl := Roster.command_limit(fl.command)
	var over_milli := per_milli - cl * 1000
	var hrow := _kv(_body, "지휘 한도", "%d  (제독 통솔 %d)" % [cl, fl.command])
	var hg := Gauge.new()
	hg.custom_minimum_size = Vector2(300, 14)
	hg.bar_color = UiPalette.ROUTE_FAST if over_milli <= 0 else UiPalette.DANGER
	hg.set_value(per_milli, maxi(cl * 1000, 1), 0, -1)
	hrow.add_child(hg)
	if over_milli > 0:
		# §4.2 — 편성을 바꾸는 것이 지휘 능력을 갉는다. **확정 전에** 보여준다.
		var pen := (over_milli + 999) / 1000 * 3
		_lbl(_body, "⚠ 한도 초과 %.2f → 전 부대 사기 −%d (§6.2)" % [
			over_milli / 1000.0, mini(pen, 30)], UiPalette.DANGER, 18, 620)

	_body.add_child(_issue_bar(fl, _issue_plan))
	_note.text = "발행은 편성안·초기 진형을 사자 지연을 태워 반영한다 (즉시 도달 아님). " + \
		"강화 축은 코어에 담을 필드가 없어 미리보기까지다 (강화 축 코어 필드 — 신설 검토)."


# ================================================================ SC-F3 임명 시트
func _draw_appoint(fl: Fleet) -> void:
	_title.text = "제%d함대  임명" % fl.id
	_clear(_body)

	var pool := _candidate_pool(fl)

	# ---- 4계층 상단 — 제독 · 부제독 · 임무대장 3
	for slot in _SLOTS:
		var stat: String = _SLOT_STAT[slot]
		var cur_id := String(_ap.get(slot, ""))
		var cur := _char(fl.owner, cur_id)
		var name_txt := "—"
		if not cur.is_empty():
			name_txt = "%s  (%s %d)" % [String(cur["name"]), stat,
				Roster.stat_of(cur, stat)]
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 12)
		_body.add_child(r)
		if not cur.is_empty():
			var chip := PortraitFrame.new()
			chip.set_character(cur, true)
			r.add_child(chip)
		_lbl(r, slot, UiPalette.TEXT_FAINT, 18, 90)
		_lbl(r, name_txt, UiPalette.TEXT, 18, 320)
		if slot == "제독":
			_lbl(r, "지휘 한도 %d" % Roster.command_limit(
				Roster.stat_of(cur, "통솔") if not cur.is_empty() else 50),
				UiPalette.TEXT_DIM, 17, 150)
		elif slot == "부제독" and not cur.is_empty():
			var add := Roster.command_limit(Roster.stat_of(cur, "통솔")) / 2
			_lbl(r, "한도 +%d (§6.5 예시 기준)" % add, UiPalette.TEXT_DIM, 17, 200)
		var cyc := _btn(r, "▸ 교체", 110)
		cyc.pressed.connect(_cycle_slot.bind(slot, pool))
		if not cur.is_empty():
			var preview := _btn(r, "초상", 80)
			preview.pressed.connect(_show_portrait.bind(cur))
		if cur_id != "":
			var clr := _btn(r, "비움", 90)
			clr.pressed.connect(func():
				_ap[slot] = ""
				refresh())
		if slot == "보급" and not cur.is_empty():
			# §4.6 — 순욱을 전선에 보내면 세력 내정 −25%. 담당 권역은 코어에 없다.
			_lbl(_body, "⚠ 보급대장은 내정 담당관과 같은 풀이다 — 전출 시 세력 내정 효율이 떨어진다 (§6.7 · 담당 권역 표시는 코어 미구현)",
				UiPalette.WARN, 16, 660)

	_body.add_child(HSeparator.new())

	# ---- 전대장 (5) — 자동 · 수동 (§4.6)
	_body.add_child(_section("전대장 (5)   —   조작은 함대당 1회가 설계 목표다 (§4.4)"))
	var tbar := HBoxContainer.new()
	tbar.add_theme_constant_override("separation", 8)
	_body.add_child(tbar)
	for m in ["자동", "수동"]:
		var b := _btn(tbar, m, 110)
		b.toggle_mode = true
		b.button_pressed = (_squad_mode == m)
		b.pressed.connect(func():
			_squad_mode = m
			refresh())

	var squad := _squad_assignment(fl, pool)
	var srow := _wrap()
	_body.add_child(srow)
	for i in 5:
		var c: Dictionary = squad[i]
		var nm := "—" if c.is_empty() else "%s %d" % [
			String(c["name"]), Roster.stat_of(c, "통솔")]
		if _squad_mode == "자동":
			_lbl(srow, "%d  %s" % [i + 1, nm], UiPalette.TEXT_DIM, 17, 160)
		else:
			var b := _btn(srow, "%d  %s" % [i + 1, nm], 160)
			b.pressed.connect(_cycle_squad.bind(i, pool))
	var scalar := _squad_command_scalar(squad)
	var cap := _squad_cap_display(squad)
	_lbl(_body, "훈련도 상한 %d%s" % [cap,
		"   ⚠ 빈 전대가 있다 — 40 에서 멈춘다 (§6.6)" if scalar == 0 else ""],
		UiPalette.WARN if scalar == 0 else UiPalette.TEXT_DIM, 17, 520)

	_body.add_child(_issue_bar(fl, _issue_appoint))
	_note.text = "발행은 지휘부 5직 + 전대장 훈련 상한을 반영한다. 사자 지연을 탄다 (§1.1 ④)."


# ================================================================ SC-F1 이동 명령 (§4.3)
func _draw_move(fl: Fleet) -> void:
	_title.text = "제%d함대  이동" % fl.id
	_clear(_body)

	if fl.is_moving():
		# §1.3 — 이미 이동 중. 조회만 남는다 (진로 변경은 이 명령의 몫이 아니다 · §1.5).
		var dn := String(data.regions[fl.target_region]["name"]) \
			if data.regions.has(fl.target_region) else "—"
		_kv(_body, "현재 목적지", "%s · 도착 %s" % [dn,
			UiPalette.tick_label(fl.arrival_tick, start_year)])
		_note.text = "이미 이동 중이다 — 진로는 도착 후 다시 발행한다 (§1.5)."
		return

	_kv(_body, "현재 위치", data.system_name(fl.at_system) + "성역 주둔")
	_body.add_child(_section("목적 권역 — 경로·소요를 보고 고른다 (§4.3)"))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for rid in _move_candidates(fl):
		list.add_child(_move_row(fl, rid))

	if _move_dest != "":
		_body.add_child(HSeparator.new())
		var t := _move_ticks(fl, _move_dest)
		var cors := FleetRecommend.corridors_on_route(data, campaign, fl.at_system, _move_dest)
		var cor_txt := "—"
		if not cors.is_empty():
			var ns: Array[String] = []
			for cid in cors:
				ns.append(String(data.corridors[cid]["name"]))
			cor_txt = " · ".join(ns)
		_kv(_body, "선택", "%s  (%s성역)" % [
			String(data.regions[_move_dest]["name"]),
			data.system_name(data.system_of(_move_dest))])
		_kv(_body, "경로 회랑", cor_txt)
		var now := campaign.world.clock.tick
		var bar := HBoxContainer.new()
		bar.add_theme_constant_override("separation", 16)
		_lbl(bar, "발행 %s → 도착 %s  (항행 %s)" % [
			UiPalette.tick_label(now, start_year),
			UiPalette.tick_label(now + maxi(t, 1), start_year),
			_hours(t)], UiPalette.TEXT_DIM, 18, 460)
		var b := _btn(bar, "발행", 150)
		var locked := _issue_locked(fl)
		if locked == "" and t < 0:
			locked = "닿지 않는다 — 회랑이 끊겼을 수 있다"
		b.disabled = locked != ""
		if locked != "":
			b.tooltip_text = locked
		b.pressed.connect(_issue_move)
		_body.add_child(bar)

	_note.text = "발행 = 즉시 출항 (AI 함대와 대칭 · 사자 지연 없음). 도착 전까지는 취소 없음 (§1.5)."


## 후보 — 현재 성계의 권역 + 아군 권역에 인접한 권역 + 함대 위치에 인접한 권역.
## **권역 ID 오름차순** (V-31 · 결정론). 닿지 않는 곳은 제외한다.
func _move_candidates(fl: Fleet) -> Array:
	var f: Faction = campaign.factions.get(fl.owner)
	var seen := {}
	for rid in data.regions_of.get(fl.at_system, []):
		seen[rid] = true
	if f != null:
		for rid in f.regions:
			seen[rid] = true
			for nb in data.region_adjacency.get(rid, []):
				seen[nb] = true
	var out: Array = []
	for rid in seen.keys():
		if _move_ticks(fl, rid) >= 0:
			out.append(rid)
	out.sort()
	return out


func _move_row(fl: Fleet, rid: String) -> Button:
	var st = campaign.world.region_states.get(rid)
	var own := "중립"
	if st != null and String(st.owner) != "":
		own = String(st.owner)
	var t := _move_ticks(fl, rid)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	b.button_pressed = (rid == _move_dest)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 42)
	b.text = "%s  ·  %s성역  ·  %s  —  도착 %s (%s)" % [
		String(data.regions[rid]["name"]),
		data.system_name(data.system_of(rid)), own,
		_hours(t), UiPalette.tick_label(campaign.world.clock.tick + maxi(t, 1), start_year)]
	b.pressed.connect(func():
		_move_dest = rid
		refresh())
	return b


## **코어 판정** — 경로·소요는 `Orders.resolve_move` 가 낸다 (A-03 · V-60 ⑤).
## 화면은 이 값을 표시하고 발행 버튼을 잠글 뿐, payload 에는 목적 권역만 싣는다.
func _move_ticks(fl: Fleet, rid: String) -> int:
	return int(Orders.resolve_move(campaign.world.graph, data,
		fl.at_system, rid)["travel_ticks"])


static func _hours(ticks: int) -> String:
	if ticks < 0:
		return "닿지 않음"
	if ticks == 0:
		return "즉시"
	return "%.1fh" % (ticks / 60.0)          # 1틱 = 실제 1분 (time-and-monetization §2.1)


func _issue_move() -> void:
	var fl := _fleet()
	if fl == null or _issue_locked(fl) != "" or _move_dest == "":
		return
	var t := _move_ticks(fl, _move_dest)
	if t < 0:
		return
	# **목적 권역만 싣는다.** 경로·소요는 도달 시 `Orders.resolve_move` 가 낸다
	# (A-03 · V-60 ⑤ — UI 페이로드가 판정하지 않는다). origin 은 기본값 "player".
	campaign.world.issue(Domestic.CMD_FLEET_MOVE, {
		"faction": fl.owner,
		"fleet": fl.id,
		"region": _move_dest,
	}, 0)
	_note.text = "발행됨 — %s 로 출항. 도착 %s." % [
		String(data.regions[_move_dest]["name"]),
		UiPalette.tick_label(campaign.world.clock.tick + maxi(t, 1), start_year)]
	_move_dest = ""


# ================================================================ SC-F1 분할 / 합류 (§4.3 · §13)
func _draw_reorg(fl: Fleet) -> void:
	_title.text = "제%d함대  분할 / 합류" % fl.id
	_clear(_body)
	if fl.is_moving():
		_note.text = "이동 중에는 재편할 수 없다 (§13). 도착 후 다시 연다."
		return

	var sq_total := fl.ships / Battle.SQUADRON_SHIPS       # 온전한 전대 수 (내림)
	_kv(_body, "현재", "%d척 · 전대 %d · 편성안 %s · %s" % [
		fl.ships, sq_total, fl.plan, fl.formation])

	# -------------------------------------------------- 분할
	_body.add_child(_section("분할 — 전대 단위로만 · 원함대가 지휘부·편성안·진형을 지킨다 (§13.2)"))
	if sq_total < 2:
		_lbl(_body, "전대가 하나뿐이라 분할할 수 없다 (하한 28척)", UiPalette.TEXT_DIM, 17, 480)
	else:
		var maxdet := sq_total - 1
		_split_squadrons = clampi(_split_squadrons, 1, maxdet)
		var sbar := HBoxContainer.new()
		sbar.add_theme_constant_override("separation", 8)
		_body.add_child(sbar)
		_lbl(sbar, "분견 전대", UiPalette.TEXT_FAINT, 18, 100)
		var minus := _btn(sbar, "−", 60)
		minus.pressed.connect(func():
			_split_squadrons = maxi(1, _split_squadrons - 1)
			refresh())
		_lbl(sbar, "%d" % _split_squadrons, UiPalette.TEXT, 20, 50)
		var plus := _btn(sbar, "+", 60)
		plus.pressed.connect(func():
			_split_squadrons = mini(maxdet, _split_squadrons + 1)
			refresh())
		var det := _split_squadrons * Battle.SQUADRON_SHIPS
		_kv(_body, "결과", "원함대 %d척 (전대 %d)  ·  분견대 %d척 (전대 %d)" % [
			fl.ships - det, sq_total - _split_squadrons, det, _split_squadrons])
		_lbl(_body, "분견대 — 무명 장교 · 보정 0 · 어린진 · 훈련 상한 40 (§13.2). 아래에서 제독을 곧바로 지정할 수 있다.",
			UiPalette.TEXT_DIM, 16, 640)

		var pool := _candidate_pool(fl)
		var cbar := HBoxContainer.new()
		cbar.add_theme_constant_override("separation", 8)
		_body.add_child(cbar)
		var cc := _char(fl.owner, _split_commander)
		_lbl(cbar, "분견대 제독", UiPalette.TEXT_FAINT, 18, 110)
		_lbl(cbar, "— 무명" if cc.is_empty() else "%s (통솔 %d)" % [
			String(cc["name"]), Roster.stat_of(cc, "통솔")], UiPalette.TEXT, 18, 240)
		var cyc := _btn(cbar, "▸ 지정", 100)
		cyc.pressed.connect(func():
			var seq: Array = [""]
			for c in pool:
				seq.append(String(c["id"]))
			var i := seq.find(_split_commander)
			_split_commander = seq[(i + 1) % seq.size()]
			refresh())

		var sib := HBoxContainer.new()
		sib.add_theme_constant_override("separation", 16)
		_body.add_child(sib)
		var now := campaign.world.clock.tick
		_lbl(sib, "발행 %s = 즉시 (§13 · 함대 위치에서의 재편)" %
			UiPalette.tick_label(now, start_year), UiPalette.TEXT_DIM, 18, 420)
		var sb := _btn(sib, "분할 발행", 150)
		sb.disabled = _issue_locked(fl) != ""
		sb.pressed.connect(_issue_split)

	_body.add_child(HSeparator.new())

	# -------------------------------------------------- 합류
	_body.add_child(_section("합류 — 같은 성역의 아군 함대 · 통솔 상위 제독이 통합 함대를 맡는다 (§13.3)"))
	var mates := _merge_candidates(fl)
	if mates.is_empty():
		_lbl(_body, "같은 성역에 합류할 아군 함대가 없다", UiPalette.TEXT_DIM, 17, 480)
		_note.text = "분할은 새 함대를 만드는 것이다 — 쓰려면 임명 시트에서 제독을 앉힌다 (§13.2)."
		return
	var mrow := _wrap()
	_body.add_child(mrow)
	for m in mates:
		var b := _btn(mrow, "제%d함대 %d척 · %s" % [m.id, m.ships,
			m.commander_name if m.commander_name != "" else "무명"], 240)
		b.toggle_mode = true
		b.button_pressed = (m.id == _merge_target)
		b.pressed.connect(func():
			_merge_target = m.id
			refresh())

	if _merge_target >= 0:
		var other := _fleet_by_id(_merge_target)
		if other != null:
			var keep := fl if fl.command >= other.command else other
			var lose := other if keep == fl else fl
			var plan := keep.plan if keep.ships >= lose.ships else lose.plan
			var form := keep.formation if keep.ships >= lose.ships else lose.formation
			var total := keep.ships + lose.ships
			_kv(_body, "통합", "%d척 · 제독 %s · 편성안 %s · %s · 훈련도 %d" % [
				total, keep.commander_name if keep.commander_name != "" else "무명",
				plan, form, mini(keep.drill, lose.drill)])
			_kv(_body, "해산", "제%d함대 — 제독 %s 는 미임명 풀로 (§13.3)" % [
				lose.id, lose.commander_name if lose.commander_name != "" else "무명"])
			var per := Economy.plan_point_milli(plan)
			var pts_milli := total * 1000 / Battle.SQUADRON_SHIPS * per / 1000
			var cl := Roster.command_limit(keep.command)
			if pts_milli > cl * 1000:
				var over := pts_milli - cl * 1000
				var pen := (over + 999) / 1000 * 3
				_lbl(_body, "⚠ 통합 유지점 %.2f > 지휘 한도 %d → 전 부대 사기 −%d (§6.2 · 확정 전 표시 · §13.3)" % [
					pts_milli / 1000.0, cl, mini(pen, 30)], UiPalette.DANGER, 18, 640)
			var mib := HBoxContainer.new()
			mib.add_theme_constant_override("separation", 16)
			_body.add_child(mib)
			_lbl(mib, "발행 %s = 즉시" % UiPalette.tick_label(
				campaign.world.clock.tick, start_year), UiPalette.TEXT_DIM, 18, 300)
			var mb := _btn(mib, "합류 발행", 150)
			mb.disabled = _issue_locked(fl) != "" or _issue_locked(other) != ""
			mb.pressed.connect(_issue_merge)

	_note.text = "분할·합류는 사자 지연 없이 즉시다 (이동과 대칭). 되돌리려면 다시 발행한다 (§1.5)."


## 같은 성계 · 같은 세력 · 이동 중 아님 · 자기 자신 아님.
func _merge_candidates(fl: Fleet) -> Array:
	var out: Array = []
	for m in campaign.fleets:
		if m.id == fl.id or m.owner != fl.owner or not m.is_alive():
			continue
		if m.is_moving() or m.at_system != fl.at_system:
			continue
		out.append(m)
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


func _issue_split() -> void:
	var fl := _fleet()
	if fl == null or _issue_locked(fl) != "":
		return
	var payload := {
		"faction": fl.owner,
		"fleet": fl.id,
		"squadrons": _split_squadrons,
	}
	var cc := _char(fl.owner, _split_commander)
	if not cc.is_empty():
		payload["commander"] = {
			"id": _split_commander, "name": String(cc["name"]),
			"통솔": Roster.stat_of(cc, "통솔"),
			"무력": Roster.stat_of(cc, "무력"),
			"지력": Roster.stat_of(cc, "지력"),
		}
	campaign.world.issue(Domestic.CMD_FLEET_SPLIT, payload, 0)
	_note.text = "발행됨 — %d전대(%d척) 분견. 제독 미임명이면 임명 시트에서 앉힌다." % [
		_split_squadrons, _split_squadrons * Battle.SQUADRON_SHIPS]
	_split_squadrons = 1
	_split_commander = ""


func _issue_merge() -> void:
	var fl := _fleet()
	var other := _fleet_by_id(_merge_target)
	if fl == null or other == null:
		return
	if _issue_locked(fl) != "" or _issue_locked(other) != "":
		return
	var keep := fl if fl.command >= other.command else other
	var lose := other if keep == fl else fl
	var plan := keep.plan if keep.ships >= lose.ships else lose.plan
	var form := keep.formation if keep.ships >= lose.ships else lose.formation
	campaign.world.issue(Domestic.CMD_FLEET_MERGE, {
		"faction": fl.owner,
		"fleet": lose.id,
		"into": keep.id,
		"plan": plan,
		"formation": form,
	}, 0)
	_note.text = "발행됨 — 제%d함대가 제%d함대를 흡수한다." % [keep.id, lose.id]
	_merge_target = -1
	_fleet_id = keep.id                      # 해산될 쪽을 보고 있었으면 통합 함대로 옮겨 본다


# ---------------------------------------------------------------- 발행 (조항 ④)
func _issue_bar(fl: Fleet, on_issue: Callable) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)
	var delay := _issue_delay(fl)
	var now := campaign.world.clock.tick
	_lbl(bar, "발행 %s → 도달 %s" % [
		UiPalette.tick_label(now, start_year),
		UiPalette.tick_label(now + delay, start_year)],
		UiPalette.TEXT_DIM, 18, 360)
	var b := _btn(bar, "발행", 150)
	var locked := _issue_locked(fl)
	b.disabled = locked != ""
	if locked != "":
		b.tooltip_text = locked
	b.pressed.connect(on_issue)
	return bar


## §1.3 — 전제가 무너지면 발행 버튼이 잠기고 사유를 한 줄로 적는다.
func _issue_locked(fl: Fleet) -> String:
	if fl == null or not fl.is_alive():
		return "함대가 사라졌다"
	if fl.owner != campaign.world.player_faction:
		return "자기 세력 함대가 아니다"
	var f: Faction = campaign.factions.get(fl.owner)
	if f == null or not f.alive:
		return "세력이 소멸했다"
	if campaign.world.graph.is_empty():
		return "항로망이 없다"
	return ""


func _issue_delay(fl: Fleet) -> int:
	var f: Faction = campaign.factions.get(fl.owner)
	if f == null or f.capital_system == "" or fl.at_system == "":
		return 0
	var t := Routing.travel_ticks(campaign.world.graph, f.capital_system, fl.at_system)
	return maxi(t, 0)


func _issue_plan() -> void:
	var fl := _fleet()
	if fl == null or _issue_locked(fl) != "":
		return
	# 강화 축은 코어 필드가 없다 — 페이로드에는 담되 apply 가 대입할 곳이 없다.
	var payload := {
		"faction": fl.owner,
		"fleet": fl.id,
		"plan": _plan,
		"formation": _formation,
		"axis": _axis,
		"step": _step,
	}
	campaign.world.issue(Domestic.CMD_FLEET_PLAN, payload, _issue_delay(fl))
	_note.text = "발행됨 — 편성안 「%s」 · 초기 진형 「%s」. 도달 %s 에 반영된다." % [
		_plan, _formation,
		UiPalette.tick_label(campaign.world.clock.tick + _issue_delay(fl), start_year)]


func _issue_appoint() -> void:
	var fl := _fleet()
	if fl == null or _issue_locked(fl) != "":
		return
	var pool := _candidate_pool(fl)
	var squad := _squad_assignment(fl, pool)
	# **화면이 인물을 다 풀어서 보낸다** — id + 해당 직의 스탯.
	var ids: Dictionary = {}
	var resolved: Dictionary = {}
	for slot in _SLOTS:
		var cid := String(_ap.get(slot, ""))
		ids[slot] = cid
		var c := _char(fl.owner, cid)
		resolved[slot] = {
			"id": cid,
			"name": String(c.get("name", "")) if not c.is_empty() else "",
			"통솔": Roster.stat_of(c, "통솔") if not c.is_empty() else 50,
			"무력": Roster.stat_of(c, "무력") if not c.is_empty() else 50,
			"지력": Roster.stat_of(c, "지력") if not c.is_empty() else 50,
			"정치": Roster.stat_of(c, "정치") if not c.is_empty() else 50,
		}
	var payload := {
		"faction": fl.owner,
		"fleet": fl.id,
		"appoint": resolved,
		"squad_command": _squad_command_scalar(squad),
	}
	# 계략 배선 값을 화면이 미리 푼다 (campaign._refresh_scheme_staff 와 같은 규칙).
	payload.merge(_scheme_fields(fl.owner, ids))
	campaign.world.issue(Domestic.CMD_FLEET_APPOINT, payload, _issue_delay(fl))
	_note.text = "발행됨 — 지휘부. 도달 %s 에 반영된다." % \
		UiPalette.tick_label(campaign.world.clock.tick + _issue_delay(fl), start_year)


## `campaign._refresh_scheme_staff` 의 규칙을 옮긴다 (combat.md §5.2·§5.3).
## 화면이 미리 풀어 페이로드에 싣고, `Domestic.apply` 는 대입만 한다 —
## `Domestic.apply` 서명에 로스터가 없기 때문이다 (campaign.gd 는 이 레인이 못 고친다).
func _scheme_fields(owner: String, ids: Dictionary) -> Dictionary:
	var cmd_c := _char(owner, String(ids.get("제독", "")))
	var wits_max := Roster.stat_of(cmd_c, "지력") if not cmd_c.is_empty() else 50
	var trait_union: Array = []
	var det_wits := 0
	var det_name := ""
	var det_traits: Array = []
	var wits80 := 0
	for slot in _SLOTS:
		var c := _char(owner, String(ids.get(slot, "")))
		if c.is_empty():
			continue
		var w := Roster.stat_of(c, "지력")
		wits_max = maxi(wits_max, w)
		var t = c.get("traits")
		if t is Array:
			for tr in t:
				if not trait_union.has(tr):
					trait_union.append(tr)
		var cls = c.get("class")
		var is_staff: bool = cls is Array and cls.has("참")
		if is_staff and w > det_wits:
			det_wits = w
			det_name = String(c.get("name", ""))
			det_traits = (t if t is Array else [])
		if is_staff and w >= 80:
			wits80 += 1
	return {
		"staff_wits_max": wits_max,
		"staff_traits": trait_union,
		"detector_wits": det_wits,
		"detector_name": det_name,
		"detector_traits": det_traits,
		"staff_wits80_count": wits80,
	}


# ---------------------------------------------------------------- 추천 (§4.5)
func _apply_recommendation() -> void:
	var fl := _fleet()
	if fl == null:
		return
	var f: Faction = campaign.factions.get(fl.owner)
	var spare := 0
	if f != null:
		var mob := f.mobilized(data, campaign.world.region_states,
			campaign.world.graph, campaign.world.clock.tick)
		spare = mob - _consumed_points_milli(fl.owner) / 1000
	var dest := fl.target_region
	if dest == "":
		dest = _nearest_enemy_region(fl)
	var r := FleetRecommend.recommend(data, campaign, fl, dest, spare)
	_plan = String(r["plan"])
	_axis = String(r["axis"])
	_step = int(r["step"])
	_formation = String(r["formation"])
	_rule_note = String(r["note"])


## 목적지가 없으면 추천이 볼 것이 없다. 인접한 적 권역 하나를 잡아 준다 (권역 ID 오름차순 · V-31).
func _nearest_enemy_region(fl: Fleet) -> String:
	var f: Faction = campaign.factions.get(fl.owner)
	if f == null:
		return ""
	var cands: Array[String] = []
	for rid in f.regions:
		for nb in data.region_adjacency.get(rid, []):
			var ns = campaign.world.region_states.get(nb)
			if ns != null and String(ns.owner) != "" and String(ns.owner) != fl.owner:
				if not cands.has(nb):
					cands.append(nb)
	cands.sort()
	return cands[0] if not cands.is_empty() else ""


# ---------------------------------------------------------------- 편성 계산
func _current_ratio() -> Array:
	var base: Array = Economy.PLANS.get(_plan, Economy.PLANS[Economy.PLAN_DEFAULT])
	var arr: Array = []
	for v in base:
		arr.append(int(v))
	if _axis != "" and _step > 0:
		var tgt: int = _AXIS_TARGET[_axis]
		var move: int = mini(_step * 5, arr[0])
		arr[0] -= move
		arr[tgt] += move
	# 백분율 → 척수 (140척 기준). 합이 100 이므로 그대로 곱한다.
	var ships := _fleet_ships()
	var out: Array = []
	for pct in arr:
		out.append(int(pct) * ships / 100)
	return out


func _fleet_ships() -> int:
	var fl := _fleet()
	return fl.ships if fl != null else Battle.FLEET_SHIPS


## 이 함대의 유지점 (milli · 전대 수 × 전대당). 강화 축 반영.
func _fleet_points_milli(fl: Fleet, plan: String, axis: String, step: int) -> int:
	var per := Economy.plan_point_milli(plan)
	if axis != "" and step > 0:
		var base: Array = Economy.PLANS.get(plan, Economy.PLANS[Economy.PLAN_DEFAULT])
		var arr: Array = []
		for v in base:
			arr.append(int(v))
		var tgt: int = _AXIS_TARGET[axis]
		var move: int = mini(step * 5, arr[0])
		arr[0] -= move
		arr[tgt] += move
		per = 0
		for i in Economy.SHIP_KINDS.size():
			per += int(arr[i]) * int(Economy.SHIP_POINT_MILLI[Economy.SHIP_KINDS[i]])
		per = per / 100
	return fl.squadrons_milli() * per / 1000


func _consumed_points_milli(fid: String) -> int:
	var sum := 0
	for fl in campaign.fleets:
		if fl.owner == fid and fl.is_alive():
			sum += _fleet_points_milli(fl, fl.plan, "", 0)
	return sum


## 이 함대가 초기 진형을 펼 지형. 목적지가 있으면 경로의 최악 회랑,
## 없으면 주둔 상태로 근사한다 (§3.3 지형 필터의 입력).
func _terrain(fl: Fleet) -> String:
	if fl.target_region != "":
		# 코어 판정 — 회랑 등급 + 기저 항로까지 본다 (A-03 · V-60 ⑤)
		var terr := Orders.terrain_on_route(campaign.world.graph, data,
			fl.at_system, data.system_of(fl.target_region))
		if terr != "개활":
			return terr
	if fl.station == "회랑":
		return "중회랑"
	return "개활"


# ---------------------------------------------------------------- 임명 계산
## 그 세력에서 아직 어느 함대에도 앉지 않은 인물 (통솔 내림차순 · Roster 정렬 유지).
## **현재 편집 중인 함대의 기존 배치는 후보로 되돌린다** — 자기 자리 교체가 가능해야 한다.
func _candidate_pool(fl: Fleet) -> Array:
	var used := {}
	for other in campaign.fleets:
		if other.owner != fl.owner or other.id == fl.id:
			continue
		for cid in [other.commander_id, other.vice_id, other.assault_id,
				other.siege_id, other.supply_id]:
			if cid != "":
				used[cid] = true
	# 이 함대에서 지금 화면이 이미 배정한 것도 뺀다
	for slot in _SLOTS:
		var cid := String(_ap.get(slot, ""))
		if cid != "":
			used[cid] = true
	var out: Array = []
	for c in campaign.roster.get(fl.owner, []):
		if not used.has(String(c.get("id", ""))):
			out.append(c)
	return out


func _cycle_slot(slot: String, pool: Array) -> void:
	# 현재 인물 다음 후보로 돌린다. 마지막이면 비운다.
	var cur := String(_ap.get(slot, ""))
	var seq: Array = [""]
	for c in pool:
		seq.append(String(c["id"]))
	if cur != "" and not seq.has(cur):
		seq.append(cur)
	var i := seq.find(cur)
	_ap[slot] = seq[(i + 1) % seq.size()]
	refresh()


func _cycle_squad(idx: int, pool: Array) -> void:
	var seq: Array = [-1]
	for j in pool.size():
		seq.append(j)
	var cur := _squad_pick[idx]
	var i := seq.find(cur)
	_squad_pick[idx] = seq[(i + 1) % seq.size()]
	refresh()


## 전대장 5인. 자동이면 미배치 통솔 상위부터, 수동이면 _squad_pick.
## 반환은 인물 Dictionary 배열이며 빈 자리는 {} 다.
func _squad_assignment(fl: Fleet, pool: Array) -> Array:
	var out: Array = [{}, {}, {}, {}, {}]
	if _squad_mode == "자동":
		for i in mini(5, pool.size()):
			out[i] = pool[i]
	else:
		for i in 5:
			var p := _squad_pick[i]
			if p >= 0 and p < pool.size():
				out[i] = pool[p]
	return out


## 전대장 통솔 스칼라 (§13.4 근사 — 최소값). 다섯이 다 차야 40 을 넘긴다 —
## 하나라도 비면 그 함대의 훈련 상한은 무명 장교값(40)이다 (§6.6).
func _squad_command_scalar(squad: Array) -> int:
	var lowest := 999
	var filled := 0
	for c in squad:
		if (c as Dictionary).is_empty():
			continue
		filled += 1
		lowest = mini(lowest, Roster.stat_of(c, "통솔"))
	if filled < 5 or lowest == 999:
		return 0
	return lowest


## 화면에 적는 훈련도 상한 = max(전대장 통솔 스칼라, 40).
func _squad_cap_display(squad: Array) -> int:
	return maxi(_squad_command_scalar(squad), Battle.DRILL_CAP_UNLED)


# ---------------------------------------------------------------- SC-F1 보조
func _command_stock(fid: String) -> String:
	var grade := {"특급": 0, "1급": 0, "2급": 0, "3급": 0, "4급": 0, "5급": 0, "급외": 0}
	var used := {}
	for fl in campaign.fleets:
		if fl.owner == fid and fl.is_alive() and fl.commander_id != "":
			used[fl.commander_id] = true
	for c in campaign.roster.get(fid, []):
		if used.has(String(c.get("id", ""))):
			continue
		grade[_grade(Roster.stat_of(c, "통솔"))] += 1
	var unassigned := 0
	for fl in campaign.fleets:
		if fl.owner == fid and fl.is_alive() and fl.commander_id == "":
			unassigned += 1
	return "미배치 제독 — 특급 %d · 1급 %d · 2급 %d · 3급 %d · 그 밖 %d   ·   미임명 함대 %d" % [
		grade["특급"], grade["1급"], grade["2급"], grade["3급"],
		grade["4급"] + grade["5급"] + grade["급외"], unassigned]


static func _grade(command: int) -> String:
	if command >= 95: return "특급"
	if command >= 85: return "1급"
	if command >= 75: return "2급"
	if command >= 65: return "3급"
	if command >= 55: return "4급"
	if command >= 40: return "5급"
	return "급외"


func _fleet_warnings(fl: Fleet) -> String:
	var w: Array[String] = []
	if fl.commander_id == "":
		w.append("⚠ 제독 미임명 — 보정 0")
	if fl.squadron_command == 0:
		w.append("⚠ 전대장 없음 — 훈련 상한 40")
	if fl.station == "회랑":
		w.append("⚠ 회랑 봉쇄 — 유지비 ×1.5")
	var cl := Roster.command_limit(fl.command)
	if _fleet_points_milli(fl, fl.plan, "", 0) > cl * 1000:
		w.append("⚠ 지휘 한도 초과")
	return "   ".join(w)


static func _station_mult(station: String) -> float:
	return float(Economy.STATION_MULT.get(station, 100)) / 100.0


# ---------------------------------------------------------------- 잡동사니
func _fleet() -> Fleet:
	return _fleet_by_id(_fleet_id)


func _fleet_by_id(fid: int) -> Fleet:
	for fl in campaign.fleets:
		if fl.id == fid:
			return fl if fl.is_alive() else null
	return null


func _count_fleets(fid: String) -> int:
	var n := 0
	for fl in campaign.fleets:
		if fl.owner == fid and fl.is_alive():
			n += 1
	return n


func _char(owner: String, cid: String) -> Dictionary:
	if cid == "":
		return {}
	for c in campaign.roster.get(owner, []):
		if String(c.get("id", "")) == cid:
			return c
	return {}


func _clear(n: Node) -> void:
	for c in n.get_children():
		c.queue_free()


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", UiPalette.ACCENT)
	return l


func _wrap() -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 6)
	return f


func _kv(parent: Node, key: String, value: String) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 14)
	parent.add_child(r)
	_lbl(r, key, UiPalette.TEXT_FAINT, 18, 260)
	_lbl(r, value, UiPalette.TEXT, 18, 360)
	return r


func _lbl(parent: Node, text: String, col: Color, fsize: int, minw: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", fsize)
	l.custom_minimum_size = Vector2(minw, 0)
	l.clip_text = true
	parent.add_child(l)
	return l


func _btn(parent: Node, text: String, w: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 48)
	b.focus_mode = Control.FOCUS_NONE
	parent.add_child(b)
	return b
