"""Mixagem do áudio do Flow do Aiku (cena + Flow): as FALAS dele (do vídeo "Aiku's Flow State",
Blue Lock S2), a trilha "Oliver Aiku Theme" e efeitos SINTETIZADOS (sem direito autoral).
Uso: python mixar_cena_aiku.py video.mp4 trilha.mp3 saida.mp3 [wav_debug.png]
Precisa de ffmpeg, numpy e scipy. Os tempos batem com Cutscenes.Flow_Aiku (HissatsuCutscenes.luau, v125).

PEDIDO: "faça de uma forma que o áudio mantenha o sentido, interprete a cena completamente e o
áudio também". Como a cena corta o meio do vídeo (0:19-0:32 e 0:37-0:57), as falas foram
REORDENADAS em um monólogo só, na ordem em que fazem sentido, cada uma sobre o plano certo:
  1 "My senses are in overdrive!"                      (vídeo 12.45-14.15) → avança / radar
  2 "I understand it all with my whole body."          (15.15-16.85)       → close no olho
  3 "When I reach the max of the abilities I've built up so far..." (17.65-20.65) → listras
  4 "There's a world I can see only once I'm there."   (21.72-23.65, fala que a cena cortou) → painéis
  5 "It's the intervening time and space he needs in order to use his abilities." (33.05-38.00)
  6 "That's when I'll hunt him down."                  (38.62-40.05, fala que a cena cortou) → rosto
  7 "I'll crush you all..."                            (56.95-58.45)       → setas 30%/70% → DASH
  8 "...so that I can bloom!"                          (63.35-64.65)       → o olho do Flow
A trilha começa no ponto em que a QUEDA dela (a pausa de 76,2-77,4s e a batida em 77,5s) cai
em cima da pausa antes do DASH (a fala 7) e a batida no DASH (17,3s)."""
import subprocess
import sys
import numpy as np
import scipy.io.wavfile as wav
import scipy.signal as sg

SR = 44100
DASH = 17.3          # a batida forte da trilha (OST 77,5s) cai aqui
OST_BATIDA = 77.5
DUR = 50.0           # cena (22.6s) + Flow (25s) + folga
rng = np.random.default_rng(11)


def ler_wav(caminho):
    sr, x = wav.read(caminho)
    x = x.astype(np.float32)
    if x.dtype != np.float32 or x.max() > 2:
        x = x / 32768.0
    if x.ndim == 1:
        x = np.stack([x, x], 1)
    return x.T  # (2, n)


def extrair(entrada, saida):
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", entrada, "-vn", "-ac", "2", "-ar", str(SR), saida], check=True)


def t(seg):
    return np.arange(int(seg * SR)) / SR


def env_ad(n, ataque, queda):
    tt = np.arange(n) / SR
    return np.minimum(tt / max(ataque, 1e-4), 1) * np.exp(-tt / max(queda, 1e-4))


def ruido(n):
    return rng.standard_normal(n).astype(np.float32)


def passa_baixa(x, corte):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= 1 / np.sqrt(1 + (f / corte) ** 4)
    return np.fft.irfft(X, len(x)).astype(np.float32)


def passa_alta(x, corte):
    sos = sg.butter(2, corte, "highpass", fs=SR, output="sos")
    return sg.sosfilt(sos, x).astype(np.float32)


# ---------- efeitos sintetizados ----------
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
    terra = passa_baixa(ruido(len(tt)), 1800) * env_ad(len(tt), 0.001, 0.06) * crocante
    return corpo + terra


def sfx_brilho(f0=1800, dur=0.9):
    tt = t(dur)
    s = np.zeros(len(tt), np.float32)
    for k, f in enumerate([f0, f0 * 1.5, f0 * 2.01, f0 * 3.02]):
        s += np.sin(2 * np.pi * f * tt + k) * (0.5 ** k)
    return s * env_ad(len(tt), 0.01, dur / 3.5) * 0.5


