# HANDOVER — SEONGHANJI: MANDATE

> **2026-09-12 DEMO-RC-G6-03 — 자동 보급 영역·한 턴 정박·처리량·결정론적 우선순위 — PASS:** 보급함/강습모함/세력 거점의 자동 영역과 유비·손권 상호 보급을 구현했다. 고속정은 이동 후 자동 등록되며 target/provider 모두 실제 이동거리 0으로 한 턴 정박해야 완료한다. 이동·이탈·source 변경/비가동은 진행을 중단하고 재진입 턴을 다시 기록한다. 처리량 순위는 raw 남은 연료, 진입 턴, stable ID 순이다. 보급은 사격 소모 뒤 연료와 실제 G4 finite ammo/special만 capacity까지 복원하고 energy/heat와 현재 턴 사격 receipt는 유지해 다음 턴부터 사용한다. 독립 QA에서 abstract ammo 표시와 실제 자원 불일치, out-and-back 정박, source 입력순서 의존을 교정했다. 최종 시험은 core 53/0, UI 39/0, GPU 41/0, 관련 회귀 679/0이다. 캡처는 `out/demo-rc-g6-03-fast-craft-supply/fast-craft-supply-1600x900.png`, SHA-256 `E2A023DC60C289C8ACA17E238FCB74F178583B0485784EB5F16B63C7BFE0B0B7`; `out/`은 커밋하지 않는다. 라벨 밀도와 rules 엄격 검증은 P2다. 다음은 **DEMO-RC-G6-04 — 비상 귀환 기준·목적지 재탐색·조기 귀환·UI 경고**다.

> **2026-09-12 DEMO-RC-G6-02 — 전술 임무 상시 변경과 판정 중 변경의 다음 턴 적용 — PASS:** immutable 장비와 active/draft/next-turn 전술 임무를 분리했다. 요격 장비는 요격/호위, 뇌격은 뇌격/기습, 정찰은 정찰/연락, 구조는 구조/연락만 선택한다. 명령 단계는 제출 전 재선택을 허용하고 제출 시 active를 원자 적용한다. 판정 중 요청은 다음 턴 queue로 보내 현재 결과를 유지하고 다음 command/AI draft 전에 1회 승격하며, 20턴 예약은 거부한다. AI도 같은 validator 경로를 사용한다. 독립 QA에서 mutation requester 검증과 전역 단조 event serial을 추가해 교차 세력 조작과 최신 이벤트 오표시를 막았다. 최종 시험은 core 154/0, UI 53/0, GPU 55/0, 추가 회귀 포함 headless 1021/0이다. 캡처는 `out/demo-rc-g6-02-fast-craft-mission/fast-craft-mission-1600x900.png`, SHA-256 `8851E16897F671635F26A82009D0D15F726523A1BD18B14AC6111C66AB910CEA`; `out/`은 커밋하지 않는다. 일반 저장 시험은 sandbox `user://` 권한으로 실행되지 않았으나 primitive snapshot 계약은 집중 시험에서 통과했다. 다음은 **DEMO-RC-G6-03 — 자동 보급 영역·한 턴 정박·처리량·결정론적 우선순위**다.

> **2026-09-11 DEMO-RC-G3-03R — 지휘 한도 초과 명중·진형 변경 불이익 실제 적용 — PASS:** 과거 G3-03에서 계산·표시만 하던 명중/진형 변경 penalty를 전투에 연결했다. 변경한 턴의 새 진형 효과는 초과 tier별 92/84/76/68%이고 다음 유지 턴은 100%로 복귀한다. 실제·추정 사격은 모두 후속 명중 입력에 96/92/88/84%를 기록하고, 자원 비용·소모량은 기존 G4-06 권위를 그대로 사용한다. 수동·AI 공통이며 자기 전대/자기 사격에만 수치를 공개하고 hit·damage·casualties·winner는 pending이다. 독립 QA 중 신규 고속정 위치 fixture 누락으로 발생하던 UI SCRIPT ERROR 위음성 2건과 실제 실패 1건을 교정했다. 최종 시험은 core 60/0, UI 37/0, GPU 39/0, 영향 회귀 23개 합계 1523/0이다. 캡처는 `out/demo-rc-g3-03r-command-penalty/command-penalty-1600x900.png`, SHA-256 `8EF64F4038EBC5567BA336B854DFDB29CDCF12E088F868CDADA8BF728605E9F1`; `out/`은 커밋하지 않는다. SceneTree harness의 SCRIPT ERROR 자동 실패 집계는 P2다. 다음은 **DEMO-RC-G6-02 — 전술 임무 상시 변경과 판정 중 변경의 다음 턴 적용**이다.

> **2026-09-11 DEMO-RC-G6-01 — 고속정 전대와 요격·뇌격·정찰·구조 임무 장비·코스트 — PASS:** 유비 기본 편성에 조운의 순수 고속정 전대 `RC-LIU-FC-01` 6척/정찰/코스트 18을 추가하고 실제 이동·명령·진형·무기·자원·탐지·원장에 참여시켰다. 고속정은 요격함과 별도 범주이며 4장비의 선체+장비 비용, 재고, 비용 초과를 데모 전용 rules에서 관리한다. 준비 UI는 여러 전대 선택·생성·해체, 혼성 고속정 분리·이전, 독립/동일 세력 함대 편입, 독립정/모함/거점 기반 metadata를 제공한다. 역사본·적용본·초안을 분리해 재진입과 부모/자식 동기화가 오래된 전체 setup을 덮지 않으며 active battle loadout은 불변이다. 독립 QA 최종은 core 124/0, UI 55/0, 집중 headless 합계 913/0, GPU 57/0이다. 캡처는 `out/demo-rc-g6-01-fast-craft/fast-craft-formation-1600x900.png`, SHA-256 `C8B884771C88E3423453E6508ACD84A60BAEDBC473319F7449490963D22D9189`; `out/`은 커밋하지 않는다. 실제 모함/거점 운용은 G6-03 이후, 전투 중 임무 변경은 G6-02다. 초과 비용의 명중·진형 변경 소비가 빠진 과거 G3-03 범위는 **DEMO-RC-G3-03R — 지휘 한도 초과 명중·진형 변경 불이익 실제 적용**으로 먼저 닫는다.

> **2026-09-11 DEMO-RC-G5-06 — 연쇄 폭발 작전 조건·방해·발동 — PASS:** 유비가 직접 호출하는 별도 연합 특수작전 자산에 6조건 준비도와 `idle → staged → disrupted | triggered` 상태를 추가했다. resolve 때 실제 이동·진형·탐지·자원 판정 뒤 조건을 다시 검사하며, 방해 뒤 다음 유비 명령 턴 재시도와 trigger 뒤 불가역·중복 금지를 보장한다. 조조 AI의 분산·요격 차폐·탐지 교란·거리 이탈은 자기 viewer 정보로만 결정한다. 독립 QA에서 AI intent만으로 발생하던 무료 방해를 없애고, 자원 gate를 통과한 `shot_authorized` 요격만 인정했으며, 유비 viewer에 적 formation/stable squadron/blocking event ID가 재노출되지 않도록 정화했다. 발동 결과는 실제 피해나 승패를 만들지 않고 effect intent와 pending 계약으로 넘긴다. 최종 시험은 core 70/0, UI 48/0, GPU 50/0과 G5-05~G2 관련 회귀 27개가 exit 0이다. 캡처는 `out/demo-rc-g5-06-chain-explosion/chain-explosion-1600x900.png`, SHA-256 `F614EA1C2943898A31CCD4189ADD4AFF141D2A9097B1B84157998340C33B275E`; `out/`은 커밋하지 않는다. 실제 효과 적용은 신규 **DEMO-RC-G8-00 — 전투 피해·사기·센서·지형 효과 적용**에서 승패 판정 전에 닫는다. 다음은 **DEMO-RC-G6-01 — 고속정 전대와 요격·뇌격·정찰·구조 임무 장비·코스트**다.

> **2026-09-11 DEMO-RC-G5-05 — 조조·손권 AI 동일 규칙·제한 자원 운용 — PASS:** AI planner는 자기 viewer 접촉·자원 preview와 공개 지형만 받아 손권 방어형·조조 압박형 명령을 JSON posture로 생성한다. 확인 접촉은 공개 좌표만, 추정 접촉은 sealed last-known만 사용하며 숨은 적을 추가하거나 실제 위치를 바꿔도 AI 결과가 변하지 않는다. 이동·진형·무기·추정 사격·자원은 수동과 동일 resolver를 통과하고 부족 시 대체 무기 없이 억제한다. 독립 QA에서 faction ID 하드코딩을 제거해 세력 차이가 profile에만 남도록 했다. UI는 current own viewer의 AI 근거만 표시하고 foreign plan·target·resource는 숨긴다. 최종 시험은 core 57/0, UI 28/0과 G5-04~G2 회귀가 exit 0이며 구현 GPU 30/0이다. 캡처는 `out/demo-rc-g5-05-ai-parity/ai-parity-1600x900.png`, SHA-256 `75B8B107C216D75B9A1AF147CFAA6A0F087F73ED7A60687D8AD578EB1BDAB6DE`; `out/`은 커밋하지 않는다. AI rules 엄격 검증·다전대 intent 필터·라벨 충돌은 P2다. 다음은 **DEMO-RC-G5-06 — 연쇄 폭발 작전 조건·방해·발동**이다.

> **2026-09-11 DEMO-RC-G5-04 — 손권 제어 문의 계약 재검증 — PASS:** 기본 매턴 문의, 수동 손권, 이번 턴만 AI, AI 고정과 설정 재활성화를 G5 전체 명령으로 통합 검증했다. prompt policy는 현재 턴 snapshot과 다음 턴 예약값을 분리해 설정 변경이 현재 수동 초안이나 이미 시작된 판정을 되돌리지 않는다. direct phase마다 HOLD·현재 진형/무기·빈 추정 사격의 새 전체 초안을 만들고 유비/손권/턴 간 변조를 격리한다. AI는 동일 이동·탐지·지형·무기·자원·원장 pipeline을 사용한다. UI는 중앙 modal·3개 선택지·순환 focus·배경 포인터 차단을 제공한다. 최종 독립 시험은 core 180/0, UI 46/0과 G5-03~G2 회귀가 exit 0이며 구현 GPU 48/0이다. 캡처는 `out/demo-rc-g5-04-sun-control-contract/sun-control-contract-1600x900.png`, SHA-256 `7A5E041538158D13DB185283BB32C69318CBA7EE107FC701B0C1EA1EF6CD3F9E`; `out/`은 커밋하지 않는다. 물리 Shift-Tab·스크린리더·고DPI는 P2다. 다음은 **DEMO-RC-G5-05 — 조조·손권 AI 동일 규칙·제한 자원 운용**이다.

> **2026-09-11 DEMO-RC-G5-03 — 전장 지형의 이동·탐지·무기 효과 — PASS:** 성운·잔해대·행성 그림자 2D AABB를 데모 전용 단일 rules로 정의하고 실제 도달 이동 구간에만 가중 비용, sensor/concealment, 사격 range/arc 보정을 적용한다. 경계 포함·접선/끝점 0거리 membership·공선 이동·중첩 max-cost/additive 정책을 고정했다. 추정 사격은 실제 적 위치나 지형을 보지 않고 sealed aim 구간만 사용하며 지형 부적격은 자원 소모 전에 억제된다. UI는 공개 zone과 자기 전대 membership/transition/보정만 표시한다. dirty `terrain_v4`와 외부/3D 자산은 수정·로드하지 않았다. 최종 독립 시험은 core 40/0, UI 20/0과 G5-02~G2 회귀가 exit 0이며 구현 GPU 22/0이다. 캡처는 `out/demo-rc-g5-03-battlefield-terrain/battlefield-terrain-1600x900.png`, SHA-256 `558FD881756FF00DB030F1E06C2A2526F78A3A73E50A20CE1AF22DE8051C740F`; `out/`은 커밋하지 않는다. zone/marker 라벨 겹침·고대비 패턴·물리 입력은 P2다. 다음은 **DEMO-RC-G5-04 — 손권 제어 문의 계약 재검증**이다.

> **2026-09-11 DEMO-RC-G5-02 — 센서·전자전·진형·장수 탐지 보정 — PASS:** 함종·정찰 장비의 sensor/EW, 실제 거리, 현재 진형 detection 보정, 배치 지휘관 `지력`을 단일 정수 rules로 합산해 탐지 상태를 판정한다. command/level이나 설명 문자열은 파싱하지 않고, 다중 관측자는 안정 규칙으로 병합한다. 지형 보정은 중립·G5-03 pending이다. viewer에는 자기 관측 능력과 한국어 판정 이유만 보이고 적 EW·장수·진형·거리·raw score는 노출하지 않는다. 독립 QA에서 예비 장수 5명의 잘못된 ID를 canonical로 수정하고 G3 편성 적용→G5 탐지 초기화 통합 시험을 추가했다. 최종 시험은 core 67/0, UI 20/0과 G5-01~G2 회귀가 exit 0이며 구현 GPU 22/0이다. 캡처는 `out/demo-rc-g5-02-detection-modifiers/detection-modifiers-1600x900.png`, SHA-256 `47F4205BF59ED6F393949A19686D4390C66073727C2EFA7E03928DB878BB41F3`; `out/`은 커밋하지 않는다. 동일 좌표 라벨 겹침과 물리 입력·스크린리더·고DPI는 P2다. 다음은 **DEMO-RC-G5-03 — 전장 지형의 이동·탐지·무기 효과**다.

