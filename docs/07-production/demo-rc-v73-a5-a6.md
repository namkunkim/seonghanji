# DEMO-RC V-73 A5·A6 — 진형 기동 %의 이동 반영 · 무기 능력의 현재 편성 기준

> 상위: `docs/07-production/battle-core-upstream-verdict.md` A5·A6 · `DECISIONS.md` V-73
> 작성일: 2026-10-04 · 상태: **구현 완료 — 결정적 기대값 1건 갱신** · 개정 2026-10-04: §6 미리보기 기동 % 내역, §7 자원 용량 상한 축소(검토 포인트 2 해소, 사용자 확정)

판정문이 「본편 고침 (코드, 후속 작업)」으로 남긴 두 항목을 코드로 닫는다.
수치(진형 기동 %, 무기 사거리)는 그대로이고 **어디에 적용하느냐**만 바뀐다.

---

## 1. A5 — 진형 기동 %를 이동에 반영

### 문제

`RedCliffsMovementResolver.effective_speed()`는 지휘 초과 불이익(`formation_draft.squadron_metrics().mobility_percent`)만
속도에 썼다. 진형 규칙(`data/red-cliffs-formation-rules.json`)의 `mobility_percent`는 snapshot에만 실리고
어디에도 소비되지 않았다. 그런데 같은 규칙의 `application_timing`은
`applied_atomically_at_resolution_start_before_movement_detection_and_fire`다 — 이동 **전에** 적용되는 값이다.

### 결정 — 결합 방식

```
기동 % = 지휘 초과 불이익 %(G3) + 진형 기동 %(변경 효율 반영값, G3-03)
유효 속도 = max(1, floor(최저 기본 속도 × (100 + 기동 %) / 100))
```

| 선택지 | 판정 | 근거 |
|---|---|---|
| **가산 후 한 번 내림** | **채택** | 두 값 모두 「기본 속도 대비 %」라는 같은 눈금이다. 사격 쪽도 진형 방어 %와 방향 방어 %를 더한다(`total_defense_percent`) — 같은 관례. 내림은 한 번뿐이라 이중 반올림 오차가 없다 |
| 곱셈(각각 내림) | 기각 | 내림이 두 번 생겨 같은 합계 %라도 순서에 따라 1씩 어긋난다. 데모 수치가 ±15% 이내라 곱셈의 교차항(≤1.5%p)은 의미 있는 차이를 만들지 않는다 |
| 진형 %만 쓰고 지휘 불이익 무시 | 기각 | G3-03R 계약(`penalty_application.mobility_percent = active_g4_movement`)을 깨뜨린다 |

- **진형 % 값은 `modifier_snapshots().modifiers.mobility_percent` — 효율이 반영된 값이다.** 지휘 초과 상태에서
  진형을 바꾼 턴은 `modifier_effectiveness_basis_points`만큼 줄고 0 쪽으로 자른다(G3-03R의 `_scaled_modifiers`).
  기본값을 그대로 쓰지 않는다.
- **하한 1** 은 기존 그대로다. 합계가 −100% 이하가 되어도 정지하지 않는다.

### 어느 진형 상태를 쓰는가

| 경로 | 사용하는 진형 | 이유 |
|---|---|---|
| `resolve_turn` 이동 판정 | `formation_result.formation_state` — 이번 턴 해결 시작에 적용된 진형 | 판정 순서가 진형 → 이동이다 |
| `resolve_turn` 귀환 계획(G6-04) 속도 | 같음 | 같은 턴의 이동과 같은 속도를 써야 귀환 ETA가 맞는다 |
| `movement_preview` · 귀환 상태 표시 | **명령 초안의 진형**(초안이 없으면 현재 진형)을 `planned_mobility_percent()`로 미리 산출 | 초안 진형은 해결 시작에 적용되므로 미리보기가 실제 판정과 일치해야 한다 |

진형 상태는 진형 판정기가 권위다. 이동 판정기는 진형 %를 **인자로 받기만** 한다
(`effective_speed(id, formation_mobility_percent = 0)`, `resolve_orders(..., formation_mobility = {})`).
인자를 생략하면 0 — 이동 판정기 단독 시험(G4-02)의 기존 계약이 유지된다.

