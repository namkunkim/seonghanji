class_name FormationIcon
extends Control

## 함대 아이콘의 본체 — `screens.md` §3.2 「함대 하나 = 아이콘 + 진형 도형 + …」
##
## 세 채널을 한 도형에 겹친다 (색각 이상 대응 — `FormationSpec` 주석 참조).
##   ① 소유 관계 → 테두리 도형  ▣ 아군(채움) · ▢ 적(속 빔) · ▨ 동맹(반채움)
##   ② 세력 정체 → 색조 (행마다 세력명도 글자로 적힌다)
##   ③ 진형     → 실루엣 + 전개 폭 (광폭은 넓게, 최협은 한 줄)
##
## 진형이 **미정**일 수 있다 — `Fleet.formation` 필드가 서기 전(검토 14)이거나
## 관측 단계 미달로 적 진형을 모를 때(§12). 그때는 점선 테두리 + `?` 로 그린다.
## **없는 값을 어린진으로 채워 그리지 않는다** (§3.2 「빈자리는 빈자리로」).

enum Rel { OWN, FOE, ALLY }

var relation: int = Rel.OWN
var faction_color: Color = UiPalette.NEUTRAL
var formation_name: String = ""        # "" 이면 미정
var locked: bool = false               # 잠긴 층/전제 붕괴 — 회색


func _init() -> void:
	custom_minimum_size = Vector2(84, 84)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_icon(rel: int, fcol: Color, formation: String, is_locked: bool = false) -> void:
	relation = rel
	faction_color = fcol
	formation_name = formation
	locked = is_locked
	queue_redraw()


func _draw() -> void:
	var pad := 6.0
	var r := Rect2(pad, pad, size.x - pad * 2.0, size.y - pad * 2.0)
	var line_col := UiPalette.TEXT_DIM if locked else UiPalette.TEXT
	var fill := faction_color
	fill.a = 0.0 if locked else 0.22
	var undetermined := formation_name == ""

	# ---- ① 테두리 도형 = 소유 관계
	if undetermined:
		_dashed_rect(r, line_col)
	else:
		match relation:
			Rel.OWN:
				draw_rect(r, fill)
				draw_rect(r, line_col, false, 2.0)
			Rel.FOE:
				draw_rect(r, line_col, false, 2.0)        # 속 빔
			Rel.ALLY:
				# 반채움 — 대각선 아래쪽만
				var tri := PackedVector2Array([
					r.position + Vector2(0, r.size.y),
					r.position + r.size,
					r.position + Vector2(r.size.x, 0)])
				draw_colored_polygon(tri, fill)
				draw_rect(r, line_col, false, 2.0)

	# ---- ③ 실루엣 = 진형
	var c := r.get_center()
	if undetermined:
		var f := get_theme_default_font()
		draw_string(f, c + Vector2(-7, 8), "?", HORIZONTAL_ALIGNMENT_CENTER, -1, 26, line_col)
		return

	var sil_col := line_col if locked else faction_color.lerp(UiPalette.TEXT, 0.35)
	var spread: float = FormationSpec.spread(formation_name) * r.size.x
	var half := spread * 0.5
	var h := r.size.y * 0.30
	match FormationSpec.shape_of(formation_name):
		"wedge":                       # ◤◥ 중앙 돌파 — 안으로 파고드는 쐐기 두 짝
			_poly(sil_col, [c + Vector2(-half, -h), c + Vector2(-2, 0), c + Vector2(-half, h)])
			_poly(sil_col, [c + Vector2(half, -h), c + Vector2(2, 0), c + Vector2(half, h)])
		"arc":                         # ⌒ 양익 포위 — 아래로 벌린 활
			var pts := PackedVector2Array()
			for i in 13:
				var t := float(i) / 12.0
				pts.append(c + Vector2(lerpf(-half, half, t), -h + sin(t * PI) * h * 1.7))
			draw_polyline(pts, sil_col, 2.5, true)
		"rings":                       # ◎ 종심 방어 — 겹으로 두른 원
			draw_arc(c, half, 0, TAU, 32, sil_col, 2.5, true)
			draw_arc(c, half * 0.5, 0, TAU, 24, sil_col, 2.5, true)
		"rake":                        # ⋰ 사격 전개 — 비껴 그은 사선 셋
			for k in 3:
				var ox := lerpf(-half, half, float(k) / 2.0)
				draw_line(c + Vector2(ox - 9, h), c + Vector2(ox + 9, -h), sil_col, 2.5, true)
		"barbs":                       # ▲▲▲ 축차 투입 — 위로 쌓은 화살촉
			for k in 3:
				var oy := lerpf(h, -h, float(k) / 2.0)
				var bw := half * (1.0 - 0.18 * k)
				_poly(sil_col, [c + Vector2(-bw, oy + 7), c + Vector2(0, oy - 7),
					c + Vector2(bw, oy + 7)])
		"bar":                         # ▬ 종렬 항진 — 한 줄
			draw_rect(Rect2(c.x - half, c.y - 4, spread, 8), sil_col)
		"star":                        # ✳ 팔진 — 여덟 갈래
			for k in 8:
				var a := float(k) / 8.0 * TAU
				draw_line(c, c + Vector2(cos(a), sin(a)) * half, sil_col, 2.5, true)


func _poly(col: Color, pts: Array) -> void:
	draw_polyline(PackedVector2Array(pts + [pts[0]]), col, 2.5, true)


func _dashed_rect(r: Rect2, col: Color) -> void:
	var dash := 6.0
	var corners := [r.position, r.position + Vector2(r.size.x, 0),
		r.position + r.size, r.position + Vector2(0, r.size.y)]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var seg := a.distance_to(b)
		var dir := (b - a).normalized()
		var t := 0.0
		while t < seg:
			draw_line(a + dir * t, a + dir * minf(t + dash, seg), col, 1.5)
			t += dash * 2.0
