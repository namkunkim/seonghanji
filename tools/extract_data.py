# -*- coding: utf-8 -*-
"""
SEONGHANJI — 문서 → 데이터 추출기 (data-model.md §7-3)

`data/_ids.json` 의 ID를 키로 삼아 문서에서 실제 값을 뽑아 `data/*.json` 을 만든다.
**1회성 작업이 아니라 재현 가능한 변환이다** — 문서를 고치면 다시 돌린다.

추출할 수 없는 값은 **만들어내지 않는다.** null 로 두고 리포트에 적는다.

실행: PYTHONIOENCODING=utf-8 python tools/extract_data.py
"""
import io, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAPS = []
CORDATA = []


def read(p):
    return io.open(os.path.join(ROOT, p), encoding='utf-8').read()


def cells(line):
    return [c.strip() for c in line.strip().strip('|').split('|')]


def clean(s):
    s = s.replace('**', '').replace('★', '').strip()
    return re.sub(r'\s*\([^)]*\)\s*', '', s).strip()


def nkey(name):
    """문서 간 동명이인 구분자 표기 차이를 흡수한다.
    officers-256 「장횡(서량)」 vs character-assignments 「장횡(서량 진영)」.
    괄호 안에서 진영·계·측 같은 꼬리말을 떼고 비교한다."""
    m = re.match(r'^(.+?)\((.+)\)$', name.strip())
    if not m:
        return name.strip()
    base, q = m.group(1).strip(), m.group(2).strip()
    q = re.sub(r'\s*(진영|계열|계|측)$', '', q).strip()
    return "%s(%s)" % (base, q)


def num(s):
    m = re.search(r'-?\d+(\.\d+)?', s.replace('**', ''))
    return float(m.group(0)) if m else None


def write(name, obj):
    p = os.path.join(ROOT, 'data', name)
    io.open(p, 'w', encoding='utf-8').write(
        json.dumps(obj, ensure_ascii=False, indent=2) + '\n')
    print("  %-20s %4d건" % (name, len(obj)))


IDS = json.load(io.open(os.path.join(ROOT, 'data', '_ids.json'), encoding='utf-8'))
SYS = {i["name"]: i["id"] for i in IDS["systems"]["items"]}
RGN = {i["name"]: i["id"] for i in IDS["regions"]["items"]}
CHR = {i["name"]: i["id"] for i in IDS["characters"]["items"]}
SHP = {i["name"]: i["id"] for i in IDS["ship_types"]["items"]}
FRM = {i["name"]: i["id"] for i in IDS["formations"]["items"]}


# ================================================================ 성계
def systems():
    byname = {i["name"]: i for i in IDS["systems"]["items"]}
    regs = {}
    for r in IDS["regions"]["items"]:
        regs.setdefault(r["system"], []).append(RGN[r["name"]])
    txt = read('docs/01-world/star-map.md')
    planets = {}
    for line in txt.split('\n'):
        if not line.startswith('| '):
            continue
        c = cells(line)
        if len(c) < 6 or not re.match(r'^\d+(-b)?$', c[0].replace('**', '').strip()):
            continue
        nm = clean(c[1])
        if nm in byname:
            planets[nm] = [x.strip() for x in
                           c[3].replace('**', '').split('·') if x.strip()]
    out = []
    for nm, meta in byname.items():
        out.append({"id": meta["id"], "name": nm,
                    "display_name": meta.get("display_name") or nm,
                    "display_no": meta.get("display_no"),
                    "split_from": None,
                    "grade": meta.get("grade"),
                    "terran_planets": planets.get(nm, []),
                    "regions": regs.get(nm, [])})
    # 분리 이력 (star-map.md §1 분리 표)
    for line in read('docs/01-world/star-map.md').split('\n'):
        if not line.startswith('| **') or '분리' in line:
            continue
        c = cells(line)
        if len(c) == 3 and clean(c[0]) in SYS and clean(c[1]) in SYS:
            for o in out:
                if o["name"] == clean(c[0]):
                    o["split_from"] = SYS[clean(c[1])]
    miss = [o["name"] for o in out if not o["regions"]]
    if miss:
        GAPS.append("systems: 권역이 비어 있는 성계 %s" % miss)
    return out