def sfx_vento(dur, sobe=True, f1=300, f2=3500):
    tt = t(dur)
    n = ruido(len(tt))
    out = np.zeros(len(tt), np.float32)
    bloco = int(0.05 * SR)
    for i in range(0, len(tt), bloco):
        u = i / len(tt)
        fc = (f1 + (f2 - f1) * u) if sobe else (f2 + (f1 - f2) * u)
        seg = n[i:i + bloco * 2]
        out[i:i + len(seg)] += passa_baixa(seg, fc)[:len(out) - i] * 0.5
    return out * (np.sin(np.pi * np.clip(tt / dur, 0, 1)) ** 1.5)


def sfx_explosao(dur=1.6):
    tt = t(dur)
    chiado = passa_baixa(ruido(len(tt)), 5000) * env_ad(len(tt), 0.003, 0.35) * 0.5
    return sfx_baque(42, dur, 0.9) + chiado


def sfx_ping(f0=1500, eco=True):
    """blip de radar/painel: senoide curta + eco"""
    tt = t(0.35)
    s = np.sin(2 * np.pi * f0 * tt) * env_ad(len(tt), 0.003, 0.05)
    if eco:
        d = int(0.12 * SR)
        s[d:] += 0.35 * s[:len(s) - d]
    return s * 0.7


def sfx_fogo(dur):
    """chama crepitando que cresce (o olho pegando fogo)"""
    tt = t(dur)
    base = passa_baixa(ruido(len(tt)), 3500) * (tt / dur) ** 1.5
    estalos = np.zeros(len(tt), np.float32)
    for _ in range(int(dur * 28)):
        i = int(rng.uniform(0, dur - 0.03) * SR)
        c = passa_alta(ruido(int(0.012 * SR)), 1500) * env_ad(int(0.012 * SR), 0.0005, 0.004)
        estalos[i:i + len(c)] += c * rng.uniform(0.3, 1.0) * (i / len(tt) + 0.2)
    return base * 0.6 + estalos * 0.8


def sfx_choque():
    """a bota arrancando a bola do pé do adversário: pancada seca + estalo metálico"""
    tt = t(0.8)
    seco = passa_alta(ruido(len(tt)), 600) * env_ad(len(tt), 0.0008, 0.04)
    corpo = sfx_baque(130, 0.5, 0.3)
    metal = np.zeros(len(tt), np.float32)
    for f in (880, 1330, 1760, 2570):
        metal += np.sin(2 * np.pi * f * tt) * env_ad(len(tt), 0.001, 0.18) * 0.25
    s = seco * 0.9
    s[:len(corpo)] += corpo
    return s + metal


def sfx_zumbido(dur):
    """o domo de projeção: zumbido grave com tremolo lento"""
    tt = t(dur)
    s = (np.sin(2 * np.pi * 96 * tt) + 0.6 * np.sin(2 * np.pi * 144 * tt) + 0.3 * np.sin(2 * np.pi * 288 * tt))
    s *= 0.6 + 0.4 * np.sin(2 * np.pi * 3.2 * tt)
    return s * np.minimum(tt / 0.5, 1) * np.minimum((dur - tt) / 0.5, 1)


