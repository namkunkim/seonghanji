class_name RegionGraph
extends Control

## SC-L2 상단 — **권역 관계도** (`screens.md` §2.2)
##
## > **지도가 아니라 그래프다.** 좌표는 성역 내 실제 배치가 아니라 항로 인접으로만 그린다.
##
## 그러므로 **좌표계를 만들지 않는다.** 권역은 성역당 2~4개이므로
## 지그재그 열 하나에 전부 들어가고, 스크롤이 필요한 성역은 없다.
##
## ⚠ `screens.md` 검토 5 는 **성역별 고정 배치표가 없다**고 적었다.
## 여기 배치는 **권역 ID 순서로 결정되는 유도값**이지 정본 배치표가 아니다.
## 다만 ID 순서는 고정이므로 같은 성역은 언제나 같은 모양으로 그려진다 —
## 「매번 모양이 달라져 지도로 쓸 수 없다」는 검토 5 의 우려는 여기서는 성립하지 않는다.
##
## **회랑은 항로가 아니라 권역에 붙인다** (§2.2).
## 「그 권역을 쥔 세력이 통행을 통제한다」가 그림에서 바로 읽혀야 하기 때문이다.
## 회랑 판정은 **반드시 `GameData.is_corridor()`** 로 한다 —
## 진령삼도 · 이릉협도 · 기산도 · 남중산도는 이름에 「회랑」이 없다 (V-36).

signal region_tapped(rid: String)
signal region_long_pressed(rid: String)
signal fleet_tapped(fleet_id: int)
signal swiped(dir: int)

const NODE_R := 21.0
const HIT_R := 46.0                    # 손가락 크기를 전제한다 (ui-design.md)
const LONG_PRESS_SEC := 0.5
const SWIPE_MIN_PX := 120.0

var data: GameData
var campaign: Campaign
var system_id: String = ""
var viewer: String = ""
var start_year: int = 208

var _nodes: Array[Dictionary] = []
var _edges: Array[Dictionary] = []
var _links: Array[Dictionary] = []
var _marks: Array[Dictionary] = []
var _node_of: Dictionary = {}

var _press_rid: String = ""
var _press_t: float = 0.0
var _press_pos: Vector2 = Vector2.ZERO
var _long_fired: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(0, 300)
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


func set_context(d: GameData, c: Campaign, sid: String) -> void:
	data = d
	campaign = c
	system_id = sid
	viewer = c.world.player_faction
	queue_redraw()


func refresh() -> void:
	queue_redraw()


# ---------------------------------------------------------------- 배치
func _layout() -> void:
	_nodes.clear()
	_edges.clear()
	_links.clear()
	_marks.clear()
	_node_of.clear()
	if data == null or system_id == "":
		return

	var rids: Array = data.regions_of.get(system_id, [])
	var n := rids.size()
	if n == 0:
		return

	var top := 62.0
	var span := maxf(size.y - 130.0, 40.0)
	for i in n:
		var x := 118.0 + float(i % 2) * 126.0
		var y := top + span * 0.5
		if n > 1:
			y = top + span * float(i) / float(n - 1)
		var pos := Vector2(x, y)
		_nodes.append({"rid": rids[i], "pos": pos})
		_node_of[rids[i]] = pos

	# 성역 내 인접 — 기저 항로(회색 실선)
	for i in n:
		for j in range(i + 1, n):
			var a: String = rids[i]
			var b: String = rids[j]
			if data.region_adjacency.get(a, []).has(b):
				_edges.append({"a": _node_of[a], "b": _node_of[b]})

	_build_links()
	_build_fleet_marks()