# ================================================================ 권역
def regions():
    meta = {i["name"]: i for i in IDS["regions"]["items"]}
    vals = {}
    txt = read('docs/01-world/region-power.md').split('\n')
    in23 = False
    for line in txt:
        if line.startswith('### 2.3'):
            in23 = True
        if line.startswith('## 3'):
            break
        if not line.startswith('| '):
            continue
        c = cells(line)
        if in23:
            # | 성계 (n) | | 주권역 26 | 부권역 19 |
            if len(c) < 4 or c[0] in ('성계',):
                continue
            for raw in (c[2], c[3]):
                nm = re.sub(r'\s*\d+\s*$', '', clean(raw)).strip()
                n = num(raw)
                if nm in meta and n is not None:
                    vals[nm] = {"population": int(n), "production": None,
                                "income": None, "dev_potential": None,
                                "defense": None, "notes": "§2.3 2권역 일괄 — 총 국력만 기재"}
            continue
        # | 권역 | 인구 | 생산 | 수입 | 개발여지 | 방어 | (비고) |
        if len(c) < 6 or c[0] in ('권역',):
            continue
        nm = clean(c[0])
        if nm not in meta:
            continue
        if num(c[1]) is None or num(c[2]) is None:
            continue
        vals[nm] = {"population": int(num(c[1])), "production": int(num(c[2])),
                    "income": int(num(c[3])) if num(c[3]) is not None else None,
                    "dev_potential": (clean(c[4]) if clean(c[4]) not in ('', '—', '-') else None),
                    "defense": clean(c[5]) or None,
                    "notes": (c[6].strip() if len(c) > 6 else "") or None}
    # 거점·귀속 항로 — partial-occupation.md §2.1
    holds, hosted, seat = {}, {}, {}
    for line in read('docs/03-systems/partial-occupation.md').split('\n'):
        if not line.startswith('| '):
            continue
        c = cells(line)
        if len(c) != 4 or c[1] in ('권역', '주권역 ★'):
            continue
        nm = clean(c[1])
        if nm not in meta:
            continue
        seat[nm] = '★' in c[1]
        # **괄호 안의 가운뎃점을 보호한다.** 「기저(사예 · 옹주)」를 그냥 쪼개면
        # 「기저(사예」와 「옹주)」가 되어 방향 정보가 깨진다 (2026-08-25).
        # star-map §4.5 에서 고쳤던 것과 같은 함정이다.
        SEP = "␟"

        def split_protect(text):
            t = re.sub(r'\(([^)]*)\)',
                       lambda m: '(' + m.group(1).replace('·', SEP) + ')',
                       text.replace('**', ''))
            return [x.replace(SEP, '·').strip()
                    for x in re.split(r'\s*·\s*', t)
                    if x.strip() and x.strip() != '—']

        holds[nm] = split_protect(c[2])
        hosted[nm] = split_protect(c[3])

    out = []
    for nm, m in meta.items():
        v = vals.get(nm, {})
        if not v:
            GAPS.append("regions: %s 의 수치를 찾지 못했다" % nm)
        out.append({"id": m["id"], "name": nm, "system": SYS[m["system"]],
                    "is_seat": seat.get(nm), "population": v.get("population"),
                    "production": v.get("production"), "income": v.get("income"),
                    "dev_potential": v.get("dev_potential"),
                    "defense": v.get("defense"), "adjacent": [],
                    "strongholds": holds.get(nm, []),
                    "routes_hosted": hosted.get(nm, []),
                    "notes": v.get("notes")})
    nohost = [o["name"] for o in out if not o["routes_hosted"]]
    if nohost:
        GAPS.append("regions: 귀속 항로가 비어 있는 권역 %d개 — partial-occupation.md "
                    "§2.2 2급 성계 표에는 항로 열이 없다 (예: %s)" % (len(nohost), nohost[:5]))
    GAPS.append("regions: 권역 간 인접(adjacent) 자체는 여전히 표가 없으나, "
                "귀속 항로에서 **전부 유도된다** (2026-08-25). 성계 간 간선 37개가 "
                "모두 문서 근거로 이어지며 추정 보완은 0건이다")
    return out


