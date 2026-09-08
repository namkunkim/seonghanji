> Task ID: Q-05-04 — GitHub Actions 품질 게이트 구성
>
> 공식 제목: GitHub Actions 품질 게이트 구성
>
> 상태: 구현 완료 · 원격 실행 수용은 Q-05-QA-01에서 기록

# Q-05-04 GitHub Actions 품질 게이트

워크플로 [`quality-gate.yml`](../../.github/workflows/quality-gate.yml)는 `pull_request`, `main` push 및 수동 실행에서 단일 로컬 계약 실행기 `tools/ci/run_quality_gate.ps1`를 호출한다. CI가 시험 목록을 별도로 복제하지 않으므로 로컬/원격의 순서와 집계 종료 코드는 같은 실행기에 의해 결정된다.

## 실행 계약

- Windows hosted runner에서 Godot **4.7.2 stable console** zip을 공식 Godot release에서 내려받아 headless 실행한다.
- 실행기에 Godot 경로와 로그 디렉터리를 명시적으로 주입한다.
- `GODOT_USER_DATA_DIR` 및 `QUALITY_GATE_LOG_DIR`는 runner workspace의 `out/` 아래 쓰기 가능한 임시 경로다. `user://` 저장 시험을 건너뛰지 않는다.
- job은 30분 timeout을 가지며, 같은 PR/ref의 이전 실행은 취소한다.
- 권한은 `contents: read`뿐이다.
- checkout/upload-artifact는 각각 검증된 commit SHA로 고정했다. 생성한 `out/`, 사용자 저장, 로그는 artifact로만 14일 보존하고 git에는 추가하지 않는다.

집계 실행기가 수행하는 순서는 다음과 같다.

1. Godot 버전 확인 및 import
2. 전체 단위시험
3. 잠금 ruleset 100회 캠페인
4. 국력 · 예산 · 적벽 · 글리프 검산
5. 캠페인 저장·복원 및 명령 로그 재생
6. A-05 진형 집중 시험
7. G-10 E2E 회귀

개별 시험 실패는 실행기가 기록하고 실행 가능한 후속 시험을 계속 실행한 뒤, 하나 이상 실패면 1을 반환한다. GitHub step은 그 종료 코드를 그대로 job 결과로 사용한다. `always()` artifact 단계는 실패 뒤에도 앞선 시험의 로그를 남긴다.

## 원격 상태

이 문서는 workflow 구성 증거다. push 뒤 GitHub Actions가 실제로 실행되었는지와 green 결과는 추정하지 않으며 Q-05-QA-01 수용 기록에 commit SHA, run URL/결과를 별도로 남긴다.