## 외부 연결. **회랑은 귀속 권역에, 그 밖의 항로는 주권역에 붙인다.**
##
## `data/routes.json` 에는 항로 이름이 없고 `kind` 와 회랑 ID 만 있다.
## 그래서 **비회랑 항로는 어느 권역이 쥐는지 데이터로 알 수 없다** —
## 주권역에 붙이는 것은 이 화면의 대체 규칙이지 정본이 아니다.
## 회랑은 `regions.json` 의 `routes_hosted` 가 이름으로 귀속을 적어 두므로 정확하다.
func _build_links() -> void:
	var rids: Array = data.regions_of.get(system_id, [])
	if rids.is_empty():
		return
	var seat: String = rids[0]
	for rid in rids:
		if bool(data.regions[rid].get("is_seat", false)):
			seat = rid
			break

	var host_of := {}
	for rid in rids:
		for h in data.regions[rid].get("routes_hosted", []):
			if data.is_corridor(String(h)):
				host_of[String(h)] = rid

	var raw: Array[Dictionary] = []
	var drawn := {}
	for rt in data.routes:
		var cs: Array = rt["connects"]
		var other := ""
		if String(cs[0]) == system_id:
			other = String(cs[1])
		elif String(cs[1]) == system_id:
			other = String(cs[0])
		else:
			continue
		var cor_id = rt.get("corridor")
		var cor_name := ""
		var scale := ""
		if cor_id != null and data.corridors.has(cor_id):
			cor_name = String(data.corridors[cor_id]["name"])
			scale = String(data.corridors[cor_id]["scale"])
		var rid: String = seat
		if cor_name != "":
			rid = String(host_of.get(cor_name, seat))
			drawn[cor_name] = true
		raw.append({
			"rid": rid,
			"name": cor_name if cor_name != "" else String(rt["kind"]),
			"target": _side_label(other),
			"corridor": cor_name != "",
			"fast": String(rt["kind"]).contains("고속"),
			"scale": scale,
		})

	# 항로망에 잡히지 않은 귀속 회랑 (성역 안에서 끝나는 관문 등)
	var extra: Array = host_of.keys()
	extra.sort()
	for cname in extra:
		if drawn.has(cname):
			continue
		raw.append({
			"rid": String(host_of[cname]),
			"name": String(cname),
			"target": _corridor_far_side(String(cname)),
			"corridor": true,
			"fast": false,
			"scale": _corridor_scale(String(cname)),
		})

	var m := raw.size()
	if m == 0:
		return
	var x_end := maxf(size.x - 250.0, 470.0)
	var top := 46.0
	var span := maxf(size.y - 96.0, 40.0)
	for i in m:
		var e: Dictionary = raw[i]
		var y := top + span * 0.5
		if m > 1:
			y = top + span * float(i) / float(m - 1)
		var from: Vector2 = _node_of.get(e["rid"], Vector2(150.0, y))
		e["from"] = from
		e["mid"] = Vector2(maxf(from.x + 96.0, 340.0), y)
		e["to"] = Vector2(x_end, y)
		_links.append(e)


func _side_label(side: String) -> String:
	if side.begins_with("EXT:"):
		return side.substr(4)
	if data.systems.has(side):
		return data.system_name(side) + "성역"
	if data.regions.has(side):
		return String(data.regions[side]["name"])
	return side


func _corridor_far_side(cname: String) -> String:
	for cid in data.corridor_ids:
		if String(data.corridors[cid]["name"]) != cname:
			continue
		for side in data.corridors[cid]["sides"]:
			for token in side:
				var t := String(token)
				if t == system_id:
					continue
				if data.regions.has(t) and data.system_of(t) == system_id:
					continue
				return _side_label(t)
	return "—"


func _corridor_scale(cname: String) -> String:
	for cid in data.corridor_ids:
		if String(data.corridors[cid]["name"]) == cname:
			return String(data.corridors[cid]["scale"])
	return ""