속도 receipt에 `command_mobility_percent` · `formation_mobility_percent`를 추가했다.
`mobility_percent`는 **실제 적용된 합계**다(무진형 시 기존 값과 같다).

## 2. A6 — 무기 능력을 현재(피해 반영) 편성으로

### 문제

`RedCliffsWeaponAllocation`은 초기화 때 받은 setup 편성으로 가용 무기·사거리·플랫폼을 계산했다. G8-00 계약은
「원본 applied setup/composition은 불변이며 별도 effect state만 변한다」이므로 setup 편성은 **영원히 무손실**이다.
그래서 조조 전대가 강습모함(SHP-01) 2척을 모두 잃어도 전열 사격은 SHP-01 플랫폼 · 사거리 190 · 함재기 출격
비용(`carrier_platform_shot_cost`)을 계속 썼다.

### 결정

- **현재 편성의 출처는 G8-00 effect state의 `current_composition`이다.** 다만 이 값은 함종별 합산이라
  `mission_equipment_id`가 없다. `RedCliffsCombatEffects.current_compositions(state)`가 생존 척수를 setup 성분
  모양(장비 포함)에 setup 순서대로 되돌려 붙인다. setup 원본은 여전히 건드리지 않는다.
- `available_categories` · `interception_policy` · `resolve_orders`가 `current_compositions`를 받는다. 생략하면
  setup 편성 = 무손실로 본다(기존 단독 시험 계약 유지).
- **같은 턴 사격은 피해 전 편성**이다. G8-00이 같은 턴 일반 사격·연쇄 폭발을 pre-damage snapshot으로 산출하는
  것과 같은 원칙이다. `resolve_turn`은 턴 시작 시의 effect state로 능력을 계산한다.
- **피해 확정 뒤** `refresh_capabilities()`가 무기 배분 상태를 현재 편성에 맞춘다. 다음 턴 초안은 이 상태에서 시작한다.
  - 가용 무기 종류가 그대로인 전대는 바꾸지 않는다(사거리·플랫폼만 정책 산출 시 달라진다).
  - 잃은 무기 종류의 비율은 남은 가용 무기에 **이전 비율대로** 다시 나눈다. 남은 쪽 비율이 모두 0이면 균등.
    정규화는 기존 `floor_then_fraction_desc_weapon_id_asc`를 그대로 쓴다.
  - 가용 무기가 0이면 자동 사격 보류(G4-05의 「무장 0 전대」 규칙과 같다).
  - 변경은 턴 로그 `weapon_capability_events`에 `weapon_capability_changed`로 남긴다. 공개 receipt는 바꾸지 않았다.
- `resolve_turn`은 제출된 명령을 `conform_orders()`로 현재 편성에 맞춘 뒤 엄격 검증한다. 정상 흐름에서는
  초안이 이미 갱신된 상태에서 시작하므로 아무것도 바뀌지 않는다. 시험처럼 명령 제출 뒤 effect state가
  바뀐 경우에만 작동한다. **setup에서도 쓸 수 없던 무기에 비율을 둔 명령은 고치지 않고 그대로 거부한다.**
- 요격 판정기의 무기 정책 검증(「capability는 권위 규칙과 같아야 한다」)도 현재 편성 기준 정책과 비교한다.

### 범위 밖 (바꾸지 않은 것)

- **전투 자원 용량**(`red_cliffs_combat_resources.gd`의 탄약·에너지·함재기 출격 용량)은 여전히 초기 편성으로 정한다. *(개정: §7에서 상한 축소로 바뀌었다.)*
  함재기 출격 **비용**은 선택된 플랫폼으로 정해지므로 SHP-01을 잃으면 SHP-04로 쏘며 출격을 쓰지 않는다 —
  판정문이 지적한 「상실 뒤에도 출격」은 이것으로 닫힌다. 남은 용량 자체를 줄일지는 아래 검토 포인트 2.
