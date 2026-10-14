import json,pathlib,subprocess,sys
sim=sys.argv[1];out=pathlib.Path('build/logs/night');out.mkdir(parents=True,exist_ok=True)
p=subprocess.run(['xcrun','simctl','get_app_container',sim,'ua.semmyx.svitanok','data'],capture_output=True,text=True,check=True)
src=pathlib.Path(p.stdout.strip())/'Documents/night-probe.jsonl'
records=[json.loads(l) for l in src.read_text().splitlines()] if src.exists() else []
(out/'night-probe.jsonl').write_text('\n'.join(json.dumps(r) for r in records))
lock=json.loads((out/'locked.json').read_text()) if (out/'locked.json').exists() else {}
required=['task.started','lease.extended','release.scheduled','release.alerting']
missing=[e for e in required if not any(r['event']==e for r in records)]
background=bool(lock) and any(r['event']=='check' and r.get('background') is True and r['time']>lock['time'] for r in records)
release=bool(lock) and any(r['event']=='release.alerting' and r['time']>lock['time'] for r in records)
passed=not missing and background and release
result={'passed':passed,'missing_events':missing,'checks_after_LOCK_in_background':background,'AlarmKit_alerting_after_LOCK':release,'scope':'short synthetic all-clear; Simulator only, not overnight hardware/audio guarantee'}
(out/'result.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
sys.exit(0 if passed else 1)
