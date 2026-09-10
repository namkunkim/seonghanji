# 적벽 데모 최종 기술 감사 — run33 읽기 전용 판정

> 감사 시각: 2026-09-10 07:46~07:47 KST
> 감사자: GPT-5.6 Terra (읽기 전용)
> 대상 후보: `C:/WorkSpace/Seonghanji/tmp/demo-rc-fin-20260909`
> 실행 기록: `C:/WorkSpace/Seonghanji/tmp/demo-rc-fin-qa-run-20260910-33/quality-gate/summary.json`
> 최종 판정: **자동 게이트 기록은 통과로 확인; 현재 후보와 run33의 동일성은 미확인. 따라서 최종 기술 수용/릴리스 PASS는 선언하지 않는다.**

## 범위와 제외

- 이 문서는 코드 변경, 시험 재실행, 프로세스 조작, commit 없이 작성한 읽기 전용 감사다.
- 후보 worktree의 HEAD는 격리 기준 `111d0f2a6e8cfbf98000ae3a88eefcfc60296bd5`다. 후보는 미커밋 변경을 포함한다.
- 모든 `out/` 폴더의 내용은 열람·해시·증거·판정에서 제외했다.
- [중간 QA 증거](demo-rc-fin-qa-evidence.md)는 01:57 KST 이전 후보의 해시 기록이다. run33의 최종 후보 manifest가 아니므로 이 문서에서는 과거 증거로만 취급한다.

## run33 종료 기록 확인

`summary.json`은 2026-09-10 02:13:13 KST에 존재하며 7,791 byte다. 21개 모든 stage에 `Started`, `Ended`, `ExitCode: 0`, `TimedOut: false`, `Status: PASS`가 있다. summary가 지시하는 21개 실제 stage log도 모두 존재하며 빈 파일이 아니다.

별도의 `*.exitcode.txt` 또는 stage별 종료 파일은 run33 디렉터리에 없다. 따라서 이 감사에서 인정하는 종료 근거는 summary의 명시적 종료 시각·exit code와 해당 stage log의 실출력이다. summary와 log 모두 없는 단계는 없다.

| 구분 | stage 수 | 확인 결과 |
| --- | ---: | --- |
| import | 1 | PASS, exit 0, timeout 없음 |
| 기본 회귀·검증·저장·재생·A-05·G10 | 10 | 모두 PASS, exit 0, timeout 없음 |
| 적벽 데모 집중 회귀 (LT02/03, 권한, QA01/03/04, G7/8, QA02) | 10 | 모두 PASS, exit 0, timeout 없음 |
| 합계 | 21 | **21 PASS / 0 non-PASS / 0 non-zero exit / 0 timeout / 0 missing log** |

로그의 구체적 자동 결과에는 unit 701/0, campaign locked 3/3, save/restore 73 passed·2 skipped·0 failed, replay 29/0, A-05 93/0, G10 E2E 24/0, LT02 loop 38/0, LT03 55/0, player authority 64/0, QA03 107/0, QA04 33/0, G7 save/load 15/0, G8 16/0, QA02 native input 28/0가 포함된다. QA01은 `0 failures`로 기록됐다.

모든 stage log에는 Godot의 Windows root certificate store 읽기 경고가 있다. import log에는 그 경고에 수반된 `ERROR: Condition` 4건도 있다. 이는 exit 0/summary PASS와 함께 기록된 환경 진단이며, 이 감사는 이를 제품·GPU·사람 검수 PASS로 승격하지 않는다. Parse Error나 SCRIPT ERROR 표식은 stage log에서 찾지 못했다. QA04/G7/G8에는 `ObjectDB instance was leaked at exit` 경고가 남아 있어, 자동 assertion 통과와 별개로 후속 기술 점검 대상이다.

## 후보 동일성(해시) 대조

과거 중간 증거에 고정된 16개 지정 파일을 **현재** 격리 후보에서 다시 SHA-256 계산했다. 10개는 일치하고, 다음 6개는 불일치한다.

