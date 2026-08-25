# -*- coding: utf-8 -*-
"""
SEONGHANJI — ID 부여기 (data-model.md §2 · §7-2)

문서에서 개체 목록을 추출해 `data/_ids.json` 레지스트리를 만든다.
**결정적으로 동작한다** — 같은 문서를 넣으면 항상 같은 ID가 나온다.
부여 순서는 각 정본 문서의 표 순서를 그대로 따른다 (data-model.md 검토 포인트 5).

주의: ID는 불변이다. 이 스크립트를 다시 돌려 순서가 바뀌면 안 된다.
문서에서 항목이 삭제되면 결번으로 두고 재사용하지 않는다 (§2.1 규칙 2).

실행: PYTHONIOENCODING=utf-8 python tools/assign_ids.py
"""
import io, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read(p):
    return io.open(os.path.join(ROOT, p), encoding='utf-8').read()


def cells(line):
    return [c.strip() for c in line.strip().strip('|').split('|')]


def clean(s):
    """굵게·별표·괄호주석을 벗겨 순수 이름만 남긴다."""
    s = s.replace('**', '').replace('★', '').strip()
    s = re.sub(r'\s*\([^)]*\)\s*', '', s).strip()
    return s


# ---------------------------------------------------------------- 성계 19
def systems():
    txt = read('docs/01-world/star-map.md')
    out, seen = [], set()
    for line in txt.split('\n'):
        if not line.startswith('| '):
            continue
        c = cells(line)
        if len(c) < 6:
            continue
        no = c[0].replace('**', '').strip()
        if not re.match(r'^\d+(-b)?$', no):
            continue
        name = clean(c[1])
        if not name or name in seen:
            continue
        seen.add(name)
        out.append({"name": name, "display_no": no,
                    "display_name": c[2].split('·')[0].replace('**', '').strip(),
                    "grade": clean(c[5]) if len(c) > 5 else None})
    return out


# ---------------------------------------------------------------- 회랑 15
def corridors():
    txt = read('docs/01-world/star-map.md')
    out, scale = [], None
    for line in txt.split('\n'):
        if line.startswith('### 3.1'):
            scale = '대회랑'; continue
        if line.startswith('### 3.2'):
            scale = '중회랑'; continue
        if line.startswith('### 3.3') or line.startswith('## 4'):
            scale = None
        if scale and line.startswith('| **') and '회랑' in line or \
           (scale and line.startswith('| **') and ('도' in line or '관문' in line)):
            c = cells(line)
            if len(c) < 4 or c[0].startswith('---'):
                continue
            name = clean(c[0])
            if name in ('회랑',):
                continue
            out.append({"name": name, "scale": scale,
                        "connects_raw": c[1].replace('**', '').strip(),
                        "source": c[2].strip()})
    return out


# ---------------------------------------------------------------- 권역 45
def regions():
    txt = read('docs/01-world/region-power.md').split('\n')
    out = []
    cur = []          # 현재 #### 블록이 다루는 성계 목록
    in23 = False      # §2.3 2권역 일괄 표

    for line in txt:
        if line.startswith('### 2.3'):
            in23 = True; cur = []; continue
        if line.startswith('## 3') or line.startswith('### 3'):
            break
        if line.startswith('#### '):
            head = line[5:].strip()
            if '복구도' in head or '판정' in head:
                cur = []; continue
            head = re.split(r'\s*[—–-]\s*', head)[0]   # 「형주 (총 85) — 태양계 소재」의 주석 제거
            cur = [clean(x) for x in head.split('·')]
            cur = [x for x in cur if x and '태양계권' not in x]
            continue

        if not line.startswith('| ') or line.startswith('|---'):
            continue
        c = cells(line)

        if in23:
            # | 성계 (n) | | 주권역 ★ | 부권역 |
            if len(c) < 4 or c[0] in ('성계',):
                continue
            sysname = clean(c[0])
            if not sysname or sysname.startswith('-'):
                continue
            for raw in (c[2], c[3]):
                nm = re.sub(r'\s*\d+\s*$', '', clean(raw)).strip()
                if nm:
                    out.append({"name": nm, "system": sysname})
            continue

        if not cur or c[0] in ('권역',) or c[0].startswith('-'):
            continue
        raw = c[0]
        # "남정권 ★ (한중)" → 성계 = 한중
        m = re.search(r'\(([^)]+)\)', raw.replace('**', ''))
        sysname = cur[0]
        if m and m.group(1).strip() in cur:
            sysname = m.group(1).strip()
        nm = clean(raw)
        if not nm:
            continue
        out.append({"name": nm, "system": sysname})
    return out


