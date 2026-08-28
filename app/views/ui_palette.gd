class_name UiPalette
extends RefCounted

## S3.3 화면 팔레트 · 서체 · 표기 보조
##
## `screens.md` §8 이 「색각 이상 대응 — 소유 세력 색과 진형 도형의 이중 부호화」를
## **미작성**으로 남겨 두었다. 그래서 **색에만 의미를 싣지 않는다** —
## 소유는 색과 함께 도형(● 아군 · ○ 타 세력 · ◌ 중립)으로도 적는다.

const BG          := Color("0e1116")
const PANEL       := Color("161b23")
const PANEL_HI    := Color("1e2634")
const PANEL_DIM   := Color("12161d")
const LINE        := Color("2b3441")
const TEXT        := Color("d9dfe8")
const TEXT_DIM    := Color("8a94a3")
const TEXT_FAINT  := Color("5d6675")
const ACCENT      := Color("d8b46a")     # ★ 주권역 · 강조
const FLASH       := Color("f0d79a")     # 값이 변했다 (§1.3)
const WARN        := Color("d9895c")
const DANGER      := Color("c8544a")
const ROUTE_BASE  := Color("55606f")     # 기저 항로 — 회색 실선
const ROUTE_FAST  := Color("5fb6bd")     # 고속항로 — 청록 실선
const ROUTE_COR   := Color("c2705c")     # 회랑·관문 — 이중선
const FLEET_OWN   := Color("8fc9e8")
const FLEET_FOE   := Color("c9a0a0")

## 세력 색. 시나리오 3 의 여덟 세력을 고정한다.
const FACTION_COLORS := {
	"조조": Color("6f8fd0"),
	"손권": Color("6fc08a"),
	"유종": Color("c9a05f"),
	"유장": Color("b07fc4"),
	"장로": Color("7fb5c4"),
	"마등한수": Color("c47f7f"),
	"사섭": Color("9fa86f"),
	"공손강": Color("8f8f9f"),
}

const NEUTRAL := Color("4b5462")


static func faction_color(fid: String) -> Color:
	if fid == "":
		return NEUTRAL
	if FACTION_COLORS.has(fid):
		return FACTION_COLORS[fid]
	# 정본에 없는 세력은 ID 해시로 고른다. **매번 같은 색이어야 한다**
	var h := 0
	for i in fid.length():
		h = (h * 31 + fid.unicode_at(i)) & 0xFFFFFF
	return Color.from_hsv(float(h % 360) / 360.0, 0.42, 0.72)


## 소유 표식. **색과 별개의 부호다** (screens.md §2.2)
static func owner_glyph(owner: String, viewer: String) -> String:
	if owner == "":
		return "◌"
	return "●" if owner == viewer else "○"


## ---------------------------------------------------------------- 서체
##
## Godot 기본 서체에는 한글 글리프가 없다. 화면 전체가 두부가 된다.
## 에셋 대장(`asset-ledger.md` FNT-001)이 **미판정**이므로 서체를 저장소에 넣지 않고
## 시스템 서체를 빌린다. 임베딩 라이선스 판정이 끝나면 여기만 바꾼다.
static func make_theme() -> Theme:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Malgun Gothic", "Noto Sans KR", "NanumGothic",
		"Apple SD Gothic Neo", "Sans-Serif"])
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	var t := Theme.new()
	t.default_font = f
	t.default_font_size = 19
	return t


## ---------------------------------------------------------------- 연호
##
## 시각 바는 연호로 적는다 (`screens.md` §1.2 — 「건안 십삼년 시월」).
## **시나리오 3(208~211)만 정본이 확정되어 있다.** 나머지는 연도로 적는다.
const MONTH_NAMES: Array[String] = [
	"정월", "이월", "삼월", "사월", "오월", "유월",
	"칠월", "팔월", "구월", "시월", "동짓달", "섣달",
]

const SINO: Array[String] = [
	"", "원", "이", "삼", "사", "오", "육", "칠", "팔", "구", "십",
	"십일", "십이", "십삼", "십사", "십오", "십육", "십칠", "십팔", "십구", "이십",
	"이십일", "이십이", "이십삼", "이십사", "이십오", "이십육", "이십칠", "이십팔",
	"이십구", "삼십",
]


## 서기 연 → 연호 표기. 건안은 196~220 이다.
static func era_year(year: int) -> String:
	if year >= 196 and year <= 220:
		var n := year - 195
		if n < SINO.size():
			return "건안 %s년" % SINO[n]
	return "%d년" % year


static func month_name(month: int) -> String:
	return MONTH_NAMES[clampi(month, 1, 12) - 1]


## 틱 → [연, 월]. `GameClock.calendar` 와 같은 셈이되 임의의 틱에 쓴다.
static func calendar_of(tick: int, start_year: int) -> Array:
	var m := tick / GameClock.TICKS_PER_MONTH
	return [start_year + m / 12, m % 12 + 1]


static func tick_label(tick: int, start_year: int) -> String:
	var c := calendar_of(tick, start_year)
	return "%s %s" % [era_year(int(c[0])), month_name(int(c[1]))]
