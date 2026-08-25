# -*- coding: utf-8 -*-
"""스키마 자체 점검 — jsonschema 없이 구조 규약만 확인한다."""
import json, glob, os, re, sys

errs = []
files = sorted(glob.glob('schema/*.json'))
defs = json.load(open('schema/_defs.json', encoding='utf-8'))['$defs']
known = set(defs.keys())

for f in files:
    name = os.path.basename(f)
    try:
        s = json.load(open(f, encoding='utf-8'))
    except Exception as e:
        errs.append("%s: JSON 파싱 실패 %s" % (name, e)); continue
    for k in ("$schema", "$id", "title", "description"):
        if k not in s:
            errs.append("%s: %s 누락" % (name, k))
    if not s.get("$id", "").endswith(name):
        errs.append("%s: $id 불일치 (%s)" % (name, s.get("$id")))
    # 모든 $ref 가 _defs 에 실재하는지
    for m in re.finditer(r'"_defs\.json#/\$defs/([A-Za-z]+)"', json.dumps(s)):
        if m.group(1) not in known:
            errs.append("%s: 미정의 $ref -> %s" % (name, m.group(1)))
    # 컬렉션은 additionalProperties:false 를 갖는지
    if s.get("type") == "array":
        it = s.get("items", {})
        if it.get("additionalProperties") is not False:
            errs.append("%s: items.additionalProperties 가 false 가 아님" % name)
        if not it.get("required"):
            errs.append("%s: items.required 없음" % name)

# ID 패턴이 정본 총량과 맞는지 (문서 수치 대조)
counts = {"sysId": 19, "rgnId": 45, "corId": 15, "scnId": 6, "actId": 68,
          "fId": 40, "shpId": 6, "frmId": 7}
for key, n in counts.items():
    pat = re.compile(defs[key]["pattern"])
    pre = key[:-2].upper()
    pre = {"SYS": "SYS", "RGN": "RGN", "COR": "COR", "SCN": "SCN",
           "ACT": "ACT", "F": "F", "SHP": "SHP", "FRM": "FRM"}[pre]
    width = {"SYS": 2, "RGN": 2, "COR": 2, "SCN": 2, "ACT": 2,
             "F": 2, "SHP": 2, "FRM": 2}[pre]
    hits = sum(1 for i in range(0, 200) if pat.match("%s-%0*d" % (pre, width, i)))
    if hits != n:
        errs.append("ID 총량 불일치: %s 패턴이 %d개를 받는데 정본은 %d개" % (key, hits, n))

print("점검 파일 %d개" % len(files))
if errs:
    print("\n실패 %d건:" % len(errs))
    for e in errs:
        print("  -", e)
    sys.exit(1)
print("전 항목 통과 — 구조 규약 · $ref 무결성 · ID 총량 8종")