| 파일 | 과거 증거 SHA-256 | 현재 후보 SHA-256 |
| --- | --- | --- |
| `core/campaign.gd` | `5EBF83E3347AE4F8F5D97A27F1FFA268E3FCBEBA8F0769C1E3BAB90978FE1082` | `7D71B6BE80539D40B051508CC836C9E23AF53B89771C19465E806698C4573CFA` |
| `scripts/Main.gd` | `BE949058B80DF41A35E8211D36EF955AEAC1A4F097FA4781DE08CC88B34953BA` | `184EB3BBB664F1080B546DB1360F7A9250BF970AAC6B0C2744A42A3DF4C69929` |
| `tests/test_demo_rc_fin_player_authority.gd` | `BA8CA1A083EF6292179F2EE591FA43F03FAD9E892B388076B859755320163FF3` | `8CD0E432A64D8DB7BF6E88AA97DF770F113C899B3D0F4A5C053DB272648CAAE2` |
| `tests/test_demo_rc_qa01_e2e.gd` | `81F1DD7FCE0BD5E7E4175C0D26A0DE805211367614E0AA6ED4331D62C0E34030` | `2B5E81D890CCB3AA5097AFB55375CDB905F34B276B3EF7E415221105D7F37D8B` |
| `tests/test_demo_rc_qa03_full_scenario_loop.gd` | `AE33EFB278C1283DC4CE13DC1D0DB8598D03E6465A21A9E9F4AB782D75622842` | `1B99F76B597CD18853C5BA340748F558981CBC5D83CA0597D935F8A473548177` |
| `tools/ci/run_quality_gate.ps1` | `A1D0DCCF928AE63BC2CF3D35F37E03AE5FB7B3AF712C9FC23EA663DA2DD7824D` | `6BDDDAC8C82032ACCF10D5D78D7CCF2B03442F717EFED68BA867E9140DDA4531` |

run33 자체에는 후보 파일 manifest 또는 SHA-256 기록이 없다. 그러므로 위 불일치는 “현재 후보가 01:57 중간 증거와 다르다”는 사실은 입증하지만, run33가 현재 후보를 실행했는지 또는 다른 후보를 실행했는지를 판별하지 못한다. run33의 21 PASS를 현재 후보의 최종 게이트 PASS로 수용할 수 없는 이유다.

## 체크리스트에 대한 제한적 제안

동일 후보 manifest를 run 기록에 남기는 것이 선행되면, 자동시험만으로 최소한 검토·수용 가능한 체크 항목은 다음과 같다.

| 체크 ID | 자동 근거 | 한계 |
| --- | --- | --- |
| G2-02 | player authority 64/0 | 실제 GPU 화면의 역할 표시는 별도 |
| G4-07 | QA03 107/0 및 LT02/03 회귀 | 사람의 집결 이해·정상 배속 시간은 별도 |
| G5-06 | QA01 0 failures, QA03 107/0 | 사람 관찰과 시각적 전투 수용은 별도 |
| G7-03 | G7 save/load 15/0, save/restore 73/0 | 앱 종료 후 모든 경계와 구버전 정책은 별도 |
| G9-02 | whole gate가 LT02·LT03·QA03·QA04·권한·저장·입력을 포함 | G9-01의 깨끗한 checkout, G9-03~07과 최초 사용자 수용은 자동으로 대체 불가 |

위 다섯 항목도 현재는 hash-bound run 증거가 없으므로 `미수용`이다. 이 표는 자동 수용 가능한 최소 범위 제안이며 체크박스를 변경하지 않는다.

## 남은 수용 불가 항목

- Windows GPU 1600×900 화면, OS 물리 입력, 사람의 무힌트 완주, 실제 ×4 완결 시간, 최소 사양 성능은 PASS가 아니다.
- export template·실행 패키지·패키지 해시가 없어 G10은 차단/미수용이다.
- 최종 수용에는 run summary와 같은 시점에 생성한 후보 manifest(소스·시험·runner SHA-256), 실행 환경, 패키지 식별자를 연결해야 한다. 이후 변경은 영향받는 자동 수용을 다시 열어야 한다.
