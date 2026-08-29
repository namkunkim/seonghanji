# SEONGHANJI — AI 미디어 제작 가이드 v0.1

> 상위: `docs/07-production/asset-ledger.md` · `DECISIONS.md` **V-43 · V-44 · V-45**
> 작성일: 2026-08-30 · 최종 갱신: 2026-08-30 · 상태: **규격·시드 규칙 확정 — 모델 시험생성 착수 전**
>
> **이 문서가 답하는 것:** 초상 131장 · 배경 · BGM 6트랙을 **실제로 어떻게 만드는가.**
> 무엇을 만들지는 `asset-ledger.md`가 정했다. **이 문서는 그 다음이다.**

---

## 1. 만드는 것과 만들지 않는 것

**「모든 미디어를 AI로」에는 넷이 들어가지 않는다** (V-44).

| 대상 | 물량 | 방법 |
|---|---|---|
| **명장 초상** `ART-C001~120` | 120 | **AI — 개별** |
| **공용 초상** `ART-C901~911` | 11 | **AI — 유형별** |
| ~~권역 배경~~ `ART-R001~045` | ~~45~~ **0** | **폐기 — V-45.** 그려질 자리가 없다 |
| 배경 (등급 3 + 태양계권) `ART-R101~104` | 0~4 | **조건부** — `SC-L2` 배경 슬롯 결정 시 |
| **BGM** `BGM-001~006` | 6 | **AI 작곡** |
| **L3 컷씬** `VID-001~004` | 4 | **AI 영상 — S6 선택 구간** |

| 만들지 않는 것 | 왜 |
|---|---|
| **한글 서체** `FNT-001·002` | **불가능.** 음절 11,172자 + 힌팅. **OFL 서체를 쓴다** |
| **효과음** `SFX-001~020` | CC0 라이브러리가 품질도 시간도 낫다 |
| **UI 부품** `ART-U001` | 9-slice 늘어남 · hover/press 상태 · 픽셀 정합 |
| **L1 영상 4종** `ART-B001~B004` | **AI 영상이 아니라 자작 인게임 연출이다** — 대장 §5.3 |

> ⚠ **마지막 줄을 특히 주의한다.** 「영상 11종을 AI로」로 읽히기 쉬우나
> **L1 바닥 4종은 게임 화면 그 자체**다. 진형 7종과 5페이즈는 전투 규칙이라
> AI로 대체하면 규칙과 그림이 어긋난다.

---

## 2. 공통 원칙 넷

### 2.1 오픈 가중치만 쓴다 — 그리고 변종을 지정한다

**「로컬이면 안전하다」가 아니라 「이 변종이 안전하다」이다** (대장 §4.4-b).

| 쓴다 | 라이선스 |
|---|---|
| **FLUX.1 [schnell]** | Apache 2.0 |
| **SDXL** | OpenRAIL++-M · 매출 상한 없음 |
| **ACE-Step 1.5** | MIT/Apache 계열 · Intel 지원 명시 |

| 쓰지 않는다 | 왜 |
|---|---|
| **FLUX.1 [dev]** | 내려받기는 자유이나 **상업 이용에 유료 계약 필요** |
| **SD 3 · 3.5** | 연 매출 100만 달러 임계 |
| **Stable Audio Open** | 같은 임계 |

### 2.2 대장에 즉시 기록한다

`asset-ledger.md` §0 — **에셋 하나 = 한 줄. 나중에 몰아 쓰면 복원할 수 없다.**
상태를 `판정` → `확보` → `검증`으로 올리고 **확인일을 반드시 적는다.**

### 2.3 미공개 서사 원고를 프롬프트에 넣지 않는다

`CLAUDE.md` §9 규칙 3 · `roadmap-solo.md` §3.3-3.
**인물명과 외형만 넣는다.** 프롤로그·엔딩·막간 원고는 넣지 않는다.

### 2.4 화풍 기준선을 먼저 고정한다

**이것이 안 B를 고른 이유다** (V-43). 화풍이 흔들리면 2단 차등의 이점이 사라진다.
고정할 것은 §4.3의 다섯이다.

---

## 3. 실행 환경

### 3.1 기기 제약

```
Intel Arc 130V GPU (내장) · 공유 약 8GB · CUDA 없음 · 시스템 RAM 15.5GB
```

