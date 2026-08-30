class_name FleetRow
extends PanelContainer

## `SC-L3` 세부 뷰 — **함대 한 줄** (`screens.md` §3.2)
##
## > 함대 하나 = 아이콘 + 진형 도형 + 사기 게이지 + 지휘부 한 줄.
##
## §1.3 재진입 표시를 지킨다.
##   · 값이 변했다        → 그 수치를 1.5초 강조 후 원복
##   · 대상이 사라졌다     → 회색 처리 · 조작 불가 (부모가 목록에서 뺀다)
##   · 전제가 무너졌다     → 잠금 사유 한 줄 (여기서는 층 잠금이 부모 소관이라 표시만)
##
## ⚠ **진형은 `Fleet.formation` 이 서기 전까지 「미정」이다** (검토 14).
## `_formation_of` 가 필드 유무를 보고 갈라, 필드가 들어오면 자동으로 도형이 뜬다 —
## 「필드를 넣은 것」과 「배선한 것」은 다르므로(HANDOVER 함정 10) 읽는 자리를 여기 하나로 모았다.

signal tapped(fleet_id: int)
signal formation_tapped(fleet_id: int)
signal log_requested(fleet_id: int)          # 더블탭 → 전투 로그(S4.2) · 3D 씬(S5)

const FLASH_SEC := 1.5
const DOUBLE_TAP_SEC := 0.30

var data: GameData
var campaign: Campaign
var fleet_id: int = -1
var viewer: String = ""
var start_year: int = 208

var _icon: FormationIcon
var _l_name: Label
var _l_ships: Label
var _l_form: Label
var _l_morale: Label
var _gauge: Gauge
var _l_cmd: Label
var _drill: Gauge
var _l_drill: Label
var _l_move: Label

var _last: Dictionary = {}
var _flash: Dictionary = {}
var _tap_t: float = 0.0
var _pending_tap: bool = false


func setup(d: GameData, c: Campaign, fid: int) -> void:
	data = d
	campaign = c
	fleet_id = fid
	viewer = c.world.player_faction
	_build()
	refresh()


func _build() -> void:
	custom_minimum_size = Vector2(0, 92)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiPalette.PANEL
	sb.border_color = UiPalette.LINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	add_theme_stylebox_override("panel", sb)

	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_icon = FormationIcon.new()
	root.add_child(_icon)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)

	# ---- 1행: 이름 · 척수 · 진형명 · 사기 게이지
	var r1 := _hbox(col)
	_l_name = _label(r1, "", UiPalette.TEXT, 22)
	_l_name.custom_minimum_size = Vector2(150, 0)
	_l_ships = _label(r1, "", UiPalette.TEXT_DIM, 19)
	_l_ships.custom_minimum_size = Vector2(96, 0)
	_l_form = _label(r1, "", UiPalette.TEXT_DIM, 19)
	_l_form.custom_minimum_size = Vector2(150, 0)
	_l_form.tooltip_text = "진형 도형을 탭하면 지형 필터·요구 통솔을 미리 본다 (§3.4)"
	_l_morale = _label(r1, "", UiPalette.TEXT_FAINT, 18)
	_l_morale.custom_minimum_size = Vector2(120, 0)
	_l_morale.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gauge = Gauge.new()
	_gauge.custom_minimum_size = Vector2(300, 15)
	r1.add_child(_gauge)

	# ---- 2행: 지휘부 한 줄 · 훈련도 가는 선
	var r2 := _hbox(col)
	_l_cmd = _label(r2, "", UiPalette.TEXT_DIM, 18)
	_l_cmd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_l_drill = _label(r2, "", UiPalette.TEXT_FAINT, 16)
	_l_drill.custom_minimum_size = Vector2(120, 0)
	_l_drill.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_drill = Gauge.new()
	_drill.custom_minimum_size = Vector2(300, 6)          # **게이지 아래 가는 선** (§3.2)
	_drill.bar_color = UiPalette.TEXT_FAINT
	r2.add_child(_drill)

	# ---- 3행: 이동 중 도착 예정 (없으면 숨김)
	_l_move = _label(col, "", UiPalette.ROUTE_FAST, 17)
	_l_move.visible = false


func _hbox(parent: Node) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(h)
	return h