> **2026-09-11 DEMO-RC-G5-01 — 전쟁 안개·마지막 확인·추정 사격 — PASS:** 한 번 확인한 접촉은 viewer별 opaque ID로 age 1~2 추정, age 3 stale, 이후 만료하며 재탐지 시 갱신한다. 유비/수동 손권은 expired 전의 estimated 접촉을 직접 선택해 last-known 기반 결정론적 조준점을 만들 수 있다. true enemy navigation을 바꿔도 추정 사격 결과가 변하지 않으며, 사거리·사격각·제한 자원은 기존 공용 resolver를 거친다. UI는 마지막 확인 좌표·턴·신뢰도·오차·만료만 표시하고 unknown/expired와 실제 적 정보는 숨긴다. 독립 QA에서 조준점 bounds와 expired 접촉 재노출 P1을 수정했다. 최종 시험은 core 67/0, UI 24/0, 구현 GPU 26/0과 G4-07~G2 전 회귀가 exit 0이다. 캡처는 `out/demo-rc-g5-01-fog-estimated-fire/fog-estimated-fire-1600x900.png`, SHA-256 `2F30336DAA2526D57301DADE53534010632E289AD6E30BB6AFBB08E5CC07A895`; `out/`은 커밋하지 않는다. 물리 입력·스크린리더·고DPI·대량 접촉 탐색은 P2다. 다음은 **DEMO-RC-G5-02 — 센서·전자전·진형·장수 탐지 보정**이다.

> **2026-09-11 DEMO-RC-G4-07 — 턴 전투 5단계 판정 원장 — PASS:** 한 번의 턴 판정 안에서 접적·포화·교전·강습·결착 5단계를 고정하고 G4-02~06의 권위 이벤트를 단일 JSON 매핑으로 배치한다. 현재 실제 사건은 접적과 포화에만 기록하며 교전·강습·피해·승패는 pending을 유지한다. 단계·사건 ID와 digest는 재생 가능하고 mapper 실패·잘못된 턴·중복 resolve는 전체 상태를 원자 보존한다. viewer 단계 원장은 redacted 사건만 다시 구성해 숨은 사건 수나 적 ID·기하·자원을 노출하지 않는다. 최종 독립 시험은 core 59/0, UI 22/0과 G4-06~G2 회귀가 exit 0이며 구현 GPU 24/0이다. 캡처는 `out/demo-rc-g4-07-five-phase-ledger/five-phase-ledger-1600x900.png`, SHA-256 `CAC6C74CC70A0EC362CF7ABA3DF83BBF5088386DD7D2F077D67B6BACD12641A9`; `out/`은 커밋하지 않는다. 물리 입력·스크린리더·고DPI·대량 원장 UX는 P2다. 다음은 **DEMO-RC-G5-01 — 전쟁 안개·마지막 확인·추정 사격**이다.

> **2026-09-11 DEMO-RC-G4-06 — 제한 전투 자원과 결정론적 소모 — PASS:** 전대 편성 기반 탄약·에너지·열·함재기 준비도·데모 한정 특수 charge를 단일 자원 규칙으로 초기화하고, 사격 승인마다 안정 순서로 예약·소모한다. 부족·과열·미복귀 시 대체 무기 없이 억제하고 자원은 원자적으로 보존한다. 에너지·열·함재기는 1턴 무회복, 2턴부터 판정 시작에 턴당 1회 회복하며 ammo/special은 자동 회복하지 않는다. 이벤트 원장으로 다른 턴·중복 resolve·재생 이중 소모를 막고 자기 viewer에만 자원 상태·영수증을 공개한다. 실제 명중·피해·사상·승패는 pending이다. 최종 독립 시험은 core 79/0, UI 29/0, GPU 31/0과 G4-05~G2 전 회귀가 exit 0이다. 캡처는 `out/demo-rc-g4-06-limited-resources/limited-resources-1600x900.png`, SHA-256 `51091D392E343FA634C7EF009F09EC22982C4FEB9EF5C2C75B306D57830F6A11`; `out/`은 커밋하지 않는다. 실제 OS/DPI와 긴 스크롤은 P2다. 다음은 **DEMO-RC-G4-07 — 턴 전투 5단계 판정 원장**이다.

> **2026-09-11 DEMO-RC-G4-05 — 무기 비율·프리셋·사격 중지 명령 — PASS:** 직접 지휘 전대는 MOVE/HOLD·진형과 함께 가용 무기의 10,000bp 배분, 4개 프리셋, 직접 1bp 편집, 공격 보류·재개를 같은 초안에서 지정한다. 코어가 합계 100%, 불가 무기 0%, 결정론적 정규화와 무기별 사거리·사격각 적격성을 단독 판정하며 resolve 시작 적용과 턴 간 지속을 보장한다. 사수에게만 배분 snapshot을 공개하고 피격 측에는 적 무기 정보를 숨긴다. 실제 탄약·에너지·열·명중·피해·승패는 pending이다. 최종 독립 시험은 G4-05 core 80/0, UI 30/0, GPU 32/0과 G4-04~G2 전 회귀가 exit 0이다. 캡처는 `out/demo-rc-g4-05-weapon-allocation/weapon-allocation-1600x900.png`, SHA-256 `65E4126B5C2BE587DC6F12DFABE4DEEFBA5BB903BECC5562028DC929350DC7AA`; `out/`은 커밋하지 않는다. 실제 OS/DPI와 무기 종류 증가 스크롤은 P2다. 다음은 **DEMO-RC-G4-06 — 제한 전투 자원과 결정론적 소모**다.

> **2026-09-11 DEMO-RC-G4-04 — 진형과 정면·측면·후면 보정 — PASS:** 직접 지휘 전대는 HOLD/MOVE와 함께 허용 진형 7종을 초안으로 선택하며, 변경은 resolve 시작에 적용돼 같은 턴의 이동·탐지·기회 사격과 다음 턴에 유지된다. 표적→사수 입사 방향으로 정면·측면·후면을 분류하고 단일 rules JSON의 진형 modifier를 `shot_authorized` 원장에 pending 보정으로만 기록한다. 실제 명중·피해·탄약·열·승패는 후속이다. viewer API는 자기 진형과 자기 역할 상세만 공개하고 unknown/estimated 적 정보와 피격 측의 적 사수 기하를 숨긴다. 독립 QA에서 경계각 epsilon과 추정 접촉 보정 누출 P1을 수정했다. 최종 시험은 G4-04 core 68/0, UI 22/0, GPU 24/0과 G4-03~G2 전 회귀가 exit 0이다. 캡처는 `out/demo-rc-g4-04-formation-facing/formation-facing-1600x900.png`, SHA-256 `8905146E812B573274E472D74EDF344838BD53B7A6E706B48C836CCDA34C76C5`; `out/`은 커밋하지 않는다. 실제 OS/DPI와 다중 이벤트 라벨 충돌은 P2다. 다음은 **DEMO-RC-G4-05 — 무기 비율·프리셋·사격 중지 명령**이다.

> **2026-09-11 DEMO-RC-G4-03 — 경로 교차 요격·탐지 기반 기회 사격 — PASS:** 실제 도달 이동 구간의 적대 교차와 확인 탐지된 이동 표적의 사거리·사격각 진입만 판정해 `path_intersection`·`shot_authorized` 원장을 만든다. 미도달 예정 경로·단순 종점 근접·미탐지/추정 접촉·공격 보류는 사격하지 않으며 피해·명중·자원·승패는 후속 pending이다. UI는 viewer별 redacted API만 소비해 unknown은 숨기고 estimated/stale는 마지막 확인 위치·턴과 불확실성만 표시한다. 독립 QA에서 피격 측의 적 사수 기하 정보 누출 P1을 수정했다. 최종 시험은 G4-03 core 111/0, UI 21/0, GPU 23/0과 G4-02/G4-01/G3/G2 전 회귀가 exit 0이다. 캡처는 `out/demo-rc-g4-03-interception-detection/interception-detection-1600x900.png`, SHA-256 `4DEF3501155184402C6F1A689A1517C6D708F8D00ED88AF22CA8D077A2C7AB1A`; `out/`은 커밋하지 않는다. G4-03 전용 손권 수동 요격 fixture와 실제 OS/DPI·다수 접촉 라벨은 P2다. 다음은 **DEMO-RC-G4-04 — 진형과 정면·측면·후면 보정**이다.

> **2026-09-10 DEMO-RC-G4-02 — 자유 좌표·다중 경유점·방향 이동 판정 — PASS:** 턴 화면의 HOLD-only 경계를 실제 MOVE 초안으로 확장했다. 전대 선택, 지도 클릭/X·Y 입력, 최대 5개 경유점, 중간 삭제·초기화, 0~359도 방향, 줌·팬·보기 복원, 코어 preview의 거리·예산·ETA·도달점을 제공한다. 이동은 최저 함종 속도와 지휘 초과 불이익을 적용한 속도순 결정론 판정이며, 부분 이동과 live 위치·방향을 다음 턴에 보존한다. 최종 교차 시험은 G4-02 core 78/0, UI 43/0, GPU 45/0과 G4-01/G3/G2 전 회귀가 exit 0이다. 캡처는 `out/demo-rc-g4-02-movement/movement-ui-1600x900.png`, SHA-256 `1A8E4960C5F039EB146FE324E415F9CC3F6D06B364919A2DC3092D31EE8B9297`; `out/`은 커밋하지 않는다. 실제 OS 물리 입력·고DPI와 대규모 경로 겹침은 P2다. 다음은 **DEMO-RC-G4-03 — 경로 교차 요격·탐지 기반 기회 사격**이다.

> **2026-09-10 DEMO-RC-G4-01 — 유비 명령·손권 제어 선택·20턴 판정 루프 — PASS:** 준비 화면의 전투 시작이 current applied setup/revision/digest로 단일 2D 턴 화면을 연다. 유비 HOLD 확정 뒤 손권에게 매 턴 직접 명령·이번 턴 AI·AI 고정 중 하나를 묻고, 수동 손권 또는 stable AI와 조조 AI 명령을 원장에 기록한 뒤 승리 조건 확인 대기로 간다. 문의는 현재 전투에서 다시 켤 수 있고 20턴 뒤 결과 판정 대기에서 다음 턴을 금지한다. 최종 독립 시험은 core 236/0, UI 44/0, G2 77/0, G3 core/UI 135/0·62/0, GPU 46/0이며 모두 exit 0이다. 캡처는 `out/demo-rc-g4-01-turn-loop/turn-loop-1600x900.png`, SHA-256 `B6421B6E80926AAFEA634DDF632DF76763FBAE2E05251010C07880B717228B8A`; `out/`은 커밋하지 않는다. 이 Task는 이동·사격·피해·승자를 만들지 않았다. 다음은 **DEMO-RC-G4-02 — 자유 좌표·다중 경유점·방향 이동 판정**이며, 물리 마우스/DPI 입력은 후속 수용에 남긴다.

> **2026-09-10 DEMO-RC-G3-01 — 비용 기반 전대·함대 편성 편집기 — PASS:** 적벽 준비 화면의 사용자 편성이 실제 2D 편집기를 연다. 역사 원본·마지막 적용본·초안은 깊은 복사로 분리되며, 편집기 닫기/재열기와 같은 Main 세션 재진입에도 적용 revision·digest·setup을 보존한다. 유비 직접 편집, 손권 opt-in, 조조 잠금과 세력별 재고·장수·비용·고속정 장비·함대 그룹·자동 기함·지휘 초과 경고를 검증했다. 최종 독립 결과는 core 135/0, UI 62/0, G2 72/0, GPU 64/0이며 모두 exit 0이다. 캡처는 `out/demo-rc-g3-01-formation-editor/formation-editor-1600x900.png`, SHA-256 `CB9687A63D7F9FEDC272E69FB8A57D2132464CCDC7BE1FAF39C810769540F983`; `out/`은 커밋하지 않는다. 남은 핵심은 전투 중 지휘 체계가 아니라 **실제로 턴을 시작하고 명령을 받는 루프**다. 다음은 **DEMO-RC-G4-01 — 유비 명령·손권 제어 선택·20턴 판정 루프**다.

> **2026-09-10 DEMO-RC-G2-01 — 유비 직행 전투 준비 화면 및 역사적 초기 상태 경계 — PASS:** 사용자가 인터뷰 종료 후 구현 시작을 승인했다. `gpt-5.6-sol / medium` 구현 에이전트와 별도 UX 검증 에이전트가 적벽 버튼의 유비 준비 화면 직행, 조조·손권·유비 3세력 전대, `normal-demo-v1` 게임용 수량·비용·좌표, 요격함과 임무장비 고속정, 오류 잠금과 중복 진입 방지를 수용했다. 집중 시험 **63/63 PASS, exit 0**, 관련 회귀 0 failures·33/33 PASS, Vulkan/Intel Arc 130V 1600×900 화면 잘림·겹침 없음이다. 캡처 SHA-256은 `1B45E0AF6AE53183AB0BF30A0F3F343EB653457C10287EBFAB670D70DFB95FA6`; `out/`은 증거 산출물로 커밋하지 않는다. 사용자 편성·전투 시작은 아직 비파괴 후속 안내이며 기능 완료로 보지 않는다. 과거 선행 사건·집결 시험 실패는 구계약 충돌이다. 다음은 **DEMO-RC-G3-01 — 비용 기반 전대·함대 편성 편집기**이며, 전체 장수 명단·재고·지휘 한도·초과 불이익·함대 편입/제외를 독립 검증 가능한 단위로 구현한다.