- 장수 결과(G8-04)·승패 판정(G8-01~03)은 건드리지 않았다.

## 3. 잠복 결함 하나

`_validate_allocations`의 오류 문구 `"사용 불가 무기는 0%여야 합니다: %s"`가 `%여`를 형식 지정자로 읽어
**스크립트 오류로 중단**했다. 지금까지는 가용 무기가 setup에서 바뀌지 않아 도달할 수 없던 경로였다. `0%%`로 고쳤다.

## 4. 결정적 기대값 갱신

| 시험 | 이전 | 이후 | 근거 |
|---|---|---|---|
| `test_demo_rc_g4_02_movement.gd` 「partial live position persists after resolution」 | `[450, 590]` | `[457, 590]` | `RC-LIU-SQ-01`의 현재 진형은 FRM-01 어린진(+5%). 예산 floor(140×1.05)=147, 출발 310 → 457 |

같은 시험의 이동 판정기 단독 기대값(속도 140, 예산 140, 예상 위치 450)은 진형 인자를 넘기지 않으므로 그대로다.

## 5. 검증

신규 `tests/test_demo_rc_v73_a5_a6.gd` — 속도 공식(가산·단일 내림·하한), 계획/해결 진형 % 일치, 전투 미리보기와
해결 위치 일치, 장비 보존 현재 편성, 강습모함 상실 시 전열 사거리 190→180 · 플랫폼 SHP-01→SHP-04, 갱신·정규화·
자동 사격 보류, 명령 맞춤과 위조 거부, 요격 정책 권위.

전체 `tests/test_demo_rc_*.gd` 전후 비교 결과는 `HANDOVER.md` 상단 기록을 본다.

## 6. 이동 미리보기 — 기동 % 내역 표시 (후속, 2026-10-04)

미리보기만 보면 예산 147이 어디서 왔는지 알 수 없었다. 코어 receipt에 내역을 싣고 UI는 옮기기만 한다
(`demo-rc-g4-02-movement.md`의 「UI는 코어 receipt만 표시하고 계산하지 않는다」 원칙).

- `RedCliffsMovementResolver.movement_preview` receipt에 `base_speed` · `mobility_percent` · `command_mobility_percent` ·
  `formation_mobility_percent`를 추가했다. 값은 `effective_speed()` receipt 그대로다.
  `RedCliffsTurnBattle.movement_preview`는 이 receipt를 감싸기만 하므로(연료 제한 고속정 경로 포함) 그대로 전달된다.
- 표시(`red_cliff_turn_battle_view.gd` `_speed_preview_text`): `속도 140 · 기동 +5% (지휘 +0% · 진형 +5%) → 유효 147`.
  합계·내림은 코어 값이다. 일반 미리보기와 연료 제한 미리보기 모두에 한 줄로 들어간다.
- 진형 %는 **명령 초안의 진형** 기준이다(§1 「어느 진형 상태를 쓰는가」). 초안에서 진형을 바꾸면 내역도 바로 바뀐다.

## 7. 함선 손실 시 전투 자원 용량 — 상한 축소 (검토 포인트 2 해소, 2026-10-04 사용자 확정)

### 결정

```
새 용량 = min(기존 용량, 현재 편성으로 다시 산출한 용량)
현재량 = min(현재량, 새 용량)
```

| 선택지 | 판정 | 근거 |
|---|---|---|
| **상한 축소** | **채택** | G8-00은 함별 상태를 추론하지 않는다(`never infer per-ship hull`). 잃은 함선이 탄약을 얼마나 쓴 상태였는지 알 수 없으므로, 「손실 함선의 탄약이 남는」 어색함만 막고 그 이상은 가정하지 않는다 |
| 비례 감소 | 기각 | 탄약이 함선마다 고르게 남아 있었다고 가정한다. 이미 많이 쏜 전대를 한 번 더 깎는 이중 불이익이 생긴다 |
| 유지 | 기각 | A6 뒤로 출격 **비용** 문제는 닫혔지만, 강습모함을 모두 잃은 전대가 출격 용량 8을 계속 보유·회복하는 표시상 모순이 남는다 |

