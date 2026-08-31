#!/usr/bin/env python3
"""
SEONGHANJI 초상 배치 생성 — RunPod ComfyUI 파드용.

`docs/07-production/runpod-runbook.md` Phase 5·6. 결정론적 — 같은 입력에 같은 출력.
프롬프트 조립은 `ai-media-pipeline.md` §4.3(고정부·계층부·성향부) + §4.8(개별부),
기계형 정본은 `tools/comfyui/fragments.json`. 시드는 §4.2-2 규칙(명장=CHR-id · 공용=ART-id).

의존성: 표준 라이브러리만.

  # 스모크 — 공용 1장, POST 안 함
  python tools/gen_portraits.py --common --only ART-C903 --dry-run

  # 화풍 기준선(Phase 4) — 공용 11 × SDXL
  python tools/gen_portraits.py --model sdxl --common --host http://127.0.0.1:8188

  # 명장 120 벌크(Phase 6) — FLUX
  python tools/gen_portraits.py --model flux --named

  # 실패분만 재생성 (시드 고정이라 재현)
  python tools/gen_portraits.py --model flux --only ART-C007,ART-C042 --force
"""

import argparse
import hashlib
import json
import re
import sys
import time
import uuid
from pathlib import Path
from urllib import request as urlreq
from urllib.error import HTTPError
from urllib.parse import urlencode

ROOT = Path(__file__).resolve().parents[1]
CFG_DIR = ROOT / "tools" / "comfyui"
NS = "seonghanji:portrait:v1:"

# 워크플로 JSON 의 어느 노드를 배치가 덮어쓰는가 (runpod-runbook.md 「워크플로 JSON 두 개」)
INJECT = {
    "sdxl": {"workflow": "sdxl_portrait.json",
             "text": ["6", "15"], "negative": ["7", "17"],
             "seed": ["10", "11"], "fileprefix": ["19"]},
    "flux": {"workflow": "flux_schnell_portrait.json",
             "text": ["6"], "negative": [], "seed": ["25"], "fileprefix": ["9"]},
}

TRAIT_RE = re.compile(r"[「『]([^」』]+)[」』]")  # 「」 『』


def seed_for(key: str) -> int:
    return int(hashlib.sha256((NS + key).encode()).hexdigest()[:8], 16)


def load_json(p: Path):
    return json.loads(Path(p).read_text(encoding="utf-8"))


def trait_names(traits):
    out = []
    for t in traits or []:
        out += TRAIT_RE.findall(t)
    return out


# ---------------------------------------------------------------- 프롬프트 조립

def build_individual(frag, faction, class0, traits):
    """§4.8 개별부: [연령 신호] + [세력 악센트] + [기조어] + [trait 외형 표지]."""
    parts = []
    names = trait_names(traits)

    # 2. 연령 신호 — trait 이 나이를 문자 그대로 담을 때만
    for n in names:
        if n in frag["age_signal"]:
            parts.append(frag["age_signal"][n])
            break

    # 1. 세력 악센트 — "<색> <복식어> piping" · 군웅은 없음
    color = frag["faction_accent_color"].get(faction)
    if color is None:
        parts.append(frag["faction_accent_none"])
    else:
        parts.append(f"{color} {frag['faction_accent_garment'][class0]} piping")

    # 3. 기조어 — trait 계열에서 1개
    for n in names:
        if n in frag["bearing"]:
            parts.append(frag["bearing"][n])
            break

    # 4. trait 외형 표지 — 회수되는 것 전부 (§4.8-4)
    for n in names:
        if n in frag["trait_marker"]:
            parts.append(frag["trait_marker"][n])

    return parts


def assemble(frag, *, tint, class0, disp_keys, faction=None, traits=None, named=False):
    """고정부 → 계층부 → 성향부 → (개별부). §4.3 조립 순서."""
    parts = [frag["fixed"].replace("<TINT>", tint), frag["class"][class0]]
    for dk in disp_keys:
        parts.append(frag["disposition"][dk])
    if named:
        parts += build_individual(frag, faction, class0, traits)
    return ", ".join(p for p in parts if p)


