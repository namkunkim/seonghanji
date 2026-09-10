# DEMO-RC-QA-03 — 적벽대전 단편 시나리오 전체 루프 독립 수용

> **최신 상태(2026-09-10 · `MGMT-HANDOVER-01`): 과거 구현 기준선 증거.** 선행 선택·수동 집결·기존 5페이즈 결과 루프는 최신 시나리오 계약에 의해 대체됐으며 새 완료 판정에 사용하지 않는다.

상위 Task: **DEMO-RC-LT-02 — 적벽대전 단편 시나리오 시작·분기·엔딩 플레이 루프**
상태: **자동 독립 수용 PASS (91/0) · Windows GPU GUI 대기**

## 1. 독립 판정 범위

이 수용은 제품 경로에서 다음 한 단편 루프만 판정한다.

```
새 적벽대전 데모 → 브리핑 → Event 03·04·06·07 선택
→ Event 09 조건 판정
  ├─ all true → pending → participant 도착 → active 5페이즈 → resolved 브리핑
  └─ 하나라도 false → DEC-01 조기 종료 브리핑
→ 홈 복귀 또는 새 데모 재시작 / 저장 뒤 이어하기
```

정본 기준은 `scenario-200-208.md` 208 ACT 1·3·4·5·7,
`endings.md` §5.2, `preproduction-scope.md` §5.1 DEC-01이다. 특히 적벽
미발생은 대체 대회전을 만들지 않고 마지막 선행 결과가 확정되는 전이에서 조기
종료하며, §5.2의 종료 시점 형 판정을 즉시 적용해야 한다.

이번 수용은 C-01, C-02, C-03~05 또는 전체 G-07의 완료 판정이 아니다. UI는
canonical Campaign 공개 API의 읽기 투영과 명령 발행만 할 수 있으며, battle snapshot,
private field, 승자·손실·사기·사건 결과의 직접 주입은 즉시 실패다.

## 2. 필수 자동 수용 매트릭스

| ID | 제품 경로·입력 | 독립 관찰 / 통과 기준 |
|---|---|---|
| QA03-01 | 새 데모를 시작한다 | 브리핑에는 시나리오 제목·시점·현재 명령 가능 진영·목표가 있고, 이전 데모의 선택·뉴스·전투·결과 화면이 없다. |
| QA03-02 | Event 03·04·06·07을 화면에서 각각 한 번 확정한다 | 선택은 공개 Campaign 명령 로그에만 기록된다. 같은 사건의 재클릭·뒤로 가기·UI 재구성은 모순 결과나 추가 명령을 만들지 않는다. 권장 선택은 자동 확정하지 않는다. |
| QA03-03 | 역사 경로의 정본 선택을 완료한다 | `cao_southward_complete`, `sun_quan_independent`, `liu_bei_hostile_to_cao`, `sun_liu_military_pact`, `yangtze_defense_line`가 모두 true이고 Event 09가 한 번만 파생된다. canonical pending 하나만 만들어진다. |
| QA03-04 | participant 도착 뒤 개전한다 | 기존 manifest 및 도착 공개 명령으로만 active phase 1이 된다. 개전 뉴스·인터럽트는 한 번이며 canonical battle ID만 전투 진입 경계에 전달한다. |
| QA03-05 | 기존 제품 UI에서 5페이즈를 결착까지 진행한다 | 기존 명령/AI 위임 계약이 유지된다. resolved 결과, 결과 적용, resolved news, 종료 브리핑은 각각 정확히 한 번이고 canonical 상태만 읽는다. |
| QA03-06 | Event 04 항복/불참 등 한 정본 비발생 선택을 완료한다 | 조건 결과가 어떤 조건이 false인지 설명한다. pending/manifest/active battle/대체 대회전이 없고 `DEC-01: 적벽 미발생` 조기 종료 브리핑으로만 간다. |
| QA03-07 | Event 03·04·06·07의 각 조건 false 사례를 끝까지 확정한다 | 미확정(unknown)은 종료가 아니며, 마지막 선행 사건 뒤에만 DEC-01이 한 번 난다. 군사협정 false + 장강 방어선 true 같은 모순 payload는 거부된다. |
| QA03-08 | 선택 중, active, resolved/ending에서 저장·복원한다 | 저장은 seed + player-origin command log로 재생된다. 현재 선택 단계·canonical battle·결과/ending 단계·digest가 복원되며 snapshot 소유 상태를 저장하지 않는다. |
| QA03-09 | 동일 seed·동일 선택 두 번, 다른 정본 선택 한 번을 실행한다 | 동일 조합의 command log 및 digest는 같다. 다른 선택은 로그/digest 또는 분기 결과가 다르다. |
| QA03-10 | unknown/display/오류 battle ID 및 resolved battle 진입을 요청한다 | 모두 거부된다. resolved 후 전술 입력도 거부되며 홈 복귀는 ending/resolved canonical 상태를 훼손하지 않는다. |
| QA03-11 | 종료 브리핑에서 홈 복귀 뒤 새 데모를 시작한다 | 홈에서는 종료 상태를 읽을 수 있으나 새 데모는 새 canonical Campaign으로 시작한다. 이전 news, battle, 선택, result 브리핑이 누출되지 않는다. |

