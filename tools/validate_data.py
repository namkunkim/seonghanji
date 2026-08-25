# -*- coding: utf-8 -*-
"""
SEONGHANJI — 정합성 검증기 (data-model.md §6)

두 층으로 검사한다.
  A. 스키마 적합성  — data/*.json 이 schema/*.json 을 지키는가
  B. 도메인 검사 8종 — 참조 무결성 · 총량 · 범위 · 도달성 · 미사용
                       · ID 유일성 · 결번 재사용 · 문서↔데이터 개수

**미확보(null)는 위반이 아니다.** data/_gaps.txt 에 기록된 결손이며 커버리지로 따로 센다.
외부 라이브러리를 쓰지 않는다 (JSON Schema 부분집합 자체 구현).

실행: PYTHONIOENCODING=utf-8 python tools/validate_data.py
종료 코드: 위반이 있으면 1
"""
import io, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FAIL, WARN = [], []


def load(rel):
    p = os.path.join(ROOT, rel)
    return json.load(io.open(p, encoding='utf-8')) if os.path.exists(p) else None


def fail(cat, msg):
    FAIL.append("[%s] %s" % (cat, msg))


def warn(cat, msg):
    WARN.append("[%s] %s" % (cat, msg))


# ---------------------------------------------------------------- 데이터 적재
PAIRS = [("systems", "systems"), ("regions", "regions"), ("corridors", "corridors"),
         ("routes", "routes"),
         ("characters", "characters"), ("assignments", "assignments"),
         ("ship-types", "ship-types"), ("formations", "formations"),
         ("scenarios", "scenarios"), ("acts", "acts"), ("events", "events")]

DATA = {}
for d, _ in PAIRS:
    v = load('data/%s.json' % d)
    if v is None:
        fail("적재", "data/%s.json 이 없다" % d)
    else:
        DATA[d] = v

IDS = load('data/_ids.json')
DEFS = load('schema/_defs.json')["$defs"]


# ================================================================ A. 스키마
def resolve_ref(node):
    while isinstance(node, dict) and "$ref" in node:
        key = node["$ref"].split('/')[-1]
        node = DEFS[key]
    return node


def check_node(val, sch, path, out):
    sch = resolve_ref(sch)
    if not isinstance(sch, dict):
        return
    if val is None:
        # 추출기는 없는 값을 만들지 않는다. null 은 결손이지 위반이 아니다.
        # 커버리지로만 센다 (data/_gaps.txt 와 짝을 이룬다).
        out.append("__NULL__%s" % path)
        return
    if "anyOf" in sch:
        for alt in sch["anyOf"]:
            probe = []
            check_node(val, alt, path, probe)
            if not probe:
                return
        out.append("%s: anyOf 어느 것도 만족하지 않는다 (값 %r)" % (path, val))
        return
    if "const" in sch:
        if val != sch["const"]:
            out.append("%s: const %r 아님 (%r)" % (path, sch["const"], val))
        return
    if "enum" in sch:
        if val not in sch["enum"]:
            out.append("%s: enum 밖의 값 %r (허용 %s)" % (path, val, sch["enum"]))
        return

    t = sch.get("type")
    types = t if isinstance(t, list) else ([t] if t else [])
    ok = {"string": str, "integer": int, "number": (int, float),
          "boolean": bool, "array": list, "object": dict}
    if types:
        hit = any(isinstance(val, ok[x]) and not (x == "integer" and isinstance(val, bool))
                  for x in types if x in ok)
        if not hit:
            out.append("%s: 타입 %s 아님 (%r)" % (path, types, val))
            return
    if isinstance(val, str) and "pattern" in sch:
        if not re.match(sch["pattern"], val):
            out.append("%s: 패턴 %s 불일치 (%r)" % (path, sch["pattern"], val))
    if isinstance(val, (int, float)) and not isinstance(val, bool):
        if "minimum" in sch and val < sch["minimum"]:
            out.append("%s: 최소 %s 미만 (%r)" % (path, sch["minimum"], val))
        if "maximum" in sch and val > sch["maximum"]:
            out.append("%s: 최대 %s 초과 (%r)" % (path, sch["maximum"], val))
    if isinstance(val, list):
        if "minItems" in sch and len(val) < sch["minItems"]:
            out.append("%s: 원소 %d개 < minItems %d" % (path, len(val), sch["minItems"]))
        if "maxItems" in sch and len(val) > sch["maxItems"]:
            out.append("%s: 원소 %d개 > maxItems %d" % (path, len(val), sch["maxItems"]))
        if "items" in sch:
            for i, v in enumerate(val):
                check_node(v, sch["items"], "%s[%d]" % (path, i), out)
    if isinstance(val, dict):
        props = sch.get("properties", {})
        for r in sch.get("required", []):
            if r not in val:
                out.append("%s: 필수 키 %s 없음" % (path, r))
        if sch.get("additionalProperties") is False:
            for k in val:
                if k not in props:
                    out.append("%s: 스키마에 없는 키 %s" % (path, k))
        for k, v in val.items():
            if k in props:
                check_node(v, props[k], "%s.%s" % (path, k), out)


