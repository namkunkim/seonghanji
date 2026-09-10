# SEONGHANJI — 적벽 개전·활성 전투·뉴스 기존 통합 기준선

> 상위: `PROJECT-TRACKER.md` D1 · `docs/07-production/preproduction-save-contract.md` (V-62) · `docs/07-production/preproduction-dev-gate.md` §8
> 작성일: 2026-09-06 · 갱신: 2026-09-07 · 상태: **부분 구현 검수 완료 — G-10 전체 완료 아님.**
> 범위: 시나리오 3 「적벽 전야」의 조건 판정부터 저장·복원·재생 가능한 지속 전투와 홈 표시까지의 경계. 이 문서는 규칙값이나 코드를 만들지 않는다.

> **최신 상태(2026-09-10 · `MGMT-HANDOVER-01`): 대체 계약 확정.** 이 문서의 pending→active,
> 뉴스, 홈 지도, 기존 phase 1~5 명령 내용은 현재 구현 이력과 통합 기준선으로 보존한다.
> 제품 목표와 충돌하는 부분은 `demo-rc-requirements-interview.md` 및 `demo-rc-01`~`05`가 대체한다.

## 0. 최신 적벽 데모 대체 경계

- 데모는 홈 지도와 선행 사건 진행을 필수로 하지 않고 역사적 전투 준비 상태에서 바로 시작한다.
- 플레이어는 유비군을 지휘한다. 손권군은 매 턴 수동 제어 여부를 묻고 조조군은 AI가 지휘한다.
- 기존 단일 `advance_phase`·전투 전체 `delegate_ai` 흐름은 전대·함대별 턴 명령으로 대체한다.
- 접적·포화·교전·강습·결착은 전투 전체의 순차 단계가 아니라 각 턴의 결정론적 판정 단계다.
- 매 턴 이동·전투 뒤 승리 조건을 검사하며 최대 20턴이다. phase 5에서만 승자를 정하는 기존 계약은 폐기한다.
- 결과 화면이 데모 종료점이며 홈 지도나 후속 캠페인으로 복귀하지 않는다.
- 2D 전술 지도와 정지 이미지·2D 효과만 사용하며 함선 3D 모델과 3D 시네마틱을 사용하지 않는다.
- 기존 구현·시험이 이 대체 경계를 충족한다는 의미는 아니다. 구현 승인 뒤 별도 Task에서 코어, UI, 저장, 시험을 정합화한다.

> 구현 기준선: `675347f`(조건 원장·DEC-01·pending battle), `7c7c6c5`(participant manifest·
> `pending → active`), `145dfbb`·`6efab57`(phase 1→2·resolved 결과 1회 적용), `c1e6de1`
> (전이 뉴스 exactly-once·HomeMap core projection). 2026-09-07 슬라이스는 `HomeMapSnapshot`
> 뉴스 투영·active phase 1 전용 1행 배너·canonical `battle_id` 진입 요청 신호를 추가했다.
> 시작 HEAD/`origin/main`은 `9452b6d2517b4ce8b973ff63dfcee76a030381bd`; 구현·디버깅과
> 읽기 전용 독립 감사는 `gpt-5.6-terra`가 수행했다. 신규 배너 시험은 50단언·실패 0,
> 기존 대상 회귀는 38/0·348/0·175/0·347/0·4/0이다. 전체 코어의 698/701·실패 2는
> 기존 A-07-E1 `user://` 저장 실패이며 이번 슬라이스 실패가 아니다. phase 3~5·실제 전투 화면·
> 일반 C-02 정책·expiry/default delegation은 아직 없다. Windows 1600×900의 기본
> `scenes/main.tscn` + `scripts/Main.gd` 경로에서 active phase 1의 배너 표시와 입력 경계는
> 2026-09-07에 별도 수용 검증했다.

## 1. 목표와 비목표

목표는 동일한 시드와 입력에서 다음 흐름을 결정론적으로 재현할 수 있게 하는 구현 계약이다.

```
208 개전 조건 판정 → 시나리오 사건 기록 → 활성 전투 전이 → 전이 뉴스
→ HomeMapSnapshot 읽기 전용 표시 → 전투 진행·종료 → 저장·복원·재생
```