## 3. 정확히 한 번 감사

아래 항목은 각 경로에서 배열 길이, command log, canonical records 및 UI 표시 상태를
교차 대조한다. 화면을 닫거나 다시 열어도 항목을 다시 발행해서는 안 된다.

| 사실 | 성공 경로 | DEC-01 경로 |
|---|---|---|
| 사건 선택 명령 | Event별 최초 확정 1회 | Event별 최초 확정 1회 |
| Event 09 / pending battle | Event 09 1회 / pending 1개 | 둘 다 0 |
| 개전 news / banner | 1 / 1 | 0 / 0 |
| active battle | canonical ID 1개 | 0 |
| resolved 적용 / news / ending briefing | 각 1회 | 0 / 0 / 해당 없음 |
| DEC-01 end reason / early ending briefing | 0 / 해당 없음 | 각 1회 |

`endings.md` §5.2.2에 따라 플레이어 세력 소멸은 사분면 판정 대신 Extinction이며,
그 외 조기 종료는 종료 시점의 일극형(통합) / 삼국·양강·북방형(병립) 및 천명 70 축을
재사용해야 한다. 새로운 엔딩 규칙이나 서사를 이 수용에서 허용하지 않는다.

## 4. 실행 예정

구현 통합 뒤 `tests/test_demo_rc_qa03_full_scenario_loop.gd`로 QA03-01~11을 공개
제품 경로에서 검증한다. 기존 집중 회귀도 함께 실행한다.

- `tests/test_demo_rc_01_playable_entry.gd`
- `tests/test_demo_rc_03_04.gd`
- `tests/test_demo_rc_qa01_e2e.gd`
- `tests/test_demo_rc_qa02_native_input.gd`
- `tests/test_g10_qa01_red_cliffs_entry_e2e.gd`
- `tests/test_a05_formation_combat.gd`
- `tests/run_save_restore.gd`
- `tests/run_campaign_replay.gd`
- `tests/run_tests.gd`

GUI 수용은 Windows 1600×900에서 브리핑, 사건 선택, 조건 설명, 전투 진입, 두 종료
브리핑, 홈/이어하기/재시작을 마우스 및 Tab/Shift+Tab/Enter/Space/Esc로 확인한다. GPU
캡처는 `out/`만 사용하고 커밋하지 않는다. Computer Use가 Windows 물리 SendInput을
제공하지 않으면 공개 입력 자동 검증 PASS와 사람 스모크 미검증을 분리 기록한다.

## 5. 실행 결과 — 자동 독립 수용

2026-09-09, Godot 4.7.2 headless에서
`tests/test_demo_rc_qa03_full_scenario_loop.gd`를 독립 실행했다.

| 항목 | 결과 |
|---|---|
| 신규 QA03 | **91 통과 / 0 실패 / exit 0** |
| 제품 브리핑 overlay → 마우스 동등 버튼 선택 → pending/active | PASS |
| 제품 새 데모 → 대체 선택 → DEC-01 → 홈 복귀, 이전 battle 누출 없음 | PASS |
| 역사 선택 → pending → manifest-derived voyage → active → 5페이즈 resolved | PASS |
| 대체 선택 → DEC-01 조기 종료, pending/대체 전투 없음 | PASS |
| 선택 단계·active·resolved/DEC-01 저장 재생 digest | PASS |
| 중복 queued 선택·deployment, invalid/display/resolved battle 입력 거부 | PASS |
| 동일 seed·동일 선택 command log/digest | PASS |

테스트는 `Main._start_red_cliff_demo()`와 실제 overlay Button `pressed` signal,
`Campaign.scenario_03`, `scn03_demo_progression`,
`issue_scn03_demo_choice`, `continue_red_cliff_scenario_demo`, 기존 공개 전투
명령과 저장 API만 사용했다. 진행 원장, battle snapshot, private field, 승자·손실·사기,
뉴스를 직접 쓰지 않았다. participant voyage도 UI가 fleet ID나 route를 제공하지 않고,
Campaign이 수락된 canonical manifest에서 일반 player-origin 이동 명령을 파생한다.

### 독립 감사 결론

현재 코어 범위에서는 DEC-01의 “대체 대회전 없음”과 Event 09/pending/news/result의
exactly-once 경계가 충족된다. resolved 재전술 입력은 거부되고 저장은 snapshot이 아닌
명령 로그 재생으로 digest를 검증한다.

제품 UI의 브리핑·선택·발생·DEC-01 홈 복귀·새 데모 누출은 headless 공개 Button signal로
검증했다. 그러나 **Windows 1600×900 GPU 화면, Tab/Shift+Tab/Enter/Space/Esc, 물리
마우스/키보드 검수는 아직 실행하지 않았다.** 따라서 이 문서는 GUI PASS를 주장하지
않는다. 실행 환경은 `user://logs` 쓰기와 Windows root certificate 읽기 경고를 출력했지만
QA03 assertion 결과와 exit code는 91/0, 0이었다.
