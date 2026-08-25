class_name Power
extends RefCounted

## 국력 산출 (region-power.md §3)
##
## **실효 국력 = Σ (권역 국력 지수 × 성계 전화 계수)**
##
## 이 산식은 추정이 아니다. `region-power.md` §3.2 의 문서값과 대조해 확인했다 —
## 유장 61.7/62 · 장로 10.8/11 · 사섭 12.3/12 · 공손강 6.6/7 · 마등한수 9.3/9.
##
## ⚠ **다만 큰 세력 셋은 문서값과 어긋난다** (조조 212.2/191 · 손권 44.2/30 ·
## 유종 31.4/28). 산식이 아니라 **문서의 요약표가 권역표에서 재계산되지 않은 것**으로
## 보인다. 상세와 파급은 `docs/07-production/data-model.md` §9.
##
## **데이터가 정본이므로 코드는 데이터에서 계산한다.** 문서값을 하드코딩하지 않는다.

## 시나리오 3 (208) 전화 계수 — region-power.md §3.1
## 성계 이름을 키로 쓴다. 성계 ID 는 데이터에서 얻는다.
const WAR_DAMAGE_208 := {
	"사예": 0.25, "옹주": 0.35, "회남": 0.30, "서주": 0.40, "연주": 0.45,
	"병주": 0.50, "청주": 0.50, "남양": 0.50, "예주": 0.55, "양주": 0.60,
	"기주": 0.70, "유주": 0.70, "형주": 0.85, "오회": 0.85, "한중": 0.90,
	"익주": 0.95, "교주": 0.95, "요동": 0.95, "남중": 0.95,
}

## 같은 표를 1/1000 정수로. 코어는 부동소수를 쓰지 않는다 (§2.3).
const WAR_DAMAGE_208_MILLI := {
	"사예": 250, "옹주": 350, "회남": 300, "서주": 400, "연주": 450,
	"병주": 500, "청주": 500, "남양": 500, "예주": 550, "양주": 600,
	"기주": 700, "유주": 700, "형주": 850, "오회": 850, "한중": 900,
	"익주": 950, "교주": 950, "요동": 950, "남중": 950,
}

## 동원율 (region-power.md §3.4-b)
const MOBILIZATION_BASE := 0.85
const MOBILIZATION_MIN := 0.20
const MOBILIZATION_MAX := 0.90

## 접경 부담 — 개방 접경과 회랑 접경은 6배 차이가 난다.
## 「회랑 하나에 소수를 두면 대군을 막는다」가 계수로 성립하는 지점 (§3.4-b ①)
const BORDER_OPEN := 0.030
const BORDER_CORRIDOR := 0.005


## 권역 하나의 실효 국력. 소수를 쓰지 않기 위해 **1/1000 단위 정수**로 돌려준다.
## 부동소수 금지 (dev-requirements.md §2.3).
static func region_effective_milli(data: GameData, rid: String,
		damage: Dictionary = WAR_DAMAGE_208) -> int:
	var base := data.region_power(rid)
	var sys_name := data.system_name(data.system_of(rid))
	var w: float = damage.get(sys_name, 1.0)
	return int(round(float(base) * w * 1000.0))


## 여러 권역의 실효 국력 합 (1/1000 단위 정수).
## **순회 순서를 고정한다** — 정렬된 배열로만 받는다.
static func total_effective_milli(data: GameData, region_ids: Array,
		damage: Dictionary = WAR_DAMAGE_208) -> int:
	var sorted_ids := region_ids.duplicate()
	sorted_ids.sort()
	var sum := 0
	for rid in sorted_ids:
		sum += region_effective_milli(data, rid, damage)
	return sum


## 표시용. 문서가 「약 191」처럼 정수로 적으므로 같은 눈금으로 돌려준다.
static func to_display(milli: int) -> int:
	return int(round(float(milli) / 1000.0))


## 접경 부담 — 개방 접경 수와 회랑 접경 수로 산출 (§3.4-b ①)
static func border_burden(open_borders: int, corridor_borders: int) -> float:
	return open_borders * BORDER_OPEN + corridor_borders * BORDER_CORRIDOR