# ================================================================ 회랑
def resolve(tok):
    """회랑 끝점 토큰을 SYS / RGN / 외부 로 푼다."""
    t = clean(tok)
    if t in SYS:
        return {"kind": "system", "id": SYS[t], "name": t}
    if t in RGN:
        return {"kind": "region", "id": RGN[t], "name": t}
    if t + '권' in RGN:
        return {"kind": "region", "id": RGN[t + '권'], "name": t + '권'}
    # 「옹주 서부」처럼 성계명 + 방위 수식이 붙은 경우
    for s in SYS:
        if t.startswith(s):
            return {"kind": "system", "id": SYS[s], "name": s, "qualifier": t[len(s):].strip()}
    return {"kind": "external", "id": None, "name": t}


def corridors():
    meta = {i["name"]: i for i in IDS["corridors"]["items"]}
    out, ext = [], []
    for nm, m in meta.items():
        raw = m.get("connects_raw", "")
        parts = re.split(r'\s*(?:↔|~)\s*', raw)
        sides = []
        for p in parts:
            side = [resolve(t) for t in re.split(r'\s*·\s*', p) if t.strip()]
            sides.append(side)
        for s in sides:
            for e in s:
                if e["kind"] == "external":
                    ext.append("%s: %s" % (nm, e["name"]))
        out.append({"id": m["id"], "name": nm, "scale": m["scale"],
                    "sides": [[e["id"] or ("EXT:" + e["name"]) for e in s] for s in sides],
                    "multiplier": 5.0 if m["scale"] == '대회랑' else 3.0,
                    "source": m.get("source"), "effect": None, "canal": None})
    if ext:
        GAPS.append("corridors: 성계·권역으로 풀리지 않는 끝점 %s" % sorted(set(ext)))
    multi = [o["name"] for o in out if any(len(s) > 1 for s in o["sides"])]
    if multi:
        print("    참고: 한쪽 끝이 복수인 회랑 %s — 스키마를 sides 로 이미 고쳤다" % multi)
    return out


