class_name FormationSpec
extends RefCounted

## 진형 도형 규격 — `screens.md` §3.2 · §8 미작성 「진형 도형 아이콘 규격」
##
## `data/formations.json` 7종을 읽어 **화면이 쓰는 형태**로 내놓는다.
## 정본 수치(계수·요구 통솔·전개 폭)는 그 파일이고, 이 클래스는 거기에
## **도형 한 벌**을 얹을 뿐이다. `ship-specs.md` §5.2 표와 어긋나면 JSON 이 맞다.
##
## ---------------------------------------------------------------- 왜 코어가 아니라 여기인가
##
## `Fleet.formation` 은 진형 **이름 하나**만 든다(검토 14 — 코어 레인). 계수는
## 전장 모델(`battle.gd`)이 읽을 값이고 아직 배선되지 않았다. 도형·전개 폭·색은
## 순수하게 화면의 것이므로 카탈로그를 `app/views/` 에 둔다. 레인 2(SC-F2)도
## 같은 카탈로그를 읽는다 — `plan` 처럼 코어로 올릴 필요가 생기면 그때 옮긴다.
##
## ---------------------------------------------------------------- 색각 이상 대응 (§8 미작성)
##
## **의미를 색 하나에만 싣지 않는다.** 함대 아이콘은 세 채널을 겹쳐 쓴다.
##
## | 채널 | 무엇을 | 부호 | 색에 의존하나 |
## |---|---|---|---|
## | ① 소유 관계 | 아군 / 적 / 동맹 | **테두리 도형** ▣ 채움 · ▢ 속 빔 · ▨ 반채움 | 아니오 |
## | ② 세력 정체 | 어느 세력인가 | 색조 + **행마다 적히는 세력명 라벨** | 색 + 글자 |
## | ③ 지시·진형 | 어느 대형인가 | **실루엣 + 전개 폭** (광폭은 넓게, 최협은 한 줄) | 아니오 |
##
## 붕괴 위험(사기 39↓)도 게이지 색 + 눈금 위치 + `⚠ 붕괴` 글자로 **세 겹**이다.

## 전개 폭 → 도형이 가로로 벌어지는 비율 (아이콘 폭 대비). §3.2
## 「광폭은 넓게, 최협은 한 줄로 그린다」를 눈금으로 옮긴 것.
const SPREAD := {
	"최협": 0.30,
	"협": 0.52,
	"중": 0.66,
	"광": 0.92,
	"가변": 0.74,
}

## 실루엣 종류. `_draw` 가 이 키로 분기한다. FRM-id 에 매단다 —
## 이름이 바뀌어도(팔진 ↔ 팔문금쇄진) 도형은 따라가지 않는다.
const SHAPE := {
	"FRM-01": "wedge",    # 어린진 — 중앙으로 파고드는 쐐기 두 짝 ◤◥
	"FRM-02": "arc",      # 학익진 — 양익을 벌린 활 ⌒
	"FRM-03": "rings",    # 방원진 — 겹으로 두른 원 ◎
	"FRM-04": "rake",     # 안행진 — 비껴 그은 사선 셋 ⋰
	"FRM-05": "barbs",    # 봉시진 — 위로 쌓은 화살촉 ▲▲▲
	"FRM-06": "bar",      # 장사진 — 종렬 한 줄 ▬
	"FRM-07": "star",     # 팔진 — 여덟 갈래 ✳
}

## 폴백 텍스트 글리프 (§3.2 도해에 적힌 것). 도형을 못 그리는 자리 —
## 하프 시트 한 줄 표기 등 — 에서 쓴다. 서체에 없을 수 있어 화면 본체는 벡터다.
const GLYPH := {
	"FRM-01": "◤◥", "FRM-02": "⌒", "FRM-03": "◎", "FRM-04": "⋰",
	"FRM-05": "▲▲▲", "FRM-06": "▬▬▬", "FRM-07": "✳",
}

const DEFAULT_NAME := "어린진"          # `Fleet.formation` 초기값 (§10.4 판정 3)

static var _rows: Array = []            # data/formations.json 원본, 1회 적재
static var _by_name: Dictionary = {}


static func _ensure() -> void:
	if not _rows.is_empty():
		return
	var f := FileAccess.open("res://data/formations.json", FileAccess.READ)
	if f == null:
		push_error("formations.json 을 열 수 없다")
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if not (parsed is Array):
		push_error("formations.json 이 배열이 아니다")
		return
	_rows = parsed
	for r in _rows:
		_by_name[String(r["name"])] = r


## 이름 순이 아니라 **JSON 순서**(어린→학익→…→팔). 선택 목록이 매번 같아야 한다.
static func all() -> Array:
	_ensure()
	return _rows


static func get_by_name(name: String) -> Dictionary:
	_ensure()
	return _by_name.get(name, _by_name.get(DEFAULT_NAME, {}))


static func required_command(name: String) -> int:
	var r := get_by_name(name)
	return int(r.get("required_command", 0)) if not r.is_empty() else 0


static func width_class(name: String) -> String:
	var r := get_by_name(name)
	return String(r.get("width", "중")) if not r.is_empty() else "중"


static func spread(name: String) -> float:
	return float(SPREAD.get(width_class(name), 0.6))


static func shape_of(name: String) -> String:
	var r := get_by_name(name)
	return String(SHAPE.get(String(r.get("id", "")), "wedge"))


static func glyph(name: String) -> String:
	var r := get_by_name(name)
	return String(GLYPH.get(String(r.get("id", "")), "?"))


static func directive(name: String) -> String:
	var r := get_by_name(name)
	return String(r.get("directive", "—")) if not r.is_empty() else "—"


## 지형이 이 진형을 허용하는가 (§3.3 · `ship-specs.md` §5.3).
##   terrain: "개활" | "기저" | "중회랑" | "대회랑"
static func allowed_in(name: String, terrain: String) -> bool:
	match terrain:
		"대회랑":
			return name == "장사진"
		"중회랑":
			return name in ["방원진", "봉시진", "장사진"]
		"기저":
			return width_class(name) != "광"          # 학익·안행 불가
		_:
			return true


## 지형 강제 사유 한 줄 (§3.3). 허용되면 빈 문자열.
static func terrain_note(name: String, terrain: String) -> String:
	if allowed_in(name, terrain):
		return ""
	match terrain:
		"대회랑":
			return "대회랑 — 장사진 강제 · 변경 불가"
		"중회랑":
			return "중회랑 — 방원 · 봉시 · 장사만"
		"기저":
			return "기저 항로 — 광폭 전개 불가"
		_:
			return "사용 불가"
