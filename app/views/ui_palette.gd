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
## Godot 기본 서체에는 한글 글리프가 없다(용량 때문에 CJK 제외). 시스템 서체를
## 빌리면 이 PC(맑은 고딕)에서는 보이지만 실기(안드로이드)에는 그 이름이 없어
## 폴백이 Roboto 까지 흘러 두부(□)가 된다. `DECISIONS.md` V-44 가 OFL 서체
## 임베딩으로 못박았고, `asset-ledger.md` FNT-001·002 가 그 실행이다.
##
## **Noto Sans KR 가변 폰트 1개**(`assets/fonts/NotoSansKR-VF.ttf`, OFL 1.1)를
## `wght` 축으로 나눠 쓴다 — 본문 400(FNT-001) · 제목 700(FNT-002). 파일은 하나다.
## 가변 폰트의 기본 인스턴스는 Thin(100)이라 굵기를 반드시 고정한다.
## 테마를 안 받는 Control 의 전역 폴백은 project.godot 가 `NotoSansKR-Regular.tres`
## (wght 400 고정)로 건다. 앱 화면은 아래 make_theme() 가 덮어쓴다.
const FONT_VF: FontFile = preload("res://assets/fonts/NotoSansKR-VF.ttf")

const FONT_SIZE_BODY  := 19
const FONT_WGHT_TITLE := 700   # FNT-002


## VF 파일을 특정 굵기로 고정한 자족. 화면은 이걸 직접 안 쓰고 테마로 받는다.
static func weighted_font(wght: int) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = FONT_VF
	fv.variation_opentype = {"wght": wght}
	return fv


## 기호 폴백. Noto Sans KR 는 한글은 전수 담지만 UI 가 쓰는 장식 기호
## 10종(▸ ⚔ ▬ ⚑ ⋰ ✳ ⌄ ✕ ⌃ ⇢)은 없다. **한글은 임베드 폰트가 결정하고**,
## 그 기호들만 시스템 서체로 흘린다 — Godot 기본 폴백과 같은 처리다.
## tests/verify_glyphs.gd 가 「한글 누락 0」은 경성 실패로, 기호 누락은 경고로 잡는다.
static func _symbol_fallback() -> SystemFont:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray([
		"Segoe UI Symbol", "Segoe UI Emoji",
		"Malgun Gothic", "Noto Sans CJK KR", "Noto Sans KR",
		"Apple SD Gothic Neo", "DejaVu Sans", "Sans-Serif"])
	return sf


## 앱 전역 테마. `app/main.gd` 가 루트 Control 에 한 번 걸면 15개 화면에
## 전부 내려간다 — 개별 화면에서 add_theme_font_override 를 흩뿌리지 않는다.
## 제목은 `theme_type_variation = "Title"` 로 옵트인한다(폰트 정의는 여기 한 곳).
static func make_theme() -> Theme:
	var fb: Array[Font] = [_symbol_fallback()]
	var body := weighted_font(400)                # FNT-001
	body.fallbacks = fb
	var title := weighted_font(FONT_WGHT_TITLE)   # FNT-002 — 같은 파일 wght 700
	title.fallbacks = fb

	var t := Theme.new()
	t.default_font = body
	t.default_font_size = FONT_SIZE_BODY

	t.add_type("Title")
	t.set_type_variation("Title", "Label")
	t.set_font("font", "Title", title)
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