# ================================================================ 항로망
def routes():
    """성계 간 연결망.

    두 출처를 합친다.
      - star-map.md §4.5 인접 관계표 → 고속항로 · 기저 항로
      - corridors.json                → 회랑 (회랑 하나 = 간선 하나)

    **회랑을 성계 쌍으로 뭉치지 않는다.** 진령삼도와 기산도는 둘 다 옹주↔한중이지만
    다른 길이며(전자는 3경로 택1·은닉 가능), 하나로 합치면 그 차이가 사라진다.
    """
    rgn2sys = {r["id"]: r["system"] for r in json.load(
        io.open(os.path.join(ROOT, "data", "regions.json"), encoding="utf-8"))}

    def endpoints(cor):
        """회랑의 양쪽을 성계 수준으로 올린다."""
        out = []
        for side in cor["sides"]:
            ids = set()
            for x in side:
                ids.add(rgn2sys.get(x, x))
            out.append(sorted(ids))
        return out

    out, corr_pairs = [], set()

    # ① 회랑 — 하나씩 그대로 간선이 된다
    for cor in CORDATA:
        eps = endpoints(cor)
        for a in eps[0]:
            for b in eps[1]:
                if a == b:
                    continue
                corr_pairs.add(tuple(sorted([a, b])))
                out.append({"connects": sorted([a, b]), "kind": "회랑",
                            "multiplier": cor["multiplier"], "corridor": cor["id"],
                            "_name": cor["name"]})

    # ② 인접 관계표 — 고속·기저 항로
    #
    # **회랑이 있는 성계 쌍에는 병렬 간선을 만들지 않는다.**
    # star-map.md §4.5 가 「형주(고·양번관문)」처럼 하나의 간선에 고속항로 표기와
    # 관문 이름을 함께 적는다 — 대항로가 회랑을 **지나는** 것이지 옆으로 도는 것이 아니다.
    # 병렬로 두면 이릉협도·함곡회랑·양번관문을 ×1 로 우회할 수 있어
    # 불가침 §2-2(회랑은 어떤 수단으로도 ×1이 되지 않는다)와
    # §2-4(봉쇄는 성립한다)가 코드에서 무너진다.
    #
    # 배율: 고속항로가 **관문**(호뢰·관도·양번)을 지나면 §3.1 의
    # 「고속항로 + 관문 통과 68분 ×1.5」를 쓴다. 그 밖의 회랑은 회랑 배율 그대로.
    GATEWAYS = ("호뢰관문", "관도관문", "양번관문")
    grab, seen = False, set()
    missing, merged = [], []
    for line in read('docs/01-world/star-map.md').split('\n'):
        if line.startswith('### 4.5'):
            grab = True; continue
        if grab and line.startswith('### 4.6'):
            break
        if not grab or not line.startswith('| '):
            continue
        c = cells(line)
        if len(c) != 2 or c[0] in ('성계',) or c[0].startswith('-'):
            continue
        aid = SYS.get(clean(c[0])) or ("EXT:" + clean(c[0]))
        # 괄호 안의 · 를 보호한다. 「형주(고·양번관문)」을 그냥 쪼개면
        # 「형주(고」 라는 가짜 노드가 생긴다 (2026-08-24 발견).
        row = re.sub(r'\(([^)]*)\)',
                     lambda m: '(' + m.group(1).replace('·', '␟') + ')', c[1])
        for tok in re.split(r'\s*·\s*', row):
            tok = tok.replace('␟', '·')
            tok = tok.strip()
            if not tok or tok.startswith('*('):
                continue
            fast = '(고' in tok
            kind = "고속항로" if fast else ("회랑" if '(회' in tok else "기저항로")
            nm = clean(re.sub(r'\*|\(.*?\)', '', tok)).strip()
            if not nm:
                continue
            bid = SYS.get(nm) or ("EXT:" + nm)
            pair = tuple(sorted([aid, bid]))

            if pair in corr_pairs:
                # 회랑이 이미 있는 쌍 — 별개 간선을 만들지 않는다.
                # 고속항로가 관문을 지나는 경우만 배율을 x1.5 로 낮춘다.
                if fast:
                    for e in out:
                        if tuple(sorted(e["connects"])) == pair and e["kind"] == "회랑":
                            if e["_name"] in GATEWAYS and e["multiplier"] > 1.5:
                                e["multiplier"] = 1.5
                                e["kind"] = "고속항로+관문"
                                merged.append("%s(%s)" % (e["_name"], "x1.5"))
                continue

            if kind == "회랑":
                missing.append("%s<->%s" % pair)
                continue
            if pair in seen:
                continue
            seen.add(pair)
            out.append({"connects": list(pair), "kind": kind,
                        "multiplier": 1.0 if kind == "고속항로" else 4.0,
                        "corridor": None, "_name": ""})

    if merged:
        print("    회랑 병합: 고속항로가 관문을 지나는 간선 %d개를 x1.5 로 (%s)"
              % (len(merged), ", ".join(sorted(set(merged)))))

    out.sort(key=lambda r: (r["connects"][0], r["connects"][1], r["kind"]))
    for i, r in enumerate(out, start=1):
        r["id"] = "RTE-%03d" % i
    out = [{"id": r["id"], "connects": r["connects"], "kind": r["kind"],
            "multiplier": r["multiplier"], "corridor": r["corridor"]} for r in out]

    if missing:
        GAPS.append("routes: star-map.md §4.5 인접표가 (회)로 표시했으나 회랑 15개 목록에 "
                    "대응물이 없는 간선 %s. §3.1-3.2 어디에도 없다 — "
                    "인접표의 오기이거나 회랑 하나가 누락된 것" % sorted(set(missing)))
    return out