> **2026-09-10 MGMT-HANDOVER-01 — 성한지 프로젝트 진행·일정·작업 프롬프트 관리 — 시나리오 문서 최신화:** 최신 요구사항을 우선 정본으로 삼아 `scenario-200-208.md`, `demo-rc-01`~`05`, `demo-rc-fin-play-guide.md`, `demo-rc-fin-narrative-contract.md`, `demo-rc-lt02-scenario-ending-loop.md`, `red-cliffs-active-battle-contract.md`와 완성 체크리스트를 갱신했다. 새 목표는 **유비 플레이 → 역사적 전투 준비 → 손권 턴별 수동/자동 선택 → 최대 20턴의 전대·함대 전투 → 결과 화면에서 데모 종료**다. 과거 손권 플레이·선행 선택·수동 집결·5페이즈 단일 진행·캠페인 복귀 문서와 QA는 기존 구현 이력으로만 보존한다. 구현 코드·테스트·자산은 수정하지 않았으며 사용자 시작 승인 전 구현 잠금을 유지한다.

> **2026-09-10 MGMT-HANDOVER-01 — 성한지 프로젝트 진행·일정·작업 프롬프트 관리 — 🟨 인터뷰 진행:** 사용자 요구사항 정본을 `demo-rc-requirements-interview.md`에 기록한다. 플레이어는 유비, 손권·조조는 AI이며 전투 직전 역사적 배치와 사용자 편성 뒤 20턴 전대 단위 전투를 진행한다. 손권 함대는 매 턴 수동 제어 여부를 묻고, 전장은 자유 좌표·다중 경로·탐지·제한 자원·결정적 사기/장수 상태·연쇄 폭발 작전을 지원한다. 함선 표현은 3D를 전면 제외하고 스틸 이미지와 2D 연출을 사용한다. 구현·감사·리뷰 모델은 `gpt-5.6-sol / medium`이다. **인터뷰 완료와 사용자 시작 승인 전에는 구현·자산 생성·음원 반입을 시작하지 않는다.**

> **2026-09-09 DEMO-RC-LT-02 — 적벽대전 단편 시나리오 시작·분기·엔딩 플레이 루프 — PARTIAL:** 범위는 208 단편의 Event 03·04·06·07 선택, Event 09의 다섯 전제, 발생 시 기존 적벽 5페이즈와 미발생 시 DEC-01, canonical 결과 브리핑·홈 복귀·이어하기/새 데모 격리다. UI는 공개 Campaign 명령·projection만 사용하며 승패·battle snapshot·사건 결과를 주입하지 않는다. LT-02 38/0, RC-01 15/0, QA-01 40/0, RC-03/04 0 failures, G-10 24/0, SCN-03 저장/재생 40/0가 exit 0이다. 미완료는 Windows 1600×900 GPU QA-02의 반복 실행 브리핑 mount 실패와 기존 전체 suite의 `user://` 저장 거부(698<701, exit 1)다. 다음 추천은 이 GUI mount/입력 불안정성을 먼저 격리·수정한 뒤 QA-02와 전체 suite를 녹색으로 재실행하는 일이다.

> **2026-09-09 DEMO-RC 멀티 에이전트 전투 UX 마감 — PASS:** 코어·UI·독립 QA 트랙을 분리해 canonical 결착 점수와 명령 거부 코드, 지도 전과/전력 전후, 명령 상태, 모달 접근성, 함대 hover·키보드 선택을 통합했다. 실시간 3D는 재개하지 않았다. 집중·E2E·GPU·저장·재생·A-05·G-10·701 코어 회귀가 모두 통과했다. GPU 시험은 Godot 공개 입력 경로이며 Win32 `SendInput`·물리 입력은 출시 전 사람 스모크다.
>
> **2026-09-09 DEMO-RC 진형 전술 비교 — PASS:** `진형 비교` 패널이 현재/후보 진형의 canonical 5페이즈 계수, 전개폭, 통솔 요구를 비교하고 현재 페이즈 및 증감을 표시한다. 비교만으로 코어 진형을 변경하지 않는다. 집중·제품 E2E 실패 0, native 입력 47/0, 코어 701/701, GPU 검수 PASS.
>
> **2026-09-09 DEMO-RC 함대 선택 상세 — PASS:** 네 함대 표식이 클릭·터치 선택과 펄스 강조를 지원한다. 상세 카드는 canonical 진영 전력·사기·진형과 페이즈별 목표·교전 상태를 표시하고, 전멸 시 선택을 해제한다. 전투 판정은 불변이다. 집중·제품 E2E 실패 0, native 입력 43/0, 코어 701/701, GPU 검수 PASS.
>
> **2026-09-09 DEMO-RC 누적 전투 기록 — PASS:** `전투 기록` 패널이 완료된 페이즈 전체의 손실·사기 변화·발동 계략을 canonical 결과에서 표시하며, 결착 후 최종 승자까지 확인할 수 있다. 전투 판정은 불변이다. 집중·제품 E2E 실패 0, native 입력 41/0, 코어 701/701, GPU 검수 PASS.
>
> **2026-09-09 DEMO-RC 페이즈 전환·계략 표시 — PASS:** 단계 변경 배너가 번호·이름·전환 신호를 1.8초 표시하고 입력을 가로채지 않는다. 전과 패널은 실제 발동 계략 이름 또는 `계략 없음`을 canonical 결과에서 표시한다. 집중·제품 E2E 실패 0·GPU 검수 PASS.
>
> **2026-09-09 DEMO-RC 결착 결과 가시화 — PASS:** 결착 완료 시 승자·양측 잔존 함선·사기를 타임라인 아래 전면 배너로 표시한다. 숨겨진 상태 문자열 의존을 제거했고 색상과 `승전` 텍스트를 함께 쓴다. 제품 E2E 실패 0·GPU 검수 PASS.
>
> **2026-09-09 DEMO-RC 진형 선택 브리핑 — PASS:** 선택한 진형의 강점 페이즈·계수·전개폭·필요 통솔·특성을 `Formations` 정본에서 하단에 표시한다. 적용 전에는 코어 진형을 변경하지 않는다. 집중·제품 E2E 실패 0·native 입력 41/0·GPU 검수 PASS.
>
> **2026-09-09 DEMO-RC 명령 덱 시각 계층 — PASS:** `다음 페이즈`를 금색 주 행동으로 강조하고 모든 전술 조작에 명시적 hover·pressed·focus·disabled 스타일을 적용했다. 1600×900 GPU에서 상태 구분과 잘림을 확인했다.
>
> **2026-09-09 DEMO-RC 페이즈 작전 지침 — PASS:** `PhaseBattleReport` 두 번째 줄이 5페이즈별 현재 판단 목표와 AI 위임 상태를 표시한다. 설명 전용이며 코어 판정값을 만들지 않는다. 집중·제품 E2E 실패 0·1600×900 GPU 검수 PASS.
>
> **2026-09-09 DEMO-RC 진형 가독성 — PASS:** 위군 전력 카드가 현재 코어 진형을 표시하고 선택기도 실제 `attacker_formation_id` 변경 시 동기화한다. 사용자가 고른 다음 진형 후보는 매 프레임 덮어쓰지 않는다. 제품 E2E 실패 0·1600×900 GPU 검수 PASS.
>
> **2026-09-09 DEMO-RC 명령 가용성 일치 — PASS:** phase 1 자동 접적 중 `can_advance=false`, phase 2 이후 true이며, AI 위임 뒤 플레이어 전술 입력 전체를 UI에서 잠근다. 버튼 상태는 `Campaign.red_cliff_command_state`만 따른다. 코어 46/0·제품 E2E 실패 0·native 입력 41/0.
>
> **2026-09-09 DEMO-RC 전과·명령 피드백 — PASS:** `PhaseBattleReport`가 직전 페이즈의 양측 손실·사기 증감·계략 수를 `ActiveBattle.phase_results`에서 읽어 표시한다. UI 명령 접수는 한국어 행동명과 실제 반영 시점을 안내한다. 우측은 계속 정지 이미지다.
>
> **2026-09-09 DEMO-RC 전술 지도 동적 연출 — PASS:** 우측 정지 이미지 정책은 유지한다. 좌측 함대는 5페이즈 진행도에 따라 곡선 항로를 따라 목표로 접근하고, 항로 표식·교전 링·사격선·폭발 신호가 2D 표시 시계로 움직인다. 코어 판정은 불변이며 집중 회귀와 제품 E2E 실패 0.
>
> **2026-09-09 적벽 전투 표현 정책 변경 — 적용:** 별도 발주자 지시 전까지 우측 실시간 3D는 `red-cliffs-live-battle-v1.png` 정지 이미지 한 장으로 대체한다. 현재 전력·사기·페이즈만 이미지 위 HUD에서 canonical 상태로 갱신하고, 후속 구현은 전술 지도·상태 전달·명령 UX·가독성을 우선한다.
>
> **2026-09-09 DEMO-RC-LT-01 — 적벽대전 5페이즈 전투 및 플레이어블 데모 — PASS:** `Main`의 `적벽` 버튼은 seed 20803의 실제 `Campaign.scenario_03` 명령 경로로 canonical active battle을 만든다. `ActiveBattle`/Campaign은 5페이즈·손실·사기·계략·player command·AI 위임·결과 함대 투영·stable result news·log replay를 담당한다. `RedCliffBattleView`는 5단계 timeline, 궤도·교전권·곡선 항로·쐐기 전열의 2/3 전략 지도, 실제 `SubViewport` 3D 함대·엔진·사격·피격·phase 카메라의 1/3 전장을 같은 코어 상태로 갱신한다. 비콘솔 Godot Vulkan Forward+ / Intel Arc 130V에서 1600×900 캡처 6개와 마우스·Tab/Enter 입력 흐름 40/40, writable user-data에서 save 73/0·replay 29/29, 장기 회귀 400/400·500/500을 확인했다. Computer Use의 네이티브 앱 미노출 때문에 Windows 하드웨어 SendInput 자체만 출시 전 사람 스모크 제한으로 남는다.

> **2026-09-08 Q-06-01 — CI 필수 자산 추적 계약 및 캠페인 실행 안정화 — PASS:** `NotoSansKR-VF.ttf`와 P0-04 승인 PNG는 추적 파일이며 fresh checkout 실패는 Godot import race였다. 두 pass import 뒤 단위시험 35/35·701/0을 확인했다. `run_campaign.gd`는 표준 100회와 HB 3×100회를 합쳐 400회를 돌리므로, 110초 banner-only 관찰은 hang이 아니다. 격리 4회 probe는 1.221초에 완주했고 campaign timeout은 900초로 조정했다.

> **2026-09-08 Q-05-LT-01 — 테스트·검산기 CI 기준화 및 자동 실패 게이트 구축 — PARTIAL:** `Q-05-01`~`Q-05-QA-01`으로 검산기 종료 코드, 11단계 PowerShell 게이트, GitHub Actions workflow를 도입했다. 그러나 `b184fc7` 깨끗한 worktree에서 추적되지 않은 `NotoSansKR-VF.ttf`와 승인 PNG 누락으로 P0-04 단위시험 23건·690<701이 실패했고, `campaign-locked-100`은 유휴 hang을 재현했다. 실패를 성공으로 숨기지 않았으며 정상 aggregate 0·원격 green은 아직 없다. 다음은 **Q-06-01 — CI 필수 자산 추적 계약 및 캠페인 실행 안정화**다.

> **2026-09-08 Q-01-MGMT-01 — Q-01 무인 장기 작업 상위 기록 마감 — PASS:** **Q-01-NIGHT-01 — 8시간 무인 계략·전투 밸런스 조정 및 회귀 검증**의 하위 `A-05-MGMT-01`, `Q-01-01`~`03`, `Q-01-QA-01`, `Q-02-01`, `Q-01 최종 증거 보완`을 연결해 마감했다. 현재 잠금 ruleset은 회랑 출구 매복 보정 0이며, 최신 지표는 재현율 **60.0%**·조기 종료율 **0.0%**·주역 편차 **1.3배**다. Q-02의 독립 100회도 일치했다. 오래된 67.0%는 조정 전 역사 기록이며 현재 기준선이 아니다. Q-01·Q-02는 완료 상태를 유지한다.

> **2026-09-08 Q-01 최종 증거 보완 — PASS:** 잠금 ruleset `verify_chibi.gd`가 표준 진형 5페이즈 계수(0.860/1.060/1.070/0.910/0.875)와 화공·간파·위장 항복의 페이즈별 손실·사기 대조값을 출력했고 불일치가 없었다. 상세는 `q01-01-balance-baseline-diagnosis.md`에 병합했다.

> **2026-09-08 Q-02-01 독립 100회 회귀 — PASS:** `3b6f4b7` 잠금 상태에서 새 `codex/q02-regression` worktree가 ruleset을 바꾸지 않고 시드 1000..1099를 재실행했다. Q-01과 동일하게 재현율 60.0%, 조기 종료 0.0%, 조조/손권/유종 35/34/44%(1.3배), 평균 전투/점령 72.6/55.2, 이벤트 17/17, 구조 7/7·잠금 3/3이며 차이는 없다. 상세: `docs/07-production/q02-01-100-campaign-regression.md`.

