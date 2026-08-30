# SEONGHANJI — RunPod 파드 세팅·실행 런북 v0.1

> 상위: `ai-media-pipeline.md` §3.3 (실행 환경 결정 · V-46) · `asset-ledger.md`
> 작성일: 2026-08-30 · 상태: **초안 — 착수 전. 명령은 시작점이며 현행 템플릿과 대조 후 실행한다**
>
> **이 문서가 답하는 것:** RunPod Community 파드를 **어떻게 띄우고, 무엇을 받고,
> 어떤 순서로 생성하고, 어떻게 반출·정리하는가.** 「왜 RunPod인가 · GPU를 왜 그걸
> 고르나 · 비용은 얼마인가」는 `ai-media-pipeline.md` §3.3 이 이미 답했다. 여기는 절차다.

---

## 0. 이 런북의 범위

| 한다 | 안 한다 |
|---|---|
| 계정·크레딧·리전 · Network Volume · 파드 생성 · 가중치 다운로드 · 시험생성 · 배치 실행 · 후처리 · 반출·정리 | 음원(자택 로컬 — §5.2) · 영상(S6 게이트 — §3.3-6) · 모델 선택 판단(시험생성 결과로 §4.2가 정함) |

**선행 조건 — 아래가 확정되어 있어야 Phase 4로 넘어간다.**

| 선행물 | 상태 | 위치 |
|---|---|---|
| 초상 규격 (4:5 · 896×1120 · 틴트 5색) | ✅ | `ai-media-pipeline.md` §4.1 |
| 시드 규칙 (`sha256("seonghanji:portrait:v1:"+id)[:8]`) | ✅ | §4.2-2 |
| 프롬프트 골격 · 계층/성향 조각 | ✅ | §4.3 |
| 명장 120 매핑 (ID·시드·틴트) | ✅ | §4.7 · `data/portrait-map.json` |
| 개별부 규칙 | ✅ | §4.8 |
| **모델·샘플러·가중치 해시** | ❌ **Phase 4에서 확정** | §4.2 칸 1·4 |
| ComfyUI 워크플로 JSON 2종 | ✅ | `tools/comfyui/sdxl_portrait.json` · `flux_schnell_portrait.json` |
| 배치 생성 스크립트 | ❌ 미작성 | 이 문서 미작성 항목 |
| 후처리 스크립트 | ❌ 미작성 | 〃 |

---

## Phase 0 — 계정 · 크레딧 · 리전

1. **가입** — `runpod.io` 계정 생성, 이메일 인증.
2. **결제수단 등록 · 선불 크레딧 충전** — $20 권장(이미지 단계 소계 ~$10–15 + 여유).
   ⚠ **크레딧은 환불 불가**(§3.3-0). 필요분만 넣는다.
3. **API 키 발급** — Console → Settings → API Keys → `+ API Key`.
   배치 스크립트·`runpodctl`용. 안전한 곳에 보관, 저장소에 넣지 않는다.
4. **`runpodctl` 설치**(로컬, 선택) — 파일 반출·파드 제어에 쓴다.
   ```bash
   # macOS/Linux
   wget -qO- cli.runpod.net | bash
   # Windows: https://github.com/runpod/runpodctl/releases 에서 exe
   runpodctl config --apiKey <API_KEY>
   ```
5. **리전 재고 확인** — Console → Pods → `+ Deploy` → **Community Cloud** 필터 →
   `RTX 4090` 과 `RTX 3090` 이 **둘 다** 재고 있는 리전을 찾는다(예: EU-RO, EU-SE, US 계열).
   **그 리전 코드를 적어 둔다.** 다음 단계 Network Volume이 이 리전에 묶인다.

> ⚠ **Community Cloud는 재고가 유동적이다.** 재고 0이면 Phase 2에서 대기하거나
> Secure Cloud(같은 카드, 시간당 1.5~2배)로 전환한다. 실패 모드는 부록 B.

---

## Phase 1 — Network Volume

1. Console → **Storage** → **Network Volumes** → `+ New Network Volume`.
2. **Region** = Phase 0-5에서 고른 리전. (변경 불가 — 신중히)
3. **Size** = **60 GB** (가중치 캐시 ~50GB + 작업 여유, §3.3-2).
4. **Name** = `seonghanji-media`.
5. Create. **이 시점부터 ~$4.2/월 과금**($0.07/GB·월).

