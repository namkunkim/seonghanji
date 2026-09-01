extends SceneTree

## 저장 복원 층 (V-61 ② — 시험 5층의 넷째) · **스텁**.
##
## 무엇을 잡을 층인가: 저장 전 세계와 재생 후 세계의 지문이 같은가
## (save-contract.md §4.2 인수 조건 7종).
##
## 왜 지금은 스텁인가: A-01(캠페인 저장 모델)·A-02(지문·변조 검증)가 서기
## 전이라 대상 API 가 없다. A-07 은 이 층의 **자리만** 만든다 —
## 5층 하네스에서 넷째 슬롯이 비어 보이지 않게, 그리고 A-02 가 채울 곳을
## 명시해 둔다. 케이스 구현은 A-02.
##
## 실행: godot --headless --path . --script tests/run_save_restore.gd
## 종료 코드: 스킵은 통과(0)로 끝난다 — 이 층이 아직 없다는 것은 회귀가 아니다.

const Harness := preload("res://tests/harness.gd")


func _init() -> void:
	print("저장 복원 층 — A-07 스텁")
	print("")
	print("  SKIP — 케이스 미구현")
	print("    선행: A-01 캠페인 저장 모델 · A-02 지문·변조 검증")
	print("    채울 곳: save-contract.md §4.2 인수 조건 7종")
	print("      1) 캠페인 지문(Campaign.digest())이 존재한다")
	print("      2) 저장 전 지문 = 순수 로그 재생 후 지문")
	print("      3) 경계 스냅숏에서 이어 재생해도 같은 지문")
	print("      4) 규칙 버전 불일치 시 로드 거부/승격 규약")
	print("      5) 명령 로그 부분 손상 = 직전까지 재생 + 고지")
	print("      6) 변조된 저장 = 지문 불일치로 검출")
	print("      7) 자동 저장(월 정산) 왕복 일치")
	print("")
	print("스킵 1 · 실패 0")
	quit(Harness.EXIT_PASS)
