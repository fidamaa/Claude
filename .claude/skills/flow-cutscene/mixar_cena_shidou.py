"""Mixagem do áudio do Flow do Shidou (cena + Flow): trilha do Big Bang Drive + falas
do Shidou separadas do vídeo (demucs --two-stems vocals), cada uma no instante da
coreografia (Cutscenes.Flow_Shidou, HissatsuCutscenes.luau, v125: chute em 10.4s).

⚠️ v125b — o Roblox marcou o áudio como RESTRITO: a última fala tinha "クソども"
(kusodomo = "seus merdas"). Essa frase saiu inteira; fica "Saa... ore no goal wo,
ore no idenshi wo" ("Vamos... meu gol, meus genes").

Uso: python mixar_cena_shidou.py vocals.wav shidou_trilha.m4a saida.mp3"""
import sys
import av
import numpy as np

SR = 44100
DUR = 39.0          # cena (12s) + Flow (25s) + folga
TRILHA_INI = 58.2   # a explosão da trilha (68.6s) cai no chute (10.4s)
VOZ_GANHO = 1.0
DUCK = 0.5          # a música abaixa pra metade debaixo da voz

# (início no vídeo, fim no vídeo, instante na cena)
FALAS = [
    (14.95, 18.60, 0.6),    # あれ?なんだこの感覚
    (18.50, 22.40, 4.3),    # めちゃくちゃ遠いのに、背中でゴールを感じる
    (43.95, 46.45, 8.9),    # ビッグバン・ドライブ
    (52.15, 53.50, 12.2),   # さあ、
    (57.70, 62.40, 13.75),  # 俺のゴールを、俺の遺伝子を  (sem 53.5-57.7: クソども)
]


def ler(caminho):
    c = av.open(caminho)
    s = c.streams.audio[0]
    rs = av.AudioResampler(format="fltp", layout="stereo", rate=SR)
    partes = []
    for f in c.decode(s):
        for g in rs.resample(f):
            partes.append(g.to_ndarray())
    for g in rs.resample(None):
        partes.append(g.to_ndarray())
    return np.concatenate(partes, axis=1).astype(np.float32)


def rampa(x, seg=0.03):
    n = min(int(seg * SR), x.shape[1] // 2)
    if n > 0:
        r = np.linspace(0, 1, n, dtype=np.float32)
        x[:, :n] *= r
        x[:, -n:] *= r[::-1]
    return x


def main(voz_p, trilha_p, saida):
    voz, trilha = ler(voz_p), ler(trilha_p)
    total = int(DUR * SR)
    mus = np.zeros((2, total), np.float32)
    t0 = int(TRILHA_INI * SR)
    pedaco = trilha[:, t0:t0 + total]
    mus[:, :pedaco.shape[1]] = pedaco
    mus[:, -int(2 * SR):] *= np.linspace(1, 0, int(2 * SR), dtype=np.float32)  # fade final

    vz = np.zeros((2, total), np.float32)
    duck = np.ones(total, np.float32)
    for ini, fim, em in FALAS:
        trecho = rampa(voz[:, int(ini * SR):int(fim * SR)].copy()) * VOZ_GANHO
        a = int(em * SR)
        b = min(a + trecho.shape[1], total)
        vz[:, a:b] += trecho[:, :b - a]
        duck[max(a - int(0.15 * SR), 0):min(b + int(0.25 * SR), total)] = DUCK
    # suaviza o duck (sem degrau)
    k = int(0.12 * SR)
    duck = np.convolve(duck, np.ones(k, np.float32) / k, mode="same")

    mix = mus * duck + vz
    pico = np.abs(mix).max()
    if pico > 0:
        mix *= 0.89 / pico  # -1 dB

    o = av.open(saida, "w")
    st = o.add_stream("libmp3lame", rate=SR)
    st.layout = "stereo"
    st.bit_rate = 192000
    passo = 1152 * 8
    for i in range(0, total, passo):
        fr = av.AudioFrame.from_ndarray(np.ascontiguousarray(mix[:, i:i + passo]), format="fltp", layout="stereo")
        fr.sample_rate = SR
        for p in st.encode(fr):
            o.mux(p)
    for p in st.encode(None):
        o.mux(p)
    o.close()
    print("ok", saida, DUR, "s")


if __name__ == "__main__":
    main(*sys.argv[1:4])