| 용도 | 이 기기에서 |
|---|---|
| 이미지 | SDXL 가능(OpenVINO) · FLUX schnell 은 양자화하면 돌지만 **느리다** |
| **음원** | ✅ **ACE-Step 1.5가 Intel 지원을 명시한다.** 이 기기에서 돈다 |
| 영상 | ❌ **불가능.** 최소가 8~12GB, 제대로는 24GB |

### 3.2 실행 위치 3안

| 안 | 라이선스 | V-43 | 평가 |
|---|---|---|---|
| **로컬** | Apache 2.0 유지 | 유지 | 이미지가 느리다. **음원은 이것으로 충분** |
| **클라우드 GPU 임대 + 오픈 가중치** | **Apache 2.0 유지** | **유지** | ✅ **권고** |
| 구독형 생성 서비스 | 서비스 약관에 종속 | **무효화** | 화풍 고정이 어렵다 |

> **V-43의 「로컬 생성」은 「오픈 가중치 — 실행 위치 무관」으로 읽는다** (V-44).
> **FLUX.1 [schnell]은 남의 GPU에서 돌려도 Apache 2.0이다.**

---

## 4. 이미지 파이프라인

### 4.1 규격 — **확정 (2026-08-30)**

> 검토 1 을 닫는다. 근거는 `screens.md` 가 초상을 실제로 놓는 세 자리 —
> 인물 시트 헤더(§10.5) · 명장 카드 그리드(`ui-design.md` §4.4) ·
> `SC-F3` 임명 후보 행·담당관 칩(§4.6·§2.3) — 의 실측 크기다.
> 화면 기준 1600×900 가로, 단기판은 안드로이드 태블릿.

**표시 크기 실측**

| 자리 | 폭(추정) | 크롭 |
|---|---|---|
| 인물 시트 헤더 (하프 시트 오버레이) | ~280–320 px | 원본 4:5 |
| 명장 카드 그리드 | ~240–300 px | 원본 4:5 |
| `SC-F3` 후보 행 · 담당관 칩 | ~48–64 px | **정사각 상단 크롭** |

최대 표시가 ~320 px 이므로 마스터는 3배 여유를 둔다.

**확정 규격**

| 축 | 값 | 근거 |
|---|---|---|
| **종횡비** | **4:5 (세로)** | §4.2 구도 「상반신」. 카드·시트가 세로 프레임 |
| **마스터 해상도** | **896 × 1120** | SDXL/FLUX schnell 네이티브 근방(~1.0 MP). 최대 표시 320 px 대비 2.8배 |
| **얼굴 위치** | 눈높이 세로 **30%** · 머리 상단 세로 12–18% | 정사각 상단 크롭(896×896)에 얼굴 전체가 들어와야 `SC-F3`·담당관 칩이 성립 |
| **구도** | 상반신 · 어깨선이 프레임 폭의 ~85% · 하단·좌우 안전여백 12–16 px | 잘림 방지 |
| **배경** | **계층별 단색 틴트 5색 + 원형 비네트.** 장면 없음 · 알파 없음(굽는다) | 검토 3 — 카드 크기에서 계층이 색으로 읽힌다. V-45(장면 배경 폐기)는 유지 |
| **배경 틴트값** | 제독형 `#2E3A4C` · 강습형 `#43262A` · 파일럿형 `#243B3D` · 참모형 `#2F2A44` · 관료형 `#3B352B` | 저채도·중명도. `class[0]` 로 결정(§4.4 매핑과 같은 기준) |
| **비네트** | 가장자리 명도 −18% · 부드러운 원형 | 틴트가 인물을 밀어내지 않게 |
| **색공간** | sRGB · ICC 미임베드 | — |
| **마스터 형식** | **PNG** (8-bit · 알파 없음) — 저장소·아카이브 기준 | 무손실 원본 |
| **배포 형식** | **WebP q90** — APK 동봉 | Godot 4 임포트. 「영상은 곧 용량」과 같은 이유 |
| **파일명** | `ART-C001.png` … `ART-C120.png` · `ART-C901.png` … `ART-C911.png` | 대장 ID 그대로 · 결번 없음 |

> ⚠ **이 표가 잠기면 131장이 끝날 때까지 바꾸지 않는다.**
> 특히 **종횡비·얼굴 위치·틴트 5색** — 여기가 바뀌면 전부 재생성이다(§4.6).
> 마스터 해상도·형식은 재생성 없이 후처리로 흡수 가능한 유일한 칸이다.

> **다중 class 인물**(예: `["제","참"]`)은 `class[0]` 이 배경 틴트와 계층부 프롬프트를
> 결정한다. §4.4 매핑표가 이미 `class[0]` 기준이다.

