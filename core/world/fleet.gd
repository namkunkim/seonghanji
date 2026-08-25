class_name Fleet
extends RefCounted

## 함대 (combat.md §4.3.1 — 전대 40척 · 함대 200척)

var id: int = 0
var owner: String = ""

## 현재 성계. 이동 중이면 출발지
var at_system: String = ""

## 목적 권역. 없으면 주둔
var target_region: String = ""

## 도착 틱. -1 이면 이동 중이 아니다
var arrival_tick: int = -1

var ships: int = Battle.FLEET_SHIPS
var morale: int = Battle.MORALE_NOMINAL

## 지휘관 스탯 (없으면 평균)
var command: int = 50
var might: int = 50
var wits: int = 50


func is_moving() -> bool:
	return arrival_tick >= 0


func is_alive() -> bool:
	return ships > 0
