"""Mixagem do áudio do Flow do Isagi (cena + Flow): música Puzzle + fala do Sung
Jin-Woo ("I haven't lost yet", Solo Leveling ep. 11, 0:29,4-0:34,0) + efeitos
sonoros SINTETIZADOS (sem direito autoral), cada um no instante da coreografia.
Uso: python mixar_cena_isagi.py puzzle.m4a solo_leveling.m4a saida.mp3
Os tempos batem com Cutscenes.Flow_Isagi (HissatsuCutscenes.luau, v120b):
pisada 9.55 (a batida da Puzzle), dash 10.55. Serve de modelo pros outros Flows:
troque a lista EVENTOS e os trechos."""
import sys
import av
import numpy as np

SR = 44100
DUR = 39.0  # cena (12s) + Flow (25s) + folga
# ⚠️ v120e — PEDIDO: "o áudio acontece 0.1s depois da cena: tem que começar 0.1s antes"
ADIANTA = 0.1


def ler(caminho):
    c = av.open(caminho)
    s = c.streams.audio[0]
    x = np.concatenate([f.to_ndarray().astype(np.float32) for f in c.decode(s)], axis=1)
    if x.shape[0] == 1:
        x = np.vstack([x, x])
    x = x[:2]
    if s.rate != SR:  # reamostra simples (linear)
        n = int(x.shape[1] * SR / s.rate)
        t0 = np.linspace(0, 1, x.shape[1])
        t1 = np.linspace(0, 1, n)
        x = np.vstack([np.interp(t1, t0, x[k]) for k in range(2)]).astype(np.float32)
    return x


def trecho(x, ini, fim, fi=0.05, fo=0.2):
    y = x[:, int(ini * SR):int(fim * SR)].copy()
    n = y.shape[1]
    env = np.ones(n, np.float32)
    a, b = int(fi * SR), int(fo * SR)
    if a: env[:a] = np.linspace(0, 1, a)
    if b: env[-b:] = np.minimum(env[-b:], np.linspace(1, 0, b))
    return y * env


def t(seg):
    return np.arange(int(seg * SR)) / SR


def env_ad(n, ataque, queda):
    tt = np.arange(n) / SR
    return np.minimum(tt / max(ataque, 1e-4), 1) * np.exp(-tt / max(queda, 1e-4))


def ruido(n, rng):
    return rng.standard_normal(n).astype(np.float32)