비목표는 전투 수치·새 기능 이벤트 수치·새 화공 확률·태양계권 소유 규칙을 정하는 것, 화면·에셋·3D 구현, 그리고 현재 모든 즉시 전투를 지속형으로 교체하는 것이다. 이 계약은 적벽만 지속형으로 시작하는 안과 전체 전투를 일반화하는 안 중 하나를 확정하지 않는다.

## 2. 현재 구현과 결손

`Campaign.step()`은 도달 명령, 월 정산, 함대 도착, AI, 이벤트, 종료를 고정 순서로 처리한다. 일반 적대 권역 도착은 기존 `_resolve_battle()`의 즉시 전투를 유지한다. 적벽만 안정 ID `SCN-03-E09-RED-CLIFF-01`로 `pending`을 만들고 participant manifest의 필수 함대가 SYS-13에 모이면 `active` phase 1로 전이한다. 참가자 목록·역할·시작 tick은 전이 시 고정되고, 다음 tick에 phase 2로 결정론적으로 전이한다. phase 2의 canonical 승자 결과는 player command log에서 한 번만 적용되어 `resolved`가 된다. phase 3~5와 손실·점령을 포함한 결과 효과는 아직 없다 (`core/campaign.gd`, `core/combat/active_battle.gd`). `Battle`은 기존 일반 전투의 정수 산식 모듈이다 (`core/combat/battle.gd`).

캠페인 저장·재생은 시드, 플레이어 명령 로그, 목표 tick에서 재구성한다. pending/active/resolved 상태·manifest·phase 1/2·결과는 replay/digest 대상이며, manifest·phase·결과·중복 적용 변조 검출 시험도 통과했다. 전이 뉴스는 별도 저장 스냅숏이 아니라 재생에서 파생되며, 그 ID는 replay 후에도 같다. V-62의 원칙대로 파생 가능한 상태는 로그 재생으로 만들고, 스냅숏은 캐시이며 로그와 충돌하면 로그가 정본이다.

`HomeMapSnapshot`은 SCN-03의 적벽 조건을 `Campaign.scn03_progress`에서, canonical active battle과 exactly-once 전이 뉴스를 Campaign에서 투영한다. core 행은 canonical `battle_id`와 `campaign_core` provenance를 가지며 runtime fixture가 적벽 사실·뉴스·action identity를 주입하거나 덮어쓸 수 없다. SCN-03 뉴스 capability/provenance는 ledger가 비어도 원자적으로 `true`/`campaign_core`다. active phase 1 뉴스만 `severity`, headline/template, `open_active_battle`, canonical `action_battle_id`, core `can_open`, `acknowledged: false`, `expiry_kind: "unsupported"`를 가진 1행 배너 대상이다. `scripts/Main.gd` 기반 기본 홈 경로는 별도 `battle_entry_requested(battle_id)` 신호를 내며 host가 canonical/current active phase 1/entry availability를 재검증한다. `stage:5`는 카메라 포커스일 뿐 전투 명령 진입이 아니다. 미커밋 `app/main.gd`/`app/main.tscn` 별도 표면은 parse/setup 오류가 있는 실험 경로이므로 본 계약의 구현 대상으로 삼지 않는다.

## 3. 적벽 개전 조건의 정본과 미정값

개전의 직접 정본은 `scenario-200-208.md` §8 ACT 7 Event 09 [FIXED]이다.

```
조조 남하 완료
∧ 손권 독립 유지
∧ 유비 대조조 적대
∧ 손유 군사협정 성립
∧ 장강 방어선 형성
```

하나라도 어긋나면 적벽은 발생하지 않는다. F-09 설득 성공 또는 F-26 손권 불참·항복의 미발생 경로는 V-48/DEC-01에 따라 조기 종료 및 즉시 형 판정이며 대체 대회전은 만들지 않는다. 조조 101 대 손유 46(2.20배)은 `scenario-200-208.md` §7.2 및 V-37의 기준이며, F-19의 전력비·지형·계략 인물 조건은 **개전 조건이 아니라** 화공 같은 전투 내부 선택 조건이다. 화공 자동 성공으로 해석하지 않는다.

태양계권 궤도는 ACT 8 주력전의 장소이나 개전식의 추가 논리항이 아니다. 태양계권/구지의 소유, 무주 상태에서의 전장 접근, 각 전제를 코어 상태와 함대 도달 틱으로 증명하는 방법은 미정이다. `function-events.md` §8.1과 오래된 handover의 전력값은 V-37과 충돌할 수 있으므로 구현 입력으로 사용하지 않는다.

