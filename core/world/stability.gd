class_name Stability
extends RefCounted

## 권역 안정도(Regional Stability) — 0~100 (function-events.md §0.3-④)
##
## **권역마다 하나씩. 신설 변수다** —
## 지금까지 문서에 「민심」·「안정도」라는 말만 있고 눈금이 없었다.
##
## 2026-08-25 배선.

const MIN: int = 0
const MAX: int = 100

## ---------------------------------------------------------------- 초기값
##
## **어떻게 얻었는가가 그 땅의 출발점을 정한다** —
## 동원율의 신복속 부담(§3.4-b ②)과 같은 사고다.
const INIT_STANDARD: int = 60
const INIT_SUBMISSION: int = 75      # 귀부·협정으로 획득 ([F-35])
const INIT_CONQUEST: int = 40        # 무력 정복 직후
const INIT_FRONTIER: int = 25        # 이민족·산월·남중 등 미평정 변경

## 평시 회복은 **초기값 + 20 이 상한**이다.
## 「원래 그랬던 것보다 더 좋아지지는 않는다」 — 전화 회복의 0.95 상한과 같은 형태다.
const RECOVER_PER_MONTH: int = 2
const RECOVER_CAP_MARGIN: int = 20

## ---------------------------------------------------------------- 매월 증감
const DELTA_ENCLAVE: int = -8        # 비지 상태 ([F-13])
const DELTA_TYRANNY: int = -10       # 「폭정」·수탈 정책 ([F-36])
const DELTA_DESPOT: int = -2         # 전횡 인물 집권 ([F-32])
const PACIFY_GAIN: int = 15          # 회유 성공 ([F-39])
const PACIFY_FLOOR: int = 50         # 회유 이후 영구 하한


static func initial_for(acquired_by: String) -> int:
	match acquired_by:
		"항복", "귀부", "협정":
			return INIT_SUBMISSION
		"정복":
			return INIT_CONQUEST
		"변경":
			return INIT_FRONTIER
	return INIT_STANDARD


## 한 달치 증감을 적용한다. 바뀐 양을 돌려준다.
static func tick(st: RegionState, enclave: bool = false,
		tyranny: bool = false, despot: bool = false) -> int:
	var before := st.stability
	var d := 0
	if enclave:
		d += DELTA_ENCLAVE
	if tyranny:
		d += DELTA_TYRANNY
	if despot:
		d += DELTA_DESPOT
	if d == 0:
		# **평시 회복.** 상한은 초기값 + 20
		var cap := mini(MAX, st.stability_initial + RECOVER_CAP_MARGIN)
		if st.stability < cap:
			d = mini(RECOVER_PER_MONTH, cap - st.stability)
	var floor_v: int = PACIFY_FLOOR if st.pacified else MIN
	st.stability = clampi(st.stability + d, floor_v, MAX)
	return st.stability - before


## ---------------------------------------------------------------- 할거 페널티
##
## §0.3-⑤. `star-map.md` §4.6 ① 이 「연속 N턴」으로만 두었던 N 을 확정한다.
##
## **이 게임에 턴은 없다.** 실시간이므로 **게임 내 개월**로 센다.
##
## > **12개월인 이유:** 시나리오 1회가 게임 내 10~15년이므로
## > 한 시나리오 안에 **열 번 이상 청구된다.**
## > 그리고 촉의 북벌 간격이 대체로 1~2년이었다 —
## > **「가만히 있으면 진다」가 원전의 출병 빈도와 같은 리듬으로 온다.**
const STAGNATION_MONTHS: int = 12
const STAGNATION_HEAVY_MONTHS: int = 24
const STAGNATION_MANDATE: int = -1
const STAGNATION_MANDATE_HEAVY: int = -2

## 면제 — 유랑 세력([F-40]) · 보유 권역 3개 이하 · 이민족 세력
##
## ⚠ **시나리오 3 에서는 여덟 중 여섯이 면제된다.**
## 조조(23)와 마등한수(5)만 걸리고 나머지는 전부 2~3권역이다.
## 이 규칙은 **시나리오 1(190)** 을 상정한 것으로 보인다 — 1~2권역 군웅이 다수인 판.
##
## **면제를 1 로 낮춰 재봤더니 지표가 한 자리도 변하지 않았다**
## (재현율 69% · 편차 2.0배 · 유장 최강 67회 — 전부 동일).
## 천명 −1/월 × 24개월 = −24 로 유장이 40 → 16 이 되어도
## **검각회랑이 「본거지 존속」을 보장한다.** 그것은 불가침 ② 의 의도된 결과다.
##
## **할거 페널티는 이 시나리오의 레버가 아니다.** 문서값 3 을 그대로 둔다.
const STAGNATION_EXEMPT_REGIONS: int = 3


## 이번 달 천명 감소분. 0 이면 발동하지 않은 것이다.
##
## **중단은 공세 개시 즉시**이며 **원정에 실패해도 정지한다** (§4.6 원문 유지) —
## 세어야 하는 것은 성과가 아니라 **의지**다.
static func stagnation_mandate_delta(months_idle: int, region_count: int,
		wandering: bool, foreign: bool = false) -> int:
	if wandering or foreign:
		return 0
	if region_count <= STAGNATION_EXEMPT_REGIONS:
		return 0
	if months_idle >= STAGNATION_HEAVY_MONTHS:
		return STAGNATION_MANDATE_HEAVY
	if months_idle >= STAGNATION_MONTHS:
		return STAGNATION_MANDATE
	return 0
