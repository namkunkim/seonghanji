class_name RegionCard
extends PanelContainer

## SC-L2 하단 — **권역 카드** (`screens.md` §2.3)
##
## | 행 | 항목 | 평시 |
## |---|---|---|
## | 1 | 권역명 · ★주권역 · 소유 세력 · 국력 지수 · ⚔ | 표시 |
## | 2 | 공략 진행도 바(4층 축약) · 직할/위임 배지 · 담당관 | **공략 중에만 바 표시** |
## | 3 | 전화 계수 · 권역 안정도 · 개발여지 잔여 · 주둔 함대 수 | 접힘 — 탭하면 펼침 |
##
## **§2.3 과 §2.5 가 「탭」을 두 번 쓴다.** §2.3 은 3행을 펼치라 하고
## §2.5 는 하프 시트를 열라 한다. 둘 다 지키기 위해 **탭 대상을 나눴다** —
## 카드 본문 탭은 하프 시트, 오른쪽 ⌄ 단추는 3행이다.
## (어긋난 곳이므로 고치지 않고 보고한다.)
##
## ⚠ **공략 진행도 바를 그리지 못한다.** 코어에 4층 공략 진행 상태가 없다 —
## `Campaign._capture()` 는 전투 결과로 소유를 한 번에 바꾼다.
## `partial-occupation.md` 의 외곽→궤도권→식민지→지구형 행성은 아직 코드가 아니다.
## **없는 값을 0% 로 그리지 않는다.** 바 자체를 내지 않는다.

signal tapped(rid: String)
signal long_pressed(rid: String)

const LONG_PRESS_SEC := 0.5
const FLASH_SEC := 1.5                 # §1.3 — 값이 변하면 1.5초 강조 후 원복
const MIN_HEIGHT := 66                 # 손가락 크기 (ui-design.md)

var rid: String = ""
var data: GameData
var campaign: Campaign
var viewer: String = ""

var _row1: HBoxContainer
var _row2: HBoxContainer
var _row3: HBoxContainer
var _chevron: Button

var _l_head: Label
var _l_owner: Label
var _l_power: Label
var _l_badge: Label
var _l_admin: Label
var _l_officer: Label
var _l_damage: Label
var _l_stab: Label
var _l_dev: Label
var _l_fleet: Label

var _last: Dictionary = {}
var _flash: Dictionary = {}            # Label -> 남은 초
var _expanded_detail: bool = false
var _dimmed: bool = false

var _press_t: float = 0.0
var _pressing: bool = false
var _long_fired: bool = false


func setup(d: GameData, c: Campaign, region_id: String) -> void:
	data = d
	campaign = c
	rid = region_id
	viewer = c.world.player_faction
	_build()
	refresh()


func _build() -> void:
	custom_minimum_size = Vector2(0, MIN_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiPalette.PANEL
	sb.border_color = UiPalette.LINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 16
	sb.content_margin_right = 12
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	add_theme_stylebox_override("panel", sb)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)

	_row1 = _row(col)
	_l_head = _label(_row1, "", UiPalette.TEXT, 21)
	_l_head.custom_minimum_size = Vector2(210, 0)
	_l_owner = _label(_row1, "", UiPalette.TEXT_DIM, 19)
	_l_owner.custom_minimum_size = Vector2(120, 0)
	_l_power = _label(_row1, "", UiPalette.TEXT, 19)
	_l_power.custom_minimum_size = Vector2(120, 0)
	_l_badge = _label(_row1, "", UiPalette.WARN, 19)
	_l_badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_chevron = Button.new()
	_chevron.text = "⌄"
	_chevron.flat = true
	_chevron.custom_minimum_size = Vector2(56, 44)
	_chevron.focus_mode = Control.FOCUS_NONE
	_chevron.tooltip_text = "3행 펼침 — 전화 계수 · 안정도 · 개발여지 · 주둔"
	_chevron.pressed.connect(_toggle_detail)
	_row1.add_child(_chevron)

	_row2 = _row(col)
	_l_admin = _label(_row2, "", UiPalette.TEXT_DIM, 18)
	_l_admin.custom_minimum_size = Vector2(210, 0)
	_l_officer = _label(_row2, "", UiPalette.TEXT_FAINT, 18)
	_l_officer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_row3 = _row(col)
	_row3.visible = false
	_l_damage = _label(_row3, "", UiPalette.TEXT_DIM, 18)
	_l_damage.custom_minimum_size = Vector2(210, 0)
	_l_stab = _label(_row3, "", UiPalette.TEXT_DIM, 18)
	_l_stab.custom_minimum_size = Vector2(160, 0)
	_l_dev = _label(_row3, "", UiPalette.TEXT_DIM, 18)
	_l_dev.custom_minimum_size = Vector2(180, 0)
	_l_fleet = _label(_row3, "", UiPalette.TEXT_DIM, 18)
	_l_fleet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_l_fleet.tooltip_text = "코어는 함대를 성계 단위로 둔다 — 이 성역에 있는 소유 세력의 함대 수다"


