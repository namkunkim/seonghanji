# DEMO-RC-LT-02 — 적벽대전 단편 시나리오 시작·분기·엔딩 플레이 루프

## 범위와 정본

이 단편은 `SCN-03`의 208년 정본 사건과 `endings.md` §5.2의 DEC-01만을
제품 흐름으로 연결한다. 전투 장식, 전체 9세력, C-01/C-02, 일반 G-07은 포함하지
않는다. 전투 결과·승패·battle snapshot·private field를 UI가 만들거나 주입하는
경로는 없다.

시작은 새 `Campaign.scenario_03(data, 20803)`이며, 홈의 **새 데모**는 반드시 이
새 인스턴스를 만든다. **이어하기**는 기존 Campaign 인스턴스 또는 검증된 저장의
재생 결과만 다시 표시한다. 두 경로 모두 runtime fixture나 이전 화면의 선택·전투
상태를 옮기지 않는다.

## 플레이 흐름

```
홈 적벽대전 데모
  → 시나리오 브리핑
  → Event 03 → Event 04 → Event 06 → Event 07 선택
  → Event 09 전제 판정
     ├─ 다섯 조건 충족 → pending → manifest/도착 → 기존 5페이즈 전투
     │                       → canonical resolved 결과 브리핑 → 홈
     └─ 하나라도 불충족 → DEC-01: 적벽 미발생 브리핑 → 홈
홈 → 이어하기 | 새 데모
```

각 사건 선택은 `Campaign.issue_scn03_event_outcome(event_id, outcome)`만으로
`origin="player"` 명령 로그에 기록한다. 해당 Event의 첫 선택만 허용하며, 아직
도착하지 않은 중복·상충 선택과 도착 후 재선택 모두 거부한다. 진행 원장은 명령이
도착한 reducer에서만 파생한다. 따라서 같은 seed와 같은 명령 순서는 같은 digest,
Event 09 상태, 종료 이유를 낸다.

선택 내용은 `scenario-200-208.md`의 사건 정의를 따른다.

| 사건 | 정본 선택 질문 | 적벽 전제에 남기는 결과 |
|---|---|---|
| Event 03 | 조조의 남하 | `cao_southward_complete` |
| Event 04 | 손권의 항복·동맹·독립·유비 연합 | `sun_quan_independent` |
| Event 06 | 유비의 외교 | `liu_bei_hostile_to_cao` |
| Event 07 | 손유 회담 | `sun_liu_military_pact`, `yangtze_defense_line` |

Event 09는 아래 결과가 **모두 도착해 true**일 때만 한 번 평가한다.

```
cao_southward_complete
∧ sun_quan_independent
∧ liu_bei_hostile_to_cao
∧ sun_liu_military_pact
∧ yangtze_defense_line
```

성공이면 canonical `SCN-03-E09-RED-CLIFF-01` pending 전투를 한 번 만든다.
데모 UI는 `Campaign.activate_scn03_red_cliff_demo()`로만 정본 최소 manifest와
구지 도착을 요청한다. Campaign이 선택한 두 함대와 명령을 normal reducer로
도달시킨 뒤에만 active phase 1이 되며, 기존 DEMO-RC-02/03의 5페이즈 명령 API가
계속 유일한 전투 입력이다. 하나라도
false이면 pending/active 전투를 만들지 않고 `DEC-01: 적벽 미발생`으로 즉시 종료한다.

## 엔딩과 홈 복귀

resolved 전투와 DEC-01은 Campaign의 canonical 상태·종료 이유·전이 뉴스만으로
브리핑한다. 같은 canonical 종료 사실은 UI refresh, 화면 재진입, 저장 복원에서
중복 브리핑하지 않는다. resolved battle은 전투 셸에 재진입할 수 없으며, 홈 복귀는
Campaign 상태를 수정하지 않는다.

저장은 선택 결과 원장이나 전투 snapshot을 정본으로 삼지 않는다. seed와 player
명령 로그를 재생해 active/pending/resolved 및 DEC-01을 다시 파생하고 digest로
검증한다.

## 수용 경계

- 발생 경로: 브리핑의 네 Event 선택 → Event 09 → active → 5페이즈 → canonical 결과 브리핑 → 홈.
- 미발생 경로: 완료된 전제 중 하나가 false → `DEC-01: 적벽 미발생` → 전투 없음 → 브리핑 → 홈.
- 동일 seed+선택, 저장/복원, pending 중복 클릭, 공개 activation의 active 도달·재호출 거부, resolved 재진입, 새 데모의 상태 누출을 자동 시험한다.
- 1600×900 Windows GPU에서는 브리핑·선택·발생/미발생 브리핑·홈의 마우스와 Tab/Enter 흐름을 검수한다. `out/` 캡처는 산출 증거일 뿐 커밋하지 않는다.
