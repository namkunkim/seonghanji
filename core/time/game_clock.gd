class_name GameClock
extends RefCounted

## 고정 스텝 게임 시계 (DECISIONS.md V-25 ③ · V-28)
##
## 세계는 **틱 단위로만** 나아간다. 프레임률과 배속이 달라도
## 같은 명령 집합이면 같은 결과가 나와야 하기 때문이다.
##
##     누적 += 실제경과 × 배속
##     while 누적 >= 1틱:
##         advance_one_tick()
##         누적 -= 1틱
##
## ## 왜 1틱 = 실제 1분인가
##
## `time-and-monetization.md` §3 의 소요표가 **전부 분 단위로 쓰여 있다** —
## 고속항로 45분 · 관문 통과 68분 · 중회랑 135분 · 대회랑 225분 · 기저 항로 180분.
## **68분이 있으므로 15분 배수도 아니다.**
##
## 틱을 실제 1분에 맞추면 **소요표가 그대로 정수 틱이 된다. 반올림이 사라진다.**
## 실제 1시간 = 게임 1개월이므로 **60틱 = 게임 1개월**, 720틱 = 게임 1년으로도 정확히 떨어진다.
##
## 「일」 단위는 쓰지 않는다. 설계 문서 어디에도 없고(원전 기록도 연·월 단위다),
## 넣는 순간 45분이 22.5일이 되어 반올림 문제가 생긴다.
##
## **부동소수를 누적하지 않는다** (dev-requirements.md §2.3 결정론 요건).
## 프레임 델타를 받는 즉시 정수 밀리초로 바꾸고, 그 뒤로는 정수만 다룬다.
##
## 시계의 출처는 이 클래스가 모른다 (roadmap-solo.md §5.1).

## 1틱 = 실제 1분
const REAL_MS_PER_TICK: int = 60_000

## 실제 1시간 = 게임 내 1개월 (time-and-monetization.md §2.1)
const TICKS_PER_MONTH: int = 60
const TICKS_PER_YEAR: int = TICKS_PER_MONTH * 12

## 허용 배속. 상한은 미결 — roadmap-solo.md 검토 포인트 1
const SPEEDS: Array[int] = [1, 2, 4]

## 게임 내 경과 틱. 세이브에 그대로 들어간다 (schema/save.json 의 game_tick)
var tick: int = 0

## 아직 한 틱에 못 미친 나머지. 정수 밀리초.
var _remainder_ms: int = 0

var speed: int = 1:
	set(v):
		assert(v in SPEEDS, "허용되지 않은 배속: %d" % v)
		speed = v

## 일시정지. 「설정 중에도 시간이 흐른다」(V-25 ④)가 기본이므로 평소에는 false.
## 전투 개입 시점의 예외는 미결 — roadmap-solo.md 검토 포인트 7
var paused: bool = false


## 나머지만 누적하고 **넘어간 틱 수를 돌려준다. `tick` 은 건드리지 않는다.**
##
## 시계를 한 번에 밀어 올리면 안 되기 때문이다 — 세계를 진행시키는 쪽(`Sim`)이
## **틱을 하나씩 밟으며** `tick` 을 올려야 「지금 몇 틱인가」에 의존하는 처리
## (연 1회 정산 등)가 옳게 돈다.
##
## 2026-08-24: 이것을 뭉쳐 두었다가 11년치 연 정산이 **7,920번** 돌았다.
func take_ticks(elapsed_ms: int) -> int:
	assert(elapsed_ms >= 0, "시간은 거꾸로 흐르지 않는다")
	if paused or elapsed_ms == 0:
		return 0
	_remainder_ms += elapsed_ms * speed
	var ticks: int = _remainder_ms / REAL_MS_PER_TICK
	if ticks > 0:
		_remainder_ms -= ticks * REAL_MS_PER_TICK
	return ticks


## 시계만 쓰는 경우의 편의 함수. 세계를 진행시키지 않으므로
## **`Sim` 은 이것을 쓰지 않는다** — `take_ticks` + `step_ticks` 를 쓴다.
func advance(elapsed_ms: int) -> int:
	var n := take_ticks(elapsed_ms)
	tick += n
	return n


## 프레임 델타(초, float)를 정수 밀리초로 바꿔 넘긴다.
##
## **부동소수가 코어로 들어가는 유일한 문턱이며, 여기서 끊는다.**
## 내림으로 고정한다 — 반올림 방식이 바뀌면 결정론이 깨진다.
func from_delta(delta_sec: float) -> int:
	return advance(int(delta_sec * 1000.0))


## 재생 전용. dt 를 거치지 않고 틱씩 나아간다.
##
## 세이브가 「시드 + 명령 로그」이므로(V-25 ③ · schema/save.json),
## 재생은 프레임률과 무관하게 **틱 단위로만** 진행된다.
## 이것이 결정론의 실제 보장 지점이다 — 라이브 플레이의 dt 경로는
## 「언제 틱이 넘어가는가」만 바꾸고 「무슨 일이 일어나는가」는 바꾸지 않는다.
func step_ticks(n: int) -> int:
	assert(n >= 0)
	tick += n
	return n


## ---------------------------------------------------------------- 표시 단위
## 플레이어에게는 연·월만 보인다. 틱은 내부 눈금이다.

func months_elapsed() -> int:
	return tick / TICKS_PER_MONTH


func years_elapsed() -> int:
	return tick / TICKS_PER_YEAR


## 시나리오 시작 연도를 주면 현재 연·월을 돌려준다. 예) 208년 1월 → [208, 1]
func calendar(start_year: int) -> Array:
	var m: int = months_elapsed()
	return [start_year + m / 12, m % 12 + 1]


## ---------------------------------------------------------------- 소요 변환
## 소요표가 분 단위이므로 **변환이 항등에 가깝다.** 반올림이 없다.

static func minutes_to_ticks(minutes: int) -> int:
	return minutes


static func hours_to_ticks(hours: float) -> int:
	var m := hours * 60.0
	assert(absf(m - round(m)) < 0.0001, "소요는 분 단위로 떨어져야 한다: %f시간" % hours)
	return int(round(m))


static func months_to_ticks(months: float) -> int:
	var t := months * float(TICKS_PER_MONTH)
	assert(absf(t - round(t)) < 0.0001, "소요는 분 단위로 떨어져야 한다: %f개월" % months)
	return int(round(t))


func to_dict() -> Dictionary:
	return {"tick": tick, "remainder_ms": _remainder_ms, "speed": speed}


func from_dict(d: Dictionary) -> void:
	tick = int(d.get("tick", 0))
	_remainder_ms = int(d.get("remainder_ms", 0))
	speed = int(d.get("speed", 1))
