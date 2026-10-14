"""Hardware LOCK via IDB. Never substitute Home-only background for a locked test."""
import json,pathlib,subprocess,sys,time
sim=sys.argv[1]; out=pathlib.Path('build/logs/night');out.mkdir(parents=True,exist_ok=True)
end=time.monotonic()+170
while time.monotonic()<end:
    p=subprocess.run(['xcrun','simctl','get_app_container',sim,'ua.semmyx.svitanok','data'],capture_output=True,text=True)
    if p.returncode==0:
        src=pathlib.Path(p.stdout.strip())/'Documents/night-probe.jsonl'
        if src.exists():
            records=[json.loads(l) for l in src.read_text().splitlines() if l]
            if any(r['event'] in ['task.rejected','task.not_registered'] for r in records):
                sys.exit('NOT VERIFIED: iOS refused the task; see probe records.')
            if any(r['event']=='task.started' for r in records) and any(r['event']=='check' and r.get('background') is True for r in records):
                # XCTest has already pressed Home; LOCK cannot be undone by a later Home press.
                subprocess.run(['build/idb-env/bin/idb','ui','button','LOCK','--udid',sim],check=True)
                (out/'locked.json').write_text(json.dumps({'time':time.time(),'method':'IDB HID LOCK','simulator':sim}))
                subprocess.run(['xcrun','simctl','io',sim,'screenshot',str(out/'screen-locked.png')],check=True)
                print('LOCK hardware event delivered to Simulator',flush=True);sys.exit(0)
    time.sleep(2)
sys.exit('NOT VERIFIED: background task did not start; no fake lock-success result.')