# ================================================================ 인물
def characters():
    meta = {i["name"]: i for i in IDS["characters"]["items"]}
    nmap = {nkey(k): k for k in meta}          # 정규 키 → 정본 이름
    stats, disp, traits = {}, {}, {}

    def find(raw, tier=None):
        raw = raw.replace('**', '').replace('★', '').strip()
        for cand in (raw, clean(raw), nmap.get(nkey(raw))):
            if cand and cand in meta:
                if tier is None or meta[cand].get("tier") == tier:
                    return cand
        return None

    # 명장 150 — | 인물 | 격 | 통솔 | 무력 | 지력 | 정치 | 매력 |
    for line in read('docs/02-characters/generals-stats.md').split('\n'):
        if not line.startswith('| '):
            continue
        c = cells(line)
        if len(c) != 7:
            continue
        if not all(num(c[i]) is not None for i in range(2, 7)):
            continue
        nm = clean(c[0])
        if nm in meta:
            stats[nm] = [int(num(c[i])) for i in range(2, 7)]

    # 일반 249 — 표가 두 변종이다.
    #   11칸: 인물 | 시대 | 격 | 클래스 | 성향 | 통솔..매력 | 특성
    #   10칸: 인물 |      격 | 클래스 | 성향 | 통솔..매력 | 특성   ← 시대 열 없음
    for line in read('docs/02-characters/officers-256.md').split('\n'):
        if not line.startswith('| '):
            continue
        c = cells(line)
        off = {11: 5, 10: 4}.get(len(c))
        if off is None:
            continue
        if not all(num(c[i]) is not None for i in range(off, off + 5)):
            continue
        key = find(c[0])
        if key:
            stats[key] = [int(num(c[i])) for i in range(off, off + 5)]
            disp[key] = clean(c[off - 1]) or None
            traits[key] = c[off + 5] if len(c) > off + 5 else None

    # 이역 93 — | 인물 | 활동기 | 계층 | 클래스 | 통솔..매력 | 특성 |
    for line in read('docs/02-characters/foreign-90-stats.md').split('\n'):
        if not line.startswith('| '):
            continue
        c = cells(line)
        if len(c) != 10:
            continue
        if not all(num(c[i]) is not None for i in range(4, 9)):
            continue
        nm = c[0].replace('**', '').strip()
        # 반드시 이역 계층에서만 찾는다. 「유기」처럼 다른 계층에 동명이인이 있어
        # 이름만으로 조회하면 엉뚱한 인물에 스탯이 덮인다 (2026-08-24 발견).
        key = find(nm, tier="이역")
        if key is None:
            cand = [k for k, m in meta.items()
                    if m.get("tier") == "이역" and k.startswith(nm + '(')]
            key = cand[0] if cand else None
        if key:
            stats[key] = [int(num(c[i])) for i in range(4, 9)]
            traits[key] = c[9] or None

    # 명장 성향 예외 22인 (dispositions.md §6.1)
    for line in read('docs/02-characters/dispositions.md').split('\n'):
        if not line.startswith('| '):
            continue
        c = cells(line)
        if len(c) != 3:
            continue
        d = clean(c[1])
        if d not in ('절의', '명사', '실무', '야심', '무뢰'):
            continue
        for nm in re.split(r'\s*·\s*', clean(c[0])):
            k = find(nm)
            if k:
                disp[k] = d

    out, nostat, nodisp = [], [], []
    for nm, m in meta.items():
        st = stats.get(nm)
        if not st:
            nostat.append(nm)
        if not disp.get(nm):
            nodisp.append(nm)
        out.append({"id": m["id"], "name": nm, "tier": m["tier"],
                    "stats": (dict(zip(["통솔", "무력", "지력", "정치", "매력"], st))
                              if st else None),
                    "disposition": disp.get(nm),
                    "traits": [traits[nm]] if traits.get(nm) else [],
                    "origin_faction": m.get("origin_faction")})
    if nostat:
        GAPS.append("characters: 스탯 미확보 %d명 (예: %s)" % (len(nostat), nostat[:6]))
    if nodisp:
        GAPS.append("characters: 성향 미확보 %d명 — 명장 성향은 dispositions.md 의 "
                    "규칙 배정이며 표로 열거되어 있지 않다 (예외 22인만 표에 있다)" % len(nodisp))
    return out