> 리전 재고가 계속 꼬이면 볼륨을 만들지 않고 **매 파드 startup에서 HF 재다운로드**하는
> 방법이 있다(§3.3-2). 세션이 3회 이하면 그쪽이 싸다. 이 런북은 볼륨 방식을 기본으로 쓴다.

---

## Phase 2 — 파드 생성 (시험생성용 · RTX 4090)

1. Console → Pods → `+ Deploy`.
2. **Cloud Type** = **Community Cloud**.
3. **GPU** = `RTX 4090`, 수량 `1`.
4. **Network Volume** = `seonghanji-media` → 마운트 경로 `/workspace`.
5. **Template** = 공식 **"RunPod ComfyUI"** 또는 `ai-dock/comfyui:latest`.
6. **Container Disk** = 20 GB (임시 — 볼륨과 별개, 파드 삭제 시 소멸).
7. **Expose HTTP Ports** — `8188`(ComfyUI), `8888`(Jupyter/터미널).
8. **On-Demand** 로 배포(Spot 아님 — 시험생성은 중단되면 곤란).
9. 상태가 **Running** 이 되면 → **Connect**:
   - `Connect to HTTP Service [Port 8188]` → ComfyUI 웹 UI
   - `Connect to Web Terminal` (또는 Jupyter Port 8888) → 셸

> 파드는 Ada(4090)/Ampere(3090)라 **Blackwell `sm_120` 빌드 이슈가 없다**
> (자택 5060 제약과 무관 — §3.3-3). PyTorch/xformers 기본 빌드가 그대로 돈다.

---

## Phase 3 — 가중치 다운로드 (볼륨에 1회)

**웹 터미널에서**, 볼륨(`/workspace`) 안에 받는다. 파드를 지워도 남는다.

```bash
cd /workspace
pip install -q "huggingface_hub[cli]"

# --- FLUX.1 [schnell] : Apache 2.0, 비게이트 (토큰 불필요) ---
huggingface-cli download black-forest-labs/FLUX.1-schnell \
  flux1-schnell.safetensors ae.safetensors \
  --local-dir /workspace/w/flux

huggingface-cli download comfyanonymous/flux_text_encoders \
  t5xxl_fp16.safetensors clip_l.safetensors \
  --local-dir /workspace/w/clip

# --- SDXL 1.0 base + refiner : OpenRAIL++-M ---
huggingface-cli download stabilityai/stable-diffusion-xl-base-1.0 \
  sd_xl_base_1.0.safetensors --local-dir /workspace/w/sdxl
huggingface-cli download stabilityai/stable-diffusion-xl-refiner-1.0 \
  sd_xl_refiner_1.0.safetensors --local-dir /workspace/w/sdxl
```

**가중치 해시를 즉시 기록** (§4.2 칸 1의 「파일 SHA-256」):

```bash
sha256sum \
  /workspace/w/flux/flux1-schnell.safetensors \
  /workspace/w/sdxl/sd_xl_base_1.0.safetensors \
  /workspace/w/sdxl/sd_xl_refiner_1.0.safetensors \
  | tee /workspace/WEIGHTS.sha256
```

**ComfyUI 가 이 파일들을 찾게 연결** — 템플릿마다 규약이 다르다. 둘 중 하나:
- 심링크: `ln -s /workspace/w/sdxl/*.safetensors /workspace/ComfyUI/models/checkpoints/` 등
  (FLUX unet → `models/diffusion_models` 또는 `models/unet`, 텍스트 인코더 → `models/clip`,
  `ae.safetensors` → `models/vae`)
- 또는 `ComfyUI/extra_model_paths.yaml` 에 `/workspace/w` 를 base_path 로 등록.

> ⚠ **착수 시 FLUX.1-schnell 저장소의 라이선스 동의 화면 유무를 확인한다.**
> schnell 은 Apache 2.0 비게이트이나 HF UI 가 클릭 동의를 요구하는 경우가 있다.
> `dev` 는 게이트다 — **받지 않는다**(§2.1).

---

## 워크플로 JSON 두 개 — `tools/comfyui/`

**ComfyUI API 포맷.** 896×1120·4:5 고정, §4.2-1 파라미터가 이미 박혀 있다.
기본값은 공용 `ART-C903`(제독형×무뢰) 한 장이라 **그대로 `POST /prompt` 하면 스모크
테스트가 된다.** 배치(Phase 5)는 대상마다 아래 세 자리만 덮어쓴다.