- 용량 산출식은 초기화와 같다(`_capacities`): 에너지·열 = 기본값 + 함선 수 × 함당 값, 탄약·특수 = 플랫폼 수 × 플랫폼당 값,
  출격 = SHP-01 수 × 4. 현재 편성은 A6과 같은 `RedCliffsCombatEffects.current_compositions()`(장비 보존)다.
- **용량은 줄기만 한다.** 편성은 늘지 않지만, 방어적으로 `min(기존, 재산출)`을 쓴다. 같은 편성으로 다시 적용하면 아무것도 바뀌지 않는다.
- 열은 「누적량」이다. 열 용량이 줄면 현재 열을 새 용량으로 자른다 — 남은 열 여유가 0이면 열 비용이 있는 사격은 보류된다(기존 `overheat` 규칙).
- **적용 시점:** 피해 확정(G8-00) → 무기 능력 갱신(A6 `refresh_capabilities`) → **자원 용량 축소** → 고속정 보급(G6-03).
  보급은 줄어든 용량까지만 채운다. 같은 턴 사격은 이미 피해 전 상태로 자원을 소모했다.
- 변경은 턴 로그 `resource_capacity_events`에 `resource_capacity_reduced`(`CAP-<턴>-<전대>`)로 남긴다. A6의
  `weapon_capability_events`와 같이 공개 receipt는 바꾸지 않았다. 자원 패널은 줄어든 상태를 그대로 보여 준다.

### 결정적 기대값

기존 시험 기대값은 바꾸지 않았다. `tests/test_demo_rc_*.gd` 전후 비교에서 기존 시험 결과·로그가 모두 같았다
(결정적 기대값 갱신 0건). 검증은 `HANDOVER.md` 상단 기록.

### 시험

신규 `tests/test_demo_rc_v73_preview_capacity.gd` — 미리보기 내역(현재·초안 진형, 연료 경로), 상한 축소(출격 8→0,
에너지·열 용량 −함당 값, 상한 아래 현재량 보존, 열만 상한으로 자름), 포격 플랫폼 전멸 시 탄약 0, 멱등·비증가,
잘못된 편성 거부, 턴 해결 통합(턴 로그 기록).

---

## 검토 포인트

| # | 쟁점 | 메모 |
|---|---|---|
| 1 | 진형 + 지휘 불이익 가산이 밸런스상 맞는가 | 장사진(+15%)으로 지휘 초과(−5~−20%)를 상쇄할 수 있다. 수치는 미검증(CLAUDE.md §5 함정 2) |
| 2 | ~~함선 상실 시 전투 자원 용량(탄약·출격 용량)도 줄일 것인가~~ | **2026-10-04 사용자 확정: 상한 축소.** 용량은 현재 편성으로 재산출해 줄이고 현재량은 새 상한을 넘을 때만 자른다. 비례 감소·유지는 기각. §7 |
| 3 | 손실 배분이 `ship_type_id` 오름차순이라 SHP-01(강습모함)이 항상 먼저 잃는다 | G8-00 규칙 그대로다. A6로 이 순서가 화력에 직접 영향을 주게 되었다 |
| 4 | `weapon_capability_changed`를 공개 receipt·UI에 노출할지 | 지금은 턴 로그에만 있다. 무기 패널은 갱신된 가용 무기를 그대로 보여 준다. §7의 `resource_capacity_reduced`도 같은 처지다 |
| 5 | 자원 상한 축소가 밸런스상 맞는가 | 출격 용량은 강습모함 상실과 함께 0이 된다. 열 용량이 줄면 손상 전대의 연속 사격이 빨리 막힌다. 수치 미검증(CLAUDE.md §5 함정 2) |

## 미작성 항목

- [x] A5 진형 기동 % 이동 반영 (코드 + 시험)
- [x] A6 무기 능력 현재 편성 기준 (코드 + 시험)
- [x] 검토 포인트 2 — 자원 용량의 손실 반영 여부 결정 (상한 축소, §7)
- [x] 이동 미리보기 UI에 기동 % 내역(지휘·진형) 표시 (§6)
