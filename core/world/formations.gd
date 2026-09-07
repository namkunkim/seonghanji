class_name Formations
extends RefCounted

## 진형 규칙 — `data/formations.json` 7종 위의 판정 (A-03 · `DECISIONS.md` V-60)
##
## ## 왜 코어에 있나
##
## V-60 ①: **값은 한 소유 지점에서 파생한다.** `screens.md` §3.3 지형 강제·
## `ship-specs.md` §5.3 진형 허용·§4.5 하향 사슬이 화면 세 곳(`FormationSpec`·
## `FleetRecommend`·`DetailView`)에 흩어져 있었다. 규칙의 **정본은 core** —
## 화면은 이 클래스를 부르고, 코어(`Orders`)도 같은 것을 부른다.
##
## 도형·전개 폭·색은 순수하게 화면의 것이므로 `app/views/FormationSpec` 에
## 남는다. 이 클래스는 **수치와 허용 규칙**만 다룬다.
##
## 정본 값: `data/formations.json` (`id`·`name`·`width`·`coefficients`·
## `required_command`·`requires_trait`). 어긋나면 JSON 이 맞다.
##
## 순수 static · 파일 1회 적재. `GameData` 를 요구하지 않는다 —
## 화면의 정적 호출부(`FormationIcon` 등)가 데이터 핸들 없이 부르기 때문이다.

const DEFAULT_NAME: String = "어린진"       ## `Fleet.formation` 초기값 (§10.4 판정 3)
const DEFAULT_ID: String = "FRM-01"
const PALJIN_ID: String = "FRM-07"
const PALJIN_TRAIT: String = "신기묘산"

## JSON phase keys are deliberately kept here: data owns the values, while this
## core class owns the stable enum-to-data mapping used by combat.
const PHASE_KEYS: Array[String] = ["contact", "barrage", "engagement", "assault", "resolution"]
const MATCHUP_WINNER: Dictionary = {
	"FRM-02": "FRM-01", # 학익 → 어린
	"FRM-01": "FRM-03", # 어린 → 방원
	"FRM-03": "FRM-05", # 방원 → 봉시
	"FRM-05": "FRM-04", # 봉시 → 안행
	"FRM-04": "FRM-02", # 안행 → 학익
}

## §4.5 진형 하향 사슬 — 요구 통솔 미달이면 충족하는 가장 가까운 하위 진형으로.
##   학익 75 → 봉시 70 → 안행 65 → 어린 60 → 방원 55 → 장사 40
const DOWNGRADE_CHAIN: Array[String] = [
	"학익진", "봉시진", "안행진", "어린진", "방원진", "장사진",
]

static var _rows: Array = []
static var _by_name: Dictionary = {}
static var _by_id: Dictionary = {}


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
		_by_id[String(r["id"])] = r


## JSON 원본 행 배열. **이름 순이 아니라 파일 순서** — 선택 목록이 매번 같아야 한다.
static func rows() -> Array:
	_ensure()
	return _rows


## 진형 이름 전부 (파일 순서).
static func all_names() -> Array[String]:
	_ensure()
	var out: Array[String] = []
	for r in _rows:
		out.append(String(r["name"]))
	return out


static func exists(name: String) -> bool:
	_ensure()
	return _by_name.has(name)


## New combat/command APIs accept data IDs only.  Existing Fleet saves retain
## Korean names, so persistence boundaries use `id_for_name`/`name_for_id`.
static func exists_id(formation_id: String) -> bool:
	_ensure()
	return _by_id.has(formation_id)


static func id_for_name(name: String) -> String:
	_ensure()
	var row: Dictionary = _by_name.get(name, {})
	return String(row.get("id", ""))


static func name_for_id(formation_id: String) -> String:
	_ensure()
	var row: Dictionary = _by_id.get(formation_id, {})
	return String(row.get("name", ""))


## Strategic persistence accepts either a legacy Korean name or an explicit
## FRM ID, but never silently substitutes an unknown formation.
static func normalized_persisted_name(value: String) -> String:
	if exists_id(value):
		return name_for_id(value)
	if exists(value):
		return value
	return ""


static func _row(name: String) -> Dictionary:
	_ensure()
	return _by_name.get(name, _by_name.get(DEFAULT_NAME, {}))


static func required_command(name: String) -> int:
	var r := _row(name)
	return int(r.get("required_command", 0)) if not r.is_empty() else 0


## 전개 폭 등급 — "최협" | "협" | "중" | "광" | "가변".
static func width_class(name: String) -> String:
	var r := _row(name)
	return String(r.get("width", "중")) if not r.is_empty() else "중"


## 전용 특성 요구 (팔진 = "팔진 전용"). 없으면 빈 문자열.
static func requires_trait(name: String) -> String:
	var r := _row(name)
	var t = r.get("requires_trait") if not r.is_empty() else null
	return String(t) if t != null else ""


## 페이즈 계수 — 전투 배선(`A-05`)이 읽을 값. 여기서는 노출만 한다.
##   { contact, barrage, engagement, assault, resolution } · float
static func coefficients(name: String) -> Dictionary:
	var r := _row(name)
	var c = r.get("coefficients") if not r.is_empty() else null
	return c.duplicate() if c is Dictionary else {}


static func coefficient_milli(formation_id: String, phase: int) -> int:
	if not exists_id(formation_id) or phase < 0 or phase >= PHASE_KEYS.size():
		return 1000
	var row: Dictionary = _by_id[formation_id]
	var coefficients: Dictionary = row.get("coefficients", {})
	# JSON carries human-readable decimals; combat receives fixed-point integers.
	return roundi(float(coefficients.get(PHASE_KEYS[phase], 1.0)) * 1000.0)


