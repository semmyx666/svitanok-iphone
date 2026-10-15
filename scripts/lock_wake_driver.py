import json,pathlib,subprocess,sys,time
sim=sys.argv[1];out=pathlib.Path('build/logs/wake');out.mkdir(parents=True,exist_ok=True)
locks=[];end=time.monotonic()+420
while time.monotonic()<end:
 p=subprocess.run(['xcrun','simctl','get_app_container',sim,'ua.semmyx.svitanok','data'],capture_output=True,text=True)
 if p.returncode==0:
  src=pathlib.Path(p.stdout.strip())/'Documents/wake-probe.jsonl'
  records=[json.loads(l) for l in src.read_text().splitlines() if l] if src.exists() else []
  background=[r for r in records if r['event']=='app.background']
  first=any(r['event']=='armed' for r in records) and bool(background)
  repeats=[r for r in records if r['event']=='system.stop.rearmed']
  second=bool(repeats) and any(r['time']>repeats[-1]['time'] for r in background)
  if (len(locks)==0 and first) or (len(locks)==1 and second):
   subprocess.run(['build/idb-env/bin/idb','ui','button','LOCK','--udid',sim],check=True)
   locks.append({'time':time.time(),'method':'IDB HID LOCK'})
   (out/'locks.json').write_text(json.dumps(locks))
   subprocess.run(['xcrun','simctl','io',sim,'screenshot',str(out/f'locked-{len(locks)}.png')],check=True)
   print('LOCK',len(locks),flush=True)
  if any(r['event']=='math.finish' for r in records):sys.exit(0 if len(locks)==2 else 1)
 time.sleep(1)
sys.exit('Wake probe did not complete; no success claimed.')