# ---------------------------------------------------------------- 인물 492
def characters():
    txt = read('docs/04-campaign/character-assignments.md')
    out, seen = [], set()
    for line in txt.split('\n'):
        if not line.startswith('| '):
            continue
        c = cells(line)
        if len(c) < 9 or c[1] in ('계층', '---') or c[0] == '인물':
            continue
        if c[1] not in ('명장', '일반무장', '이역'):
            continue
        # 괄호를 벗기지 않는다 — 동명이인의 구분자다 (§2.1 규칙 4의 실물 사례).
        # 마충/마충(오) · 유선(촉)/유선(유표) · 장제(오)/장제(동탁·여포) · 장횡 2인
        nm = c[0].replace('**', '').replace('★', '').strip()
        base = clean(c[0])
        if not nm or nm in seen:
            continue
        seen.add(nm)
        out.append({"name": nm, "base_name": base,
                    "tier": c[1], "origin_faction": c[2],
                    "presence": {y: c[3 + i] for i, y in
                                 enumerate(['190', '200', '208', '219', '228', '263'])}})

    # 이역 93인은 배치표(399명)에 없다 — foreign-90-stats.md 에서 이어 붙인다.
    # 순서상 뒤에 오므로 기존 CHR-0001~0399 는 영향을 받지 않는다 (§2.1 규칙 1).
    ftxt = read('docs/02-characters/foreign-90-stats.md')
    polity = None
    for line in ftxt.split('\n'):
        if line.startswith('### '):
            # 「### §8.7 동이권 — 백제 (12인)」 → 백제
            tail = re.split(r'\s*[—–-]\s*', line.lstrip('# ').strip())[-1]
            tail = re.sub(r'^\S*\d+(\.\d+)?\s*', '', tail)   # 「§8.9 파저·판순만이」의 절 번호 제거
            polity = re.sub(r'\s*\([^)]*\)\s*', '', tail).strip() or polity
            continue
        if not line.startswith('| '):
            continue
        c = cells(line)
        if len(c) != 10:
            continue
        # | 인물 | 활동기 | 계층 | 클래스 | 통솔 | 무력 | 지력 | 정치 | 매력 | 특성 |
        if not all(re.match(r'^\d+$', c[i]) for i in range(4, 9)):
            continue
        nm = c[0].replace('**', '').strip()
        if not nm:
            continue
        if nm in seen:
            # 문서 간 동명이인. 문서 자체 관례(마충(오))를 따라 소속으로 구분한다.
            # 실례: 유기 — 유표의 아들(208년경) vs 백제 인물(261~)
            nm = "%s(%s)" % (nm, polity or "이역")
            if nm in seen:
                continue
        seen.add(nm)
        out.append({"name": nm, "base_name": clean(c[0]), "tier": "이역",
                    "polity": polity, "origin_faction": c[2]})
    return out


# ---------------------------------------------------------------- 함종·진형
def ship_types():
    # ship-specs.md §2.2 「해당 함종」 열에서 추출
    txt = read('docs/03-systems/ship-specs.md')
    order = ['강습모함', '공성함', '포격함', '전열함', '보급함', '전자전함']
    found = [n for n in order if n in txt]
    return [{"name": n} for n in found]


def formations():
    txt = read('docs/03-systems/ship-specs.md')
    out, seen = [], set()
    for line in txt.split('\n'):
        if not line.startswith('| **') or line.count('|') < 9:
            continue
        c = cells(line)
        nm = clean(c[0])
        if nm.endswith('진') and nm not in seen:
            seen.add(nm)
            out.append({"name": nm})
    return out


# ---------------------------------------------------------------- 시나리오·ACT
SCENARIOS = [(190, '군웅할거', 14), (200, '관도 전야', 12), (208, '적벽 전야', 10),
             (219, '삼국 정립', 12), (228, '출사표', 11), (263, '천하통일', 9)]


def scenarios():
    return [{"year": y, "name": n, "act_count": a} for y, n, a in SCENARIOS]


def acts():
    # name 은 ID 부여의 안정 키다. 반드시 있어야 하고 바뀌면 안 된다.
    out = []
    for i, (y, n, a) in enumerate(SCENARIOS, start=1):
        for k in range(a):
            sid = "SCN-%02d" % i
            out.append({"name": "%s#%02d" % (sid, k), "scenario": sid, "no": k})
    return out