## 함대 광점.
##
## ⚠ **코어는 함대를 성계 단위로 둔다** (`Fleet.at_system`). 권역 좌표가 없다.
## 그래서 주둔 함대는 **그 세력이 이 성역에서 가진 주권역**(없으면 ID 최소 권역)에 붙인다.
## 이것은 이 화면의 귀속 규칙이지 코어의 사실이 아니다.
##
## ⚠ **출발 틱이 없다** — `Fleet` 은 `arrival_tick` 만 갖는다. 그래서 항로 위
## 진행률을 낼 수 없고, 이동 중 함대는 위치 대신 **도착 예정 시각**으로 적는다.
func _build_fleet_marks() -> void:
	var station := {}
	var moving: Array[Dictionary] = []
	for fl in campaign.fleets:
		if not fl.is_alive():
			continue
		var inbound: bool = fl.is_moving() and fl.target_region != "" \
			and data.system_of(fl.target_region) == system_id
		if fl.at_system == system_id and not fl.is_moving():
			var rid := _home_rid(fl.owner)
			if rid == "":
				continue
			if not station.has(rid):
				station[rid] = {}
			station[rid][fl.owner] = int(station[rid].get(fl.owner, 0)) + 1
		elif (fl.at_system == system_id and fl.is_moving()) or inbound:
			moving.append({"fleet": fl, "inbound": inbound})

	var keys: Array = station.keys()
	keys.sort()
	for rid in keys:
		var owners: Array = station[rid].keys()
		owners.sort()
		var k := 0
		for own in owners:
			# 노드 **오른쪽 위**에 쌓는다. 아래는 권역명이, 왼쪽은 ⚔ 가,
			# 정면 오른쪽은 항로 선이 쓴다 — 남는 자리가 여기뿐이다.
			_marks.append({
				"kind": "station",
				"pos": Vector2(_node_of[rid]) + Vector2(40.0, -30.0 - 19.0 * float(k)),
				"owner": String(own), "count": int(station[rid][own]),
				"fleet": null, "inbound": false})
			k += 1

	moving.sort_custom(func(a, b): return (a["fleet"] as Fleet).id < (b["fleet"] as Fleet).id)
	var i := 0
	for mv in moving:
		var fl: Fleet = mv["fleet"]
		var anchor := Vector2(size.x * 0.46, 38.0 + 26.0 * float(i))
		if bool(mv["inbound"]) and _node_of.has(fl.target_region):
			anchor = Vector2(_node_of[fl.target_region]) + Vector2(-70.0, -40.0)
		_marks.append({
			"kind": "moving", "pos": anchor, "owner": fl.owner,
			"count": 1, "fleet": fl, "inbound": bool(mv["inbound"])})
		i += 1


func _home_rid(owner: String) -> String:
	var rids: Array = data.regions_of.get(system_id, [])
	var fallback := ""
	for rid in rids:
		var st: RegionState = campaign.world.region_states.get(rid)
		if st == null or st.owner != owner:
			continue
		if bool(data.regions[rid].get("is_seat", false)):
			return rid
		if fallback == "":
			fallback = rid
	return fallback


# ---------------------------------------------------------------- 그리기
func _draw() -> void:
	if data == null or campaign == null or system_id == "":
		return
	_layout()
	var font := get_theme_default_font()
	var fs := 17

	for e in _edges:
		draw_line(e["a"], e["b"], UiPalette.ROUTE_BASE, 2.0, true)

	for l in _links:
		var col: Color = UiPalette.ROUTE_BASE
		if bool(l["corridor"]):
			col = UiPalette.ROUTE_COR
		elif bool(l["fast"]):
			col = UiPalette.ROUTE_FAST
		var pts := PackedVector2Array([l["from"], l["mid"], l["to"]])
		if bool(l["corridor"]):
			# **이중선 ═══** — 회랑은 한눈에 다르게 보여야 한다
			draw_polyline(_offset(pts, -2.5), col, 2.0, true)
			draw_polyline(_offset(pts, 2.5), col, 2.0, true)
		else:
			draw_polyline(pts, col, 2.0, true)
		var label := String(l["name"])
		if String(l["scale"]) != "":
			label += " · " + String(l["scale"])
		var mid: Vector2 = (Vector2(l["mid"]) + Vector2(l["to"])) * 0.5
		draw_string(font, mid + Vector2(-100.0, -9.0), label,
			HORIZONTAL_ALIGNMENT_CENTER, 200, fs - 2, col)
		draw_string(font, Vector2(l["to"]) + Vector2(11.0, 6.0), String(l["target"]),
			HORIZONTAL_ALIGNMENT_LEFT, 230, fs, UiPalette.TEXT_DIM)

	for nd in _nodes:
		_draw_node(font, fs, String(nd["rid"]), Vector2(nd["pos"]))

	for mk in _marks:
		_draw_mark(font, fs, mk)