> **2026-09-08 Q-01-QA-01 — PASS:** main ruleset에서 100+HB 300회 재실행이 구조 8/8·잠금 밸런스 3/3으로 exit 0을 냈다. 기준선은 회랑 출구 매복 보정 0, 표준 HB·시드 1000..1099의 재현율 60.0%·조기 종료 0.0%·편차 1.3배다. `run_campaign.gd`는 이 세 지표를 exit code에 반영한다. F-10은 G-02 범위이며 Q-01 실패가 아니다. 다음은 잠긴 ruleset을 수정하지 않는 Q-02-01 독립 100회 회귀다.

> **2026-09-08 Q-01-03 — PASS:** 격리 A/B에서 회랑 출구 매복 보정만 `+15→0`으로 바꿨다. 표준 HB·시드 1000..1099는 재현율 60.0%(기존 67.0%), 조기 종료 0.0%, 조조/손권/유종 35.0/34.0/44.0%(편차 1.3배), 평균 전투/점령 72.6/55.2, 이벤트 17/17, 100+HB 300회 구조 7/7이다. 매복 성공은 15.9→9.3회, 조조 회랑 공격 피격은 31.7%→15.8%로 변했다. core 701/0·A-05 93/0·G-10 24/0·재생 29/0·저장/복원 73/0(SKIP 2)을 통과했다. 다음은 Q-01-QA-01 잠금이다.

> **2026-09-08 Q-01-02 민감도 탐색 — PARTIAL:** 동일 시드 1000..1099에서 HB만 바꾼 비침습 대조는 0.00=60.0%, 0.10=65.0%, 0.15=70.0%, 0.20=79.0%, 표준 0.25=67.0%다. 조기 종료 0.0%, 주역 편차 1.4~2.8배, 이벤트 17/17은 유지됐고 반응은 단조롭지 않았다. HB 0.00은 목표 밴드에 들어가지만 표준 역사 편향을 자유 역사 모드로 바꾸는 제품 결정이므로 채택하지 않는다. 계략별 단일 변수 A/B는 공유 작업 트리 오염을 피하려 미수행했다. 따라서 ruleset은 변경하지 않았고 Q-01-03·Q-01-QA-01은 보류다. 상세: `docs/07-production/q01-02-scheme-sensitivity-analysis.md`.

> **2026-09-08 Q-01-01 기준선 재현 — PASS:** 표준 HB 0.25·시드 1000..1099에서 역사 재현율 67.0%(목표 상단 +7.0%p), 조기 종료 0.0%, 주역 승률 편차 1.7배, 평균 전투/점령 71.7/54.3, 이벤트 17/17을 재현했다. 동일 실행 및 100+HB 300회 구조 검증 7/7은 exit 0이다. 계략은 판당 시전 121.3·성공 43.3(35.7%)이며 매복 15.9가 최대 성공량이다. 회랑 공격 중 조조 매복 피격은 31.7%, 비회랑은 20.7%다. 관측은 매복을 첫 조사 후보로 만들지만 인과 결론이나 수치 변경은 아니다. 상세: `docs/07-production/q01-01-balance-baseline-diagnosis.md`.

> **2026-09-07 A-05-MGMT-01 상위 작업 마감 — PASS:** **A-05-LT-01 — 진형 7종 전투 5페이즈 배선 및 결정론 검증**을 완료로 승격한다. `A-05-01` 계약, `A-05-02` 계수·상성·팔진, `A-05-03` 지형·변경 상태기계, `A-05-04` Campaign/UI/AI/저장 재생 통합, `A-05-QA-01` 수용이 상위 증거다. 현 HEAD 재실행은 A-05 93/0, core 35/35·701/0, G-10 entry E2E 24/0이다. 독립 `run_save_restore.gd`의 52/5는 `user://` 쓰기 거부(A-07-E1)로, 저장·재생 계약을 완화하지 않았고 Q-01 수용의 열린 환경 위험으로 유지한다. G-10의 최신 완료 범위는 **적벽 entry 수직 슬라이스**(QA-01)이며, 오래된 ‘다음 G-10 entry’ 표기는 역사 기록으로만 읽고 phase 3~5·일반 C-02가 별도 후속이다.

> **2026-09-07 A-05-QA-01 진형 5페이즈 통합 수용 — PASS:** 집중 93/0의 100회 반복, core 35/35·701/0, G-10 29/0·61/0·24/0, 캠페인 100+HB 300회 구조 검증 7/7을 통과했다. 역사 재현율 67.0%는 기존과 변화 0.0%p이며 Q-01 입력으로만 기록했다. `run_campaign.gd` 성공 종료 들여쓰기(A-07 실행 신뢰성)를 보정했다.

> **2026-09-07 A-05-04 Campaign·UI·AI·저장 재생 통합 — PASS:** UI/AI/G-10 phase 1~2는 Campaign 공용 읽기 투영만 소비하며 Main은 코어 `combat_milli`를 표시한다. 신규 전술 UX/phase 3~5 없음. A-05 93/0, entry shell 29/0, core 701/0. 다음 = A-05-QA-01.

> **2026-09-07 A-05-03 지형 강제·진형 변경 상태기계 — PASS:** 이동 시 확정한 지형을 전투까지 동결하고, 대회랑 강제·지형 거부·경계 전용 함대별 1회 변경·통솔 실패 도착 페이즈 ×0.8·팔진 자동 성공을 코어 명령/지문에 배선했다. G-10 ID는 로그 전 거부된다. 독립 집중 92/0, 전체 35/35·701/0. 다음 = A-05-04 통합.

> **2026-09-07 A-05-02 진형 계수·상성·팔진 배선 — PASS:** 일반 5페이즈 전투가 실제 `Fleet.formation`을 읽어 JSON 계수와 ③ 교전 오각 상성을 고정소수점으로 합성한다. 장사진 −10%, 팔진 상성 무효·통솔 90+`신기묘산` 조건, unknown 거부, 기존 한글 저장 호환을 확인했다. `test_a05_formation_combat.gd` 49/0, 전체 35/35·701/0. 다음 = A-05-03 지형 강제·변경 상태기계.

> **2026-09-07 A-05-01 진형 전투 계약·기준선 — PASS:** `docs/07-production/a05-01-formation-battle-contract.md`가 7개 `FRM-*` 입력/기존 `Fleet.formation` 한글 저장 호환, 팔진 실제 조건 `신기묘산`+통솔 90, 지형 단일 권위, 페이즈 경계 1회 변경 명령·재생, G-10은 phase 1~2 공용 판정만이라는 범위를 동결했다. Godot 4.7.2 전체 코어 기준선은 35/35 섹션·701 단언·실패 0. 다음 = A-05-02 계수·상성·팔진 배선; phase 3~5 전용 전투/UI·밸런스 조정은 범위 밖이다.

> **2026-09-07 G-10-QA-01 적벽 개전부터 전투 화면 진입까지 E2E 검증 — PASS:** 기능 24/0, GPU GUI 1600×900 36/0 및 독립 재검증 PASS. 4개 캡처와 hash는 `docs/07-production/g10-qa01-red-cliffs-entry-e2e-acceptance.md`; `out/`은 미커밋이다. G-10 수직 슬라이스는 완료했지만 phase 3~5·expiry/default delegation·일반 C-02는 별도 후속이다.

> **2026-09-07 G-10-UI-04 적벽 전투 화면 상태 표시 및 홈 복귀 경계 — PASS:** read-only 셸은 canonical ID, 위치, 상태, phase, 세력/함대를 표시한다. 홈 복귀·재진입은 단일 셸을 재사용하며 save contract는 불변이다. 전용 29/0·배너 61/0 및 독립 재실행 PASS. 상세: `docs/07-production/g10-ui04-red-cliffs-battle-state-return.md`. 다음은 G-10-QA-01; G-10은 🟨다.

> **2026-09-07 G-10-UI-03 canonical battle_id 기반 적벽 전투 화면 진입 셸 — PASS:** active canonical record만 재검증해 단일 read-only 셸을 열며, display/unknown/resolved는 거부한다. 상태·phase·양측 함대 수 표시와 홈 복귀를 전용 20/0·UI-02 61/0 및 독립 재실행으로 확인했다. 상세: `docs/07-production/g10-ui03-red-cliffs-battle-entry-shell.md`. 다음 작업은 G-10-UI-04이며 G-10은 🟨다.

> **2026-09-07 G-10-UI-02 적벽 인터럽트 배너 Windows 1600×900 시각·입력 수용 — PASS:** 시작 `main`/`origin/main`은 `f57f5bfabcb3a49163e4c4ec592559d31e7421a3`였다. `gpt-5.6-terra / medium` 구현·시험 및 독립 검수 모두 PASS했다. HUD 재구성은 이전 CanvasLayer를 해제해 살아남은 적벽 버튼/신호를 막으며, `size_changed` 연결도 중복하지 않는다. 전용 61/0, HomeMapSnapshot 348/0, HomeMapZoom 175/0, HomeSubmenuRouting 347/0. Vulkan GPU GUI 1600×900 캡처는 `out/g10-ui02-red-cliffs-banner-windows-acceptance/red-cliffs-banner-1600x900.png`(1,069,749 bytes, SHA-256 `F304C9795BEA1E73D27BC38B603541F9687C67A50E2A728E734D07CA19BE3BC9`)이며 수용 상세는 `docs/07-production/g10-ui02-red-cliffs-banner-windows-acceptance.md`에 있다. G-10은 🟨 유지. 다음 순서 작업은 **G-10-UI-03 — canonical battle_id 기반 적벽 전투 화면 진입 셸**이다.

> **2026-09-07 G-10 적벽 배너/action·canonical 전투 진입 경계:** 시작 HEAD/`origin/main`은
> `9452b6d2517b4ce8b973ff63dfcee76a030381bd`다. 구현·디버깅과 독립 읽기 감사는 모두
> `gpt-5.6-terra`로 수행했다. `HomeMapSnapshot`은 Campaign exactly-once 전이 뉴스를
> `campaign_core` 읽기 모델로 깊은 복사하고, active phase 1의
> `SCN-03-E09-RED-CLIFF-01`만 시각 바 아래 1행 배너를 만든다. action은 내부 ID를 노출하지
> 않으며, `battle_entry_requested`에는 canonical ID만 전달된다. host는 snapshot provenance,
> active·phase 1·`entry_available`와 live Campaign을 재검증한다. `BATTLE-RED-CLIFF`, unknown,
> phase 2, resolved, runtime-origin은 모두 거부되고 `stage:5`는 카메라 이동으로 남는다.
> runtime canonical news/battle/action 주입은 snapshot과 Main refresh 양쪽에서 차단했다.
> `test_red_cliff_interrupt_banner.gd` 50/0 및 기존 대상 회귀는 모두 exit 0; 전체 suite의
> 698/701·실패 2·exit 1은 기존 A-07-E1 `user://` 저장 환경 잔여다. 캡처는 미수행.
> expiry는 `unsupported`, default delegation·실제 전투 화면·일반 C-02는 미구현이며 G-10은
> 부분 구현 상태를 유지한다. 다음 단일 작업은 Windows 1600×900 시각/입력 수용이다.