# ---------------------------------------------------------------- 대상 목록

def named_tasks(pmap):
    for row in pmap:
        disp = row["disposition"]
        yield {
            "art": row["art"], "key": row["chr"], "named": True,
            "tint": row["tint"], "class0": row["class0"],
            "disp_keys": [disp] if disp else ["군주"],  # null → 군주
            "faction": row["faction"], "traits": row.get("traits"),
            "name": row["name"], "stored_seed": row["seed"],
        }


def common_tasks(cmap):
    for row in cmap["rows"]:
        yield {
            "art": row["art"], "key": row["art"], "named": False,
            "tint": row["tint"], "class0": row["class0"],
            "disp_keys": row["disposition_keys"],
            "faction": None, "traits": None,
            "name": None, "stored_seed": row["seed"],
        }


def parse_range(spec):
    a, _, b = spec.partition("-")
    return [f"ART-C{i:03d}" for i in range(int(a), int(b) + 1)]


# ---------------------------------------------------------------- ComfyUI API

def api_post(host, graph, client_id):
    body = json.dumps({"prompt": graph, "client_id": client_id}).encode()
    req = urlreq.Request(host + "/prompt", data=body,
                         headers={"Content-Type": "application/json"})
    try:
        with urlreq.urlopen(req, timeout=30) as r:
            return json.loads(r.read())["prompt_id"]
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"ComfyUI HTTP {exc.code}: {detail}") from exc


