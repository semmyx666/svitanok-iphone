import math,struct,wave
from pathlib import Path
sr=22050;seconds=28;out=Path(__file__).resolve().parents[1]/'ios/Svitanok/Resources/wake.wav'
frames=[]
for i in range(sr*seconds):
 t=i/sr;phase=t%1.0
 envelope=min(1,phase/.01)*min(1,max(0,(.72-phase)/.04))
 f=880 if int(t*2)%2==0 else 660
 value=.55*envelope*(math.sin(2*math.pi*f*t)+.15*math.sin(4*math.pi*f*t))
 frames.append(struct.pack('<h',round(value*32767)))
with wave.open(str(out),'wb') as w:
 w.setparams((1,2,sr,0,'NONE','not compressed'));w.writeframes(b''.join(frames))
print('Original wake sound generated: 28 seconds, not silence.')