def schema_pass():
    nulls = {}
    for dname, sname in PAIRS:
        sch = load('schema/%s.json' % sname)
        if sch is None or dname not in DATA:
            continue
        for i, row in enumerate(DATA[dname]):
            out = []
            key = row.get("id") or row.get("character") or "#%d" % i
            check_node(row, sch.get("items", {}), "%s/%s" % (dname, key), out)
            for o in out:
                if o.startswith("__NULL__"):
                    nulls[dname] = nulls.get(dname, 0) + 1
                else:
                    fail("스키마", o)
    return nulls


# ================================================================ B. 도메인 8종
CANON = {"systems": 19, "regions": 45, "corridors": 15, "characters": 492,
         # routes 는 정본 총수가 문서에 없다 — 인접표에서 파생되므로 총량 검사 대상이 아니다
         "ship-types": 6, "formations": 7, "scenarios": 6, "acts": 68,
         "events": 40, "assignments": 399 * 6}


def check_counts():
    for k, n in CANON.items():
        if k in DATA and len(DATA[k]) != n:
            fail("총량", "%s %d건 — 정본 %d건" % (k, len(DATA[k]), n))


def check_unique():
    for k in DATA:
        seen = {}
        for row in DATA[k]:
            i = row.get("id")
            if i is None:
                continue
            if i in seen:
                fail("ID유일", "%s 에 중복 ID %s" % (k, i))
            seen[i] = 1


def check_refs():
    known = {}
    for k in ("systems", "regions", "corridors", "characters",
              "ship-types", "formations", "scenarios", "acts", "events"):
        known.update({r["id"]: k for r in DATA.get(k, []) if r.get("id")})

    def ck(where, val):
        if isinstance(val, str) and re.match(r'^(SYS|RGN|COR|CHR|SHP|FRM|SCN|ACT|F)-', val):
            if val not in known:
                fail("참조", "%s → %s 가 존재하지 않는다" % (where, val))

    def walk(where, node):
        if isinstance(node, str):
            ck(where, node)
        elif isinstance(node, list):
            for x in node:
                walk(where, x)
        elif isinstance(node, dict):
            for k, v in node.items():
                walk("%s.%s" % (where, k), v)

    for k, rows in DATA.items():
        for row in rows:
            walk("%s/%s" % (k, row.get("id") or row.get("character")), row)


def check_ranges():
    for c in DATA.get("characters", []):
        st = c.get("stats")
        if not st:
            continue
        for n, v in st.items():
            if not (1 <= v <= 100):
                fail("범위", "%s %s 스탯 %s=%s (1~100 밖)" % (c["id"], c["name"], n, v))
    for co in DATA.get("corridors", []):
        m = co.get("multiplier")
        if m is not None and m <= 1:
            fail("범위", "%s 통과 배율 %s — 불가침 §2-2 위반 (1이 될 수 없다)" % (co["id"], m))


def check_unused():
    used = set()
    for k, rows in DATA.items():
        for row in rows:
            for kk, v in row.items():
                if kk == "id":
                    continue
                for x in (v if isinstance(v, list) else [v]):
                    if isinstance(x, str):
                        used.add(x)
                    elif isinstance(x, list):
                        used.update(y for y in x if isinstance(y, str))
    for k in ("characters", "regions", "corridors", "events", "acts"):
        dead = [r["id"] for r in DATA.get(k, []) if r["id"] not in used]
        if dead:
            why = {"characters": "이역 93인은 배치표에 없다 — 정상",
                   "corridors": "항로망·전투 데이터 미추출",
                   "events": "발동 조건이 미구조화 (data/_gaps.txt)",
                   "acts": "ACT 개별 데이터 미추출"}.get(k, "")
            warn("미사용", "%s 미참조 %d개 (예: %s)%s"
                 % (k, len(dead), dead[:3], " — " + why if why else ""))


def check_retired():
    live = {}
    for k, rows in DATA.items():
        live[k] = {r.get("id") for r in rows}
    for key, blk in (IDS or {}).items():
        if not isinstance(blk, dict) or "items" not in blk:
            continue
        for it in blk["items"]:
            if it.get("retired"):
                dn = {"ship_types": "ship-types"}.get(key, key)
                if it["id"] in live.get(dn, set()):
                    fail("결번", "%s 는 결번인데 %s 에 되살아나 있다" % (it["id"], dn))