| 파일 | 모델 | 배치가 덮어쓰는 노드 |
|---|---|---|
| `sdxl_portrait.json` | SDXL base+refiner (2-pass · base 0–24/30 · refiner 24–30) | `["6"].inputs.text` · `["15"].inputs.text` (동일 문자열) · `["10"].inputs.noise_seed` · `["11"].inputs.noise_seed` (동일 정수) · `["19"].inputs.filename_prefix` |
| `flux_schnell_portrait.json` | FLUX.1 [schnell] (unet+DualCLIP+ae · 4스텝 euler · guidance 0) | `["6"].inputs.text` · `["25"].inputs.noise_seed` · `["9"].inputs.filename_prefix` |

- **부정 프롬프트**는 SDXL 쪽 `["7"]`·`["17"]` 에 §4.2-3 그대로 고정 — 배치가 안 건드린다.
  FLUX schnell 은 부정 프롬프트를 쓰지 않는다(CFG 1).
- `noise_seed` 는 정수다. `int(hashlib.sha256(f"seonghanji:portrait:v1:{art}".encode()).hexdigest()[:8], 16)`.
- ⚠ **노드 class_type 은 ComfyUI 버전에 따라 이름이 바뀔 수 있다**(`UNETLoader`↔`UnetLoaderGGUF`,
  `EmptySD3LatentImage` 등). Phase 4 스모크 테스트에서 한 번 확인하고 넘어간다.

---

## Phase 4 — 화풍 기준선 시험생성 (§3.3-4 A · §4.2 칸 1·4 확정)

**목표: SDXL 세트와 FLUX schnell 세트를 나란히 뽑아 하나를 고른다.**

1. `tools/comfyui/` 의 워크플로 2개를 ComfyUI 에 올린다(UI 「Load」 또는 API `POST /prompt`).
   기본값 그대로 1장씩 뽑아 **스모크 테스트** — 노드 이름·모델 경로가 맞는지 여기서 잡는다.
   파라미터는 이미 §4.2-1 대로다(SDXL: DPM++ 2M Karras·30스텝·CFG 5.5·refiner 0.8 /
   FLUX schnell: Euler·4스텝·guidance 0).
2. **공용 11종**(`ART-C901`~`C911`) 프롬프트를 §4.3 규칙으로 조립:
   `고정부(§4.2-3) + 계층부[class](§4.3.1) + 성향부[disposition](§4.3.2)`, `<TINT>` = §4.1.
   매핑은 §4.4 표.
3. 11종 × 2세트 = **22장** 생성. 시드 = `sha256("seonghanji:portrait:v1:ART-C901")[:8]` …
   (파드 안에서 파이썬으로: `int(hashlib.sha256(b"...").hexdigest()[:8],16)`).
4. 22장을 **로컬로 반출**(Phase 8 방법) → **~320 px 로 축소** → `ai-media-pipeline.md`
   §4.6 검수. **특히 2번**(축소 시 계층이 구별되는가) — 100% 로만 보지 않는다.
5. **한 세트 선택.** `ai-media-pipeline.md` 를 편집:
   - §4.2-1 에 선택 모델 + `WEIGHTS.sha256` 해당 줄 기입
   - §4.2-4 에 수렴한 샘플러·스텝·CFG 기입
   - `git commit -- docs/07-production/ai-media-pipeline.md`
6. **검토 3 판정 기록** — 공용 11종이 실제로 구별되면 검토 포인트 3 을 취소선,
   안 되면 §4.2 로 돌아가 프롬프트 골격을 조정(모델 재선택은 아님).

> **되돌리는 비용이 11배 싸다**(§4.5). 여기서 화풍이 안 잡히면 명장 120 으로 넘어가지 않는다.

---

## Phase 5 — 배치 생성 스크립트 (§3.3-4 B)

**ComfyUI 를 API 로 두고, 스크립트가 대상마다 프롬프트·시드·파일명을 넣어 돌린다.**

- ComfyUI 실행: `python main.py --listen 0.0.0.0 --port 8188`
  (템플릿 기본값이 대개 이미 그렇다).
- 스크립트 입력:
  - 명장 120 → `data/portrait-map.json` (art · chr · class0 · disposition · tint · seed · traits)
  - 공용 11 → §4.4 표를 JSON 으로 옮긴 것(미작성)
