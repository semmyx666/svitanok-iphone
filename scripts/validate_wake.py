import json,pathlib,subprocess,sys
sim=sys.argv[1];out=pathlib.Path('build/logs/wake');out.mkdir(parents=True,exist_ok=True)
p=subprocess.run(['xcrun','simctl','get_app_container',sim,'ua.semmyx.svitanok','data'],capture_output=True,text=True,check=True)
src=pathlib.Path(p.stdout.strip())/'Documents/wake-probe.jsonl'
records=[json.loads(l) for l in src.read_text().splitlines()] if src.exists() else []
(out/'wake-probe.jsonl').write_text('\n'.join(json.dumps(r) for r in records))
locks=json.loads((out/'locks.json').read_text()) if (out/'locks.json').exists() else []
required=['armed','first.alerting','math.rejected','math.repeat','system.stop.rearmed','repeat.alerting','math.finish']
missing=[e for e in required if not any(r['event']==e for r in records)]
verified=all(any(r['event']==e and r.get('verified_followups')==3 for r in records) for e in ['math.repeat','system.stop.rearmed'])
cleared=any(r['event']=='math.finish' and r.get('remaining_system_ids')==0 for r in records)
first=len(locks)==2 and any(r['event']=='first.alerting' and r['time']>locks[0]['time'] for r in records)
repeat=len(locks)==2 and any(r['event']=='repeat.alerting' and r['time']>locks[1]['time'] for r in records)
passed=not missing and verified and cleared and first and repeat
result={'passed':passed,'missing_events':missing,'initial_and_repeat_after_LOCK':bool(first and repeat),'three_verified_after_math_and_stop_handler':verified,'zero_remaining_after_correct_finish':cleared,'scope':'Simulator, accelerated 15s repeats, actual alarms; Stop handler invoked in-app via same LiveActivityIntent, not a physical Stop swipe; production intervals >=5min'}
(out/'result.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2));sys.exit(0 if passed else 1)