def check_doc_counts():
    """문서가 적은 수와 실제 수를 대조한다 (2026-08-24 CLAUDE.md 21 vs 실제 23 유형)."""
    dec = io.open(os.path.join(ROOT, 'docs/DECISIONS.md'), encoding='utf-8').read()
    real = len(re.findall(r'^### V-', dec, re.M))
    for f in ('docs/INDEX.md', 'CLAUDE.md'):
        t = io.open(os.path.join(ROOT, f), encoding='utf-8').read()
        for m in re.finditer(r'변경 이력\s*\**\s*(\d+)', t):
            if int(m.group(1)) != real:
                fail("문서개수", "%s 가 변경 이력 %s건이라 적었으나 실제는 %d건"
                     % (f, m.group(1), real))
    # 「핵심 수치」 요약 줄만 본다. 「회랑 3개가 모인다」 같은 서술문은 세지 않는다
    # (두 개 이상의 라벨이 한 줄에 있을 때만 수치 주장으로 간주한다).
    idx = io.open(os.path.join(ROOT, 'docs/INDEX.md'), encoding='utf-8').read()
    labels = (("성계", "systems"), ("권역", "regions"), ("회랑", "corridors"))
    for line in idx.split('\n'):
        hits = [(l, k) for l, k in labels if re.search(l + r'\s*\d+', line)]
        if len(hits) < 2:
            continue
        for l, k in hits:
            m = re.search(l + r'\s*(\d+)', line)
            if int(m.group(1)) != CANON[k]:
                fail("문서개수", "INDEX.md 핵심 수치 「%s %s」가 정본 %d 과 다르다"
                     % (l, m.group(1), CANON[k]))


def check_reachability():
    """성계 19개가 항로망으로 전부 이어지는가.
    star-map.md §0 「교착 방지」의 전제다 — 닿을 수 없는 성계가 있으면 그 세력은 게임에서 빠진다."""
    rows = DATA.get("routes")
    if not rows:
        warn("도달성", "routes.json 이 없어 검사를 건너뛴다")
        return
    adj = {}
    for r in rows:
        a, b = r["connects"]
        adj.setdefault(a, set()).add(b)
        adj.setdefault(b, set()).add(a)
    nodes = {x["id"] for x in DATA.get("systems", [])}
    if not nodes:
        return
    start = sorted(nodes)[0]
    seen, stack = {start}, [start]
    while stack:
        cur = stack.pop()
        for nb in adj.get(cur, ()):
            if nb not in seen:
                seen.add(nb)
                stack.append(nb)
    unreach = sorted(nodes - seen)
    if unreach:
        fail("도달성", "항로망에서 닿지 않는 성계 %s" % unreach)
    # 회랑 하나로만 이어진 성계는 정상이지만 기록해 둔다 (요동·서역·남중)
    thin = sorted(n for n in nodes if len(adj.get(n, ())) == 1)
    if thin:
        warn("도달성", "연결이 하나뿐인 성계 %s — 회랑 전용 성계는 설계 의도다 "
                      "(star-map.md §4.5)" % thin)
    # 항로 종류 분포
    kinds = {}
    for r in rows:
        kinds[r["kind"]] = kinds.get(r["kind"], 0) + 1
    warn("도달성", "간선 %d개 — %s" % (len(rows), kinds))


# ================================================================
def main():
    print("A. 스키마 적합성")
    nulls = schema_pass()
    tot = sum(len(v) for v in DATA.values())
    print("   %d개 레코드 검사 · 미확보(null) %d필드" % (tot, sum(nulls.values())))
    for k, v in sorted(nulls.items(), key=lambda x: -x[1]):
        print("     %-12s null %d" % (k, v))

    print("\nB. 도메인 검사")
    for name, fn in [("1 참조 무결성", check_refs), ("2 총량", check_counts),
                     ("3 범위", check_ranges), ("4 도달성", check_reachability),
                     ("5 미사용", check_unused), ("6 ID 유일성", check_unique),
                     ("7 결번 재사용", check_retired), ("8 문서↔데이터", check_doc_counts)]:
        before = len(FAIL)
        fn()
        print("   %-14s %s" % (name, "OK" if len(FAIL) == before else "실패 %d" % (len(FAIL) - before)))

    if WARN:
        print("\n경고 %d건" % len(WARN))
        for w in WARN:
            print("  -", w)
    if FAIL:
        print("\n위반 %d건" % len(FAIL))
        for f in FAIL[:40]:
            print("  -", f)
        if len(FAIL) > 40:
            print("  ... 외 %d건" % (len(FAIL) - 40))
        return 1
    print("\n위반 0건 — 전 항목 통과")
    return 0


if __name__ == '__main__':
    sys.exit(main())