- 대상마다:
  ```
  seed   = row.seed                                   # §4.7 / §4.2-2
  prompt = 고정부(§4.2-3)
         + 계층부[row.class0]        (§4.3.1)
         + 성향부[row.disposition]   (§4.3.2, null 이면 군주 조각)
         + 개별부(row, 명장만)       (§4.8: 세력 악센트 + 연령 신호 + 기조어 + trait 표지)
  <TINT> = row.tint  (고정부의 `flat single-color background <TINT>` 에 들어간다)
  → tools/comfyui/{sdxl|flux_schnell}_portrait.json 로드
  → 위 「워크플로 JSON 두 개」 표의 노드에 text/seed/filename_prefix 치환
  → POST /prompt
  → 완료 대기(websocket /ws 또는 /history 폴링)
  → 결과 PNG 를 out/<art>.png 로 저장 (896×1120 · 8-bit · no alpha)
  ```
- 실패(손 붕괴 등)는 목록에 남기고 계속 — Phase 6 에서 재처리.

> 스크립트 자체는 **미작성**. `tools/` 아래 신규 파일로 만들며 다른 세션의 코드와 무관하다.
> 파이썬 표준(`requests`, `websocket-client`, `hashlib`, `Pillow`)만 쓴다.

---

## Phase 6 — 명장 120 벌크 (§3.3-4 C)

1. **Phase 2 의 4090 파드를 Terminate.** Network Volume 은 유지된다.
2. **3090 파드를 같은 볼륨으로 Deploy** (Phase 2 반복, GPU 만 `RTX 3090`).
   가중치는 볼륨에 있으므로 Phase 3 을 건너뛴다(ComfyUI 경로 연결만 재확인).
3. 배치 스크립트로 `ART-C001` ~ `ART-C120` 실행. 4090 대비 1.5~2배 느리지만 벌크는 이걸로.
4. **실패분만 재생성** — 시드 고정이라 동일 결과가 재현된다. 손·글자 붕괴(§4.6-3)는
   시드를 바꾸지 말고 개별부를 미세 조정하거나 배치 스텝을 올린다.
5. **검토 5 통념 플래그 12명**(§4.8) — 1차 결과를 통념과 대조. 어긋난 것만 개별부에
   통념 한 줄을 더해 재생성. **발주자 아트 방향 확인**(원전 도상 대 재해석) 후 진행.

---

## Phase 7 — 후처리 (로컬)

파드에서 뽑은 원본은 「거의 맞는」 상태다. 로컬 스크립트로 규격을 확정한다.

| 단계 | 내용 | 근거 |
|---|---|---|
| 1 | **계층 틴트 배경** — 모델이 근사만 하므로 정확한 `#RRGGBB` 로 교정하거나 배경만 재합성 | §4.1 |
| 2 | **원형 비네트** 가장자리 명도 −18% | §4.1 |
| 3 | **정사각 상단 크롭 검증** — 896×896 에 얼굴 전체 · 눈높이 세로 30% | §4.1 |
| 4 | **마스터 저장** — PNG 8-bit sRGB no-alpha, `ART-C###.png` | §4.1 |
| 5 | **배포본 파생** — WebP q90, `ART-C###.webp` | §4.1 |

> 결정론적 스크립트로 만든다 — 같은 입력에 같은 출력. §4.6-1(일관성)이 그 위에 선다.
> 스크립트는 **미작성**(`tools/` 신규).

---

## Phase 8 — 반출 · 기록 · 정리 (§3.3-8)

1. **생성물 전량 반출** — 파드는 저장을 보장하지 않는다.
   - `runpodctl send out/` → 로컬에서 `runpodctl receive <code>`
   - 또는 Jupyter 파일 브라우저에서 다운로드
   - 또는 파드에서 S3/버킷으로 `aws s3 sync`
2. **`WEIGHTS.sha256` 반출** — §4.2 기입 근거로 로컬 보관.
3. **대장 갱신** — `asset-ledger.md` §2.1:
   `ART-C001~120` · `ART-C901~911` 행을 `판정` → **`확보: AI`**.
   `확인일` = 생성일, `라이선스` = 확정 모델의 것(Apache 2.0 또는 OpenRAIL++-M).
   ⚠ **몰아 쓰지 않는다**(§0). 생성 직후 그 행만.
4. **파드 Terminate.** Stop 이 아니라 Terminate — Stop 은 볼륨 디스크 요금이 계속 붙는다.
5. **프로덕션 종료 후** Network Volume 을 Delete (더 안 쓸 때). 그 전까지 ~$4.2/월.

---