### 4.2 화풍 기준선 — 고정 사양

**한 번 정하면 131장이 끝날 때까지 바꾸지 않는다.**
아래 5칸 중 **1·4 는 실행 패스(클라우드 GPU) 첫 작업**에서 시험생성 10~20장으로 확정하고,
**2·3·5 는 2026-08-30 잠근다.**

#### 1. 모델과 변종 — 실행 패스에서 확정

| 후보 | 파라미터 시작점 | 라이선스 |
|---|---|---|
| **SDXL 1.0 base (+refiner)** | DPM++ 2M Karras · 30스텝 · CFG 5.5 · refiner 0.8 | OpenRAIL++-M |
| **FLUX.1 [schnell]** | Euler · 4스텝 · guidance 0 (distilled) | Apache 2.0 |

> 시험생성으로 하나를 고르고 **그 시점에 가중치 파일 SHA-256 을 이 자리에 적는다.**
> ⚠ FLUX.1 [dev] · SD 3/3.5 는 쓰지 않는다(§2.1).

#### 2. 시드 규칙 — 잠금 ★

```
명장 120 :  seed = int( sha256("seonghanji:portrait:v1:" + characters.json.id).hexdigest()[:8], 16 )
공용 11  :  seed = int( sha256("seonghanji:portrait:v1:" + asset_id       ).hexdigest()[:8], 16 )
            # asset_id = ART-C901 … ART-C911
```

- 인물 `id`(`CHR-####`)에서 유도하므로 **같은 인물을 언제든 같은 시드로 다시 뽑는다.**
  `rng_stream.gd` 의 스트림 키 방식과 같다(V-31).
- `v1` 은 네임스페이스다. 화풍 기준선이 바뀌어 **전량 재생성**해야 하면 `v2` 로 올린다 —
  결정론적으로 새 시드 집합이 나온다.
- **선행물:** `ART-C001..120 ↔ CHR-####` 매핑표가 아직 없다. 시드가 `CHR-` id 로
  유도되므로 매핑표가 생성의 선행 조건이다 → 미작성 항목.

#### 3. 프롬프트 골격 — 잠금

고정부(131장 전부 동일):
```
digital painting portrait, single character, upper body, 4:5 vertical,
head-and-shoulders framing, eyes at 30% from top,
flat single-color background <TINT>, soft circular vignette, no scenery,
muted palette, controlled brushwork, semi-realistic, even key light from front-left,
sharp focus on face, no text, no watermark, no border
```
부정 프롬프트(131장 전부 동일):
```
photo, 3d render, anime, chibi, exaggerated proportions, multiple people, full body,
hands near face, weapon pointed at viewer, busy background, scenery, landscape,
text, watermark, signature, extra fingers, deformed hands, blur, oversaturated,
lens flare, modern clothing
```
`<TINT>` 는 §4.1 계층 틴트값. **계층부·성향부·개별부는 §4.3 구조를 그대로 붙인다.**

#### 4. 샘플러·스텝·CFG — 실행 패스에서 확정

위 후보표의 시작점에서 시험생성으로 수렴시킨다.

#### 5. 구도 — §4.1 에서 확정됨

4:5 · 눈높이 30% · 상반신 · 계층 틴트 · 비네트.

> **잠금 상태:** 2·3·5 확정 / 1·4 는 시험생성 후 이 문서에 SHA-256 과 함께 기입.
> 시험생성은 **공용 11종으로 한다**(§4.5 ③) — 되돌리는 비용이 11배 싸다.

### 4.3 프롬프트 구조

```
[고정부: 화풍 · 구도 · 매체 · 조명]        ← 131장 전부 동일 (§4.2-3)
+ [계층부: 복장 · 자세 · 소품]              ← class[0] 가 정한다  (§4.3.1)
+ [성향부: 표정 · 시선]                     ← disposition 이 정한다 (§4.3.2)
+ [개별부: 인물 특징]                       ← 명장 120 에만        (§4.3.3)
```

**조립 순서는 고정부 → 계층부 → 성향부 → 개별부.** 뒤에 오는 조각이 앞을 덮어쓰지
않도록 **계층부는 복장·자세·소품만, 성향부는 표정·시선만** 건드린다. 겹치는 어휘를 두지
않는다 — 그래야 25칸(5×5)이 서로 섞이지 않는다.

