"""Original audible, seamlessly looped soft pink-ish sleep noise. NOT silent keepalive."""
import math,random,struct,wave
from pathlib import Path
sr=22050;seconds=8;rng=random.Random(42)
# Periodic harmonics ensure a continuous seam; lower frequencies carry more energy.
partials=[(rng.randint(160,9600),rng.random()*2*math.pi) for _ in range(180)]
samples=[sum(math.sin(2*math.pi*k*i/(sr*seconds)+phase)/math.sqrt(k) for k,phase in partials) for i in range(sr*seconds)]
peak=max(map(abs,samples));pcm=b''.join(struct.pack('<h',round(x/peak*.32*32767)) for x in samples)
out=Path(__file__).resolve().parents[1]/'ios/Svitanok/Resources/sleep.wav'
with wave.open(str(out),'wb') as w:
 w.setparams((1,2,sr,0,'NONE','not compressed'));w.writeframes(pcm)
print('Audible sleep noise generated: 8 seconds, looping PCM; not silence.')
