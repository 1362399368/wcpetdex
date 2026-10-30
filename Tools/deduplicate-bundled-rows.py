#!/usr/bin/env python3
"""Alias byte-identical atlas rows in staging without changing any frame pixels."""
import hashlib,json,sys
from pathlib import Path

bundle=Path(sys.argv[1]);directory=bundle/'DefaultPet';manifest=directory/'pet.json'
data=json.loads(manifest.read_text());key='wpBundledCompactRowAtlasPaths'
paths=data.get(key,[]);seen={};replacement={};saved=0
for filename in paths:
    raw=(directory/filename).read_bytes();digest=hashlib.sha256(raw).hexdigest()
    canonical=seen.setdefault(digest,filename)
    if canonical!=filename:
        assert raw==(directory/canonical).read_bytes()
        replacement[filename]=canonical
data[key]=[replacement.get(name,name) for name in paths]
for filename in replacement:
    saved+=(directory/filename).stat().st_size;(directory/filename).unlink()
manifest.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'deduplicatedRows':len(replacement),'savedBytes':saved,'logicalRows':len(paths),'aliases':replacement},ensure_ascii=False))
