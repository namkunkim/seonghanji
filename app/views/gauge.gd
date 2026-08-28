class_name Gauge
extends Control

## 눈금 게이지. **정본은 `screens.md` §2.3 의 「눈금 정본」 표다.**
##
## > ⚠ **사기 게이지는 100 에서 끝나지 않는다.** 게이지 폭을 100 으로 그리면
## > 고양 구간(101~125)이 화면에서 잘린다. **전 게이지를 0~125 로 그리고
## > 100 위치에 눈금선 하나를 둔다** — 「100 은 상한이 아니라 보정 없음」이 보여야 한다.
##
## 그래서 `span` 과 `notch` 를 분리해서 받는다. 사기는 span 125 · notch 100 이고,
## 안정도는 span 100 · notch 0 이다.
##
## `screens.md` 검토 9 는 「125 를 전폭으로 잡으면 정상 구간이 좁아진다 —
## 눈금선만으로 충분한지 실기 확인 필요」로 열려 있다. **여기서 결정하지 않는다.**

var value: int = 0
var span: int = 100
var notch: int = 0
var danger_below: int = -1          # 이 값 이하면 붉게 (사기 39 = 붕괴 위험)
var bar_color: Color = UiPalette.ROUTE_FAST


func _init() -> void:
	custom_minimum_size = Vector2(180, 14)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_value(v: int, sp: int = 100, nt: int = 0, danger: int = -1) -> void:
	value = v
	span = maxi(sp, 1)
	notch = nt
	danger_below = danger
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(0, 0, w, h), UiPalette.PANEL_DIM)
	var col := bar_color
	if danger_below >= 0 and value <= danger_below:
		col = UiPalette.DANGER
	var f := clampf(float(value) / float(span), 0.0, 1.0)
	draw_rect(Rect2(0, 0, w * f, h), col)
	if notch > 0 and notch < span:
		var x := w * float(notch) / float(span)
		draw_line(Vector2(x, -2), Vector2(x, h + 2), UiPalette.TEXT, 1.5)
	draw_rect(Rect2(0, 0, w, h), UiPalette.LINE, false, 1.0)