F-07·F-08·F-09·F-26은 연합·교섭·불참의 선행 사실을 제공하고 F-19는 전투 내부 선택을 제공한다. 적벽 전체를 대표하는 단일 F-01~F-40은 없다. 새 기능 이벤트 F-ID를 만들 근거도 아직 없다. 대신 시나리오 사건과 전투 인스턴스를 연결하는 안정적 scenario-scoped identity의 이름·형식과 Event 09/10 번호의 재사용 여부는 발주자 결정이다.

## 4. 사건·뉴스·활성 전투의 책임

| 대상 | 유일한 책임 | 해서는 안 되는 일 |
|---|---|---|
| 코어 시나리오 사건 | 개전 전제 평가와 그 결과의 안정적 원인 ID | UI 표시를 위해 미래 전투를 예약 표시 |
| 활성 전투 | 참가자·장소·페이즈·결과를 가진 저장/재생 가능한 게임 상태 | 뉴스 문안이나 UI 좌표를 정본화 |
| 뉴스 | 상태 전이에서 정확히 한 번 생성되는 불변 기록 | 전투 상태를 대체하거나 전투 사실을 역산 |
| HomeMapSnapshot/UI | 코어 투영을 읽고 표시·진입 요청 | 조건, 관측, 승패, 전력비, 배너 만료를 계산 |

## 5. 활성 전투 상태 전이

최소 전이는 다음과 같다.

```
전제 충족 → scenario_event 기록 → pending
pending 참가자·권역 재검증 → active(접적 페이즈)
active → 다음 페이즈 … → resolved(결과를 정확히 한 번 적용)
pending 재검증 실패 → invalidated
```

`pending`은 사건 틱과 실제 시작 틱을 분리할지의 발주자 결정에 따라 외부에 보이지 않을 수 있으나, 전이 이력에는 유지하는 편이 안전하다. `invalidated`는 시작 전 참가자 소멸·이동·소유권 변경으로 전제가 깨질 때만 쓴다. 활성 전투의 임의 취소/철수 규칙에는 정본 근거가 없으므로 `cancelled`는 도입하지 않는다. `resolved`와 `invalidated` 이력 보존 기간은 뉴스 보존 정책과 함께 결정한다.

## 6. 최소 데이터 구조와 ID 규칙

코어 소유 상태의 최소 필드는 다음이다.

```text
battle_id, scenario_id, origin_scenario_event_id
status, system_id, region_id, anchor_body_id
attacker { faction_id, fleet_ids[] }, defender { faction_id, fleet_ids[] }
created_tick, started_tick, resolved_tick, current_phase
observability_by_viewer
result (resolved에서만), news_transition_ids[]
```

참가 함대와 동맹 의무 참전 집합은 ID 정렬 후 고정한다. ID는 UI 입력 순서나 임의 증가값이 아니라 scenario·생성 tick·권역·정규화된 참가 함대처럼 재생 가능한 키 또는 그에 준하는 문서화된 안정 순번으로 만든다. 중복 개전을 막는 identity 규약도 같은 결정에 포함한다. 중간 페이즈를 틱에 나누면 현 전투의 RNG 소비 순서와 시점, 중간값의 보존/재생 방법을 명시해야 한다.

## 7. 저장·복원·지문·재생 계약

활성 전투가 시드·명령·tick에서 완전히 도출되면 파생 상태로 재생한다. 그렇지 않으면 A-01의 최소 포함 상태로 승격하되, 스냅숏은 로그보다 우선하지 않는다. `Campaign.digest()`에는 battle ID 순으로 상태·참가자·페이즈·필요 중간값과 전이 뉴스 ID를 포함한다.

전투 중 플레이어 선택·일시정지·전술 지시가 결과에 영향을 준다면 모두 `World.issue(..., origin="player")` 경로의 명령 로그에 남아야 한다. AI 명령은 기존 규약대로 재생 중 결정론적으로 재발행한다. 저장 손상, 규칙 세대 격리, 중간 전투 복원의 세부 정책은 A-02 인수 범위와 일치해야 하며, 정할 수 없으면 구현을 중단한다.

## 8. 관측·전쟁 안개 계약