> **2026-09-07 안정화 정정:** 시작 HEAD와 `origin/main`은 모두
> `4518e05009bf22301af943d0df6f97d19a757b6a`다. 코딩·디버깅 담당은 `gpt-5.3-codex-spark`,
> 오케스트레이터·독립 감사는 `gpt-5.6-terra`다. root `artillery_ship`·`assault_carrier`·
> `electronic_ship`·`siege_ship`·`supply_ship` GLB는 미사용 상수만 있었고 B 직접 참조가 아니다.
> 실제 `_hero_glb_path()`는 `assets/models/ships/voyage_lod/`의 동명 GLB를 사용한다. root GLB는 D/E
> 보류로 옮기며 삭제·복원·재수출 금지, `voyage_lod/**` B 참조는 유지한다. `.codex/config.toml`은
> `model = "gpt-5.6-terra"`를 고정하는 A 프로젝트 정본으로 Git 추적한다(다른 `.codex/` 파일은 제외).
> `.uid`·`.import`는 더 이상 일괄 C/삭제 가능이 아니다: 소스·런타임/승인 자산 대응 파일은 보존 후보,
> 원본 없는 `.uid`와 archive는 보류, 명확한 `out`/cache 재생성 파일만 C 후보다. 이전 A~E 합계는
> 폐기된 1차 감사값이며 전수 재집계 전 새 합계를 주장하지 않는다. C-04/C-05/P-02/G-10 상태는 승격하지 않으며,
> 다음 단일 구현 작업은 **G-10 C-02 배너/action 계약 + canonical `battle_id` 전투 진입 경계**다.
> 이번 절대 Godot 4.7.2 콘솔 재실행은 `HomeFleetRouteIntegration` 86/0, `FleetRouteTransition` 54/0,
> `HomeMapZoom` 175/0, `HomeMapSnapshot` 348/0으로 각각 exit 0이다. 전체 `run_tests.gd`는 35/35 섹션,
> 698 단언(697 통과), 실패 2, exit 1을 재현했다. `user://` 파일 저장 실패 뒤 `tests/run_tests.gd:824`의 빈
> Dictionary `seed` 접근과 701 단언 하한 guard가 뒤따른 A-07-E1 환경 잔여이며, 하한을 낮추거나 시험을 숨기지 않았다.
>
> 기존 2026-09-07 안정화 감사 완료 — 기준선과 완료 상태를 분리: 안정화 시작 기준선은
> `540189e`이며, 구현 커밋은 `9195a4a`·`8a2585b`, 문서 커밋은 `fb8f89b`다. 재확인 시점의
> 로컬 HEAD는 `fb8f89b`, `origin/main`은 `540189e`이고 로컬은 **ahead 3 / behind 0**이다. `9195a4a`는
> 3D 항행 계약은 코어 제3함대의 실제 1척을 바꾸지 않고 **관측용 전대 1개 28척**(전열 11·포격 6·강습 4·
> 전자 3·공성 1·보급 3)을 어린진으로 축약한다. 노후 통합 시험의 1척 표시 기대를 이 계약으로 교체했고,
> 구현에서 중앙열에 있던 보급함 1척을 후방으로 옮겨 공성 1·보급 3 전부가 후방 지원 역할을 갖게 했다.
> `HomeFleetRouteIntegration` 86/0, `FleetRouteTransition` 54/0이다. C-04·C-05·P-02 승격 근거가 아니다.
>
> **홈맵 적벽 marker:** 화면 회귀가 아니라 시험 fixture 노후화였다. **적벽 canonical identity에는** runtime
> `active_battles`/조건 주입을 읽지 않고 Campaign 재생에서 파생한 active battle만 투영한다(비적벽 generic
> runtime fixture는 별도 허용). 따라서
> `test_home_map_zoom.gd`가 Event 03/04/06/07 결과에서 canonical pending을 만들고 최소 active로 전이하도록
> 고쳤으며, marker 0건 뒤 배열 `[0]` 접근은 2차 오류였다. `HomeMapZoom` 175/0,
> `HomeMapSnapshot` 348/0, `HomeSubmenuRouting` 347/0, 적벽 phase/result 38/0이다.
>
> **`540189e` 은하 지도 내비게이션과 작업 트리:** `540189e`는 `app/main.gd`·`app/main.tscn`·
> `app/views/galaxy_map_view.gd`의 내비게이션 커밋이며, 위 홈맵 회귀로 유지 확인됐다. `status`의 295행은
> untracked 디렉터리를 축약한 수치이고, `ls-files --others` 651개와 수정 9개를 합친 실제 감사 대상은 660개다:
> A 54, B 46, C 511, D 42, E 7. 상세은 `docs/07-production/worktree-artifact-triage-2026-09-07.md`다.
> root 함선 GLB 5종은 현 항행이 직접 참조하지 않는 D/E 보류 자산이며, 실제 B 참조는 `voyage_lod/**`다.
> `out/**`·캐시·`.import`/`.uid`를 일괄 add하지 않는다. 다음 단일 작성 작업은
> 여전히 **G-10 C-02 배너/action 계약 + canonical `battle_id` 전투 진입 경계**다.
>
> 전체 `run_tests.gd`는 현 환경의 `user://` 로그/저장 쓰기 거부로 저장 섹션이 실패하여 698단언(697 통과),
> 실패 2, exit 1이다. 저장 실패 뒤 빈 Dictionary의 `seed` 접근이 연쇄됐으며 기능 회귀가 아니다. 저장 시험 제외나
> 하한 조정은 하지 않았다. A-07-E1(실행 환경)과 A-07-E2(3D teardown)를 후속으로 둔다.

> **A-07 후속(이번 세션 구현 금지):** **A-07-E1**은 headless `user://` 로그·저장 생성, 저장 섹션 정상 실행,
> 35섹션·701단언 이상, 실패 0·exit 0, 저장 실패 뒤 빈 Dictionary 역참조 금지가 완료 기준이다. **A-07-E2**는
> `HomeFleetRouteIntegration` 기능 단언을 유지하면서 생성 노드·Mesh·Material·Texture의 명시 해제와
> ObjectDB/RID 누수 제거(또는 엔진 한계 공식 분류), 기능·teardown 결과 분리 보고가 완료 기준이다.

> **2026-09-07 항행 상세 3D 전대 연출 완료(로컬):** `app/views/fleet_voyage_3d.gd`가 제공된 6종
> GLB를 `assets/models/ships/voyage_lod/`의 전대 관측 LOD로 읽는다. 기본 균형 편성 28척은 전열 11·
> 포격 6·강습 4·전자 3·공성 1·보급 3이며, 사용자 지정 어린진 슬롯으로 전열 선두/양익, 중앙 포격·
> 강습·전자전, 후방 공성·보급 순서로 놓인다. 전 함선에는 청백색 코어·청색 플룸·후방 광원을 붙였고,
> 성운 파노라마는 시간 회전하지 않으며 별 입자만 카메라 쪽으로 흘러 전진감을 만든다.
> 검증: Godot 4.7.2 Compatibility 캡처 성공 —
> `out/fleet-reference-scene/fleet-voyage-3d-fleet-v2.png`. 캡처 종료 시 OpenGL 리소스 해제 경고는
> 테스트 종료 경로에서 발생하며, 캡처 성공 판정과 별개다. 다음 작업자는 이 화면을 C-04/C-05 완료로
> 승격하지 말고 Windows 실기·입력·성능 수용과 자산 출처/라이선스 기록을 별도로 진행할 것.

> **2026-09-06 G-10 core news/home projection 슬라이스 검증 완료 — 다음 단일 작성 작업 확정:** 기준선은 `main` `c1e6de1`다.
> G-10은 `675347f`의 조건 원장·DEC-01·pending battle과 `7c7c6c5`의 participant manifest·
> `pending → active` 전이, `145dfbb`·`6efab57`의 결정론적 active phase 1→2와 resolved 결과 1회 적용까지
> 전용 시험 5종(81/50/40/73/25, 실패 0)과 전체 코어 35섹션·701단언(실패 0)을 통과했다. phase 3~5·
> 전이 뉴스 exactly-once 원장과 HomeMapSnapshot core projection까지 구현·검증했다. phase 3~5·
> C-02 배너·전투 진입·Windows 수용은 미구현이므로 완료 승격 금지.
> 다음 단일 작성 작업은 C-02 배너/action 계약과 canonical `battle_id` 전투 진입 경계다.
> 일반 `_resolve_battle()`·뉴스·UI·해무 함대 변경은 범위 밖으로 둔다.

> **2026-09-06 홈 지도·함대 항행 검수:** 기본 `scenes/main.tscn` 경로와 HomeMapSnapshot·
> A-03 이동 명령 경로는 전용 회귀 650단언(334+175+54+83+4, 실패 0)을 통과했다. 다만
> `app/main.tscn` 실험 경로는 `app/views/galaxy_map_view.gd:79` parse 오류와 setup 계약 불일치가
> 있으며, 3D 대표 편대·정본 항로 형상·함선 자산 출처/라이선스·Windows 실기 검증이 남았다.
> C-01 선행 전 C-04 완료 승격 금지. `.uid`·`.import`는 대응 원본과 자산별로 보존 판단하며, `.godot-appdata/**`와
> 명확한 `out/**` 재생성물만 생성물 후보다.

> **2026-09-04 경로 우선 지도 v3:** 거주 행성계 22개·표시 천체/시설 191개·행성 간 경로 150개. 기존 성간 경로 37개는 지형 추종 고정 곡선이며 기저항로 15개는 명령 시에만 표시한다. 회랑은 내부 약 40%·주변 70% 이상으로 우회 불가, 고속항로는 상시 표시한다. 하천 형상은 이동 규칙이 아닌 지형 참고선이다. 최대 상세에서 소행성·먼지·가스·방사를 함께 표시한다. v1·v2는 `data/maps/archive/`, 상세 `docs/01-world/galaxy-detail-map.md`. Godot 미연동.

> **2026-09-03 은하 상세지도:** 중국 지형 기반 공간 데이터 `data/maps/galaxy-map.json`과 `docs/assets/galaxy-detail-map.html`을 추가했다. 기존 19개 성계·45개 권역·15개 회랑·37개 항로를 유지한다. 수로 100% 개방, 분지·평원 장애 면적 20~30%는 사용자 확정. 구지 표기 중복을 생성기에서 정규화해 형주 태양계권에 1회 배치한다. 검증 및 미연동 범위는 `docs/01-world/galaxy-detail-map.md`. 기존 Godot 뷰·명령·전투 코드는 이 작업에서 수정하지 않았다.

> **2026-09-03 발주자 플랫폼 변경:** 플레이 지원 대상은 **Windows PC·Android·iOS**, 개발은 **Windows PC 우선**. 이전 Android 태블릿 선행 계획과 구분한다. 요구 정본 `docs/07-production/requirements.md` B1·C1, 화면·입력 `docs/06-tech/map-ux-concept.md` §6 참조. 기존 구현·검증 상태는 이 결정만으로 완료 승격하지 않는다.

> **새 세션·새 작업자를 위한 단일 진입점.**
> 갱신일: **2026-09-07** — **D1 검증 대기 · G-10 및 홈 지도/함대 항행 부분 구현 안정화 감사 완료.**
>
> **작업 상태의 정본은 `PROJECT-TRACKER.md` 다.** 우선순위·의존성·완료 증거는 거기서 관리한다.
> 2026-08-23 에 닫힌 `JOBS.md` 큐를 대체한다. HANDOVER 는 맥락·확정 사항·함정을,
> PROJECT-TRACKER 는 「무엇을 언제 어떤 순서로」를 담는다.
>
> **현재 단계: 개발 착수 후 (D1 기반 안정화).** `P0-01`~`P0-09` 프리프로덕션이
> 2026-09-01 에 전부 완료됐고 발주자가 개발 착수를 승인했다 (`DECISIONS.md` **V-65**).
> **개발 착수 게이트 8개 계약이 전부 확정** (GATE-PRE-01~08 · `preproduction-dev-gate.md` §8):
> 01 V-48효과 · 02 계약 A(V-60) · 03 초안대로 승인(V-62 · `preproduction-save-contract.md`) ·
> 04 계약 A(V-61) · 05 선택 A(V-63) · 06 조건 충족 · 07 승인 스냅숏 §8.4(V-64) · 08 V-49.
> 필수 콘텐츠 범위 = `단기판 필수 범위 v1.0` (§8.5). 착수 승인 시 최소 기록 ✅5 / 🟨2
> (3 밸런스 기준선 실제 잠금 = `Q-01` 완료 시 · 5 D3·D7 병렬 — 둘 다 개발 착수 후).
>
> **다음 단일 작성 작업 = G-10 C-02 배너/action 계약 + canonical `battle_id` 전투 진입 경계.**
> `A-01`·`A-02`·`A-03`·`A-07`은 구현 후 검증 대기를 유지한다.
>
> **여전히 미착수:** 명장 초상 120 대량 생성(별도 승인) · Runway 가입/결제/영상 생성
> (S6.1 약관 선행) · L2 3D 실착수(L1 완성 S4 후) · G-08·G-09 설계(L1 완성 후) · L3 컷씬(S6).
> P0-09 세션 결정 이력 = `DECISIONS.md` V-55~V-65.
>
> **[핸드오버 요약]** 이 저장소는 더 이상 문서만 있는 곳이 아니다.
> **코어 27파일 · 화면 16파일 · 시험 35섹션 701단언**이 돌고,
> `dev-requirements.md` §9 가 M0 의 산출물로 잡았던
> **「화면 하나 없이 AI 대 AI 로 100회 자동 진행되어 세력 승률 분포가 출력되는 것」**이
> **합격 기준 셋을 채웠다** (`m0-report.md`).
> **S3 클라이언트는 부분 구현됐다** — 게임 루프·성역 뷰(SC-L2)·세부 뷰(SC-L3)·함대 편성
> UI(SC-F1~F3)가 섰고, 명령 메뉴(S3.5)·배너(S3.7)·저장(S3.8)이 잔여다.
> **프리프로덕션(P0-01~P0-09)이 끝났고 개발 착수가 승인됐다(V-65). 다음은 D1 기반
> 안정화** (`A-01`·`A-03`·`A-07`) — S3 잔여는 그 뒤 D2 묶음이다 (`PROJECT-TRACKER.md` §3).

---

## 0. 30초 요약

모바일 그랜드 스트래티지 **SEONGHANJI: MANDATE (성한지: 천명)**의 기획과 구현.
후한 말 삼국시대를 우주 SF로 옮긴 은하영웅전설식 전략 시뮬레이션.

| 항목 | 현황 |
|---|---|
| **설계** | 완료. 세계관·시스템·캠페인·AI·UI 전부 문서 존재 |
| **프리프로덕션** | **P0-01~P0-09 ✅ 완료** (2026-09-01). 개발 착수 게이트 8개 계약 확정 · 발주자 개발 착수 승인 (`DECISIONS.md` V-65) |
| **코드** | **코어 27파일 · 화면 16파일 · 시험 35섹션 701단언 · 검산기 3종** |
| **데이터** | 스키마 13종 · 레코드 3,131 · 검증기 8종 (위반 0) |
| **M0** | 게이트 **3/3 통과**(2026-08-28). 계략 배선 후 재측정(08-30) — 재현율 **67.0%**(목표 40~60% 상단 초과) · 조기 종료 **0.0%** · 편차 **2.1배** · F-10 미발동. **밸런스 기준선은 `Q-01` 완료 시 잠금**(V-61) — 그때까지 M0 통과 60.0%와 현재 67.0%를 분리 기록 (§0.1 · `DECISIONS.md` V-47) |
| **현재** | **D1 기반 안정화** — `A-01`·`A-03`·`A-07` origin 반영 뒤 `A-02` 저장 지문·변조·손상 복구까지 🟦 검증 대기(2026-09-02). 진행·검증 상태 정본 = `PROJECT-TRACKER.md` §2 D1·§5. 경계 스냅숏과 Android 실기 대조는 각각 발주자 판정/C-05·C-06 후속. S3 화면 잔여(S3.5·S3.7·S3.8)는 D1 뒤 D2 묶음 |

