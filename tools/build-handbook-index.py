"""Read a user-supplied handbook directory; write only the named development index."""
from pathlib import Path
import argparse,csv,json,hashlib
p=argparse.ArgumentParser();p.add_argument('--handbook-dir',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
spec={'01_副本总览.csv':['中文名称','英文名称'],'04_装备物品目录.csv':['名称'],'05_专业配方.csv':['产物名称_缺失时用ID'],'07_职业法术.csv':['名称']}
names=set();sources={}
for filename,columns in spec.items():
 file=a.handbook_dir/filename;sources[filename]=hashlib.sha256(file.read_bytes()).hexdigest()
 with file.open(encoding='utf-8-sig',newline='') as f:
  for row in csv.DictReader(f):
   for column in columns:
    value=row.get(column,'').strip()
    if 2<=len(value)<=120 and not value.isdecimal():names.add(value)
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(sorted(names),ensure_ascii=False,indent=2),encoding='utf-8')
a.output.with_suffix('.manifest.json').write_text(json.dumps({'entries':len(names),'sources':sources,'scope':'entity names only, no account data or factual assertions'},ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'entries':len(names),'output':str(a.output)},ensure_ascii=True))