def eventos():
    ev = []
    E = ev.append
    E((0.40, sfx_brilho(1800, 0.9), 0.45))                      # olho começa a ficar verde
    E((0.45, sfx_vento(0.6, True, 300, 3000), 0.5))              # a cena escurece
    for tp, f in ((1.05, 1500), (1.40, 1500), (1.75, 1700), (2.10, 1900)):
        E((tp, sfx_ping(f), 0.6))                                 # anéis de radar
    E((1.25, sfx_vento(0.8, True, 200, 2500), 0.7))              # flash do radar
    E((2.30, sfx_fogo(1.5), 0.7))                                # fogo no olho (close de lado)
    E((3.55, sfx_explosao(0.9), 0.45))                           # o fogo estoura
    E((4.05, sfx_brilho(2400, 1.2), 0.6))                        # olhos do Flow acendem
    E((4.10, sfx_vento(3.0, True, 400, 5000), 0.55))             # correndo
    for tp in (4.5, 5.0, 5.45, 5.9, 6.35, 6.8):
        E((tp, sfx_vento(0.35, True, 800, 6000), 0.5))           # listras passando pela câmera
    E((7.30, sfx_ping(2200), 0.5))                                # painéis de dados
    E((7.50, sfx_ping(2700), 0.5))
    E((9.25, sfx_vento(0.6, True, 100, 3500), 0.8))              # o domo infla
    E((9.25, sfx_baque(70, 0.7, 0.2), 0.7))
    E((9.40, sfx_zumbido(4.6), 0.28))                            # zumbido do domo
    for i in range(12):
        E((9.55 + 0.38 * i, sfx_ping(int(rng.uniform(1800, 3200)), False), 0.3))   # painéis surgindo
    E((14.0, sfx_baque(45, 1.2, 0.1), 0.6))                      # o rosto tenso
    E((14.0, sfx_vento(1.2, True, 150, 2500), 0.45))
    E((15.0, sfx_ping(900), 0.55))                                # setas
    E((15.12, sfx_ping(1100), 0.55))
    E((15.45, sfx_ping(1500), 0.6))                               # os números
    for tp, g in ((15.55, 0.8), (16.05, 0.9), (16.45, 1.0), (16.8, 1.1), (17.1, 1.2)):
        E((tp, sfx_coracao(), g))                                 # coração, na pausa da trilha
    E((17.0, sfx_vento(0.3, True, 800, 6000), 0.7))
    E((DASH, sfx_explosao(1.6), 1.0))                             # DASH! (a batida da trilha)
    E((17.6, sfx_vento(0.5, True, 300, 5000), 0.8))               # dispara
    E((18.25, sfx_choque(), 1.0))                                 # a bota arranca a bola
    E((18.25, sfx_ping(1200), 0.5))
    E((18.4, sfx_vento(1.3, False, 3000, 200), 0.5))              # câmera lenta (som descendo)
    E((18.7, sfx_coracao(1.2), 0.9))
    E((19.4, sfx_coracao(1.2), 0.9))
    E((19.7, sfx_vento(0.35, True, 500, 6000), 0.8))              # levanta e corre
    gap, tp = 0.19, 19.85
    for _ in range(8):
        E((tp, sfx_baque(90, 0.14, 0.6), 0.5))                    # passos em volta do adversário
        tp += gap
        gap = max(gap - 0.012, 0.1)
    E((20.5, sfx_baque(70, 0.25, 0.5), 0.8))                      # pegou a bola
    E((21.0, sfx_brilho(1500, 1.0), 0.6))                         # sorriso
    E((21.3, sfx_brilho(3000, 1.4), 0.7))                         # o olho do Flow
    E((21.3, sfx_coracao(1.1), 0.8))
    E((22.3, sfx_brilho(2200, 1.2), 0.45))
    return ev


# ---------- falas: (fonte_ini, fonte_fim, cena_t, cortes_internos, ganho) ----------
FALAS = [
    (12.45, 14.15, 0.40, [], 1.0),
    (15.15, 16.85, 2.45, [], 1.0),
    (17.65, 20.65, 4.30, [(19.0, 19.3)], 1.0),                   # (corta metade da pausa no meio da frase)
    (21.72, 23.65, 7.35, [], 1.0),
    (33.05, 38.00, 9.45, [(35.70, 36.00)], 1.0),                 # (corta a pausa no meio da frase)
    (38.62, 40.05, 14.20, [], 1.0),
    (56.95, 58.45, 15.75, [], 1.0),
    (63.35, 64.65, 21.10, [], 1.0),
]