def api_wait(host, pid, timeout, poll=2.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        with urlreq.urlopen(host + f"/history/{pid}", timeout=30) as r:
            hist = json.loads(r.read())
        if pid in hist:
            entry = hist[pid]
            st = entry.get("status", {})
            if st.get("status_str") == "error":
                raise RuntimeError(f"ComfyUI error: {st}")
            if st.get("completed") or entry.get("outputs"):
                return entry
        time.sleep(poll)
    raise TimeoutError(f"prompt {pid} unfinished in {timeout}s")


def api_first_image(entry):
    for node_out in entry.get("outputs", {}).values():
        imgs = node_out.get("images")
        if imgs:
            return imgs[0]
    raise RuntimeError("no image in history outputs")


def api_fetch(host, info, dst: Path):
    q = urlencode({"filename": info["filename"],
                   "subfolder": info.get("subfolder", ""),
                   "type": info.get("type", "output")})
    with urlreq.urlopen(host + "/view?" + q, timeout=120) as r:
        data = r.read()
    dst.write_bytes(data)
    return hashlib.sha256(data).hexdigest()


def inject(graph, spec, *, text, negative, seed, fileprefix):
    for nid in spec["text"]:
        graph[nid]["inputs"]["text"] = text
    for nid in spec["negative"]:
        graph[nid]["inputs"]["text"] = negative
    for nid in spec["seed"]:
        graph[nid]["inputs"]["noise_seed"] = seed
    for nid in spec["fileprefix"]:
        graph[nid]["inputs"]["filename_prefix"] = fileprefix


# ---------------------------------------------------------------- main

def main(argv=None):
    for stream in (sys.stdout, sys.stderr):  # Windows 콘솔(cp949)에서도 한글·em-dash 출력
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass

    ap = argparse.ArgumentParser(description="SEONGHANJI 초상 배치 생성")
    ap.add_argument("--model", choices=INJECT, default="flux")
    ap.add_argument("--host", default="http://127.0.0.1:8188")
    ap.add_argument("--named", action="store_true", help="명장 120 (data/portrait-map.json)")
    ap.add_argument("--common", action="store_true", help="공용 11 (tools/comfyui/common-map.json)")
    ap.add_argument("--only", default="", help="쉼표 구분 ART-ID 목록")
    ap.add_argument("--range", dest="rng", default="", help="명장 번호 범위, 예: 1-20")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--out", default=str(ROOT / "out"))
    ap.add_argument("--timeout", type=int, default=600)
    ap.add_argument("--fragments", default=str(CFG_DIR / "fragments.json"),
                    help="시험용 프롬프트 조각 JSON (기본: 정본 fragments.json)")
    ap.add_argument("--force", action="store_true", help="이미 있는 파일도 재생성")
    ap.add_argument("--dry-run", action="store_true", help="조립만 출력, POST 안 함")
    args = ap.parse_args(argv)

    if not (args.named or args.common):
        args.named = args.common = True  # 기본: 둘 다

    frag = load_json(Path(args.fragments))
    spec = INJECT[args.model]
    workflow_path = CFG_DIR / spec["workflow"]
    base_graph = load_json(workflow_path)

    tasks = []
    if args.named:
        tasks += list(named_tasks(load_json(ROOT / "data" / "portrait-map.json")))
    if args.common:
        tasks += list(common_tasks(load_json(CFG_DIR / "common-map.json")))

    want = set()
    if args.only:
        want |= {s.strip() for s in args.only.split(",") if s.strip()}
    if args.rng:
        want |= set(parse_range(args.rng))
    if want:
        tasks = [t for t in tasks if t["art"] in want]
    if args.limit:
        tasks = tasks[:args.limit]

    if not tasks:
        print("대상 0건", file=sys.stderr)
        return 1

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    manifest = out_dir / "manifest.jsonl"
    client_id = uuid.uuid4().hex

    ok, skipped, failed = [], [], []
    print(f"model={args.model}  workflow={workflow_path.name}  대상 {len(tasks)}건  "
          f"host={args.host}{'  (DRY RUN)' if args.dry_run else ''}")

    for t in tasks:
        art = t["art"]
        seed = seed_for(t["key"])
        if seed != t["stored_seed"]:
            print(f"  ! {art}: 시드 불일치 (계산 {seed} ≠ 맵 {t['stored_seed']}) — 맵/규칙 확인", file=sys.stderr)
            failed.append(art)
            continue

        if t["named"] and t["name"] in frag["flag_iconography"]:
            print(f"  · {art} {t['name']}: 원전 도상 플래그 — 프롬프트에 통념 넣지 않고 1차 생성 (§4.8)")

        prompt = assemble(frag, tint=t["tint"], class0=t["class0"], disp_keys=t["disp_keys"],
                          faction=t["faction"], traits=t["traits"], named=t["named"])
        negative = frag["negative"]
        if args.model == "flux":
            prompt += ", avoid: " + negative

        if args.dry_run:
            print(f"\n--- {art}  seed={seed}")
            print(prompt)
            ok.append(art)
            continue

        dst = out_dir / f"{art}.png"
        if dst.exists() and not args.force:
            skipped.append(art)
            continue

        graph = json.loads(json.dumps(base_graph))  # deep copy
        inject(graph, spec, text=prompt, negative=negative, seed=seed, fileprefix=art)

        try:
            pid = api_post(args.host, graph, client_id)
            entry = api_wait(args.host, pid, args.timeout)
            info = api_first_image(entry)
            sha = api_fetch(args.host, info, dst)
        except Exception as e:  # noqa: BLE001 — 배치는 한 건 실패로 멈추지 않는다
            print(f"  ✗ {art}: {e}", file=sys.stderr)
            failed.append(art)
            continue

        with manifest.open("a", encoding="utf-8") as f:
            f.write(json.dumps({
                "art": art, "model": args.model, "seed": seed, "prompt": prompt,
                "negative_prompt": negative,
                "out": dst.name, "sha256": sha, "comfy_filename": info["filename"],
                "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
            }, ensure_ascii=False) + "\n")
        print(f"  ✓ {art}  {sha[:12]}")
        ok.append(art)

    print(f"\n완료 {len(ok)} · 건너뜀 {len(skipped)} · 실패 {len(failed)}")
    if failed:
        print("실패:", ",".join(failed))
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
