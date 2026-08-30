class_name HalfSheet
extends PanelContainer

## SC-L2 위에 겹치는 **하프 시트** (`screens.md` §0.2 · §2.5)
##
## > **하프 시트는 층이 아니라 L2 의 오버레이로 내린다.**
## > 깊이는 L1 → L2 → L3 으로 그대로 셋이다.
##
## 그래서 **관계도를 가리지 않는다.** 카드 영역만 덮고 지도는 계속 보인다.
## 그리고 **모달이 아니다** — 시뮬레이션은 시트가 열려 있는 동안에도 돈다 (V-25 ④).
##
## §1.3 재진입 표시를 여기서 지킨다.
##   · 대상이 사라졌다 (함대 전멸 · 권역 소유 변경) → **회색 처리 · 조작 불가 · 닫기만**
##   · 전제가 무너졌다 → **단추가 잠기고 사유를 한 줄로 적는다**

signal closed()
signal detail_requested(rid: String)

## 함대 시트에서 SC-F2 / SC-F3 (S3.6) 로 넘어간다 — `screens.md` §2.6 · §3.4 전이도.
signal compose_requested(fleet_id: int)
signal appoint_requested(fleet_id: int)

var data: GameData
var campaign: Campaign
var start_year: int = 208

var _mode: String = ""              # "region" | "fleet"
var _rid: String = ""
var _fleet_id: int = -1
var _owner_at_open: String = ""

var _title: Label
var _body: GridContainer
var _note: Label
var _btn_detail: Button
var _btn_more: Button
var _btn_appoint: Button          # 함대 시트에서만 — SC-F3 임명 (S3.6)
var _gauge: Gauge
var _gauge_row: HBoxContainer
var _gauge_label: Label


func _ready() -> void:
	visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiPalette.PANEL_HI
	sb.border_color = UiPalette.ACCENT
	sb.border_width_top = 2
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	add_theme_stylebox_override("panel", sb)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	col.add_child(head)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)

	_btn_detail = _button(head, "세부 ▸")
	_btn_detail.pressed.connect(func(): detail_requested.emit(_rid))
	_btn_more = _button(head, "편성 ▸")
	_btn_more.pressed.connect(func(): compose_requested.emit(_fleet_id))
	_btn_appoint = _button(head, "임명 ▸")
	_btn_appoint.pressed.connect(func(): appoint_requested.emit(_fleet_id))
	var btn_close := _button(head, "닫기")
	btn_close.pressed.connect(close)

	_gauge_row = HBoxContainer.new()
	_gauge_row.add_theme_constant_override("separation", 12)
	col.add_child(_gauge_row)
	_gauge_label = Label.new()
	_gauge_label.add_theme_font_size_override("font_size", 18)
	_gauge_label.custom_minimum_size = Vector2(210, 0)
	_gauge_row.add_child(_gauge_label)
	_gauge = Gauge.new()
	_gauge.custom_minimum_size = Vector2(420, 16)
	_gauge_row.add_child(_gauge)

	# **두 칸으로 접는다.** 한 줄에 하나씩 쌓으면 시트가 지도까지 올라온다 —
	# 그러면 §0.2 의 「하프 시트는 오버레이지 층이 아니다」가 깨진다.
	_body = GridContainer.new()
	_body.columns = 4
	_body.add_theme_constant_override("h_separation", 18)
	_body.add_theme_constant_override("v_separation", 6)
	col.add_child(_body)

	_note = Label.new()
	_note.add_theme_font_size_override("font_size", 17)
	_note.add_theme_color_override("font_color", UiPalette.WARN)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_note)


