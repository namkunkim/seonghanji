# DEMO-RC-LT-03 — 적벽 전야 플레이어 함대 수동 집결 및 개전 연결

## 문제와 경계

이전 데모는 manifest가 적용된 뒤 조조와 손권 참가 함대 모두에 이동 명령을 자동으로
발행했다. 그 결과 플레이어는 사건 선택 직후 적벽 전투로 넘어가며, 기존 함대 이동 UI를
사용할 기회가 없었다.

이 계약에서 `Campaign`은 참가자와 도착을 권위 있게 판정하고, `Main`은 읽기 전용
집결 상태를 표시한 뒤 기존 `CMD_FLEET_MOVE` 경로만 호출한다. UI는 위치, 도착 tick,
manifest 참가자 또는 battle 상태를 기록하거나 주입하지 않는다.

## 참가자 소유권과 이동

- 조조 측 비플레이어 참가 함대는 시나리오/AI 파생 이동으로 `RGN-04`, 구지 `SYS-13`에
  자동 집결한다. 이 이동은 player origin으로 기록하지 않는다.
- 손권 측 플레이어 참가 함대는 명령 대기 상태로 남는다. 플레이어가 홈 화면에서 함대를
  선택하고 기존 이동 패널로 `RGN-04`를 지정할 때만 정상 이동 명령이 만들어진다.
- manifest는 한 번만 queue되며, 반복 continue는 현재 상태를 반환하고 이동을 중복하지
  않는다.

## Deployment state

`Campaign.scn03_red_cliff_deployment_state()`는 UI 전용 read-only Dictionary를 반환한다.
필수 공통 필드는 `available`, `battle_id`, `target_region_id`, `target_system_id`,
`target_name`, `player_faction_id`, `player_fleet_ids`, `player_fleets`, `ai_fleets`,
`player_ready`, `ai_ready`, `all_ready`, `battle_status`다.

각 player fleet 행은 `fleet_id`, `display_name`, `owner`, `current_system_id`,
`destination_region_id`, `arrival_tick`, `status`를 제공한다. status는 `awaiting_order`,
`en_route`, `arrived`, `wrong_destination`, `unavailable`만 허용한다.

## 개전과 저장·재생

pending → active는 canonical manifest가 있고, 모든 필수 참가자가 생존한 채 실제
`SYS-13`에 도착했으며 Campaign이 종료되지 않았을 때만 허용된다. 이동 명령의 존재만으로
개전하지 않는다. 기존 manifest arrival 판정이 이 권위를 유지한다. manifest와 정상 명령
로그, fleet 위치/목적지/arrival tick은 저장·복원하고, AI/시나리오 파생 이동은 같은 입력에서
결정론적으로 재도출한다. active 전이 뉴스와 배너 데이터는 canonical transition의
exactly-once 계약을 따른다.

## 범위 제외

일반 내정 명령 확장, 범용 알림 정책, 전체 저장·설정 UI, G-07 엔딩/튜토리얼, 다세력
플레이, 새 전투 화면, 3D 자산/지도, 전투 밸런스 및 CI 재설계는 포함하지 않는다.

## 검증 결과

구현 완료 후 집중 코어·제품 E2E·기존 적벽/함대 이동·저장·재생·전체 회귀와 Windows
1600×900 수용의 실제 실행 결과를 관리 기록에 고정한다.