## 동원율. 하한 0.20 · 상한 0.90 으로 자른다.
static func mobilization(open_borders: int, corridor_borders: int,
		newly_taken: float = 0.0, expedition: float = 0.0,
		governance: float = 0.0) -> float:
	var r := MOBILIZATION_BASE \
		- border_burden(open_borders, corridor_borders) \
		- newly_taken - expedition + governance
	return clampf(r, MOBILIZATION_MIN, MOBILIZATION_MAX)


## 실동원 = 실효 국력 × 동원율. 세계 상태 판정(V-27)의 입력이다.
static func mobilized(effective_milli: int, rate: float) -> int:
	return int(round(float(effective_milli) * rate / 1000.0))


## ---------------------------------------------------------------- 동원율 네 항
##
## §3.4-b  동원율 = 0.85 − 접경 부담 − 신복속 부담 − 원정 부담 + 통치 보정
##                 하한 0.20 · 상한 0.90

## ② 신복속 부담 (§3.4-b ②)
##
##     (Σ 신복속 권역 × 획득 방식 계수) ÷ 총 보유 권역 수 × 0.30
##     신복속 판정 = 획득 후 게임 내 3년 이내
##
## **토호 귀부 시스템이 여기서 두 번째 값을 한다** —
## 사자를 보내 귀부시킨 권역은 뺏은 권역보다 동원율을 덜 깎는다.
## 「정통 노선은 느리지만 싸게 확장한다」가 국력이 아니라 **실동원**에서 회수된다.
const ACQUIRE_WEIGHT := {
	"정복": 1000,      # 무력 정복 ×1.0 — 잔존 세력·반란 억제에 병력이 묶인다
	"항복": 600,       # ×0.6 — 기존 통치 조직이 남는다
	"귀부": 600,
	"협정": 300,       # ×0.3 — 합의된 이전. 저항 주체가 없다
}
const NEWLY_TAKEN_FACTOR_MILLI: int = 300


static func newly_taken_burden_milli(states: Dictionary, owned: Array,
		now_tick: int) -> int:
	if owned.is_empty():
		return 0
	var weighted := 0
	var sorted_ids := owned.duplicate()
	sorted_ids.sort()
	for rid in sorted_ids:
		var st: RegionState = states.get(rid)
		if st == null or not st.is_newly_taken(now_tick):
			continue
		weighted += int(ACQUIRE_WEIGHT.get(st.acquired_by, 1000))
	return weighted / owned.size() * NEWLY_TAKEN_FACTOR_MILLI / 1000


## ③ 원정 부담 (§3.4-b ③) — **거리를 시간이 아니라 성계 단계로 센다.**
## 회랑 소요는 이미 ①에 반영되어 있고, 여기서 재는 것은 **보급선의 길이**다.
static func expedition_burden_milli(hops: int) -> int:
	if hops <= 1:
		return 0            # 인접 성계
	if hops == 2:
		return 100
	if hops == 3:
		return 200
	return 300              # 4단계 이상


## ④ 통치 보정 (§3.4-b ④)
##
## **[F-32] 전횡이 동원율에 직접 들어간다.** 황호와 손침은 전투에 나오지 않지만
## 263년 촉·오의 실동원을 각각 5%씩 깎는다 — 「해임 곤란」이 수치로 아프다.
const GOVERNANCE := {
	"중앙집권": 50,        # +0.05 — 위 · 제갈량 치하 촉
	"표준": 0,             # 원소 등 명문 세력
	"호족연합": -50,       # 오 · 유표
	"군벌연합": -100,      # 마등·한수
	"전횡": -50,           # 황호 · 손침
	"암약": -250,          # 유장 — **확장 의사 자체가 없다**
}


static func governance_milli(kind: String) -> int:
	return int(GOVERNANCE.get(kind, 0))


## 네 항을 모두 반영한 동원율(1/1000).
##
## 유랑 세력은 특례다 — 접경·신복속을 적용하지 않고 상한 0.80 (§3.4-b ④).
static func mobilization_full_milli(open_borders: int, corridor_borders: int,
		newly_taken_milli: int, hops: int, governance: String,
		wandering: bool = false) -> int:
	if wandering:
		return 800
	var r := 850
	r -= open_borders * 30 + corridor_borders * 5
	r -= newly_taken_milli
	r -= expedition_burden_milli(hops)
	r += governance_milli(governance)
	return clampi(r, 200, 900)
