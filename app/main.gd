extends Control

## S3.2 게임 루프 + S3.3 성역 뷰의 **호스트**
##
## `roadmap-solo.md` S3.2 — 시뮬레이션 구동 · 배속 ×1/×2/×4 · 시각 표시.
## `screens.md` §1.2 — **시각 바는 L1·L2·L3·시트 전부의 최상단에 고정한다.**
## 그 소유가 여기다. 화면들은 참조만 한다.
##
## > **V-25 ④ — 모든 메뉴는 비차단이다. 설정하는 동안에도 세계가 움직인다.**
##
## `_process` 가 실제 델타를 코어에 넘기고, 코어는 **시계의 출처를 모른다**
## (`core/README.md`) — 단기는 게임 루프 델타로, 장기는 서버 벽시계로
## 같은 `Campaign.advance` 를 부른다.
##
## S3.3 부터 이 파일은 **루프와 배속만** 맡는다. 그리는 것은 `app/views/` 다.
## S3.4(SC-L3) · S3.5(명령 메뉴)는 성역 뷰의 형제로 붙는다.
##
## ⚠ **×1 은 게임 내 1분에 실제 1분이다** (`time-and-monetization.md` §2.1).
## 화면에서 확인하려면 아래 「검증 배속」을 쓴다.

const SCENARIO_START_YEAR: int = 208

## 정본 배속 (`GameClock.SPEEDS`)
const SPEEDS: Array[int] = [1, 2, 4]

## **검증 배속.** 한 판을 눈으로 보기 위한 것이고 출시 빌드에서는 끈다 —
## 시나리오 3 은 게임 내 3년(2,160틱 = 실제 36시간)이라 ×4 로도 9시간이다.
const DEBUG_SPEED: int = 1200

var campaign: Campaign
var data: GameData
var _speed_index: int = 2
var _debug_speed: bool = false
var _paused: bool = false

var _clock: Label
var _speed: Label
var _queue: Label
var _view: StarmapView


func _ready() -> void:
	theme = UiPalette.make_theme()
	data = GameData.load_all()
	campaign = Campaign.scenario_03(data, 20260828)
	campaign.world.player_faction = "손권"   # 단기판 기본 (roadmap-solo.md §1.2)

	_clock = $Root/TimeBar/Bar/Clock
	_speed = $Root/TimeBar/Bar/Speed
	_queue = $Root/TimeBar/Bar/Queue
	_wire_speed_buttons()

	_view = $Root/View
	_view.start_year = SCENARIO_START_YEAR
	# 플레이어 본거지 성역에서 연다. L1 성도(미구현)가 붙으면 그쪽이 넘겨준다.
	_view.setup(data, campaign, campaign.factions[campaign.world.player_faction].capital_system)
	_refresh_bar()


func _wire_speed_buttons() -> void:
	var bar: Node = $Root/TimeBar/Bar
	(bar.get_node("Pause") as Button).pressed.connect(_toggle_pause)
	for i in SPEEDS.size():
		var b := bar.get_node("S%d" % SPEEDS[i]) as Button
		b.pressed.connect(_set_speed.bind(i))
	(bar.get_node("SDebug") as Button).toggled.connect(func(on: bool):
		_debug_speed = on
		_refresh_bar())


func _set_speed(i: int) -> void:
	_speed_index = i
	_debug_speed = false
	($Root/TimeBar/Bar/SDebug as Button).button_pressed = false
	_refresh_bar()


func _toggle_pause() -> void:
	_paused = not _paused
	_refresh_bar()


## **실제 델타를 그대로 넘긴다.** 배속은 곱셈일 뿐이다 —
## 코어의 시계 눈금(1틱 = 실제 1분)은 배속과 무관하게 고정이다.
func _process(delta: float) -> void:
	if _paused or campaign == null or campaign.ended:
		return
	var mult := DEBUG_SPEED if _debug_speed else SPEEDS[_speed_index]
	if campaign.advance(int(delta * 1000.0) * mult) > 0:
		_refresh_bar()
		_view.refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not (event as InputEventKey).echo):
		return
	match (event as InputEventKey).keycode:
		KEY_SPACE:
			_toggle_pause()
		KEY_BRACKETLEFT:
			_set_speed(maxi(0, _speed_index - 1))
		KEY_BRACKETRIGHT:
			_set_speed(mini(SPEEDS.size() - 1, _speed_index + 1))


## 시각 바 (§1.2)
##
## ```
## 건안 십삼년 시월    ▶▶ ×2     대기 결정 3     ⚑ 2
## ```
##
## ⚠ **넷 중 둘이 코어에 없다.** 「대기 결정」은 결정 큐(`ui-design.md` §4.2)이고
## 「⚑」는 미확인 인터럽트(S3.7)인데 둘 다 아직 코드가 아니다.
## **0 으로 적지 않는다** — 0 은 「비었다」이지 「없다」가 아니다.
## 대신 코어에 실제로 있는 것을 적는다: **발행되어 아직 도달하지 않은 명령**(V-25 ④).
func _refresh_bar() -> void:
	var cal := campaign.world.clock.calendar(SCENARIO_START_YEAR)
	_clock.text = "%s %s" % [
		UiPalette.era_year(int(cal[0])), UiPalette.month_name(int(cal[1]))]
	var mult := DEBUG_SPEED if _debug_speed else SPEEDS[_speed_index]
	_speed.text = "%s ×%d" % ["■ 정지" if _paused else "▶▶", mult]
	_queue.text = "대기 결정 —(S3.5)    ⚑ —(S3.7)    발행 대기 %d" % \
		campaign.world.pending_commands.size()
	if campaign.ended:
		_queue.text += "    " + campaign.end_reason
