extends Control

## S3.2 게임 루프 — **첫 화면이자 비차단 시간 모델의 실물**
##
## `roadmap-solo.md` S3.2 — 시뮬레이션 구동 · 배속 ×1/×2/×4 · 시각 표시.
##
## > **V-25 ④ — 모든 메뉴는 비차단이다. 설정하는 동안에도 세계가 움직인다.**
##
## 이 화면이 그것을 증명한다. `_process` 가 실제 델타를 코어에 넘기고,
## 코어는 **시계의 출처를 모른다** (`core/README.md`) —
## 단기는 게임 루프 델타로, 장기는 서버 벽시계로 같은 `Campaign.advance` 를 부른다.
##
## ⚠ **×1 은 게임 내 1분에 실제 1분이다** (`time-and-monetization.md` §2.1).
## 화면에서 확인하려면 ×4 로 두거나 아래 「검증 배속」을 쓴다.

const SCENARIO_START_YEAR: int = 208
const MONTH_NAMES: Array[String] = [
	"정월", "이월", "삼월", "사월", "오월", "유월",
	"칠월", "팔월", "구월", "시월", "동짓달", "섣달",
]

## **검증 배속.** 정본 배속(×1/×2/×4)과 별개로, 한 판을 눈으로 보기 위한 것이다.
## 시나리오 3 은 게임 내 3년(2,160틱 = 실제 36시간)이라 ×4 로도 9시간이다.
## 출시 빌드에서는 끈다 — `roadmap-solo.md` S3.2 의 배속은 1·2·4 뿐이다.
const DEBUG_SPEEDS: Array[int] = [1, 2, 4, 240, 1200]

var campaign: Campaign
var _speed_index: int = 2
var _paused: bool = false

@onready var _clock_label: Label = $Panel/VBox/Clock
@onready var _speed_label: Label = $Panel/VBox/Speed
@onready var _factions_label: RichTextLabel = $Panel/VBox/Factions
@onready var _log_label: RichTextLabel = $Panel/VBox/Log


func _ready() -> void:
	var data := GameData.load_all()
	campaign = Campaign.scenario_03(data, 20260828)
	campaign.world.player_faction = "손권"   # 단기판 기본 (roadmap-solo.md §1.2)
	_refresh()


func _process(delta: float) -> void:
	if _paused or campaign == null or campaign.ended:
		return
	# **실제 델타를 그대로 넘긴다.** 배속은 곱셈일 뿐이다 —
	# 코어의 시계 눈금(1틱 = 실제 1분)은 배속과 무관하게 고정이다.
	var ms := int(delta * 1000.0) * DEBUG_SPEEDS[_speed_index]
	if campaign.advance(ms) > 0:
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_SPACE:
			_paused = not _paused
			_refresh()
		KEY_BRACKETLEFT:
			_speed_index = maxi(0, _speed_index - 1)
			_refresh()
		KEY_BRACKETRIGHT:
			_speed_index = mini(DEBUG_SPEEDS.size() - 1, _speed_index + 1)
			_refresh()


func _refresh() -> void:
	var cal := campaign.world.clock.calendar(SCENARIO_START_YEAR)
	_clock_label.text = "%d년 %s   (%d틱)" % [
		cal[0], MONTH_NAMES[int(cal[1]) - 1], campaign.world.clock.tick]
	_speed_label.text = "배속 ×%d   %s        [SPACE] 정지 · [ ] 배속" % [
		DEBUG_SPEEDS[_speed_index], "■ 정지" if _paused else "▶ 진행"]
	_factions_label.text = _faction_table()
	_log_label.text = _status_line()


## 세력 요약. **플레이어 세력을 먼저 둔다.**
func _faction_table() -> String:
	var mobs := campaign.mobilized_all()
	var out := "[table=6][cell]세력[/cell][cell]권역[/cell][cell]실동원[/cell]"
	out += "[cell]천명[/cell][cell]패권[/cell][cell]자금[/cell]"
	for fid in campaign.faction_ids:
		var f: Faction = campaign.factions[fid]
		if not f.alive:
			continue
		var mark := "▸ " if fid == campaign.world.player_faction else ""
		out += "[cell]%s%s[/cell][cell]%d[/cell][cell]%d[/cell]" % [
			mark, fid, f.regions.size(), int(mobs.get(fid, 0))]
		out += "[cell]%d %s[/cell][cell]%d %s[/cell][cell]%s[/cell]" % [
			f.mandate, Mandate.band(f.mandate),
			f.hegemony, Hegemony.band(f.hegemony), _thousands(f.treasury)]
	return out + "[/table]"


func _status_line() -> String:
	var fired := 0
	for k in campaign.events_fired:
		fired += int(campaign.events_fired[k])
	return "전투 %d · 점령 %d · 함대 %d · 이벤트 %d종 %d회   %s" % [
		campaign.battles, campaign.captures, _alive_fleets(),
		campaign.events_fired.size(), fired,
		("[color=#c88]" + campaign.end_reason + "[/color]") if campaign.ended else ""]


func _alive_fleets() -> int:
	var n := 0
	for fl in campaign.fleets:
		if fl.is_alive():
			n += 1
	return n


static func _thousands(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if v < 0 else "") + out
