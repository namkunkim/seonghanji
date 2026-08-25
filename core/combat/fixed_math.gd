class_name FixedMath
extends RefCounted

## 결정론 정수 수학 (dev-requirements.md §2.3)
##
## **부동소수를 쓰지 않는다.** 기기별 부동소수 오차가 전투 결과를 뒤집기 때문이다.
## 손실률 산식이 √를, 열세 압박이 log₂ 를 쓰므로 둘을 정수로 구현한다.
##
## 모든 값은 **1/1000 단위**다.

## 정수 제곱근. 뉴턴법이며 같은 입력에 항상 같은 출력을 낸다.
static func isqrt(n: int) -> int:
	if n <= 0:
		return 0
	var x := n
	var y := (x + 1) / 2
	while y < x:
		x = y
		y = (x + n / x) / 2
	return x


## √(x/1000) 을 1/1000 단위로. 예) sqrt_milli(4000) = 2000 (√4 = 2)
static func sqrt_milli(x_milli: int) -> int:
	if x_milli <= 0:
		return 0
	return isqrt(x_milli * 1000)


## log₂(x/1000) 을 1/1000 단위로. 음수 결과도 낸다 (x < 1000 일 때).
##
## **반복 제곱으로 이진 소수를 뽑는다.** 부동소수도 표도 쓰지 않으며,
## 같은 입력에 항상 같은 출력을 낸다.
##   정수부: 2 로 나누며 세고
##   소수부: x 를 제곱해 2 를 넘는지로 비트를 하나씩 뽑는다
static func log2_milli(x_milli: int) -> int:
	if x_milli <= 0:
		return 0
	var x := x_milli
	var whole := 0
	while x >= 2000:
		x = x / 2
		whole += 1
	while x < 1000:
		x = x * 2
		whole -= 1
	# 이제 x 는 [1000, 2000). 소수부를 16비트까지 뽑는다.
	var frac := 0
	var bit := 500000                      # 0.5 를 1/1000000 단위로
	for _i in 16:
		x = x * x / 1000                   # 제곱
		if x >= 2000:
			x = x / 2
			frac += bit
		bit = bit / 2
	return whole * 1000 + frac / 1000
