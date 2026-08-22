# SEONGHANJI: MANDATE

> SEONGHANJI: MANDATE — a mobile grand strategy game that reimagines China's Three Kingdoms
> era as an interstellar civil war, where corridors, supply lines, and the Mandate of Heaven
> decide who deserves to rule.
>
> Guandu is not guaranteed to Cao Cao. Chibi may never happen. History is not replayed here —
> it is generated from pressure, alliance, and the choices you make.

**성한지: 천명** — 후한 말 삼국시대를 우주 SF로 옮긴 모바일 전략 시뮬레이션.

현재 이 저장소에는 **기획 문서**만 있습니다. 코드는 아직 없습니다.

---

## 시작하기

| 순서 | 파일 |
|---|---|
| 1 | **[`HANDOVER.md`](HANDOVER.md)** — 프로젝트 현황과 다음 작업 |
| 2 | [`CLAUDE.md`](CLAUDE.md) — 작업 규칙 · 불가침 원칙 · 표기 규칙 |
| 3 | [`docs/00-overview/design-overview.md`](docs/00-overview/design-overview.md) — 통합 기획서 |
| 4 | [`docs/assets/star-map.html`](docs/assets/star-map.html) — 인터랙티브 성계 지도 (브라우저로 열 것) |

---

## 이 게임이 다른 삼국지 게임과 다른 점

**① 역사를 재현하지 않고 생성한다**

관도는 조조가 반드시 이기지 않는다. 적벽은 반드시 일어나지 않는다.
황제 시해는 게임오버가 아니다. 손유 동맹은 자동으로 성립하지 않는다.

이벤트는 인물의 이름이 아니라 **압력의 구조**로 정의된다.
「관우의 북벌」이 아니라 **「최강자의 관문을 향한 도박적 공세」**다.
219년에 관우가 없어도 누군가는 관문을 향해 도박을 건다.

**② 정통성이 자원이다**

천명(Mandate)은 수치이며, 외교·등용·민심·반란·**전투 사기**에 직접 작용한다.
명분 없는 군대는 같은 함선 수로도 먼저 무너진다.

정복은 천명을 깎고, 천명을 지키면 정복이 느리다. **둘은 서로를 갉아먹는다.**

**③ 지형이 곧 게임 템포다**

각 주(州)가 하나의 성계이고, 회랑은 통과가 강제되는 험지다.
회랑 돌파에는 **실제 3시간 45분**이 걸린다 — 게임 내로는 3개월이며, 한중 공방전의 실제 소요와 일치한다.

**시간은 판매하지 않는다.** 속도는 항로 장악·세력 특성·인물 특성의 결과다.

**④ 인류의 고향은 형주에 있다**

지구는 「구지」라 불리며 형주 성역에 속한다. 국력은 형주 전체의 2%도 되지 않는다.
그런데 남북 대항로가 교차하는 천하의 목구멍이다.

적벽은 지구 궤도에서 벌어진다.

---

## 문서 구성

| 디렉터리 | 내용 |
|---|---|
| `00-overview/` | 통합 기획서 · 용어 대조표 |
| `01-world/` | 성계 지도(19성계 · 45권역 · 15회랑) · 권역 국력 |
| `02-characters/` | 명장 150 · 일반 무장 256 · 성향 태그 · 스탯 |
| `03-systems/` | 전투(5페이즈) · 부분 점령 · 외교 · 시간/수익 모델 |
| `04-campaign/` | 세계 상태 · 기능 이벤트 40종 · 엔딩 · 시나리오 6개 Timeline |
| `05-narrative/` | 프롤로그 · 엔딩 후일담 |
| `06-tech/` | AI 설계 · UI 설계 |
| `assets/` | 인터랙티브 성계 지도 (HTML) |

---

## 목적별 읽는 순서

**세계관·설정**
`design-overview` → `star-map` → `prologue`

**인물**
`generals-150` (§12·§13·§14가 최종본) → `officers-256` → `dispositions` → `generals-stats`

**시스템·밸런스**
`combat` → `time-and-monetization` → `region-power` → `partial-occupation`

**캠페인·서사**
`world-state` → `function-events` → `scenario-190` → … → `endings` → `epilogues`

**구현**
`ai-design` → `ui-design`

---

## 주의사항

- `02-characters/generals-150.md`는 **§12·§13·§14가 최종본**입니다. §1~6은 작업 순서대로 누적된 기록이므로, 앞뒤가 충돌하면 뒤를 따릅니다.
- 각 문서 말미의 **검토 포인트**에 미해결 쟁점이 정리되어 있습니다. **지우지 마세요.**
- `CLAUDE.md` §2의 **불가침 원칙 7조**는 재론하지 않습니다.
- 수치는 대부분 **미검증**입니다. 밸런스 테스트 전입니다.

---

## 상태

| 영역 | 상태 |
|---|---|
| 세계관·지리 | 설계 완료 |
| 인물 | 명단·성향·스탯 완료 (150인) |
| 시스템 | 설계 완료 (전투·외교·점령·시간·수익) |
| 캠페인 | 6개 시나리오 Timeline 완료 |
| 서사 | 프롤로그 · 엔딩 10종 |
| AI · UI | 설계 초안 |
| **코드** | **미착수** |