> **세계관은 우주 SF × 삼국지다.** 복장은 한대 실물이 아니라 그 실루엣을 성간 함대의
> 어휘로 옮긴 것 — 「제복」은 함대 정복, 「갑주」는 장갑복, 「관복」은 미래 관인의 예복이다.
> 은하영웅전설식 반사실 유화 초상을 기준으로 한다(고정부가 이미 `semi-realistic,
> digital painting, muted palette` 로 못 박았다).

#### 4.3.1 계층부 — `class` 5종

| 계층 | 방향 | 영문 조각 (프롬프트에 그대로) |
|---|---|---|
| **제독형** | 함대 지휘 · 정복 · 정면 · 권위 | `wearing a structured high-collar fleet dress uniform with rank insignia and a long coat, squared to camera, one hand resting on a table edge, bearing of command` |
| **강습형** | 백병 · 장갑복 · 반신 틀어짐 · 무장 | `wearing matte armor plating over a padded underlayer, torso turned three-quarters, pauldron catching the light, a close-combat blade sheathed at the shoulder` |
| **파일럿형** | 기동병기 · 비행복 · 젊음 | `wearing a fitted flight suit with harness straps and forearm controls, helmet set beside them, younger face, lean and alert` |
| **참모형** | 문관 복식 · 손에 문서나 필 | `wearing a layered scholar's robe with a narrow sash, holding a thin data-slate or a writing brush, leaning slightly forward as if mid-thought` |
| **관료형** | 행정 · 관복 · 단정 · 소품 없음 | `wearing a plain administrator's robe with a single clasp, hands folded, upright and composed, no held objects` |

> `class` 가 둘이면 `class[0]` 만 쓴다 — 배경 틴트(§4.1)와 같은 기준. 명장은 두 클래스를
> 편성 시 택1 하지만(`generals-150.md` §0.2), **초상은 하나로 고정**한다.

#### 4.3.2 성향부 — `disposition` 5종

> ⚠ **정의 정본은 `dispositions.md` §1이다.** 아래 「방향」은 그 시각화이지 새 정의가 아니다.

| 성향 | 방향 | 영문 조각 (프롬프트에 그대로) |
|---|---|---|
| **명사** | 격식 · 시선을 내리깔지 않는다 | `dignified level gaze meeting the viewer, chin neither raised nor lowered, formal reserve` |
| **무뢰** | 이완된 자세 · 시선이 정면을 비껴간다 | `gaze angled off past the viewer, faint smirk, careless ease in the shoulders` |
| **실무** | 무표정에 가까운 절제 | `near-neutral expression, steady measured gaze, no performance` |
| **야심** | 시선이 위를 향하거나 관찰한다 | `eyes lifted slightly or scanning sidelong, weighing what is in front of them, contained hunger` |
| **절의** | 굳은 입매 · 정면 응시 | `set jaw, firm closed mouth, unwavering frontal stare` |

> **무뢰의 「이완된 자세」는 어깨까지만 적용한다.** 자세 전체는 계층부 소관이라, 성향부가
> `relaxed posture` 를 통째로 넣으면 강습형의 「반신 틀어짐」과 충돌한다.

> **공용 `ART-C910`(강습)·`ART-C911`(파일럿)은 성향 축이 없다**(§4.4). **실무** 조각을
> 기본값으로 쓴다 — 189명 중 최빈 성향이고(`dispositions.md` 라인 191 「제독형 → 실무」와
> 같은 기본 배정), `ART-C901~902`(제독형 실무)와 표정 계열이 맞는다.

#### 4.3.3 개별부 — 명장 120 에만

**공용 11종에는 개별부가 없다.** 명장만 붙는다. 조각의 뼈대는 이렇다.

```
[연령대 신호] + [체격] + [두발·수염] + [식별 특징 1개]
```

- 출처는 `characters.json` 의 `traits[]` 와 원전 도상 통념. **traits → 시각 요소 변환표와
  120행 초안은 ④에서 만든다**(§4.5).
- ⚠ **인물명을 프롬프트에 넣을지는 ④에서 검토 5와 함께 판정한다** — 로마자 인물명을
  넣으면 확산 모델이 원전 도상을 끌어온다. 그것이 이득인지(통념 일치) 손해인지
  (통념과 충돌 · `characters.json` 와 어긋남)가 검토 5의 물음이다. §4.3 은 개별부를
  **외형 서술어만으로** 정의하고, 이름 처리는 열어 둔다.