관측은 결과를 바꾸지 않는 코어 판정이다. 코어는 viewer별 전투 공개 범위와 표시 가능한 참가자 요약만 투영한다. UI는 함대·세력·장소에서 적벽 공개 여부나 상세 전력을 추론하지 않는다. 관측 판정의 상세값은 기존 A-03/A-06 권위를 침범하지 않으며, `observability_by_viewer`는 이 계약에서 필요한 출력 경계만 정의한다.

## 9. HomeMapSnapshot 소비 계약

코어가 지원하면 `active_battles`, `red_cliff_conditions`, `news`를 같은 snapshot 생성 시점의 깊은 복사 읽기 모델로 제공하고 해당 capability를 `true`, provenance를 `campaign_core`로 원자적으로 전환한다. 지원 전에는 빈 배열과 unknown(조건 키 누락)을 유지하며 false를 미충족으로 바꾸지 않는다.

`active_battles[]`는 ID, scenario, status, location, phase, 관측 범위, 표시 안전 참가자 요약, 전투 진입 가능 여부와 route capability, 전이/news ID만 제공한다. `red_cliff_conditions`는 known true/false/unknown, 판정 tick, 근거 ID, 공개 범위를 제공한다. `news[]`는 immutable record ID, battle/event ID, transition, tick/date, severity, 문안 또는 템플릿 인자, action/route reference, acknowledged/expiry만 제공한다. 뉴스 본문은 battle에 중복 저장하지 않는다.

## 10. 뉴스 패널·C-02 배너·전투 진입 동선

지도는 `active` 상태의 anchor와 공개 범위만 표시한다. 뉴스 패널은 전이 기록만 렌더하며 정적 상태 행을 뉴스처럼 오인시키지 않는다. C-02 배너는 severity·expiry·action만 읽고 긴급성, 기본 위임, 만료 처리를 계산하지 않는다. 전투 진입은 `battle_id`와 코어 제공 `can_open`/route capability만 넘긴다. 현재 `stage:5`는 카메라 포커스이며 전투 명령 진입이 아니므로, 이를 전투 UI 완료 증거로 쓰지 않는다.

## 11. 의존성

| 항목 | G-10에 필요한 경계 |
|---|---|
| A-01 | 캠페인 저장·복원 모델과 active 상태/지문의 범위 |
| A-02 | 중간 저장, 변조, 손상, ruleset 격리의 인수 |
| A-03 | 모든 플레이어 전투 입력의 로그화와 관측의 코어 권위 |
| A-05 | 지속 전투가 진형을 결과에 쓸 경우의 전투 배선; 쓰지 않으면 그 예외를 명시 |
| C-01 | Windows PC 기준 화면·입력 수용의 선행 |
| C-02 | 배너의 기한·우선도·기본 위임 정책과 action 계약 |

`A-01`, `A-02`, `A-03`은 구현 후 검증 대기다. `A-05`, `C-01`은 선행 미완료다. 현재 구현은 적벽 전용 지속형의 상태 전이 경계만 열었으며 G-10 완료로 승격하지 않는다.

## 12. 단계별 구현 순서

1. ✅ 조건 원장·안정 ID·미발생 DEC-01·중복 방지 (`675347f`).
2. ✅ 전장 anchor·participant manifest·pending 재검증·`pending → active` phase 1 (`7c7c6c5`).
3. ✅ 결정론적 active phase 1→2와 resolved 결과 1회 적용을 최소 슬라이스로 구현했다 (`145dfbb`·`6efab57`).
4. ✅ phase 1·phase 2·resolved 상태의 저장·복원·재생·manifest/phase/result/reapply 변조 시험을 통과했다.
5. ✅ 뉴스 exactly-once 원장과 HomeMapSnapshot core projection을 연결했다 (`c1e6de1`).
6. ✅ 적벽 active phase 1 뉴스만 core snapshot → 1행 비차단 배너 → canonical `battle_id` 요청 신호로 연결했다. runtime canonical 주입은 차단했고, `stage:5`와 분리했다.
7. ✅ Windows 1600×900에서 canonical `SCN-03-E09-RED-CLIFF-01` active phase 1을 만들고,
   기본 `scenes/main.tscn` + `scripts/Main.gd` 경로의 한 행 배너를 수용 검증했다.
   `적벽 전투 개전` headline은 headline 노드 참조로 갱신하며, 42px 행·safe rectangle·
   `MOUSE_FILTER_IGNORE`·표시용 `전투 진입` action을 유지한다. `test_red_cliff_interrupt_banner.gd`
   는 50/0이며, Windows 캡처는 로컬 `out/**` 증적으로만 남기고 버전 관리하지 않는다.
