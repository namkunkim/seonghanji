class_name Rng
extends RefCounted

## 결정론 난수 (dev-requirements.md §2.3)
##
## 요건이 넷이다.
##   ① 부동소수 금지          → 정수만 쓴다
##   ② 시드 기반 · 시드 저장   → 마스터 시드가 세이브에 들어간다 (schema/save.json)
##   ③ **난수 소비 순서 고정** → 아래가 이 문서의 본론이다
##   ④ 컬렉션 순회 순서 고정   → `GameData` 가 정렬된 ID 배열로만 돈다
##
## ## ③ 이 가장 어렵고, 그래서 구조로 푼다
##
## 난수기를 하나만 두면 **어디에든 소비를 하나 추가하는 순간 그 뒤 전부가 어긋난다.**
## 전투에 굴림 하나를 넣었더니 등용 결과가 바뀌는 식이다.
## 세이브가 「시드 + 명령 로그」인 이상(V-25 ③) 이것은 재생이 깨진다는 뜻이다.
##
## **두 층으로 막는다.**
##
##   1. **영역별 분리 스트림** — 전투 · 등용 · 이벤트 · AI 가 각자의 흐름을 갖는다.
##      전투에 굴림을 추가해도 등용은 그대로다.
##   2. **틱별 재유도** — 스트림은 (마스터 시드, 영역, 틱)에서 매번 새로 유도된다.
##      순서가 문제 되는 범위가 **한 영역의 한 틱 안**으로 좁아진다.
##
## 개체 단위 판정(어떤 인물의 등용 등)은 `roll_for()` 를 쓴다 —
## **키에서 직접 유도하므로 호출 순서가 아예 상관없다.**
##
## Godot 내장 난수기를 쓰지 않는다. 엔진 판올림으로 알고리즘이 바뀌면
## 예전 세이브의 재생이 깨지기 때문이다.

## 영역. 새 영역을 넣을 때는 **끝에 추가한다** — 값이 유도에 쓰이므로
## 중간에 끼우면 기존 세이브의 재생이 깨진다.
const DOMAIN_COMBAT := 1
const DOMAIN_RECRUIT := 2
const DOMAIN_EVENT := 3
const DOMAIN_AI := 4
const DOMAIN_INTERLUDE := 5

const MASK32 := 0xFFFFFFFF


## 논리 우측 시프트. GDScript 의 `>>` 는 산술 시프트라 음수에서 부호가 번진다.
static func _ushr(v: int, n: int) -> int:
	if n <= 0:
		return v
	if v >= 0:
		return v >> n
	return (v >> n) & ~(-1 << (64 - n))


## splitmix64 — 짧고 통계 특성이 좋으며 상태가 64비트뿐이다.
static func _mix(x: int) -> int:
	var z := x + -7046029254386353131      # 0x9E3779B97F4A7C15
	z = (z ^ _ushr(z, 30)) * -4658895280553007687
	z = (z ^ _ushr(z, 27)) * -7723592293110705685
	return z ^ _ushr(z, 31)


## (마스터 시드, 영역, 틱) → 스트림 시드
static func stream_seed(master: int, domain: int, tick: int) -> int:
	return _mix(_mix(master ^ (domain * 0x9E3779B1)) ^ tick)


## 그 영역·틱 전용 난수기를 만든다.
static func stream(master: int, domain: int, tick: int) -> RngStream:
	return RngStream.new(stream_seed(master, domain, tick))


## ---------------------------------------------------------------- 무순서 굴림
##
## **호출 순서와 무관하다.** 키가 같으면 항상 같은 값이 나온다.
## 인물·권역처럼 대상이 정해진 판정에 쓴다 — 등용 3중 판정이 대표적이다.
## `salt` 로 같은 대상의 여러 굴림을 구분한다 (0, 1, 2 …).
static func roll_for(master: int, domain: int, tick: int,
		key: String, salt: int = 0) -> int:
	var h := _mix(master ^ (domain * 0x9E3779B1))
	h = _mix(h ^ tick)
	h = _mix(h ^ _hash_string(key))
	h = _mix(h ^ salt)
	return _ushr(h, 33)                     # 31비트 양수


## 0~99. 확률 판정에 그대로 쓴다.
static func roll_pct_for(master: int, domain: int, tick: int,
		key: String, salt: int = 0) -> int:
	return roll_for(master, domain, tick, key, salt) % 100


## FNV-1a 64. 플랫폼과 무관하게 같은 문자열은 같은 값이 된다.
static func _hash_string(s: String) -> int:
	var h := -3750763034362895579           # 0xCBF29CE484222325
	for b in s.to_utf8_buffer():
		h = (h ^ b) * 1099511628211
	return h