- 개별부도 표정·복장을 **다시 지정하지 않는다.** 성향·계층과 싸우면 개별부를 줄인다
  (`dev-requirements.md` §11-6 「부품 조합형 초상이 개성을 지운다」의 반대 방향 함정 —
  개별부가 너무 세면 화풍이 흔들린다).

#### 4.3.4 조립 예시

**공용 — `ART-C903` 제독형 × 무뢰** (담당 28명):
```
digital painting portrait, single character, upper body, 4:5 vertical, head-and-shoulders
framing, eyes at 30% from top, flat single-color background #2E3A4C, soft circular vignette,
no scenery, muted palette, controlled brushwork, semi-realistic, even key light from
front-left, sharp focus on face, no text, no watermark, no border,
wearing a structured high-collar fleet dress uniform with rank insignia and a long coat,
squared to camera, one hand resting on a table edge, bearing of command,
gaze angled off past the viewer, faint smirk, careless ease in the shoulders
```
(부정 프롬프트는 §4.2-3 그대로. 시드 = `sha256("seonghanji:portrait:v1:ART-C903")[:8]`.)

**명장 — 참모형 택1 · 성향 야심인 인물 (예시, 실제 값은 ④):**
```
… 고정부 … , flat single-color background #2F2A44 , … ,
wearing a layered scholar's robe with a narrow sash, holding a thin data-slate,
leaning slightly forward as if mid-thought,
eyes scanning sidelong, weighing what is in front of them, contained hunger,
man in his early thirties, slight build, topknot and thin beard, ink-stained fingers
```
(마지막 줄이 개별부. 시드 = `sha256("seonghanji:portrait:v1:" + 해당 CHR-id)[:8]`.)

### 4.4 공용 11종 매핑 (V-43)

| ID | 계층 | 성향 | 담당 |
|---|---|---|---|
| `ART-C901` | 제독형 | 실무 A | 31 |
| `ART-C902` | 제독형 | 실무 B | 30 |
| `ART-C903` | 제독형 | 무뢰 | 28 |
| `ART-C904` | 제독형 | 절의 | 10 |
| `ART-C905` | 제독형 | 명사+야심 | 11 |
| `ART-C906` | 관료형 | 실무 | 23 |
| `ART-C907` | 관료형 | 그 밖 | 14 |
| `ART-C908` | 참모형 | 실무 | 14 |
| `ART-C909` | 참모형 | 그 밖 | 15 |
| `ART-C910` | 강습형 | — | 9 |
| `ART-C911` | 파일럿형 | — | 4 |

**대상 선별:** `data/assignments.json`에서 `SCN-03` · `status ≠ 미등장` → 309명.
`tier=명장` 120 → 개별 / `tier=일반무장` 189 → `class[0] × disposition`으로 위 표에 매핑.

### 4.5 생성 순서

```
① 규격 확정 (§4.1)
② 화풍 기준선 확정 (§4.2) — 시험 생성 10~20장으로 수렴시킨다
③ 공용 11종        ← 수가 적어 기준선 검증이 된다
④ 명장 120
⑤ BGM 6트랙        ← §5. 이미지와 독립이라 언제 해도 된다
```

> **배경은 이 순서에 없다.** V-45 로 폐기되었다 — `screens.md` 가 `SC-L2` 에
> 배경 슬롯을 두기로 하면 그때 4종(`ART-R101~104`)이 살아난다.
> **이 세션은 배경을 만들지 않는다.**

> **③을 먼저 하는 이유.** 11장으로 화풍이 안 잡히면 120장에서도 안 잡힌다.
> **되돌리는 비용이 11배 싸다.**

### 4.6 검수 기준

| # | 기준 |
|---|---|
| 1 | **같은 계층끼리 나란히 놓았을 때 같은 세계로 보이는가** |
| 2 | 화면 실제 크기로 줄였을 때 계층이 구별되는가 |
| 3 | 손·글자 등 붕괴가 없는가 |
| 4 | 원전 인물의 통념과 충돌하지 않는가 (명장 120) |

> **2번이 실무적으로 가장 자주 걸린다.** 100% 로 보면 훌륭한데
> 카드 크기로 줄이면 다 같아 보이는 일이 흔하다. **검수는 실제 크기로 한다.**

---

## 5. 음원 파이프라인

### 5.1 6트랙

| ID | 트랙 | 쓰이는 곳 |
|---|---|---|
| `BGM-001` | 전략 | 성역 뷰 · 평시 |
| `BGM-002` | 긴장 | 결정 큐 · 인터럽트 |
| `BGM-003` | 전투 | 5페이즈 |
| `BGM-004` | 승리 | 결착 |
| `BGM-005` | 패배 | 붕괴 |
| `BGM-006` | 정적 | 막간 · 엔딩 |

