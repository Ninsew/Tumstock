"""Generates Data/Items.lua from LibRangeCheck-3.0's FriendItems/HarmItems.

Usage:
  python -I tools/gen_items.py LibRangeCheck-3.0.lua LICENSE Data/Items.lua

Source files (MIT): https://github.com/WeakAuras/LibRangeCheck-3.0
  raw: .../master/LibRangeCheck-3.0/LibRangeCheck-3.0.lua and .../master/LICENSE

The line spans below were read by hand from LibRangeCheck-3.0 MINOR_VERSION 38
(Era/Forever, Cata and Retail branches of each table). A newer library version
moves them: re-check with  grep -n "FriendItems\\|HarmItems" before reusing.
"""
import re, sys
src, lic, out = sys.argv[1], sys.argv[2], sys.argv[3]
L = open(src, encoding='utf-8').read().split('\n')
# 1-indexed inclusive line spans of each branch (verified by inspection)
spans = {
 'friend': [('era', 396, 637), ('cata', 638, 1097), ('retail', 1098, 2118)],
 'harm':   [('era', 2122, 2252), ('cata', 2253, 2698), ('retail', 2699, 3772)],
}
rng_re = re.compile(r'^\s*\[(\d+(?:\.\d+)?)\]\s*=\s*\{')
id_re = re.compile(r'^\s*(\d+),?\s*(?:--\s*(.*))?$')
res = {}
for kind, bl in spans.items():
    entries = {}  # (range,id) -> [name, set(src)]
    for tag, a, b in bl:
        cur = None
        for ln in L[a-1:b]:
            m = rng_re.match(ln)
            if m: cur = m.group(1); continue
            if ln.strip().startswith('--'): continue
            m = id_re.match(ln)
            if m and cur:
                key = (float(cur), int(m.group(1)))
                e = entries.setdefault(key, [ (m.group(2) or '').strip(), set() ])
                e[1].add(tag)
    res[kind] = entries
order = {'era':0,'cata':1,'retail':2}
abbrev = {'era':'E','cata':'C','retail':'R'}
o = []
o.append('-- Tumstock: candidate range-check items.')
o.append('-- Generated from LibRangeCheck-3.0 (github.com/WeakAuras/LibRangeCheck-3.0),')
o.append('-- tables FriendItems / HarmItems, all three branches merged:')
o.append('--   E = Era/Forever branch, C = Cata branch, R = Retail branch.')
o.append('-- None of these IDs are verified on WoW Forever; /tum scan finds out which work.')
o.append('--')
o.append('-- LibRangeCheck-3.0 license:')
for l in open(lic, encoding='utf-8').read().rstrip().split('\n'):
    o.append(('-- ' + l).rstrip())
o.append('')
o.append('local _, T = ...')
o.append('')
o.append('-- Each entry: { yards, itemID, "sources", "name" }')
for kind, var in (('harm','HarmItems'),('friend','FriendItems')):
    o.append('T.%s = {' % var)
    for (r, i), (name, srcs) in sorted(res[kind].items()):
        s = ''.join(abbrev[x] for x in sorted(srcs, key=order.get))
        rr = ('%g' % r)
        name = name.replace(chr(92), chr(92)*2).replace(chr(34), chr(92)+chr(34))
        o.append('  { %s, %d, "%s", "%s" },' % (rr, i, s, name))
    o.append('}')
    o.append('')
open(out, 'w', encoding='utf-8', newline='\n').write('\n'.join(o))
for k in res: print(k, len(res[k]))