# ---------------------------------------------------------------- 조립
SPECS = [
    ("systems",    "SYS", 2, 19,  systems,    "star-map.md §1"),
    ("regions",    "RGN", 2, 45,  regions,    "region-power.md §2"),
    ("corridors",  "COR", 2, 15,  corridors,  "star-map.md §3.1-3.2"),
    ("characters", "CHR", 4, 492, characters,
     "character-assignments.md §3 (399) + foreign-90-stats.md (93)"),
    ("ship_types", "SHP", 2, 6,   ship_types, "ship-specs.md §2.2"),
    ("formations", "FRM", 2, 7,   formations, "ship-specs.md §5"),
    ("scenarios",  "SCN", 2, 6,   scenarios,  "scenario-setup.md §8"),
    ("acts",       "ACT", 2, 68,  acts,       "time-and-monetization.md §3.4.1"),
]


REG_PATH = os.path.join(ROOT, 'data', '_ids.json')


def load_existing():
    """기존 레지스트리를 읽어 이름→ID 사상을 만든다. 없으면 빈 사상."""
    if not os.path.exists(REG_PATH):
        return {}, {}
    old = json.load(io.open(REG_PATH, encoding='utf-8'))
    name2id, retired = {}, {}
    for key, blk in old.items():
        if not isinstance(blk, dict) or "items" not in blk:
            continue
        name2id[key] = {}
        retired[key] = []
        for it in blk["items"]:
            k = it.get("name")
            if not k:
                raise SystemExit(
                    "기존 레지스트리 %s 에 name 없는 항목: %s — 안정 키 없이는 ID 불변을 보장할 수 없다"
                    % (key, it.get("id")))
            name2id[key][k] = it["id"]
            if it.get("retired"):
                retired[key].append(it)
    return name2id, retired


def assign(key, pre, width, items, name2id, retired):
    """§2.1 규칙 1·2 강제 — 기존 ID는 재사용하고, 사라진 항목은 결번으로 남긴다."""
    known = name2id.get(key, {})
    used = {int(v.split('-')[-1]) for v in known.values()} if known else set()
    nxt = max(used) + 1 if used else 1
    seen_now = set()

    for it in items:
        k = it.get("name")
        if not k:
            raise SystemExit("%s: name 없는 항목 — 안정 키가 필요하다: %r" % (key, it))
        seen_now.add(k)
        if k in known:
            it["id"] = known[k]                      # 규칙 1 — 불변
        else:
            while nxt in used:
                nxt += 1
            it["id"] = "%s-%0*d" % (pre, width, nxt)
            used.add(nxt); nxt += 1

    # 규칙 2 — 문서에서 사라진 항목은 결번으로 보존한다
    gone = [{"id": i, "name": n, "retired": True}
            for n, i in known.items() if n not in seen_now]
    prior = {r["id"] for r in retired.get(key, [])}
    for g in gone:
        if g["id"] not in prior:
            print("    결번 처리: %s %s (문서에서 사라짐)" % (g["id"], g["name"]))
    return items + gone


def main():
    name2id, retired = load_existing()
    reg, errs = {}, []
    for key, pre, width, expect, fn, src in SPECS:
        items = fn()
        if len(items) != expect:
            errs.append("%s: %d개 추출 — 정본은 %d개" % (key, len(items), expect))
        items = assign(key, pre, width, items, name2id, retired)
        live = [i for i in items if not i.get("retired")]
        reg[key] = {"source": src, "count": len(live), "items": items}

    sysnames = {i["name"] for i in reg["systems"]["items"]}
    for r in reg["regions"]["items"]:
        if r["system"] not in sysnames:
            errs.append("regions: %s 의 성계 '%s' 가 성계 목록에 없다" % (r["name"], r["system"]))

    if errs:
        print("추출 검증 실패:")
        for e in errs:
            print("  -", e)
        print("\n(레지스트리는 쓰지 않았다. 파서를 고칠 것)")
        return 1

    os.makedirs(os.path.join(ROOT, 'data'), exist_ok=True)
    p = os.path.join(ROOT, 'data', '_ids.json')
    io.open(p, 'w', encoding='utf-8').write(
        json.dumps({"note": "ID 레지스트리. 불변 · 결번 재사용 금지 (data-model.md §2.1)",
                    "generated_by": "tools/assign_ids.py", **reg},
                   ensure_ascii=False, indent=2) + '\n')
    for key, pre, w2, expect, fn, src in SPECS:
        r = [i["id"] for i in reg[key]["items"] if not i.get("retired")]
        dead = len(reg[key]["items"]) - len(r)
        print("  %-11s %3d  %s ~ %s%s" % (key, reg[key]["count"], r[0], r[-1],
                                          "  (결번 %d)" % dead if dead else ""))
    print("\ndata/_ids.json 작성 완료")
    return 0


if __name__ == '__main__':
    sys.exit(main())