# ================================================================ 배치
def assignments():
    out = []
    years = ['190', '200', '208', '219', '228', '263']
    for i in IDS["characters"]["items"]:
        pres = i.get("presence")
        if not pres:
            continue
        for k, y in enumerate(years, start=1):
            v = pres[y]
            status = "소속"
            if v in ('미등장', '사망', '재야'):
                status = v
            out.append({"character": i["id"], "scenario": "SCN-%02d" % k,
                        "status": status,
                        "faction": None if status != "소속" else v,
                        "region": None})
    GAPS.append("assignments: 인물별 배치 권역(region)이 문서에 없다 — "
                "scenario-setup.md 는 세력별 권역 보유만 적고 인물의 소재는 적지 않는다")
    return out


# ================================================================ 함종·진형
def ship_types():
    coeff = {}
    grab = False
    for line in read('docs/03-systems/combat.md').split('\n'):
        if line.startswith('### 4.1'):
            grab = True; continue
        if grab and line.startswith('### 4.2'):
            break
        if grab and line.startswith('| **'):
            c = cells(line)
            if len(c) == 6:
                coeff[clean(c[0])] = [num(x) for x in c[1:6]]
    lengths = {}
    for line in read('docs/03-systems/ship-specs.md').split('\n'):
        for nm in SHP:
            m = re.search(re.escape(nm) + r'\s*([\d,]{3,5})m', line)
            if m:
                lengths.setdefault(nm, int(m.group(1).replace(',', '')))
    CLASS = {"강습모함": "모함", "공성함": "공성함", "포격함": "주력함",
             "전열함": "주력함", "보급함": "지원함", "전자전함": "초계함"}
    out = []
    for nm, sid in SHP.items():
        cf = coeff.get(nm)
        if cf and cf[4] is None:
            GAPS.append("ship_types: %s 의 ⑤ 결착 계수가 수치가 아니다 (「사기 유지」)" % nm)
        out.append({"id": sid, "name": nm, "ship_class": CLASS[nm],
                    "length_m": lengths.get(nm),
                    "phase_coefficients": (dict(zip(
                        ["contact", "barrage", "engagement", "assault", "resolution"],
                        cf)) if cf else None)})
        if not cf:
            GAPS.append("ship_types: %s 의 페이즈 계수를 찾지 못했다" % nm)
    return out


def formations():
    out = {}
    for line in read('docs/03-systems/ship-specs.md').split('\n'):
        if not line.startswith('| **') or line.count('|') < 10:
            continue
        c = cells(line)
        nm = clean(c[0])
        if nm not in FRM or nm in out:
            continue
        cf = [num(x) for x in c[3:8]]
        out[nm] = {"id": FRM[nm], "name": nm,
                   "directive": clean(c[1]) or None, "width": clean(c[2]) or None,
                   "coefficients": dict(zip(
                       ["contact", "barrage", "engagement", "assault", "resolution"], cf)),
                   "required_command": int(num(c[8])) if num(c[8]) is not None else None,
                   "requires_trait": "팔진 전용" if nm == "팔진" else None}
    miss = [n for n in FRM if n not in out]
    if miss:
        GAPS.append("formations: 계수 미확보 %s" % miss)
    return [out[n] for n in FRM if n in out]