## 부록 A — 비용 가드레일

`ai-media-pipeline.md` §3.3-7 추산 재확인. **이미지 단계 총 ~$10–15.**

| 알림 지점 | 조치 |
|---|---|
| 크레딧 잔액 < $5 | 충전 or 중단. 볼륨은 남으므로 이어서 가능 |
| 4090 파드 누적 4시간 초과 | 시험생성이 안 끝나는 것 — 프롬프트/워크플로 문제. 파드 끄고 로컬에서 점검 |
| Volume 2개월 초과 | Phase 8-5 로 삭제 판단 |

---

## 부록 B — 실패 모드

| 증상 | 원인 | 대응 |
|---|---|---|
| Deploy 시 GPU 재고 0 | Community 유동 재고 | 다른 리전(단 볼륨 리전과 불일치) · 대기 · Secure Cloud 전환(1.5~2배) |
| 볼륨과 파드 리전 불일치로 마운트 불가 | 리전 고정(Phase 1-2) | 볼륨 리전에서만 파드 생성 · 또는 볼륨 없이 startup 재다운로드 |
| CUDA OOM | 24GB 초과 워크로드 | FLUX fp8 · 배치 크기 1 · SDXL refiner 분리 실행 |
| HF 다운로드 rate limit / 중단 | 대용량·동시 | `huggingface-cli` 재실행(이어받기) · `HF_HUB_ENABLE_HF_TRANSFER=1` |
| 파드 재시작 후 모델 경로 사라짐 | 심링크가 컨테이너 디스크에 있었음 | 심링크/`extra_model_paths.yaml` 를 볼륨 쪽에 두거나 startup script 로 재생성 |
| 생성물이 파드 삭제로 소멸 | Terminate 전 미반출 | Phase 8-1 을 세션마다. 습관화 |

---

## 검토 포인트

| # | 쟁점 | 비고 |
|---|---|---|
| 1 | ~~**ComfyUI 워크플로 JSON 2종이 없다**~~ | **작성 — 2026-08-30.** `tools/comfyui/sdxl_portrait.json` · `flux_schnell_portrait.json` (896×1120·§4.2-1 파라미터·기본값=ART-C903). **잔여 리스크:** 미실행 — 노드 `class_type` 이 파드의 ComfyUI 버전과 어긋날 수 있다(GGUF·SD3 latent 등). Phase 4 스모크 테스트에서 확인 |
| 2 | **배치·후처리 스크립트가 없다** | Phase 5·7. `tools/` 신규. 시드·프롬프트 조립이 §4.2-2·§4.3·§4.8 과 한 글자도 어긋나면 안 된다 — 재현성이 안 B 의 전제 |
| 3 | **틴트를 프롬프트로 낼까 후처리로 합성할까** | §4.1 은 프롬프트에 `<TINT>` 를 넣지만 확산 모델은 정확한 `#RRGGBB` 를 못 낸다. Phase 7-1 이 교정하는지 재합성하는지가 미정 — 시험생성에서 판정 |
| 4 | **반출 방법 미확정** | `runpodctl` / Jupyter / S3 중 무엇을 표준으로. 물량 131장 + 22장 시험분이라 어느 쪽이든 되나 하나로 고정한다 |
| 5 | **Community 재고 리스크가 일정에 반영 안 됨** | 재고 0 이 며칠 가면 Secure Cloud 비용이 추산의 1.5~2배. §3.3-7 은 Community 기준이다 |

## 미작성 항목

- [x] ~~**ComfyUI 워크플로 JSON**~~ — **2026-08-30. `tools/comfyui/sdxl_portrait.json` · `flux_schnell_portrait.json`** (896×1120 고정 · API 포맷 · 미실행)
- [ ] **배치 생성 스크립트** — `tools/gen_portraits.py` (가칭). 입력 `data/portrait-map.json` + 공용 11 표, 워크플로 JSON 의 지정 노드에 치환, 출력 `out/ART-C###.png`
- [ ] **공용 11 매핑을 기계가 읽는 형태로** — §4.4 표 → JSON (명장은 이미 `portrait-map.json`)
- [ ] **후처리 스크립트** — `tools/finish_portraits.py` (가칭). 틴트·비네트·크롭 검증·WebP
- [ ] **반출 방법 1개 확정** — 검토 4
- [ ] **BGM 로컬 런북** — 이 문서는 파드 전용. ACE-Step(자택 5060) + Audacity 절차는 별도 (§5)