func _label(parent: Node, text: String, col: Color, fsize: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", fsize)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_meta("base_color", col)
	parent.add_child(l)
	return l


# ---------------------------------------------------------------- 갱신 (구독 — 조항 ②)
func refresh() -> void:
	var fl := _find()
	if fl == null:
		modulate = Color(1, 1, 1, 0.55)
		_put(_l_name, "제%d함대 — 소실" % fleet_id)
		_gauge.visible = false
		_drill.visible = false
		return
	modulate = Color(1, 1, 1, 1)

	var rel := FormationIcon.Rel.OWN if fl.owner == viewer else FormationIcon.Rel.FOE
	if fl.owner != viewer and _is_ally(fl.owner):
		rel = FormationIcon.Rel.ALLY
	var form := _formation_of(fl)
	_icon.set_icon(rel, UiPalette.faction_color(fl.owner), form)

	var foe_tag := "  [적]" if fl.owner != viewer and rel == FormationIcon.Rel.FOE else ""
	_put(_l_name, "제%d함대%s" % [fl.id, foe_tag])
	_l_name.add_theme_color_override("font_color",
		UiPalette.TEXT if fl.owner == viewer else UiPalette.FLEET_FOE)
	_put(_l_ships, "%d척" % fl.ships)
	_put(_l_form, form if form != "" else "진형 미정")
	_l_form.add_theme_color_override("font_color",
		UiPalette.TEXT_DIM if form != "" else UiPalette.TEXT_FAINT)

	# 사기 — 0~125 · 눈금 100 · 39 이하 붕괴색 (§2.3)
	_put(_l_morale, "사기 %d / 125" % fl.morale)
	_gauge.bar_color = UiPalette.FLEET_OWN if fl.owner == viewer else UiPalette.FLEET_FOE
	_gauge.set_value(fl.morale, Battle.MORALE_MAX, Battle.MORALE_NOMINAL,
		Battle.MORALE_COLLAPSE_CEIL)
	if fl.morale <= Battle.MORALE_COLLAPSE_CEIL:
		_put(_l_morale, "사기 %d / 125  ⚠ 붕괴" % fl.morale)   # 색 + 눈금 + 글자, 세 겹

	_put(_l_cmd, _command_line(fl))

	# 훈련도 — 전대장 없으면 상한 40 에서 끊긴다 (§3.2)
	var cap: int = fl.drill_cap()
	_drill.set_value(fl.drill, Battle.DRILL_MAX, cap if cap < Battle.DRILL_MAX else 0)
	_put(_l_drill, "훈련 %d/%d%s" % [fl.drill, cap,
		"  ⚠" if fl.squadron_command == 0 else ""])

	if fl.is_moving():
		var dest := "—"
		if data.regions.has(fl.target_region):
			dest = String(data.regions[fl.target_region]["name"])
		_put(_l_move, "→ %s · 도달 %s" % [dest,
			UiPalette.tick_label(fl.arrival_tick, start_year)])
		_l_move.visible = true
	else:
		_l_move.visible = false


## 지휘부 — **배치된 것만** 적는다. 빈자리는 아예 쓰지 않는다 (§3.2).
func _command_line(fl: Fleet) -> String:
	var parts: Array[String] = []
	parts.append(fl.commander_name if fl.commander_name != "" else "무명 장교(보정 0)")
	if fl.vice_command > 0:
		parts.append("부 " + _name_of(fl.vice_id))
	if fl.assault_might > 0:
		parts.append("강습 " + _name_of(fl.assault_id))
	if fl.siege_wits > 0:
		parts.append("공성 " + _name_of(fl.siege_id))
	if fl.supply_politics > 0:
		parts.append("보급 " + _name_of(fl.supply_id))
	return "  ·  ".join(parts)


func _name_of(cid: String) -> String:
	if cid == "" or not data.characters.has(cid):
		return "?"
	return String(data.characters[cid].get("name", "?"))


## 진형. `Fleet.formation` 이 있으면 그 값, 없으면 "" (미정).
## **필드가 서면 이 한 줄이 화면을 배선한다** — 다른 데 손 안 댄다.
func _formation_of(fl: Fleet) -> String:
	if "formation" in fl:
		return String(fl.formation)
	return ""


func _is_ally(owner: String) -> bool:
	if viewer == "" or campaign.diplo == null:
		return false
	return campaign.diplo.is_allied(viewer, owner)


func _find() -> Fleet:
	for fl in campaign.fleets:
		if fl.id == fleet_id:
			return fl if fl.is_alive() else null
	return null


# ---------------------------------------------------------------- 입력
func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	# 아이콘(진형 도형) 위를 눌렀나 — §3.4 「진형 도형 탭 → 진형 선택」
	if _icon.get_global_rect().has_point(mb.global_position):
		formation_tapped.emit(fleet_id)
		return
	if _pending_tap and _tap_t <= DOUBLE_TAP_SEC:
		_pending_tap = false
		log_requested.emit(fleet_id)                # 더블탭
	else:
		_pending_tap = true
		_tap_t = 0.0


func _process(delta: float) -> void:
	if _pending_tap:
		_tap_t += delta
		if _tap_t > DOUBLE_TAP_SEC:
			_pending_tap = false
			tapped.emit(fleet_id)                   # 단일탭 확정
	_tick_flash(delta)


# ---------------------------------------------------------------- §1.3 값 변화 강조
func _put(l: Label, text: String) -> void:
	var key := str(l.get_instance_id())
	if _last.has(key) and String(_last[key]) != text:
		_flash[l] = FLASH_SEC
	_last[key] = text
	l.text = text


func _tick_flash(delta: float) -> void:
	if _flash.is_empty():
		return
	var done: Array = []
	for l in _flash.keys():
		var t: float = float(_flash[l]) - delta
		var lb := l as Label
		if t <= 0.0 or lb == null:
			done.append(l)
			if lb != null:
				lb.add_theme_color_override("font_color", lb.get_meta("base_color"))
			continue
		_flash[l] = t
		lb.add_theme_color_override("font_color",
			Color(lb.get_meta("base_color")).lerp(UiPalette.FLASH, t / FLASH_SEC))
	for l in done:
		_flash.erase(l)