func _row(parent: Node) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
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


func _toggle_detail() -> void:
	_expanded_detail = not _expanded_detail
	_chevron.text = "⌃" if _expanded_detail else "⌄"
	_row3.visible = _expanded_detail


# ---------------------------------------------------------------- 갱신
func refresh() -> void:
	var st: RegionState = campaign.world.region_states[rid]
	var r: Dictionary = data.regions[rid]
	var notable := RegionFlags.notable(data, campaign, rid)

	var seat := " ★" if bool(r.get("is_seat", false)) else ""
	_set_text(_l_head, "%s %s%s" % [
		UiPalette.owner_glyph(st.owner, viewer), String(r["name"]), seat])
	_set_text(_l_owner, st.owner if st.owner != "" else "중립")
	_l_owner.add_theme_color_override("font_color", UiPalette.faction_color(st.owner))
	_l_owner.set_meta("base_color", UiPalette.faction_color(st.owner))
	_set_text(_l_power, "국력 %d" % data.region_power(rid))
	_set_text(_l_badge, _badges(st))

	# 2행 — **공략 진행도 바는 없다**(코어 미구현). 직할/위임 배지만 남는다.
	_set_text(_l_admin, "위임" if st.delegated else "직할")
	_l_admin.add_theme_color_override("font_color",
		UiPalette.WARN if st.delegated else UiPalette.TEXT_DIM)
	_l_admin.set_meta("base_color",
		UiPalette.WARN if st.delegated else UiPalette.TEXT_DIM)
	var pend := RegionFlags.commands_pending(campaign, rid)
	var done := RegionFlags.command_done(campaign, rid)
	var line := "담당관 —"                        # 담당관 배정은 코어에 없다
	if pend > 0:
		line += "   · 명령 %d건 도달 대기" % pend
	if not done.is_empty():
		line += "   · %s 도달 (%s)" % [String(done.get("kind", "명령")),
			UiPalette.tick_label(int(done.get("arrival_tick", 0)), _start_year())]
	_set_text(_l_officer, line)

	# 3행
	_set_text(_l_damage, "전화 %.2f" % (float(st.war_damage_milli) / 1000.0))
	_set_text(_l_stab, "안정 %d" % st.stability)
	_set_text(_l_dev, "개발여지 %d / %d" % [
		data.region_dev_slots(rid) - st.development, data.region_dev_slots(rid)])
	_set_text(_l_fleet, "주둔 %d함대" % _fleets_here(st.owner))

	# §2.4 — 주목 권역만 펼친다
	_row2.visible = notable
	if not notable and _expanded_detail:
		pass                                       # 손으로 편 것은 접지 않는다
	_dim(st.owner == "" or (viewer != "" and st.owner != viewer and not notable))


func _badges(st: RegionState) -> String:
	var out: Array[String] = []
	if RegionFlags.contested(data, campaign, rid):
		out.append("⚔ 분쟁")
	if RegionFlags.enclave(data, campaign, rid):
		out.append("비지")
	elif RegionFlags.enclave_risk(data, campaign, rid):
		out.append("비지 위험")
	return "   ".join(out)


## 이 성역에 있는 그 세력의 함대 수. **성계 단위다** — 위 tooltip 참조.
func _fleets_here(owner: String) -> int:
	if owner == "":
		return 0
	var sid := data.system_of(rid)
	var n := 0
	for fl in campaign.fleets:
		if fl.is_alive() and fl.owner == owner and fl.at_system == sid and not fl.is_moving():
			n += 1
	return n


func _start_year() -> int:
	return 208


## 값이 바뀌면 1.5초 강조한다 (§1.3 조항 ② — 화면이 읽는 값은 스냅샷이 아니다)
func _set_text(l: Label, text: String) -> void:
	var key := str(l.get_instance_id())
	if _last.has(key) and String(_last[key]) != text:
		_flash[l] = FLASH_SEC
	_last[key] = text
	l.text = text


func _dim(on: bool) -> void:
	if on == _dimmed:
		return
	_dimmed = on
	modulate = Color(1, 1, 1, 0.62) if on else Color(1, 1, 1, 1)


func _process(delta: float) -> void:
	if not _flash.is_empty():
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
	if not _pressing or _long_fired:
		return
	_press_t += delta
	if _press_t >= LONG_PRESS_SEC:
		_long_fired = true
		long_pressed.emit(rid)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_pressing = true
		_press_t = 0.0
		_long_fired = false
	else:
		_pressing = false
		if not _long_fired:
			tapped.emit(rid)