8. 다음: expiry/default delegation·실제 전투 화면·일반 C-02 정책은 후속 범위다.

## 13. 검증 기준

- 단위: 다섯 전제, 중복 개전 방지, 참가자 정렬, 동맹 의무 참전, `pending` 무효화, 페이즈 전이, 뉴스 exactly-once.
- 통합: 같은 시드·입력에서 조건 → 사건 → active → 종료와 battle/news ID·결과가 같다. 기존 즉시 전투 회귀 또는 적벽 분기의 RNG 동등성을 확인한다.
- 저장: `pending`과 각 active phase에서 저장·복원 후 최종 지문이 무저장 실행과 같고, 상태/참가자/페이즈/뉴스 ID 1비트 변조는 검출된다.
- UI: fixture가 아닌 core capability/provenance, unknown 보존, 전쟁 안개 누출 없음, 다른 전투가 적벽 동선을 열지 않음, 뉴스 순서와 route 일치.
- 시각·입력: Windows 1600×900에서 G-10 범위의 canonical active phase 1 한 행 배너를 캡처하고,
  한글 headline·safe rectangle·비차단 입력·표시 action의 내부 ID 미노출을 확인했다.
  배너→결정→전투, 종료, 저장 복원 재생과 일반 C-02 정책은 이 슬라이스의 인수 기준이 아니다.

## 14. 실패 시 롤백 경계

코어 전이/저장 지문이 불일치하면 UI 배선을 시작하지 않는다. projection capability는 코어 사실과 같은 변경에서만 true로 올린다. UI 실패는 코어 상태를 되돌리지 않고 읽기 모델/표시 경계에서 분리한다. 구현 승인 뒤에도 적벽 전용 지속형과 전면 일반화의 선택은 별도, 좁은 변경으로 롤백 가능해야 하며 사용자 소유의 미커밋 홈 지도 변경을 수정·복원·정리하지 않는다.

## 15. 발주자 결정 필요

1. Event 09/10와 연결할 scenario-scoped identity의 정확한 ID 형식 및 소유자.
2. 적벽만 지속형으로 시작할지, 모든 전투를 일반화할지.
3. 다섯 전제를 어떤 코어 상태·공간·tick으로 증명할지와 태양계권 무주 상태의 전장 접근.
4. 사건 tick과 전투 시작 tick을 분리할지, `pending` 공개 여부와 `invalidated` 이력 보존.
5. 전투 중 플레이어 입력·일시정지·전술 선택의 범위와 명령 로그화.
6. active/resolved 상태와 전이 뉴스의 저장·손상 복구·규칙 세대 경계 정책.
7. C-02의 banner urgency/expiry/default delegation 정책 및 뉴스 서사 템플릿 소유자.

## 트래커 변경 제안 (미적용)

`PROJECT-TRACKER.md`는 현재 다른 세션의 수정이 있으므로 이 작업은 수정하지 않는다. 검수 후에만 다음 항목을 **설계/계약 준비**로 기록할 수 있다.

| ID | 작업 | 상태 | 권장 선행 | 권장 완료 기준 |
|---|---|---|---|---|
| G-10 | 적벽 개전·활성 전투·뉴스 수직 흐름 | 설계/계약 준비 | A-01, A-02, A-03, A-05, C-01 | 동일 시드·입력에서 조건 충족→사건·뉴스→활성 전투→홈 지도·배너→종료→저장·복원 후 동일 결과 |

## 근거

- `docs/04-campaign/scenario-200-208.md` §7.1–7.2, §8 ACT 2–9, §10
- `docs/04-campaign/function-events.md` §2 F-07–11, §3 F-19, §4 F-26, §8
- `docs/05-narrative/event-scripts.md` PART B, §7–9
- `docs/03-systems/combat.md` §4.3.3, §5.7, §10–13
- `docs/06-tech/screens.md` §1.4, §9.3, §10.6, §11
- `docs/06-tech/ui-design.md` §4.2–4.3, §7
- `docs/07-production/preproduction-save-contract.md` §2–4
- `docs/07-production/preproduction-dev-gate.md` §8
- `docs/DECISIONS.md` V-37, V-39, V-48, V-60–63