**작업 방식:** 한 번에 하나씩 묻고 확정. 선택지에는 근거를 붙인다.

---

## 0.1 M0 현황 — 2026-08-28 (M0 게이트 통과) · 지표 재측정 2026-08-30

```
godot --headless --path . --script tests/run_tests.gd      35섹션 701단언
godot --headless --path . --script tests/run_campaign.gd   100회 · 합격 2/3 (회당 2.2초 · 총 3.7분)
godot --headless --path . --script tests/verify_power.gd   국력·동원율 대조
godot --headless --path . --script tests/verify_budget.gd  예산·행정비 대조
godot --headless --path . --script tests/verify_chibi.gd   적벽 5페이즈 대조
```

| 지표 (`ai-design.md` §11.1) | 목표 | M0 (08-28) | 현재 (08-30) | |
|---|---|---|---|---|
| 역사 재현율 (표준 HB 0.25) | 40~60% | 60.0% | **67.0%** | ❌ 상단 초과 |
| 조기 종료율 | 20% 이하 | 0% | **0.0%** | ✅ |
| 세력 승률 편차 (**주역 셋** · V-40) | 3배 이내 | 1.5배 | **2.1배** | ✅ |
| 미발동 이벤트 | 0종 | 1종 (F-10) | **1종** (F-10) | ❌ |

**재현율이 08-28 이후 60.0% → 67.0% 로 밴드를 벗어났다.** 원인은 **계략 배선**(`08fe115` ·
M0 게이트 통과 직후 커밋)이다 — 그 커밋이 이미 「70% → 매복 보정 +30→+15 로 67%,
목표 미달은 남는다」고 기록했다(`combat.md` §10 검토 14·16·17 · **`DECISIONS.md` V-47**).
**매복 +30→+15 조정과 지표 영향은 V-47 에 V-41·V-36 틀로 등재 — 되돌릴 대상은 배선이
아니라 계략·전투 밸런스이며 M0 게이트 재개방이 아니다.** **S3.2~S3.6 클라이언트
커밋(게임 루프·SC-L2/L3·SC-F1~F3)은 `run_campaign` 실행 경로를 건드리지 않는다** —
편차·재현율 숫자가 `08fe115` 가 남긴 값과 동일하다.

> **밸런스 기준선 잠금 방식 = GATE-PRE-04 계약 A 확정(2026-09-01 · `DECISIONS.md` V-61):**
> 기준선은 **`Q-01`(재현율 40~60% 복귀) 완료 시점**에 잠근다. 그때까지 **M0 통과 60.0%
> (계략 없는 값)와 현재 ruleset 67.0%(`08fe115`)를 한 숫자로 섞지 않는다** — 보고 시 분리한다.

**M0 결손 6종은 전부 닫혔다** — ⑥ 계략까지(`08fe115`). 지금 열려 있는 것은 둘 —
**재현율을 밴드 안으로 되돌리는 것**(계략·전투 밸런스 · `combat.md` §10)과
**[F-10] 연합 해체 미발동**([F-12] 배신이 먼저 깨서 18개월을 못 버틴다 · `m0-report.md` §2.4 ⑫).
둘 다 게이트 재개방이 아니라 후속 조정이다.

### 이 저장소에서 반복해 나온 것 하나

> **「문서에 있는데 코드가 안 읽는다」를 2026-08-25~28 에 여섯 번 만났다.**

| | 무슨 일이 |
|---|---|
| 회랑 넷 | 코드가 **이름으로** 판정해 대회랑 둘(진령삼도·이릉협도)을 놓쳤다 — **불가침 ④ 위반 포함** (V-36) |
| 훈련도 | `collapse_chance_pct` 에 `drill` 인자를 안 넘겼다 |
| 기술 | `Tech.power_milli` 가 전투에서 불린 적이 없었다 |
| 천명 | 눈금도 산식도 확정인데 **코드가 처음 읽었다** |
| 패권 압력 | 같음 |
| **인물** | **492인 5스탯이 다 있는데 전 함대가 통솔 50 이었다** — 주유도 하후돈도 없었다 |

그리고 반대로 **「코드가 맞고 문서가 낡았다」가 둘** —
동원율 손 계산(V-37) · 편성안 유지점 두 칸(V-35).

**그래서 검산기 셋을 세웠다.** `verify_power` 가 V-29 를,
`verify_budget` 이 V-38 의 「경제 불변」을, `verify_chibi` 가 V-39 의
「화공이 아직 통하는가」를 잡았다.
**문서와 코드가 각자 계산하면 언젠가 갈라진다. 이제 갈라지는 순간 셋 중 하나가 잡는다.**

> ⚠ **새 산식을 코드에 넣으면 검산기부터 확인하라.**
> 「산식을 쓴 것」과 「배선한 것」은 다른 일이다 —
> `domestic.md` §7 이 ⑤⑥ 을 완료로 적어 두고 실제로는 호출부가 없었다.

---

## 1. 먼저 읽을 것

```
1. HANDOVER.md          ← 이 파일
2. PROJECT-TRACKER.md   ← **작업 상태 정본** · 우선순위 · 의존성 · 완료 기록
3. CLAUDE.md            ← 불가침 원칙 · 표기 규칙 · 함정
4. docs/INDEX.md        ← 전체 색인 · 핵심 수치 한눈에
5. docs/DECISIONS.md    ← 기각된 안과 그 이유 (V-01~V-58)
6. docs/07-production/m0-report.md        ← 코드가 지금 무엇이 어디까지 되었는가
7. docs/00-overview/design-overview.md    ← 통합 기획서
8. docs/assets/star-map.html              ← 브라우저로 열 것
```

> **무언가를 만들기 전에 `docs/INDEX.md` 를 먼저 본다.**
> **그리고 코어에 이미 있는지 `core/` 를 grep 한다** —
> 위 표가 말하듯 「없을 것 같은 것」이 대개 이미 있다.

---

## 2. 확정 사항 총람

### 2.1 세계관

| 항목 | 확정 |
|---|---|
| 매핑 | 원전 **직접 대응** (조조=조조) |
| 외계인 | **없음.** 인류 내부 정치만 |
| 성립사 | 지구 탈출 → 공화정↔제정 반복 → 한제국 |
| 지리 | 1주 = 1성계. **성계 19 · 권역 45 · 회랑 15** |
| **태양계** | **형주 성역.** 지구=구지, 화성=형혹, 달=태음 |
| 정통성 | 유명무실한 황제 + **천명(Mandate) 수치** |
| 동맹 세력 | **동이 연합**(배신 리스크) · **대월지**(책봉→천명 상승) |
| 교섭 불가 | 로마 · 사산조 |

### 2.2 시스템

| 항목 | 확정 |
|---|---|
| 시나리오 | **6개** (190·200·208·219·228·263) + 프롤로그(184~189, 플레이 불가) |
| 명명 | **이중 레이어** — 공식(한대 관제) / 통칭(원전) |
| 전투 | **5페이즈 · 사기 붕괴** (Contact→Barrage→Engagement→Assault→Resolution) |
| 인물 | **3계층** — 명장 150 / 일반 무장 **249** / 재야(창작 + 이역 실존 **93**) |
| 등용 | **3중 판정** (고유조건 → 상성 → 천명) |
| 점령 | **부분 점령** — 권역 45 단위 |
| 시간 | **실제 1시간 = 게임 내 1개월.** 고속항로 45분 / 대회랑 3h45m |
| 수익 | **시간 단축 과금 전면 배제** |
| 엔딩 | **사분면** Mandate/Hegemony/Division/Fragmentation + 특수 5종 |
| 캠페인 | **연속 캠페인 + 세계 상태 4형 + 기능 이벤트 40종** |

### 2.3 핵심 수치

```
국력       후한 영화 5년(140) 군국지 인구 통계 기반
전화 계수  시나리오별 전란 피해 (사예 0.25 ~ 익주 0.95)
동원율     총 국력 × 동원율 = 실동원
           확장 → 국력↑ 동원율↓ / 봉쇄 → 국력정체 동원율↑

208년 실동원   조조 67 / 손유 동맹 37   ← 적벽이 성립하는 숫자

사기       게이지 0~125 · 초기값 45~125 · 명목 100
           100은 상한이 아니라 「보정 없음」이다
천명       0~100 · 여섯 구간 계단 (사기 보정 +15 ~ −15)

ACT        68개 · 필수 304.5시간 · 캠페인 총 348시간
           게임 내 90년 중 29년만 플레이한다
```

---

## 3. 문서 지도

| 경로 | 내용 | 비고 |
|---|---|---|
| `00-overview/design-overview.md` | **통합 기획서** | 모든 결정 반영 |
| `00-overview/glossary.md` | 용어 대조표 | **표기 정본** |
| `01-world/star-map.md` | 성계 19 · 회랑 · 항로 · 교착 방지 | |
| `01-world/region-power.md` | 국력 · 전화 계수 · 동원율 · **전화 회복 계수**(§3.5) | |
| `02-characters/generals-150.md` | 명장 150 · 이역 90 · 등용 · 용병 21 | ⚠ **§12·13·14가 최종본** |
| `02-characters/officers-256.md` | 일반 무장 — **실제 249인**(J2에서 중복 3인 제거). 스탯·성향 확정 | |
| `02-characters/dispositions.md` | 성향 5종 · **상성 매트릭스 개정판** | |
| `02-characters/generals-stats.md` | 명장 150 스탯 수치 | |
| `02-characters/foreign-90-stats.md` | 이역 인물 90(실제 93) 스탯 | **신규(2026-08-22)** |
| `03-systems/combat.md` | 5페이즈 · **사기 산식 5식** · **계략 산식 4식** · 일기토 · 함종 비용 | **J3·J6 반영** |
| `03-systems/ship-specs.md` | 함급·제원 · 무장 · 탑재기 · 지휘 한도 · 편성 · **진형 7종** | **신규(2026-08-23, J3)** |
| `03-systems/partial-occupation.md` | 권역 45 · 항로 귀속 | |
| `03-systems/diplomacy.md` | 동이 연합 · 대월지 · 중원 동맹 | |
| `03-systems/time-and-monetization.md` | 시간표 + 과금 원칙 + **ACT 실시간 소요**(§3.4) | **확정 · J7 반영** |
| `04-campaign/world-state.md` | 세계 상태 4형 · 분기 폭발 방지 · **막간 규칙**(§4.2) | |
| `04-campaign/function-events.md` | 기능 이벤트 40종 — **조건식·임계값 확정** | **v0.2 (2026-08-23, J5)** |
| `04-campaign/endings.md` | 엔딩 사분면(**할거 열 추가**) · 결정점 7 · 시즌 종료 | |
| `04-campaign/scenario-setup.md` | 6시나리오 × 권역 배치(**기본형**) · 토호 · 유랑 | |
| `04-campaign/world-state-setup.md` | 세계 상태별 시작 배치 **21개** | **신규(2026-08-23, J8)** |
| `04-campaign/character-assignments.md` | 인물 소속 배치표 **399명 × 6시나리오** | **신규(2026-08-23, J9)** |
| `04-campaign/scenario-190.md` | 시나리오 1 Timeline (**ACT 14** · 53시간) | |
| `04-campaign/scenario-200-208.md` | 시나리오 2·3 Timeline (**ACT 12 / 10** · 43 / 31.5시간) | |
| `04-campaign/scenario-219.md` | 시나리오 4 Timeline (**ACT 12** · 59시간) | |
| `04-campaign/scenario-228-263.md` | 시나리오 5·6 Timeline (**ACT 11 / 9** · 69 / 49시간) · **내부 압축 구간** | |
| `05-narrative/prologue.md` | 프롤로그 + **집필 지침** | |
| `05-narrative/epilogues.md` | 엔딩 후일담 10종 · 변주 규칙 | **표기 개정 적용** |
| `05-narrative/ending-variations.md` | 세력별 엔딩 변주 **48문단** (4계열 × 4사분면) | **신규(2026-08-23, J10)** |
| `05-narrative/interludes.md` | 막간 시뮬레이션 텍스트 **5구간 35문단** | **신규(2026-08-23, J12)** |
| `05-narrative/event-scripts.md` | 기능 이벤트 연출 텍스트 **40종** | **신규(2026-08-23, J11)** |
| `06-tech/ai-design.md` | 3계층 · 유틸리티 · 절단 가치 · **계략 성향 계수**(§7.4) | |
| `06-tech/ui-design.md` | 3단계 내비 · 복귀 브리핑 | |
| `07-production/dev-requirements.md` | **제작 요건** — 아키텍처 · 데이터 정본화 · 아트 물량 · 법무 · QA · 일정 | **신규(2026-08-23)** |
| `07-production/asset-ledger.md` | **에셋 라이선스 대장** — 물량 실측(등장 309 → 초상 131) · 확보 판정 · 라이선스 등급 | |
| `07-production/ai-media-pipeline.md` | **AI 미디어 제작 가이드** — 초상 131·BGM 6 규격·시드·프롬프트 · 계층×성향 조각(§4.3) · 명장 120 매핑(§4.7 + `data/portrait-map.json`) · 개별부 규칙(§4.8) · 크레딧 문안 초안(§8) · **실행 환경 RunPod Community**(V-46) | **신규(2026-08-30)** |
| `07-production/preproduction-ship3d-procurement.md` | **D3 함선 3D 조달·시각 기준** — 함급 6종 요구사항(역할·실루엣·스케일·LOD·머티리얼·금지) · 위·촉·오·군웅 4계열 도장·문장·색상 규칙 · CC0 탐색 기준 + 라이선스 검수 양식 11필드 · 5일 실패 시 A 유료→B 외주→C L2 축소 · S5.1 선행 8항 | **신규(2026-09-01)** · L2 채택 = V-55. 실착수는 P0-09 승인 후 S5.1 |
| `assets/star-map.html` | 인터랙티브 지도 | 브라우저로 열 것 |