static func has_paljin_trait(traits: Array) -> bool:
	for raw_trait in traits:
		var trait_text := String(raw_trait)
		# Character data stores descriptive trait strings such as
		# "「신기묘산」 전투 전 배치...".  The actual trait name is the
		# canonical token, not formations.json's display label.
		if trait_text == PALJIN_TRAIT or trait_text.begins_with("「%s」" % PALJIN_TRAIT):
			return true
	return false


## Shared, stateless formation-combat verdict.  IDs are mandatory here so new
## combat and command surfaces cannot accidentally use localized display text.
## A non-eligible 팔진 is safely neutral rather than being silently upgraded.
static func combat_verdict(formation_id: String, opposing_formation_id: String,
		phase: int, command: int, staff_traits: Array, terrain: String) -> Dictionary:
	var requested_valid := exists_id(formation_id)
	var forced := forced_formation(terrain)
	var effective_id := effective_formation_id(formation_id, command, staff_traits, terrain)
	var valid := effective_id != ""
	var allowed := valid and allowed_in(name_for_id(effective_id), terrain)
	var paljin_eligible := effective_id != PALJIN_ID \
		or (command >= required_command(name_for_id(PALJIN_ID)) and has_paljin_trait(staff_traits))
	var usable := valid and allowed and paljin_eligible
	var formation_milli := coefficient_milli(effective_id, phase) if usable else 1000
	var matchup_milli := matchup_modifier_milli(effective_id, opposing_formation_id, phase) if usable else 1000
	return {
		"valid": valid,
		"usable": usable,
		"requested_valid": requested_valid,
		"formation_id": effective_id,
		"formation_name": name_for_id(effective_id),
		"forced_formation_id": id_for_name(forced),
		"terrain_allowed": allowed,
		"paljin_eligible": paljin_eligible,
		"formation_milli": formation_milli,
		"matchup_milli": matchup_milli,
		"combat_milli": formation_milli * matchup_milli / 1000,
	}


## Initial/frozen formations never bypass command or terrain rules.  Terrain
## force wins; illegal/unknown requests safely fall back through the documented
## downgrade chain instead of remaining an invalid stored display value.
static func effective_formation_id(formation_id: String, command: int,
		staff_traits: Array, terrain: String) -> String:
	var forced := forced_formation(terrain)
	if forced != "":
		return id_for_name(forced)
	if not exists_id(formation_id):
		return id_for_name(downgrade(command, DEFAULT_NAME))
	var name := name_for_id(formation_id)
	if not allowed_in(name, terrain):
		return id_for_name(downgrade(command, name))
	if formation_id == PALJIN_ID and not (command >= required_command(name) and has_paljin_trait(staff_traits)):
		return id_for_name(downgrade(command, DEFAULT_NAME))
	if command < required_command(name):
		return id_for_name(downgrade(command, name))
	return formation_id


static func matchup_modifier_milli(formation_id: String, opposing_formation_id: String,
		phase: int) -> int:
	if phase != 2 or not exists_id(formation_id) or not exists_id(opposing_formation_id):
		return 1000
	if formation_id == PALJIN_ID or opposing_formation_id == PALJIN_ID:
		return 1000
	if formation_id == "FRM-06":
		return 900
	if MATCHUP_WINNER.get(formation_id, "") == opposing_formation_id:
		return 1200
	return 1000


## ---------------------------------------------------------------- 지형 강제 (§3.3 · ship-specs §5.3)
##
##   terrain: "개활" | "기저" | "중회랑" | "대회랑"
##
## | 지형 | 허용 |
## |---|---|
## | 개활 궤도 · 고속항로 | 전부 |
## | 기저 항로 | 광폭 제외 (학익·안행 불가) |
## | 중회랑 | 방원 · 봉시 · 장사 |
## | 대회랑 | **장사진 강제** |
static func allowed_in(name: String, terrain: String) -> bool:
	match terrain:
		"대회랑":
			return name == "장사진"
		"중회랑":
			return name in ["방원진", "봉시진", "장사진"]
		"기저":
			return width_class(name) != "광"
		_:
			return true


## 지형이 허용하는 진형 전부 (파일 순서).
static func allowed_list(terrain: String) -> Array[String]:
	var out: Array[String] = []
	for name in all_names():
		if allowed_in(name, terrain):
			out.append(name)
	return out


## 이 지형이 진형을 하나로 강제하면 그 이름, 아니면 빈 문자열.
## 대회랑만 강제한다 (장사진 · 변경 불가 · §3.3).
static func forced_formation(terrain: String) -> String:
	if terrain == "대회랑":
		return "장사진"
	return ""


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


## ---------------------------------------------------------------- 하향 사슬 (§4.5)
##
## 통솔이 `from_formation` 요구치에 못 미치면 충족하는 가장 가까운 하위 진형.
## 대회랑 장사진 강제는 이 함수를 부르지 않는다 (`forced_formation`).
static func downgrade(command: int, from_formation: String) -> String:
	var start := DOWNGRADE_CHAIN.find(from_formation)
	if start < 0:
		start = 0
	for i in range(start, DOWNGRADE_CHAIN.size()):
		var fm := DOWNGRADE_CHAIN[i]
		if command >= required_command(fm):
			return fm
	return "장사진"