# ================================================================ 시나리오·ACT·이벤트
DUR = {1: 53.0, 2: 43.0, 3: 31.5, 4: 59.0, 5: 69.0, 6: 49.0}
OCC = {1: 0.88, 2: 0.90, 3: 0.88, 4: 0.82, 5: 0.88, 6: 0.91}
FAC = {1: 19, 2: 10, 3: 9, 4: 4, 5: 4, 6: 3}
OBJ = {1: "세력 확립", 2: "하북 결전", 3: "남북 대치",
       4: "형주 쟁탈", 5: "북벌 또는 저지", 6: "최종 국면"}


def scenarios():
    out = []
    for i, s in enumerate(IDS["scenarios"]["items"], start=1):
        out.append({"id": s["id"], "year": s["year"], "name": s["name"],
                    "act_count": s["act_count"], "faction_count": FAC[i],
                    "duration_hours": DUR[i], "occupancy": OCC[i],
                    "objective": OBJ[i]})
    return out


def acts():
    GAPS.append("acts: ACT 개별 유형·소요가 문서에 표로 없다 "
                "(time-and-monetization.md §3.4.3 은 시나리오 합계만 기재). "
                "type·duration_hours 를 null 로 둔다")
    return [{"id": a["id"], "scenario": a["scenario"], "no": a["no"],
             "type": None, "duration_hours": None, "title": None}
            for a in IDS["acts"]["items"]]


def events():
    out = []
    txt = read('docs/04-campaign/function-events.md')
    blocks = re.split(r'\n### \[', txt)
    for b in blocks[1:]:
        m = re.match(r'(F-\d{2})\]\s*(.+)', b)
        if not m:
            continue
        fid, name = m.group(1), m.group(2).strip()
        cls = None
        for t in ('FIXED', 'LIKELY', 'CHOICE'):
            if '[%s]' % t in b[:900]:
                cls = t; break
        out.append({"id": fid, "name": name, "classification": cls,
                    "gauge": None, "threshold": None,
                    "condition": None, "effect": None, "scenarios": []})
    if len(out) != 40:
        GAPS.append("events: %d개 추출 — 정본은 40개" % len(out))
    nocls = [e["id"] for e in out if not e["classification"]]
    if nocls:
        GAPS.append("events: 분류 미기재 %d/40 (기재된 것은 %s뿐). "
                    "CLAUDE.md §3 이 [FIXED]/[LIKELY]/[CHOICE] 를 표기 규칙으로 정했으나 "
                    "function-events.md §0.1 기재 형식에 분류 칸 자체가 없다 — 문서 쪽 결손"
                    % (len(nocls), [e["id"] for e in out if e["classification"]]))
    GAPS.append("events: 조건식·임계값이 코드 블록 자연어라 구조화되지 않았다 — 수작업 필요")
    return out


# ================================================================
def main():
    global CORDATA
    print("추출 중...")
    write('systems.json', systems())
    write('regions.json', regions())
    CORDATA = corridors()
    write('corridors.json', CORDATA)
    write('routes.json', routes())
    write('characters.json', characters())
    write('assignments.json', assignments())
    write('ship-types.json', ship_types())
    write('formations.json', formations())
    write('scenarios.json', scenarios())
    write('acts.json', acts())
    write('events.json', events())

    print("\n미확보·미결 %d건" % len(GAPS))
    for g in GAPS:
        print("  -", g)
    io.open(os.path.join(ROOT, 'data', '_gaps.txt'), 'w', encoding='utf-8').write(
        "추출 시점 미확보 목록 (tools/extract_data.py 자동 생성)\n\n" +
        "\n".join("- " + g for g in GAPS) + "\n")
    print("\ndata/_gaps.txt 기록")
    return 0


if __name__ == '__main__':
    sys.exit(main())
