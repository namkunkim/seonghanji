class_name RngStream
extends RefCounted

## 한 영역·한 틱 전용 난수 흐름 (dev-requirements.md §2.3)
##
## **소비 순서가 문제 되는 범위가 여기 안으로 좁혀진다.**
## 이 스트림 안에서의 호출 순서는 고정해야 하지만,
## 다른 영역·다른 틱에는 영향을 주지 않는다.
##
## 소비 횟수를 세어 둔다 — 재생이 어긋났을 때 **어느 영역·틱에서 갈렸는지**
## 짚을 수 있어야 하기 때문이다.

var _state: int
var draws: int = 0


func _init(seed_value: int) -> void:
	_state = seed_value


func _next() -> int:
	draws += 1
	_state = _state + -7046029254386353131
	var z := _state
	z = (z ^ Rng._ushr(z, 30)) * -4658895280553007687
	z = (z ^ Rng._ushr(z, 27)) * -7723592293110705685
	return z ^ Rng._ushr(z, 31)


## 31비트 양수
func next_int() -> int:
	return Rng._ushr(_next(), 33)


## 0 이상 n 미만. n 이 0 이하면 0.
func below(n: int) -> int:
	if n <= 0:
		return 0
	return next_int() % n


## 0~99
func percent() -> int:
	return next_int() % 100


## 확률 pct(0~100)로 참. pct 가 0 이면 절대 참이 아니고, 100 이면 항상 참이다.
func chance(pct: int) -> bool:
	if pct <= 0:
		return false
	if pct >= 100:
		return true
	return percent() < pct


## lo 이상 hi 이하
func between(lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + below(hi - lo + 1)


## 배열을 결정론적으로 섞는다 (Fisher-Yates).
## **원본을 건드리지 않고 새 배열을 돌려준다.**
func shuffled(src: Array) -> Array:
	var a := src.duplicate()
	var i := a.size() - 1
	while i > 0:
		var j := below(i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t
		i -= 1
	return a
