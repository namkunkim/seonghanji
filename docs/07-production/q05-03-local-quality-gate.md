# Q-05-03 — 로컬 통합 품질 게이트 실행기

Task ID: Q-05-03
공식 제목: 로컬 통합 품질 게이트 실행기 구축

실행:

```powershell
powershell -ExecutionPolicy Bypass -File tools/ci/run_quality_gate.ps1
```

`-GodotBin`으로 다른 Godot 실행 파일을 주입할 수 있고, `-LogDirectory`로 로그·요약 위치를 지정할 수 있다. 기본 Godot는 `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`다. CI는 `GODOT_USER_DATA_DIR`을 제공할 수 있으며, 실행기는 이를 `APPDATA`/`LOCALAPPDATA`로 적용해 모든 `user://` 파일을 격리한다.

순서는 version → import → unit → locked 100 campaign → power → budget → chibi → glyphs → save/restore → replay → A-05 → G-10이다. 실행기는 개별 실패 뒤에도 모든 실행 가능한 단계를 수행하고, 시험명·시작/종료 시각·시간·종료 코드·PASS/FAIL·로그를 `summary.json`과 콘솔에 남긴 뒤 하나라도 실패하면 exit 1을 반환한다.