---

## 4. 다음 작업

> **전체 우선순위·의존성은 `PROJECT-TRACKER.md` 가 정본** (§2 D1~D5 · §3 실행 순서).
> P0-09 개발 착수 승인(2026-09-01 · V-65) 후 현재 단계는 **D1 기반 안정화**.

### 4.0 지금 — D1 첫 착수 묶음 (`A-01` · `A-03` · `A-07`)

각 항목의 완료 기준·계약은 P0-09 게이트에서 확정됐다.
**세 슬라이스가 전부 `origin/main` 에 올라갔다 (2026-09-02).** 진행·검증 상태의 정본은
`PROJECT-TRACKER.md` §2 D1 표와 §5 완료 기록이다.

| 작업 | 무엇 | 계약·요구사항 | 착수분 |
|---|---|---|---|
| **A-01** | 캠페인 단위 저장·불러오기 모델 확정 | `preproduction-save-contract.md` §2(저장 범위 = 시드+명령 로그, 나머지 파생)·§3(순수 로그 재생, 규칙 세대·손상 복구, 자동 저장 월 정산). 캠페인 재생 경로(`Campaign` 셋업→목표 틱) | 🟦 `a101327`·`354a689`·`b65b3c0` + A-02 인수 `a69ab85` — 지문·재생 29단언, 전장 재생 ≈1.5초, 인수·문서 잔여 해소. 검수 대기 |
| **A-03** | 명령 산정·검증을 코어 권위로 이동 | `DECISIONS.md` V-60 §8.1 — 화면↔코어 갈라짐 5건(진형·함종별 척수·강화 축·관측 단계·이동 판정)의 정본 소유자 = core. 완료 기준 = 「동일 입력에서 UI·AI·재생 결과 일치」 | 🟦 `4ada641`·`67b9a56` + [현 작업] — `Campaign.observe_fleet`의 마지막 판독 신선도(실선/점선/회색·3개월 뒤 단계 1 강등), fleet_row/detail_view 연결, 지형 위임, V-66. `run_tests` 35/35·701 단언 및 `run_campaign_replay` 29 통과. 함대 이동 재생의 위치·목적지·도착 틱·척수·사기 일치는 A-02 `run_save_restore` 인수로 확인. 검수자·발주자 승격 대기 |
| **A-07** | 테스트 실행 신뢰성 보강 | `DECISIONS.md` V-61 — 실패 시험이 후속 단언을 숨기지 않음 · 단언 수 하한 **701**. 시험 5층(단위 / 100회 캠페인 / 검산기 3종 / 저장 복원 / 실기 스모크) | 🟦 `f3fd832`·`27a3509`·`5b30bf9` — 하네스·실패 격리·구조 검증. A-03 §35·§37을 반영해 35섹션/701로 상향했으며, A-01 재생 시험은 standalone이라 델타 0. 저장 복원 슬롯은 A-02 `a69ab85`에서 정식 73단언으로 채움 |
| **A-02** | 저장 지문·변조·손상 복구 인수 | `preproduction-save-contract.md` §3.2·§3.5·§4.2 — 정상/변조 지문, 규칙 세대, 부분 복구, 파일 왕복 | 🟦 **`a69ab85`** — `Save.inspect` 분리형 로더 · 지문 검증 결과 API · 손상 명령 직전 복구 · `run_save_restore.gd` 73단언/2 SKIP · 함대 스냅숏 제거. 검수 대기 |

> **`Q-01`(계략·전투 밸런스 조정) 완료 시 밸런스 기준선을 잠근다** (V-61). 그때까지 M0 통과
> 60.0%(계략 없는 값)와 현재 ruleset 67.0%(`08fe115`)를 **한 숫자로 섞지 않는다**.

### 4.1 D2 묶음 — S3 클라이언트 (D1 뒤)

```
S3.1  Godot 프로젝트 · 태블릿 가로 1600×900          ✅
S3.2  게임 루프 · 배속 · 시각 표시                    ✅ 2026-08-28
      app/main.tscn · Campaign.advance(elapsed_ms) 가 클라이언트의 입구다
S3.3  성역 뷰 (SC-L2)      명세 docs/06-tech/screens.md §2   ✅ 4472535
S3.4  세부 뷰 (SC-L3)      명세 동 §3                        ✅ 2026-08-30
      d74e187 (뷰 5파일 + Fleet.formation) · 배선 2파일은 c0fbbbe 에 포함
      app/views/detail_view.gd — 4층(LayerStrip) · 함대 아이콘(FleetRow +
      FormationIcon) · 진형 미리보기. formation_spec.gd 가 진형 7종 카탈로그.
      ★ core/world/fleet.gd 에 formation 필드 신설 (초기값 어린진 · 검토 14 해소).
      ⚠ 필드일 뿐 battle.gd 5페이즈가 안 읽는다 — 검토 18·19·20 신설(전투/코어 레인)
S3.5  명령 메뉴 — 내정. **전부 비차단**   명세 동 §9         ⬜
      ⚠ 전략·전술 명령은 정본 부재(§9.0) — 내정 7종만 확정
S3.6  함대 편성 UI — 사용자 정의 + 추천 모드   명세 동 §4    ✅ c0fbbbe (레인 2)
      선행(적 편성 관측 · 분할/합류 승계) 해소 — 동 §12·§13
S3.7  알림·인터럽트 배너                       명세 동 §11    ⬜
S3.8  저장/불러오기 · 설정                                    ⬜
```

> **화면 명세가 이미 있다.** `docs/06-tech/screens.md` 가 SC-L2·SC-L3·편성 UI 를
> 레이아웃까지 적어 두었다. **다시 설계하지 말고 그대로 구현하라.**
>
> **2026-08-30 — S3.5·S3.7 명세가 열렸다 (레인 3 · 문서 전용).** `screens.md` §9~§14 신설:
> 명령 메뉴 · 하프 시트 4종 · 알림 배너 · 적 편성 관측 · 분할/합류 지휘부 승계 ·
> 관계도 배치표(불필요 판정). 검토 5·6·10 닫힘 · 검토 11~17 신설.
> **코드는 건드리지 않았다** — 어긋난 곳(진형이 `Fleet` 필드에 없다 등)은 검토 포인트로 넘겼다.
>
> **2026-08-30 — S3.4(SC-L3)·S3.6(SC-F1~F3) 구현됨.** 세부 뷰는 검토 14(`Fleet.formation`
> 부재)를 코드로 닫았다 — 필드는 섰으나 **전장 모델 배선은 남아 검토 18** 로 이관.
> `Fleet` 에 함종별 척수가 없어 「공성함 0척」 잠금(§3.1)은 캡션까지만 — **검토 19**.
> 적 함대 진형이 §12 관측 게이팅 없이 그대로 보임 — **검토 20**. 셋 다 코어/전투 레인.
> 검증: `run_tests` 33/33 · 617 통과 · import·boot 오류 0 (HEAD `c0fbbbe`).

### 4.2 코어에 남은 것

| | 무엇 | 근거 |
|---|---|---|
| ~~**계략**~~ | **배선됨 (`08fe115`, 2026-08-30).** `core/combat/scheme.gd` 신설 · `_resolve_battle` 5페이즈에 연결. 적벽 네 갈래·이릉 12값이 문서와 일치(`verify_chibi`). **다만 역사 재현율이 60→67% 로 밴드를 벗어났고**(§0.1), 되돌리는 것은 배선이 아니라 **계략·전투 밸런스 조정** — `combat.md` §10 검토 14·16·17 · **`DECISIONS.md` V-47** | §5.3~§5.6 |
| **F-10 연합 해체** | 미발동 1종. **배신([F-12])이 먼저 깨서 18개월을 못 버틴다** — 조용히 갈라서는 경로가 필요한지가 판정 사항 | `m0-report.md` §2.4 ⑫ |
| 이벤트 23종 | 17종은 섰다. 나머지는 **인물 17 · 상징/찬탈/협상 6** 이 선행 | `core/events/events.gd` |
| 인물 연령 | `characters.json` 에 연령이 없어 **[F-30] 지도자의 죽음**이 못 선다 | — |

### 4.3 코어 지도 — 어디에 무엇이 있는가

```
core/
├── sim.gd              한 틱. **호출 순서가 규칙이다**
├── campaign.gd         시나리오 3 · 전투 · AI · 월 정산 · 이벤트
├── rng.gd rng_stream   영역별 분리 스트림 (V-31)
├── save.gd             시드 + 명령 로그 (V-25 ③)
├── time/game_clock     1틱 = 실제 1분 · 60틱 = 게임 1개월
├── data/game_data      정본 적재 · is_corridor() · region_adjacency
├── world/
│   ├── economy         자금 유량 · 행정비 · 편성별 유지점 (V-33)
│   ├── mandate         천명 0~100 · 사기 ±15
│   ├── hegemony        패권 압력 0~100 · [F-07] 견제 연합
│   ├── stability       권역 안정도 · 할거 페널티
│   ├── tech            기술 3축 5단계 · 화력−방어 뺄셈 (V-34)
│   ├── roster          인물 적재 · 지휘 한도
│   ├── domestic        전화 회복 · 내정 명령 7종
│   ├── diplomacy       4단계 · 신뢰도 구간 · 배신 기록
│   ├── faction fleet region_state power routing
├── combat/battle       5페이즈 · 사기 · 붕괴 · 훈련도
├── ai/strategy         절단 가치 · 목표 선정 · HB · 내정 판단
└── events/events       기능 이벤트 17종
```

### 4.4 미착수 (설계도 코드도 없음)

- 기동병기 상세 (에이스 판정) — **[F-16]·전투기 연출(`VFX-007`)·시각 쟁점 5·음원 검토 4 의 선행.**
  D5 = ㉮ 설계 선행 확정(V-58)으로 `PROJECT-TRACKER.md` **G-09** 로 큐에 올라감
- 무장 위성 방어 시스템 (D4 = ㉯ 시스템 신설 · V-58) — `combat.md` §8.2 재설계 + `domestic.md`
  건설 명령 + `star-map.md` §5 승격. `PROJECT-TRACKER.md` **G-08**
- 튜토리얼·온보딩
- ~~아트·사운드 방향~~ — **명세 완료.** `asset-ledger.md`(물량) + `ai-media-pipeline.md`
  (제작 방법)에 초상 131·BGM 6 의 규격·시드·프롬프트·명장 120 매핑·개별부 규칙·크레딧
  문안 초안까지 잡혔다. **실행 환경 RunPod Community**(V-46) — 자택 5060 8GB 는 음원만 로컬.
  **P0-04 공용 초상 기준선은 실행 완료** — V-50의 FLUX schnell·v2 스타일 공용 11종이
  승인됐고, `SC-F3` 256×320px 프레임·64px 칩 연결과 리소스 검수를 통과했다(`fd521c5`).
  명장 120명 생성은 자동 착수하지 않으며 별도 승인 뒤의 GPU 실행 패스다. 남은 실행 항목은
  BGM 6트랙 · 크레딧 문안 확정 · 배경/컷씬(S6)이다.
  - **사운드 P0-05 ✅ (2026-08-30)** — `preproduction-audio-plan.md` 에 씬↔큐 상태 기계(BGM 6 ·
    크로스페이드 8) · SFX 50종(UI·내정 20 · 전투 30 · 무기군 7) · 정규화 원칙 · R-14 대표 세트
    선청취 순서 · 권리(BGM = ACE-Step Apache 2.0 로컬 · **효과음 AI 전면 배제**, CC0 + 자작).
    파일별 확보·라이선스는 P0-08·P-02.
  - **시각 방향 P0-07 ✅ 완료 (2026-09-01 · `fd521c5`)** — `visual-direction-guide.md`를
    v1.0 후보로 잠그고, V-50 공용 11종을 실제 `SC-F3` 320px 프레임에 연결했다.
    34/34 섹션·664 단언이 통과했으며, PNG 11개 리소스·896×1120 규격·매핑을 자동 검증했다.
    기존 쟁점 중 초상 기준선 의존분은 해소됐다. 초상·3D 표본 비의존 **6건 확정**
    (기저 항로 선형 · 세력 색 범위 · 전투 3D 비중 2/3+1/3 · 구지 황폐 수준 · 금색 의미 · 아이콘
    기호 폴백). §8 「검수 체크리스트」를 **품질 판정 기준(통과/재작업)**으로 승격. **잔여 4건**
    (함선 세력 차별화 · 기동병기 실루엣 · 적벽 분기 · 장르 비유 교체)은 P0-09/후속 제작
    결정으로 남는다. **시각 쟁점 4(함선 세력 차별화)는 V-55로 방향 확정** — 공통 함급 6종 +
    위·촉·오·군웅 4개 시각 세력군 도장·문장·색상, 선체 실루엣 분화는 보류(도장·문장 세부만
    `preproduction-ship3d-procurement.md` · D3 착수 S5.1과 함께). **시각 쟁점 5(기동병기
    실루엣)는 D5 = 설계 선행 확정(V-58)으로 `G-09`(기동병기 상세 설계) 완료 후 판정.**
  - **라이선스 점검 P0-08 ✅ 완료 (2026-09-01)** — `preproduction-license-check.md` 로
    `asset-ledger.md` 라이선스 정본을 한 표로 전사·통합. **V-50~V-54 반영** — 공용 11종
    파일별 SHA·라이선스 잠금 · V-51 SFX AI 전면 배제 · V-52 L3·스토어 AI 고지 채택 ·
    V-53 게임 내 크레딧 4구획 문안 승인 · V-54 D6-2 Runway 우선·로컬 Wan 2.2 폴백.
    고지 요건 2갈래 분리(게임 내 크레딧 / 스토어 AI 고지란). GATE-PRE-07 5조건 매핑 완료.
    **잔여(S6.1 후속):** Runway 공식 약관 5항 원문 확인 — 부적합 시 로컬 Wan 2.2.
    가입·결제·약관 동의·영상 생성은 미승인.
