"""corta um trecho de música, põe fade e salva MP3 (PyAV, sem ffmpeg).
uso: python cortar_audio.py entrada inicio duracao saida [fadein] [fadeout]"""
import sys, av, numpy as np
src, ini, dur, out = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
fi = float(sys.argv[5]) if len(sys.argv) > 5 else 0.3
fo = float(sys.argv[6]) if len(sys.argv) > 6 else 0.6
c = av.open(src); s = c.streams.audio[0]; sr = s.rate
x = np.concatenate([f.to_ndarray().astype(np.float32) for f in c.decode(s)], axis=1)
if x.shape[0] == 1: x = np.vstack([x, x])
x = x[:2, int(ini * sr):int((ini + dur) * sr)]
n = x.shape[1]
env = np.ones(n, np.float32)
a, b = int(fi * sr), int(fo * sr)
if a: env[:a] = np.linspace(0, 1, a)
if b: env[-b:] = np.minimum(env[-b:], np.linspace(1, 0, b))
x = np.clip(x * env, -1, 1)
o = av.open(out, 'w')
st = o.add_stream('libmp3lame', rate=sr)
st.layout = 'stereo'
st.bit_rate = 192000
pcm = (x * 32767).astype(np.int16)
passo = 1152
for i in range(0, n, passo):
    bloco = np.ascontiguousarray(pcm[:, i:i + passo].T.reshape(1, -1))
    fr = av.AudioFrame.from_ndarray(bloco, format='s16', layout='stereo')
    fr.sample_rate = sr
    for p in st.encode(fr): o.mux(p)
for p in st.encode(None): o.mux(p)
o.close()
print('ok', out, round(n / sr, 2), 's')