static func _offset(pts: PackedVector2Array, d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + Vector2(0.0, d))
	return out


func _draw_node(font: Font, fs: int, rid: String, pos: Vector2) -> void:
	var st: RegionState = campaign.world.region_states[rid]
	var col := UiPalette.faction_color(st.owner)
	if st.owner != "" and st.owner == viewer:
		draw_circle(pos, NODE_R, col)                        # ● 아군
	else:
		draw_circle(pos, NODE_R, UiPalette.PANEL)
		draw_arc(pos, NODE_R, 0.0, TAU, 40, col, 2.5, true)  # ○ 타 세력 · ◌ 중립
	draw_string(font, pos + Vector2(-64.0, NODE_R + 21.0),
		String(data.regions[rid]["name"]),
		HORIZONTAL_ALIGNMENT_CENTER, 128, fs, UiPalette.TEXT)
	if bool(data.regions[rid].get("is_seat", false)):
		draw_string(font, pos + Vector2(NODE_R - 3.0, -NODE_R + 5.0), "★",
			HORIZONTAL_ALIGNMENT_LEFT, 40, fs, UiPalette.ACCENT)
	if RegionFlags.contested(data, campaign, rid):
		draw_string(font, pos + Vector2(-NODE_R - 24.0, 8.0), "⚔",
			HORIZONTAL_ALIGNMENT_LEFT, 40, fs, UiPalette.DANGER)


func _draw_mark(font: Font, fs: int, mk: Dictionary) -> void:
	var own := String(mk["owner"])
	var col := UiPalette.FLEET_OWN if own == viewer else UiPalette.FLEET_FOE
	var pos: Vector2 = mk["pos"]
	if String(mk["kind"]) == "station":
		draw_string(font, pos, "▣ ×%d  %s" % [int(mk["count"]), own],
			HORIZONTAL_ALIGNMENT_LEFT, 230, fs - 2, col)
		return
	var fl: Fleet = mk["fleet"]
	var arrow := "⇢" if bool(mk["inbound"]) else "→"
	var dest := "—"
	if fl.target_region != "" and data.regions.has(fl.target_region):
		dest = String(data.regions[fl.target_region]["name"])
	draw_circle(pos, 5.0, col)
	draw_string(font, pos + Vector2(13.0, 6.0),
		"%s %s · 도착 %s" % [arrow, dest,
			UiPalette.tick_label(fl.arrival_tick, start_year)],
		HORIZONTAL_ALIGNMENT_LEFT, 360, fs - 2, col)


# ---------------------------------------------------------------- 입력
func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_press_pos = mb.position
		_press_t = 0.0
		_long_fired = false
		_press_rid = _hit_region(mb.position)
		return
	var moved := mb.position.distance_to(_press_pos)
	if absf(mb.position.x - _press_pos.x) >= SWIPE_MIN_PX \
			and absf(mb.position.y - _press_pos.y) < SWIPE_MIN_PX:
		# 좌우 스와이프 — 인접 성역으로. **L1 을 거치지 않는다** (§2.5)
		swiped.emit(1 if mb.position.x < _press_pos.x else -1)
	elif not _long_fired and moved < 24.0:
		var fid := _hit_fleet(mb.position)
		if fid >= 0:
			fleet_tapped.emit(fid)
		elif _press_rid != "":
			region_tapped.emit(_press_rid)
	_press_rid = ""


func _process(delta: float) -> void:
	if _press_rid == "" or _long_fired:
		return
	_press_t += delta
	if _press_t >= LONG_PRESS_SEC:
		_long_fired = true
		region_long_pressed.emit(_press_rid)


func _hit_region(p: Vector2) -> String:
	var best := ""
	var bd := HIT_R
	for nd in _nodes:
		var d: float = p.distance_to(Vector2(nd["pos"]))
		if d < bd:
			bd = d
			best = String(nd["rid"])
	return best


func _hit_fleet(p: Vector2) -> int:
	for mk in _marks:
		if mk["fleet"] == null:
			continue
		if p.distance_to(Vector2(mk["pos"])) < 40.0:
			return int((mk["fleet"] as Fleet).id)
	return -1