### 5.2 ACE-Step 1.5 — 이 기기에서 돈다

**Intel 지원을 명시**하고 MIT/Apache 계열이다. **구독조차 필요 없다.**

### 5.3 루프 가공은 AI로 안 된다

**BGM은 이어 붙였을 때 이음매가 들리지 않아야 한다.**
그 지점을 찾는 것은 파형을 보고 하는 판단이지 생성이 아니다 (대장 §4.5).

| 작업 | 방법 |
|---|---|
| 생성 | **AI** |
| 잡음 제거 · 정규화 | AI 도구가 낫다 |
| **루프 지점 · 자르기 · 포맷 변환** | **파형 편집기 (Audacity)** |

---

## 6. 영상

| 계층 | 무엇 | 언제 |
|---|---|---|
| **L1 4종** | **자작 인게임 연출.** AI 아님 | **S4** — 9일 |
| **L2 6종** | 3D 전투. **부분 채택 불가** | S5 — L2를 켜는 경우만 |
| **L3 4종** | **AI 영상** | **S6 — 선택** |

> **AI 영상은 27주차 판단 이후다.** 지금 서비스를 고를 필요가 없다.
> **약관이 그때 또 바뀌어 있을 것**이므로 미리 정하는 이득이 없다.

---

## 7. 대장 기록 절차

생성분 하나마다 `asset-ledger.md` §2.1의 행을 갱신한다.

```
판정  방법만 정했다
확보  파일이 있다        ← 생성 직후
검증  라이선스 확인 완료  ← 모델 라이선스 · 확인일 기입
```

**AI 생성물은 `확보: AI`로 명시한다** (§0 · V-44).
**표기 의무가 있으므로 크레딧 화면이 UI 요건이다** — `ui-design.md` §8.1.

---

## 검토 포인트

| # | 쟁점 | 비고 |
|---|---|---|
| 1 | ~~**초상 규격이 정의된 적이 없다**~~ | **해소 — 2026-08-30.** §4.1 확정. 4:5 세로 · 마스터 896×1120 · 얼굴 눈높이 30% · 계층별 단색 틴트 5색 · 마스터 PNG / 배포 WebP q90. **종횡비·얼굴 위치·틴트가 잠겼다** |
| 2 | ~~**권역 배경 물량이 미확정이다**~~ | **해소 — V-45 (2026-08-30).** 폐기했다. 물음이 「몇 장인가」가 아니라 **「어디에 그려지는가」**였고, `screens.md` 에 배경이 0회 나온다. 되살아나면 축은 **등급 3 + 태양계권 1** |
| 3 | 공용 초상 11종이 화면에서 실제로 구별되는가 | §4.6-2. **11종이 다 같아 보이면 안 B의 의미가 없다.** 시험 생성으로 조기 확인 |
| 4 | 클라우드 GPU 임대처의 약관 | §3.2. **모델 라이선스와 별개로 임대처 약관이 있다.** 확인 필요 |
| 5 | 명장 120의 외형 근거 | `characters.json`의 `traits`뿐이다. **원전 통념과 충돌할 때 무엇을 따르는가**가 미정 |
| 6 | AI 명시의 표기 수위 | V-44가 명시를 확정했으나 **어느 수준으로 적는지**는 미정. 스토어 정책 확인 필요 — `dev-requirements.md` §7.3 |

## 미작성 항목

- [x] ~~**초상 규격** (해상도 · 종횡비 · 배경 처리 · 파일 형식)~~ — **2026-08-30 확정. §4.1**
- [ ] **화풍 기준선 — 모델·해시·샘플러 확정** (§4.2 칸 1·4) — 실행 패스 시험생성 후. 시드 규칙·프롬프트 골격·구도(칸 2·3·5)는 2026-08-30 잠금
- [ ] **`ART-C001..120 ↔ CHR-####` 매핑표** — §4.2 시드 유도의 선행물
- [ ] **④ 개별부 — `traits` → 시각 요소 변환표 + 명장 120행 초안** (§4.3.3) · 인물명 프롬프트 삽입 여부는 검토 5와 함께
- [x] ~~권역 배경 물량 재산정~~ — **V-45 로 폐기**
- [ ] 클라우드 GPU 임대처 선정과 약관 확인 — 검토 4
- [ ] 크레딧 화면 문안 — `ui-design.md` §8.1