- 특수 엔딩 5종의 세력 변주 (최소 Extinction 4계열)

---

## 5. 미해결 검토 포인트 (중요한 것만)

각 문서 말미에 검토 포인트가 있다. **판단이 남은 것 중 중요한 것:**

| 출처 | 쟁점 |
|---|---|
| `ai-design` §12-1 | **명문형 AI가 결단 임계로 마비**될 수 있음. 강제 결정 타이머 필요 |
| `ai-design` §12-2 | AI가 절단점만 노리면 예측 가능·단조로움. 노이즈 필요 |
| `ui-design` §9-2 | **인물 자동 배치가 편성 퍼즐의 재미를 가져가는가** |
| `ui-design` §9-4 | 복귀 브리핑 서술 템플릿 물량이 대규모 |
| `scenario-228-263` §9-1 | **현재는 공세 3회 실플레이다** — J7이 6회 중 3회만 실플레이로 줄였다(§4 ACT 9). 남은 쟁점 둘: **어느 3회를 고르는가**와 **그 3회 사이의 변주**. 피로도 자체는 §4.3 P2에서 측정한다 |
| `combat` §10-13 | 적벽 분기 A 27.4%는 **밀집 진형(연환) 성립을 전제**로 한다. 그 조건 자체의 발생 확률이 미정이라 27.4%는 상한이다 |
| `ending-variations` §6-1 | 특수 엔딩 5종의 세력 변주 미작성. 최소 **Extinction(절사) 4계열**은 필요 |
| `ai-media-pipeline` §4.8 | **명장 초상 — 원전 도상 대 재해석.** `traits` 는 외모를 거의 안 담는다(검토 5). 통념 12명(관우 수염 · 손권 벽안 등)을 원전 도상대로 뽑을지 이 세계의 재해석으로 둘지가 **발주자 아트 방향 판정** — 1차 생성 후 §4.6-4 검수 게이트에서 |
| `generals-stats` §8-2 | 여성 인물 통솔·무력이 대부분 10~30. 편성 다양성 제약. J2에서 ②·③ 추가 후에도 재발 없음을 확인 — 사서 기록 자체의 한계로 판단, 미해결 유지 |

**2026-08-23에 닫힌 것 — 설계 충돌 2건 + 문서 간 공백 2건**

| 출처 | 처리 |
|---|---|
| `combat` §10-12 (이릉협도 화공 ×3) | **연영도(Encampment Sprawl) 신설**(`combat.md` §5.5-b · V-20). 계수 ×3.0은 낮추지 않고 **공짜가 아니게** 했다 — 협도 진입이 아니라 **너머에서 반년을 못 이겼을 때** 열리며, 그 시계는 방어 지휘관이 돌린다(육손 ×2.0). **연영도가 피해를, 방어 지휘관이 발동 여부를 정한다** |
| `interludes` §9-2 (전화 회복 계수 부재) | **`region-power.md` §3.5 신설**(V-22). 체감형 `Δ = (0.95 − C) × r` · 기저 1.5% + 투자 최대 2.0%p. **상한 0.95는 새로 정한 값이 아니라 §3.1에 이미 있던 「전란을 겪지 않은 권역의 계수」**다. 부수로 `region-power` §6 검토 포인트 3(위 폭주/영구 폐허)과 §7 「복구 시스템 상세」도 닫혔다. 착지점: **사예 55년에 0.64**, 위가 0.8까지 올리는 데 최대 투자로도 **38년** |
| `combat` §10-11 (계략 성향 계수의 AI 대응 부재) | **`ai-design.md` §7.4 신설**(V-23). 계층은 **Tactical**이고 새로 배정할 것이 없었다 — §2 표가 이미 「전투 페이즈 지시 · 계략」을 적어 두었다. 산식은 `(기본 가중 + 0.4) × 성향 계수`(**가산 뒤 곱셈**). 부수로 **「누구의 성향인가」가 미정이었다**는 것이 드러나 `combat.md` §5.6에 **입안자 기준**을 명시했다 — 황개(절의 ×0.6)가 아니라 **주유(명사 ×0.9)**다. 실행자에 걸면 적벽 재현이 성향 단계에서 막힌다 |
| `world-state-setup` §10-1 (219 일극형 1.88배) | **배치가 아니라 검산이 틀렸다**(`world-state.md` §4.0-c · V-21). 「나머지」에 하한 미달 세력을 더한 것이 원인이며, **유효 세력만 세면 2.60배**다. 임계도 배치도 건드리지 않았다. 부수로 **263 일극형이 시작하자마자 조기 종료에 걸리는 것**을 발견해 12개월 유예 + 연합 상대 존재 조건을 추가했다 |

**J4(2026-08-23)에서 닫힌 것** — 아래 4건은 이 표에 남아 있었으나 이미 해소되었다.
`function-events` §9-2·§9-4(F-16·F-20, **의도적 유지**로 확정) · `scenario-219` §6-7(이릉 승리 허용 +
3중 제동) · `endings` §8-1(Division = **천명 순증 ≥ 0**). 상세: `docs/DECISIONS.md` V-10.

---

## 6. 알려진 함정

| # | 함정 |
|---|---|
| 1 | **`generals-150.md`의 앞뒤 충돌** — §12·13·14가 최종본 |
| 2 | 성계 수가 14→15→19로 늘었다. 오래된 문단에 옛 숫자가 남아 있을 수 있다 |
| 3 | 태양계 위치가 청주→요동→**형주**로 세 번 바뀌었다 |
| 4 | 프롤로그 범위가 184~190 → **184~189**로 단축되었다 |
| 5 | ~~표기 개정이 부분 적용 상태다~~ — **2026-08-22 전 문서 적용 완료.** `glossary.md`·`DECISIONS.md`는 신·구 대조/결정 기록 목적상 한자를 의도적으로 유지하므로 예외 |
| 6 | 수치는 대부분 미검증이다 |
| 7 | **동시 세션이 서로를 덮어쓴다** — 사고가 **양방향으로 두 번** 났다. `git commit`은 인덱스 전체를 커밋하므로 반드시 `git commit -- <경로>`로 경로를 명시한다. 문서 전역 눈금(스케일·범위)은 신설 전에 `docs/INDEX.md`를 확인한다 |
| 8 | **한 문서가 다른 문서의 미정 수치에 기대어 진행된 사례가 둘 있었다** — 전화 회복 계수(V-22) · 계략 성향 계수(V-23). **검토 포인트에 「없다」를 적기 전에 상대 문서를 한 번 더 볼 것** |
| **9** | ⚠ **「문서에 있는데 코드가 안 읽는다」** — 2026-08-25~28 에 **여섯 번** 나왔다(§0.1). 새 기능을 짜기 전에 **`core/` 를 grep 하고 `docs/` 를 grep 하라.** 대개 산식은 이미 있고 호출부만 없다 |
| **10** | ⚠ **「산식을 쓴 것」과 「배선한 것」은 다른 일이다** — `domestic.md` §7 이 훈련도·기술을 ✅ 로 적어 두고 실제로는 전투에서 한 번도 불리지 않았다. **문서의 완료 표시를 믿지 말고 호출부를 확인하라** |
| **11** | ⚠ **전대 규모가 두 번 내려갔다** — 100 → 40 (J3) → **28** (V-38). 함대 140 · 방면군 700 이 정본이다. 옛 값 40/200/1,000 이 남아 있을 수 있다 |
| **12** | ⚠ **적벽 전력비가 세 번 바뀌었다** — 1.76 → 1.54 → **2.20배** (V-37). 「1.54배는 안전한 우세가 아니다」 같은 **서술문**도 함께 낡는다 |
| **13** | ⚠ **회랑을 이름으로 판정하지 마라** — 15종 중 넷(진령삼도·이릉협도·기산도·남중산도)이 이름에 「회랑」이 없다. `GameData.is_corridor()` 가 정본이다 (V-36) |

---

## 7. 새 세션 시작 시

```
1. HANDOVER.md · PROJECT-TRACKER.md · CLAUDE.md · docs/DECISIONS.md 읽기
2. PROJECT-TRACKER.md §1~3 — 지금 무엇이 다음이고 무엇이 선행인가
3. docs/07-production/m0-report.md — 코드가 어디까지 되었는가
4. 작업할 영역의 개별 문서 읽기
5. **core/ 를 grep** — 「없을 것 같은 것」이 대개 이미 있다 (§6-9)
6. star-map.html 열어 지리 감각 잡기
```

### 기본 검증 4종 + 글리프 검산 — 무엇을 고치든 끝나고 돌린다

```
godot --headless --path . --import                      새 class_name 등록
godot --headless --path . --script tests/run_tests.gd   32섹션 375단언
godot --headless --path . --quit-after 300              화면 구동 오류 0
PYTHONIOENCODING=utf-8 python tools/validate_data.py    위반 0
```

서체 또는 UI 문자열을 바꾸면 아래를 **추가로** 돌린다. 한글 음절 11,172자를
임베드 서체가 직접 담는지 검사하므로 시스템 폴백에 기대는 두부를 헤드리스에서도 잡는다.
장식 기호의 시스템 폴백 경고는 안드로이드 실기에서 함께 육안 확인한다.

```
godot --headless --path . --script tests/verify_glyphs.gd
```

그리고 GUI 또는 실기에서 대표 문자열 `건안 십삼년 시월` · `형주성역` · `중부권`을
눈으로 확인한다. **두부는 엔진 오류가 아니므로 이 절차를 생략하지 않는다.**

Godot 콘솔 실행 파일은 `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe` 다.
GUI 실행 파일은 `C:\Tools\Godot\Godot_v4.7.2-stable_win64.exe` 다.
**GUI exe 는 stdout 을 삼킨다.**

수치를 건드렸으면 검산기도 함께 돌린다 — `verify_power` · `verify_budget` · `verify_chibi`.

**첫 질문 제안**

> **프리프로덕션 P0-01~P0-09 가 전부 완료됐습니다** (2026-09-01). 발주자가 개발 착수를
> 승인했고(`DECISIONS.md` V-65), 개발 착수 게이트 8개 계약이 전부 확정됐습니다
> (`preproduction-dev-gate.md` §8).
>
> **현재 단계 = D1 기반 안정화.** 첫 착수 묶음은 `A-01`(캠페인 저장 모델)·`A-03`(명령 판정
> 코어 이동)·`A-07`(테스트 신뢰성)이고, 셋 다 완료 기준·계약이 P0-09 게이트에 명시돼
> 있습니다 (§4.0):
> - `A-01` ← `preproduction-save-contract.md` §2·§3 (시드+명령 로그 · 경계 스냅숏 · 캠페인 재생 경로 신설)
> - `A-03` ← V-60 §8.1 (화면↔코어 갈라짐 5건의 정본 소유자 = core · 「UI·AI·재생 일치」)
> - `A-07` ← V-61 (단언 수 하한 664 · 실패 시험 격리 · 시험 5층)
>
> **어느 것부터 착수하시겠습니까?** 세 항목은 서로 독립적이라 병렬로 진행할 수 있습니다
> (`A-01`·`A-03`·`A-07` 모두 선행 없음). 상세 구현은 각각 별도 세션에서 합니다.
>
> **여전히 미착수:** 명장 초상 120 대량 생성(별도 승인) · Runway 가입/결제/영상 생성
> (S6.1 약관 선행) · L2 3D 실착수(L1 완성 S4 후) · G-08·G-09 설계(L1 완성 후).
# DEMO-RC-LT-02 — 적벽대전 단편 시나리오 시작·분기·엔딩 플레이 루프

- 완료 범위: Event 03·04·06·07 선택 기반 적벽 데모, 조건 분기, DEC-01 조기 종료, canonical manifest/active 전투 연결, 새 데모 경계 및 QA-03 자동 수용.
- 미완료 범위: Windows 1600×900 GPU 및 물리 Tab/Shift+Tab/Enter/Space/Esc 실기 검수, 그 뒤 최종 PASS/push.
- 다음 추천 작업: 전용 Windows GUI 수용을 마친 뒤 이 Task를 경로 지정 커밋·push로 마감한다. C-01/C-02/전체 G-07로 확대하지 않는다.
