class_name LayerStrip
extends VBoxContainer

## `SC-L3` 세부 뷰 — **권역 내부 4층** (`screens.md` §3.1 · `combat.md` §8.2)
##
## > `ui-design.md` §3.2 가 4층을 진행도 바 하나로 접었다. 그 바를 되펴는 화면이다.
## > **내부 계산은 언제나 4층이고, 접는 것은 L2 뿐이다.**
##
## | 층 | 공략 수단 | 소요(§8.2) |
## |---|---|---|
## | 외곽        | 함대전 승리          | 30분 |
## | 궤도권      | **공성함 필요**       | 1시간 30분 |
## | 식민지      | 강습 백병전          | 45분 / 거점 |
## | 지구형 행성 | 공성함 + 강습부대     | 4시간 |
##
## > **층은 순서다.** 바깥을 못 뚫으면 안쪽 줄은 회색으로 잠기고 사유가 뜬다 (§3.1).
##
## ⚠ **코어에 4층 공략 진행 상태가 없다.** `Campaign._capture()` 는 전투 결과로
## 소유를 한 번에 바꾼다 — `region_card.gd`·`region_flags.gd` 가 같은 한계를 안는다.
## 그래서 진행률 바를 그리지 않는다. 대신 **소유·교전 여부**로 각 층의 장악 상태를
## 표시하고, 잠금은 「외곽 미돌파」까지만 낼 수 있다. 함종별 척수가 `Fleet` 에
## 없어(§10.4 판정 3 · 아래 검토) 「공성함 0척」 잠금은 캡션으로만 적는다.

const LAYERS := ["외곽", "궤도권", "식민지", "지구형 행성"]

var data: GameData
var campaign: Campaign
var rid: String = ""
var viewer: String = ""

var _rows: Array[Dictionary] = []        # {name_l, state_l, body_l, lock_l, panel}


func setup(d: GameData, c: Campaign, region_id: String) -> void:
	data = d
	campaign = c
	rid = region_id
	viewer = c.world.player_faction
	add_theme_constant_override("separation", 0)
	_build()
	refresh()


func _build() -> void:
	for i in LAYERS.size():
		var panel := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiPalette.PANEL if i % 2 == 0 else UiPalette.PANEL_DIM
		sb.border_color = UiPalette.LINE
		sb.border_width_bottom = 1
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 12
		sb.content_margin_bottom = 12
		panel.add_theme_stylebox_override("panel", sb)
		add_child(panel)

		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 18)
		panel.add_child(h)

		var name_l := _mk(h, LAYERS[i], UiPalette.TEXT, 21, 150)
		var state_l := _mk(h, "", UiPalette.TEXT_DIM, 19, 150)
		var body_l := _mk(h, "", UiPalette.TEXT_DIM, 18, 0)
		body_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lock_l := _mk(h, "", UiPalette.WARN, 17, 260)
		lock_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

		_rows.append({
			"name": name_l, "state": state_l, "body": body_l,
			"lock": lock_l, "panel": panel})


func _mk(parent: Node, text: String, col: Color, fs: int, min_w: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", fs)
	if min_w > 0:
		l.custom_minimum_size = Vector2(min_w, 0)
	l.clip_text = true
	parent.add_child(l)
	return l


# ---------------------------------------------------------------- 갱신 (구독 — 조항 ②)
func refresh() -> void:
	if data == null or not data.regions.has(rid):
		return
	var st: RegionState = campaign.world.region_states[rid]
	var r: Dictionary = data.regions[rid]
	var held_by_us := st.owner == viewer
	var neutral := st.owner == ""
	var contested := RegionFlags.contested(data, campaign, rid)

	# 외곽을 못 뚫었나 — 적이 쥐고 있고 교전 중도 아니면 안쪽 3층은 잠긴다 (§3.1)
	var outer_open := held_by_us or neutral or contested
	var strongholds: Array = r.get("strongholds", [])
	var seat_hold := String(strongholds[0]) if not strongholds.is_empty() else String(r["name"])

	for i in LAYERS.size():
		var row: Dictionary = _rows[i]
		var locked := i >= 1 and not outer_open
		var state := ""
		var body := ""
		var lock := ""

		match i:
			0:  # 외곽 — 함대전
				state = _state_word(held_by_us, neutral, contested)
				body = "항로 진입점 %d · 관측소 —" % _entry_points()
			1:  # 궤도권 — 공성함 필수
				state = _state_word(held_by_us, neutral, contested)
				body = "조선소 — · 방어 위성망 —"
				if not locked:
					lock = "공성함 필요 (§8.2)"
			2:  # 식민지 — 강습 백병전
				state = ("⚔ 교전 중" if contested else _state_word(held_by_us, neutral, false))
				body = _colony_body(strongholds)
			3:  # 지구형 행성 — 공성함 + 강습
				state = _state_word(held_by_us, neutral, false)
				body = "%s · 인구 %d · 생산 %d" % [seat_hold,
					data.region_power(rid), data.region_production(rid)]
				if not locked:
					lock = "공성함 + 강습부대"

		if locked:
			state = "잠김"
			lock = "외곽 미돌파"

		(row["name"] as Label).text = LAYERS[i]
		(row["state"] as Label).text = state
		(row["body"] as Label).text = body
		(row["lock"] as Label).text = lock
		(row["panel"] as PanelContainer).modulate = \
			Color(1, 1, 1, 0.45) if locked else Color(1, 1, 1, 1)


## 소유가 그대로면 4층이 다 「우리」이거나 다 「적」이다 — 코어가 그 이상을 모른다.
func _state_word(ours: bool, neutral: bool, contested: bool) -> String:
	if contested:
		return "⚔ 분쟁"
	if neutral:
		return "미공략"
	return "장악" if ours else "적 장악"


## 이 성역에 닿는 항로 수. 외곽 「진입점」의 근사다 (권역별 항로 귀속이 코어에 없다).
func _entry_points() -> int:
	var sid := data.system_of(rid)
	var n := 0
	for rt in data.routes:
		var cs: Array = rt.get("connects", [])
		if cs.size() == 2 and (String(cs[0]) == sid or String(cs[1]) == sid):
			n += 1
	return n


func _colony_body(strongholds: Array) -> String:
	if strongholds.size() <= 1:
		return "거점 —"
	var names: Array[String] = []
	for k in range(1, strongholds.size()):
		names.append(String(strongholds[k]))
	return "%d거점 · %s" % [names.size(), "  ".join(names)]