def preparar_fala(mid, ini, fim, cortes):
    a, b = int(ini * SR), int(fim * SR)
    partes, cursor = [], a
    for c0, c1 in sorted(cortes):
        partes.append(mid[cursor:int(c0 * SR)])
        cursor = int(c1 * SR)
    partes.append(mid[cursor:b])
    x = np.concatenate(partes)
    sos = sg.butter(2, [110, 9000], "bandpass", fs=SR, output="sos")
    x = sg.sosfilt(sos, x).astype(np.float32)
    # mesma altura pra todas as falas (RMS alvo) e sem estourar
    rms = np.sqrt(np.mean(x ** 2)) + 1e-9
    x = x * (0.13 / rms)
    pico = np.max(np.abs(x))
    if pico > 0.9:
        x *= 0.9 / pico
    n = len(x)
    fi, fo = int(0.02 * SR), int(0.08 * SR)
    env = np.ones(n, np.float32)
    env[:fi] = np.linspace(0, 1, fi)
    env[-fo:] = np.minimum(env[-fo:], np.linspace(1, 0, fo))
    return x * env


def main():
    video, ost, saida = sys.argv[1], sys.argv[2], sys.argv[3]
    png = sys.argv[4] if len(sys.argv) > 4 else None
    extrair(video, "/tmp/_aiku_video.wav")
    extrair(ost, "/tmp/_aiku_ost.wav")
    vid = ler_wav("/tmp/_aiku_video.wav")
    mus = ler_wav("/tmp/_aiku_ost.wav")
    total = int(DUR * SR)
    mix = np.zeros((2, total), np.float32)
    # trilha: a batida (OST 77,5s) cai no DASH
    ini = OST_BATIDA - DASH
    m = mus[:, int(ini * SR):int(ini * SR) + total].copy()
    n = m.shape[1]
    fi, fo = int(0.35 * SR), int(3.0 * SR)
    m[:, :fi] *= np.linspace(0, 1, fi)
    m[:, n - fo:] *= np.linspace(1, 0, fo)
    # ducking: a trilha abaixa por baixo de cada fala (menos na pausa da própria trilha)
    voz_mask = np.zeros(total, np.float32)
    mid = vid.mean(0)
    vozes = []
    for (a, b, quando, cortes, g) in FALAS:
        x = preparar_fala(mid, a, b, cortes) * g
        i = int(quando * SR)
        vozes.append((i, x))
        voz_mask[i:i + len(x)] = 1.0
    jan = np.hanning(int(0.25 * SR))
    suave = sg.fftconvolve(voz_mask, jan / jan.sum(), mode="same")
    duck = 1.0 - 0.65 * np.clip(suave, 0, 1)
    mix[:, :n] += m * duck[:n] * 0.85
    for i, x in vozes:
        k = min(len(x), total - i)
        mix[:, i:i + k] += x[:k] * 1.35
    for quando, som, ganho in eventos():
        i = int(quando * SR)
        som = som.astype(np.float32)
        k = min(len(som), total - i)
        if k > 0:
            mix[:, i:i + k] += som[:k] * ganho * 0.5
    pico = np.max(np.abs(mix))
    mix *= 0.95 / max(pico, 1e-6)  # sobe o conjunto até o pico (a trilha e as falas já vêm equilibradas)
    wav.write("/tmp/_aiku_mix.wav", SR, (mix.T * 32767).astype(np.int16))
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", "/tmp/_aiku_mix.wav", "-codec:a", "libmp3lame", "-b:a", "192k", saida], check=True)
    print("ok", saida, DUR, "s")
    if png:
        import matplotlib  # opcional: desenha a onda com as marcas dos planos
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        fig, ax = plt.subplots(figsize=(16, 4))
        tt = np.arange(total) / SR
        ax.plot(tt[::50], mix.mean(0)[::50], lw=0.4)
        for nome, tp in (("Radar", 1.0), ("Olho", 2.25), ("Listras", 4.05), ("Bola", 7.15), ("Domo", 9.25), ("Rosto", 14.0),
                         ("Setas", 14.9), ("DASH", 17.3), ("Bota", 18.25), ("Volta", 19.7), ("Olho2", 21.0)):
            ax.axvline(tp, color="r", lw=0.6)
            ax.text(tp, 0.8, nome, rotation=90, fontsize=7)
        ax.set_xlim(0, 24)
        fig.savefig(png, dpi=110)


if __name__ == "__main__":
    main()