func _button(parent: Node, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(120, 52)      # 손가락 크기
	b.focus_mode = Control.FOCUS_NONE
	parent.add_child(b)
	return b


func setup(d: GameData, c: Campaign) -> void:
	data = d
	campaign = c


# ---------------------------------------------------------------- 열기
func open_region(rid: String) -> void:
	_mode = "region"
	_rid = rid
	_fleet_id = -1
	var st: RegionState = campaign.world.region_states[rid]
	_owner_at_open = st.owner
	visible = true
	refresh()


func open_fleet(fleet_id: int) -> void:
	_mode = "fleet"
	_fleet_id = fleet_id
	_rid = ""
	visible = true
	refresh()


func close() -> void:
	visible = false
	_mode = ""
	closed.emit()


func refresh() -> void:
	if not visible:
		return
	if _mode == "region":
		_refresh_region()
	elif _mode == "fleet":
		_refresh_fleet()


# ---------------------------------------------------------------- 권역 시트
func _refresh_region() -> void:
	var st: RegionState = campaign.world.region_states[_rid]
	var r: Dictionary = data.regions[_rid]
	_title.text = "%s%s   ·   %s성역" % [
		String(r["name"]), "  ★" if bool(r.get("is_seat", false)) else "",
		data.system_name(data.system_of(_rid))]

	_gauge_label.text = "권역 안정도 %d / 100" % st.stability
	_gauge.bar_color = UiPalette.ROUTE_FAST
	_gauge.set_value(st.stability, Stability.MAX, 0, 30)
	_gauge_row.visible = true

	_clear_body()
	_pair("소유", st.owner if st.owner != "" else "중립")
	_pair("국력 · 생산 · 수입", "%d · %d · %d" % [
		data.region_power(_rid), data.region_production(_rid),
		data.region_income(_rid)])
	_pair("전화 계수", "%.3f  (상한 0.950)" % (float(st.war_damage_milli) / 1000.0))
	_pair("개발", "%d / %d 단계   (개발여지 %s)" % [
		st.development, data.region_dev_slots(_rid),
		String(r.get("dev_potential", "—"))])
	_pair("통치", "위임 — 수입 −30% · 실동원 −50%" if st.delegated else "직할")
	_pair("획득", _acquired_text(st))
	_pair("거점", "  ·  ".join(_strings(r.get("strongholds", []))))
	_pair("귀속 항로", _routes_text(_rid))
	_pair("인접 권역", _adjacent_text(_rid))
	_pair("주둔 함대", "%d  (성계 단위 — 코어에 권역별 주둔이 없다)" % _fleets_here(st.owner))

	var notes: Array[String] = []
	if st.owner != _owner_at_open:
		notes.append("⚠ 소유가 바뀌었다: %s → %s. 조작을 잠근다 (§1.3)" % [
			_owner_at_open if _owner_at_open != "" else "중립",
			st.owner if st.owner != "" else "중립"])
	notes.append("내정 명령은 명령 메뉴(S3.5)가 붙어야 열린다 — 「발행 ○월 → 도달 △월」도 그때 나온다")
	_note.text = "\n".join(notes)

	var lost := st.owner != _owner_at_open
	modulate = Color(1, 1, 1, 0.6) if lost else Color(1, 1, 1, 1)
	_btn_detail.visible = true
	_btn_detail.disabled = lost       # SC-L3 (S3.4) 가 섰다. 대상 소멸 시엔 잠근다 (§1.3)
	_btn_detail.tooltip_text = "세부 뷰 SC-L3 — 권역 내부 4층 · 함대 진형"
	_btn_more.visible = false
	_btn_appoint.visible = false


func _acquired_text(st: RegionState) -> String:
	if st.acquired_tick == RegionState.NEVER:
		return "—"
	var when := UiPalette.tick_label(maxi(st.acquired_tick, 0), start_year)
	if st.acquired_tick < 0:
		when = "시나리오 시작 %d개월 전" % (-st.acquired_tick / GameClock.TICKS_PER_MONTH)
	var fresh := "  · 신복속" if st.is_newly_taken(campaign.world.clock.tick) else ""
	return "%s  (%s)%s" % [st.acquired_by if st.acquired_by != "" else "—", when, fresh]


## 귀속 항로. **회랑은 반드시 `is_corridor()` 로 판정한다** (V-36).
func _routes_text(rid: String) -> String:
	var out: Array[String] = []
	for h in data.regions[rid].get("routes_hosted", []):
		var n := String(h)
		out.append(("═ " + n + " 회랑") if data.is_corridor(n) else ("· " + n))
	return "  ".join(out) if not out.is_empty() else "—"


func _adjacent_text(rid: String) -> String:
	var out: Array[String] = []
	for nb in data.region_adjacency.get(rid, []):
		var ns: RegionState = campaign.world.region_states.get(nb)
		var own := "중립" if ns == null or ns.owner == "" else ns.owner
		out.append("%s(%s)" % [String(data.regions[nb]["name"]), own])
	return "  ".join(out) if not out.is_empty() else "—"


func _fleets_here(owner: String) -> int:
	if owner == "" or _rid == "":
		return 0
	var sid := data.system_of(_rid)
	var n := 0
	for fl in campaign.fleets:
		if fl.is_alive() and fl.owner == owner and fl.at_system == sid and not fl.is_moving():
			n += 1
	return n


# ---------------------------------------------------------------- 함대 시트
func _refresh_fleet() -> void:
	var fl := _find_fleet()
	if fl == null:
		_title.text = "함대 —"
		_clear_body()
		_gauge_row.visible = false
		_note.text = "⚠ 이 함대는 사라졌다. 닫기만 남는다 (§1.3)"
		modulate = Color(1, 1, 1, 0.6)
		_btn_detail.visible = false
		_btn_more.visible = false
		_btn_appoint.visible = false
		return

	modulate = Color(1, 1, 1, 1)
	_title.text = "제%d함대   ·   %s" % [fl.id, fl.owner]
	# **사기 게이지는 0~125 이고 100 에 눈금선을 둔다** (§2.3)
	_gauge_label.text = "사기 %d / 125  (명목 100)" % fl.morale
	_gauge.bar_color = UiPalette.FLEET_OWN
	_gauge.set_value(fl.morale, Battle.MORALE_MAX, Battle.MORALE_NOMINAL,
		Battle.MORALE_COLLAPSE_CEIL)
	_gauge_row.visible = true

	_clear_body()
	_pair("규모", "%d척  (전대 %d척 · 함대 %d척 정본)" % [
		fl.ships, Battle.SQUADRON_SHIPS, Battle.FLEET_SHIPS])
	_pair("편성안", fl.plan)
	_pair("진형", "%s  (%s · 요구 통솔 %d)" % [fl.formation,
		FormationSpec.directive(fl.formation),
		FormationSpec.required_command(fl.formation)])
	_pair("주둔 상태", fl.station)
	_pair("제독", "%s  (통솔 %d · 무력 %d · 지력 %d)" % [
		fl.commander_name if fl.commander_name != "" else "무명 장교 — 보정 0",
		fl.command, fl.might, fl.wits])
	_pair("부제독 · 임무대장", "부 %s · 강습 %s · 공성 %s · 보급 %s" % [
		_slot(fl.vice_command), _slot(fl.assault_might),
		_slot(fl.siege_wits), _slot(fl.supply_politics)])
	_pair("훈련도", "%d / %d%s" % [fl.drill, fl.drill_cap(),
		"   ⚠ 전대장 없음 — 상한 40" if fl.squadron_command == 0 else ""])
	if fl.is_moving():
		var dest := String(data.regions[fl.target_region]["name"]) \
			if data.regions.has(fl.target_region) else "—"
		_pair("이동", "→ %s · 도착 %s" % [dest,
			UiPalette.tick_label(fl.arrival_tick, start_year)])
	else:
		_pair("위치", data.system_name(fl.at_system) + "성역 주둔")

	_note.text = "편성안·초기 진형은 [편성 ▸](SC-F2), 지휘부는 [임명 ▸](SC-F3)에서 발행한다. 세부 뷰(SC-L3)에서 진형 도형을 탭하면 지형 필터를 미리 볼 수 있다."
	_btn_detail.visible = false
	_btn_more.visible = true
	_btn_more.disabled = false
	_btn_more.tooltip_text = "편성 시트 SC-F2 — 편성안 · 강화 축 · 초기 진형"
	_btn_appoint.visible = true
	_btn_appoint.disabled = false
	_btn_appoint.tooltip_text = "임명 시트 SC-F3 — 지휘부 5직 · 전대장"


static func _slot(v: int) -> String:
	return "—" if v == 0 else str(v)          # **빈자리는 빈자리로 보여야 한다** (§3.2)


func _find_fleet() -> Fleet:
	for fl in campaign.fleets:
		if fl.id == _fleet_id:
			return fl if fl.is_alive() else null
	return null


# ---------------------------------------------------------------- 보조
func _clear_body() -> void:
	for c in _body.get_children():
		c.queue_free()


func _pair(key: String, value: String) -> void:
	var k := Label.new()
	k.text = key
	k.custom_minimum_size = Vector2(160, 0)
	k.add_theme_color_override("font_color", UiPalette.TEXT_FAINT)
	k.add_theme_font_size_override("font_size", 18)
	_body.add_child(k)
	var v := Label.new()
	v.text = value
	v.add_theme_color_override("font_color", UiPalette.TEXT)
	v.add_theme_font_size_override("font_size", 18)
	v.custom_minimum_size = Vector2(420, 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.clip_text = true
	_body.add_child(v)


static func _strings(a: Array) -> Array[String]:
	var out: Array[String] = []
	for x in a:
		out.append(String(x))
	return out