def passa_baixa(x, corte):
    # filtro de 1 polo (simples e suficiente pra SFX)
    a = np.exp(-2 * np.pi * corte / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def passa_baixa_rapido(x, corte):
    # versão vetorizada aproximada (FFT) pra sons longos
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= 1 / np.sqrt(1 + (f / corte) ** 4)
    return np.fft.irfft(X, len(x)).astype(np.float32)


rng = np.random.default_rng(7)


def sfx_coracao(forte=1.0):
    tt = t(0.5)
    b1 = np.sin(2 * np.pi * 52 * tt) * env_ad(len(tt), 0.005, 0.07)
    b2 = np.sin(2 * np.pi * 48 * tt) * env_ad(len(tt), 0.005, 0.09)
    s = b1.copy()
    d = int(0.16 * SR)
    s[d:] += 0.8 * b2[:len(s) - d]
    return s * forte


def sfx_baque(grave=55, dur=0.6, crocante=0.4):
    tt = t(dur)
    f = grave * (1 + 1.5 * np.exp(-tt / 0.03))
    corpo = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_ad(len(tt), 0.002, dur / 4)
    terra = passa_baixa_rapido(ruido(len(tt), rng), 1800) * env_ad(len(tt), 0.001, 0.06) * crocante
    return corpo + terra


def sfx_brilho(f0=1800, dur=0.9):
    tt = t(dur)
    s = np.zeros(len(tt), np.float32)
    for k, f in enumerate([f0, f0 * 1.5, f0 * 2.01, f0 * 3.02]):
        s += np.sin(2 * np.pi * f * tt + k) * (0.5 ** k)
    return s * env_ad(len(tt), 0.01, dur / 3.5) * 0.5


def sfx_vento(dur, sobe=True, f1=300, f2=3500):
    tt = t(dur)
    n = ruido(len(tt), rng)
    # varredura: mistura bandas por janela
    out = np.zeros(len(tt), np.float32)
    bloco = int(0.05 * SR)
    for i in range(0, len(tt), bloco):
        u = i / len(tt)
        fc = (f1 + (f2 - f1) * u) if sobe else (f2 + (f1 - f2) * u)
        seg = n[i:i + bloco * 2]
        out[i:i + len(seg)] += passa_baixa_rapido(seg, fc)[:len(out) - i] * 0.5
    envelope = np.sin(np.pi * np.clip(tt / dur, 0, 1)) ** 1.5
    return out * envelope


def sfx_cliques(dur, n, rng_local, agudo=2600):
    s = np.zeros(int(dur * SR), np.float32)
    tc = t(0.04)
    clique = (np.sin(2 * np.pi * agudo * tc) + 0.6 * np.sin(2 * np.pi * agudo * 1.7 * tc)) * env_ad(len(tc), 0.0005, 0.008)
    for _ in range(n):
        i = int(rng_local.uniform(0, dur - 0.05) * SR)
        g = rng_local.uniform(0.3, 1)
        s[i:i + len(clique)] += clique * g * rng_local.choice([0.8, 1.0, 1.25])
    return s


def sfx_explosao(dur=1.6):
    tt = t(dur)
    corpo = sfx_baque(42, dur, 0.9)
    chiado = passa_baixa_rapido(ruido(len(tt), rng), 5000) * env_ad(len(tt), 0.003, 0.35) * 0.5
    return corpo + chiado


def sfx_espiral(dur):
    tt = t(dur)
    base = sfx_vento(dur, True, 200, 2500)
    taxa = 3 + 22 * (tt / dur) ** 2
    trem = 0.6 + 0.4 * np.sin(2 * np.pi * np.cumsum(taxa) / SR)
    grave = np.sin(2 * np.pi * (40 + 30 * tt / dur) * tt) * 0.4
    return (base * trem + grave * (tt / dur))


# instante (s) → (som, ganho)
def eventos():
    ev = []
    for tb in (0.35, 1.05, 1.75, 2.4):
        ev.append((tb, sfx_coracao(), 0.9))
    ev.append((2.32, sfx_baque(60, 0.5, 0.7), 1.0))           # soco no chão
    ev.append((2.75, sfx_brilho(1600, 1.1), 0.7))             # olhos acendem brancos
    for tb in (2.9, 3.35, 3.75, 4.1):
        ev.append((tb, sfx_coracao(1.2), 0.8))                # coração acelera ao levantar
    ev.append((3.0, sfx_vento(1.5, True), 0.9))               # sobe com o joelho
    ev.append((4.55, sfx_cliques(0.5, 7, np.random.default_rng(1)), 0.45))  # peças encaixando (olho vira íris) — v120e: menos
    ev.append((4.75, sfx_brilho(2400, 1.2), 0.8))
    ev.append((5.9, sfx_vento(0.7, True, 500, 7000), 1.0))    # zoom pra dentro do olho
    ev.append((6.55, sfx_brilho(3200, 0.9), 0.6))             # o branco
    for tb in (6.9, 7.65):
        ev.append((tb, sfx_coracao(1.3), 0.9))                # câmera lenta: coração
    ev.append((8.0, sfx_espiral(0.85), 1.1))                  # a espiral fecha a visão
    ev.append((9.55, sfx_explosao(1.8), 1.0))                 # A PISADA (a batida da Puzzle)
    ev.append((9.6, sfx_cliques(0.8, 14, np.random.default_rng(2), 2200), 0.5))  # peças surgindo do chão — v120e: menos
    ev.append((10.3, sfx_brilho(1900, 0.6), 0.7))             # olhos brancos
    ev.append((10.5, sfx_vento(0.35, True, 800, 6000), 1.0))
    ev.append((10.55, sfx_explosao(1.4), 1.0))                # DASH
    ev.append((10.78, sfx_cliques(0.06, 2, np.random.default_rng(3), 3500), 1.0))  # pisca
    ev.append((10.85, sfx_cliques(1.2, 18, np.random.default_rng(4), 1700), 0.4))  # cabeça se desfazendo — v120e: menos
    ev.append((10.85, sfx_brilho(2600, 1.4), 0.7))
    return ev


def main():
    puzzle_src, voz_src, saida = sys.argv[1], sys.argv[2], sys.argv[3]
    total = int(DUR * SR)
    mix = np.zeros((2, total), np.float32)
    # música: Puzzle a partir de 4,75s (a batida de 14,3s cai na pisada 9,55)
    mus = trecho(ler(puzzle_src), 4.75 + ADIANTA, 4.75 + ADIANTA + DUR, 0.6, 2.5)
    mus = mus[:, :total]
    # ducking da música enquanto a voz fala
    duck = np.ones(mus.shape[1], np.float32)
    a, b = int(0.0 * SR), int(4.9 * SR)
    duck[a:b] = 0.4
    duck[b:b + int(0.6 * SR)] = np.linspace(0.4, 1, int(0.6 * SR))
    # (a frase "I haven't lost yet": a música abaixa mais por baixo dela)
    f0, f1 = int(1.5 * SR), int(2.6 * SR)
    duck[f0:f1] = 0.22
    mix[:, :mus.shape[1]] += mus * duck * 0.85
    # voz do Jin-Woo: o grito (32,2s do clipe) cai no começo da levantada (2,9s)
    voz = trecho(ler(voz_src), 29.4, 34.0, 0.05, 0.35)
    # ⚠️ v120e — PEDIDO: "aumenta o som do 'I haven't lost yet'": a voz inteira mais
    # alta e a frase (31,0-32,0s do clipe) ainda mais
    ganho = np.full(voz.shape[1], 1.7, np.float32)
    g0, g1 = int((31.0 - 29.4) * SR), int((32.0 - 29.4) * SR)
    ganho[g0:g1] = 2.4
    ini = int(max(0.1 - ADIANTA, 0) * SR)
    mix[:, ini:ini + voz.shape[1]] += voz * ganho
    # efeitos
    for quando, som, ganho in eventos():
        i = int(max(quando - ADIANTA, 0) * SR)
        som = som.astype(np.float32)
        n = min(len(som), total - i)
        mix[:, i:i + n] += som[:n] * ganho * 0.55
    # normaliza
    pico = np.max(np.abs(mix))
    if pico > 0.97:
        mix *= 0.97 / pico
    o = av.open(saida, 'w')
    st = o.add_stream('libmp3lame', rate=SR)
    st.layout = 'stereo'
    st.bit_rate = 192000
    pcm = (mix * 32767).astype(np.int16)
    for i in range(0, total, 1152):
        bloco = np.ascontiguousarray(pcm[:, i:i + 1152].T.reshape(1, -1))
        fr = av.AudioFrame.from_ndarray(bloco, format='s16', layout='stereo')
        fr.sample_rate = SR
        for p in st.encode(fr): o.mux(p)
    for p in st.encode(None): o.mux(p)
    o.close()
    print('ok', saida, DUR, 's')


if __name__ == '__main__':
    main()
