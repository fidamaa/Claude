"""Áudio do Flow do Aiku, v3 (⚠️ v126i) — SEM a trilha oficial.
PEDIDO: "ele tava funcionando, e do nada parou pro meu amigo e parou geral, deu como RESTRITO".
Causa: o v2 tinha o "Oliver Aiku Theme" (OST oficial do anime). O Roblox analisa os áudios
enviados atrás de música com direito autoral e restringe DEPOIS (por isso funcionou um tempo).
O v3 troca a trilha por uma música ORIGINAL sintetizada aqui (lá menor, 140 BPM): começa tensa
(pad + arpejo subindo), a bateria entra aos poucos, o DASH (17.3s) cai num tempo forte com uma
pancada, e depois segue cheia até o fim do Flow. Falas (só a voz, demucs) e efeitos = os do v2.
Uso: python mixar_cena_aiku_v3.py vocals.wav saida.mp3"""
import os
import sys
import numpy as np
import scipy.signal as sg

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mixar_cena_aiku as v1  # noqa: E402
import mixar_cena_aiku_v2 as v2  # noqa: E402

SR = v1.SR
BPM = 140.0
BEAT = 60.0 / BPM
DASH = v1.DASH
T0 = DASH - round(DASH / BEAT) * BEAT  # grade de tempos que passa pelo DASH
rng = np.random.default_rng(7)

# lá menor: Am - F - C - G (um acorde por compasso)
ACORDES = [(57, 60, 64), (53, 57, 60), (48, 52, 55), (55, 59, 62)]
BAIXO = [45, 41, 36, 43]


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def env(n, a, r):
    e = np.ones(n, np.float32)
    na, nr = max(1, int(a * SR)), max(1, int(r * SR))
    e[:na] = np.linspace(0, 1, na)
    e[-nr:] *= np.linspace(1, 0, nr)
    return e


def serra(f, n, detune=0.0):
    t = np.arange(n) / SR
    x = np.zeros(n, np.float32)
    for d in (-detune, 0.0, detune):
        x += (2 * ((t * f * (1 + d)) % 1.0) - 1).astype(np.float32)
    return x / 3


def lp(x, corte, ordem=2):
    sos = sg.butter(ordem, min(corte, SR / 2 - 100), "low", fs=SR, output="sos")
    return sg.sosfilt(sos, x).astype(np.float32)


def kick():
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    f = 50 + 120 * np.exp(-t * 30)
    return (np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9)).astype(np.float32)


def caixa():
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    r = sg.sosfilt(sg.butter(2, [900, 6000], "bandpass", fs=SR, output="sos"), rng.standard_normal(n))
    tom = np.sin(2 * np.pi * 190 * t)
    return ((r * 0.8 + tom * 0.4) * np.exp(-t * 18)).astype(np.float32)


def chimbal(aberto=False):
    n = int((0.18 if aberto else 0.05) * SR)
    t = np.arange(n) / SR
    r = sg.sosfilt(sg.butter(2, 7000, "high", fs=SR, output="sos"), rng.standard_normal(n))
    return (r * np.exp(-t * (14 if aberto else 70))).astype(np.float32)


def pancada():
    n = int(2.0 * SR)
    t = np.arange(n) / SR
    grave = np.sin(2 * np.pi * (40 + 60 * np.exp(-t * 6)) * t) * np.exp(-t * 2.2)
    ruido = lp(rng.standard_normal(n).astype(np.float32), 3000) * np.exp(-t * 4)
    return (grave * 1.0 + ruido * 0.5).astype(np.float32)


def subida(dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    r = rng.standard_normal(n).astype(np.float32)
    out = np.zeros(n, np.float32)
    bloco = 2048
    for i in range(0, n, bloco):
        k = i / n
        out[i:i + bloco] = sg.sosfilt(sg.butter(2, 300 + 7000 * k ** 2, "low", fs=SR, output="sos"), r[i:i + bloco])
    return out * (t / dur) ** 2


def por(buf, i, x, g=1.0):
    if i >= len(buf) or i + len(x) <= 0:
        return
    a = max(0, -i)
    k = min(len(x) - a, len(buf) - (i + a))
    buf[i + a:i + a + k] += x[a:a + k] * g


def musica(total_s):
    n = int(total_s * SR)
    m = np.zeros(n, np.float32)
    bat = np.zeros(n, np.float32)
    K, S, H, HA = kick(), caixa(), chimbal(), chimbal(True)
    nb = int(total_s / BEAT) + 2
    for b in range(-8, nb):
        t = T0 + b * BEAT
        if t < 0 or t >= total_s:
            continue
        i = int(t * SR)
        compasso = int(np.floor((t - T0) / (4 * BEAT)))
        tempo = b % 4
        acorde, baixo = ACORDES[compasso % 4], BAIXO[compasso % 4]
        # intensidade: 0 antes de 7s, cresce até o DASH, cheia depois
        if t < 7.0:
            nivel = 0
        elif t < DASH - 4 * BEAT:
            nivel = 1
        elif t < DASH:
            nivel = 2  # pausa/tensão logo antes do DASH
        else:
            nivel = 3
        # pad (no começo do compasso)
        if tempo == 0:
            dur = 4 * BEAT
            nn = int(dur * SR)
            pad = sum(serra(hz(nota), nn, 0.004) for nota in acorde) / 3
            pad = lp(pad, 1200 if nivel < 3 else 2400) * env(nn, 0.4, 0.5)
            por(m, i, pad, 0.22 if nivel < 3 else 0.18)
        # baixo
        if nivel >= 1:
            nn = int(BEAT * 0.9 * SR)
            for meio in (0, 1):
                bx = lp(serra(hz(baixo), nn // 2, 0.002), 300 + 300 * (nivel == 3)) * env(nn // 2, 0.005, 0.05)
                por(m, i + meio * (nn // 2 + int(0.05 * BEAT * SR)), bx, 0.45)
        # arpejo (16 avos) — sobe de volume até o DASH
        if nivel >= 0 and t > 1.0:
            notas = [acorde[0] + 12, acorde[1] + 12, acorde[2] + 12, acorde[1] + 24]
            vol = 0.06 + 0.08 * min(1.0, t / DASH) if nivel < 3 else 0.11
            for q in range(4):
                nn = int(BEAT / 4 * SR)
                x = np.sign(np.sin(2 * np.pi * hz(notas[q]) * np.arange(nn) / SR)).astype(np.float32)
                x = lp(x, 2500) * env(nn, 0.003, 0.03)
                por(m, i + q * nn, x, vol)
        # bateria
        if nivel == 1 or nivel == 3:
            por(bat, i, K, 0.9 if nivel == 3 else 0.6)
            if tempo in (1, 3):
                por(bat, i, S, 0.5 if nivel == 3 else 0.3)
            for q in range(2):
                por(bat, i + int(q * BEAT / 2 * SR), H, 0.12)
            if nivel == 3 and tempo == 3:
                por(bat, i + int(BEAT / 2 * SR), HA, 0.15)
    # subida antes do DASH e a PANCADA no DASH
    sd = 4 * BEAT
    por(m, int((DASH - sd) * SR), subida(sd), 0.35)
    por(bat, int(DASH * SR), pancada(), 0.9)
    out = m + bat
    # estéreo simples (arpejo/pad um pouco abertos)
    st = np.stack([out, np.roll(out, int(0.012 * SR)) * 0.96])
    fo = int(3.0 * SR)
    st[:, -fo:] *= np.linspace(1, 0, fo)
    fi = int(0.5 * SR)
    st[:, :fi] *= np.linspace(0, 1, fi)
    return st / max(np.max(np.abs(st)), 1e-6) * 0.8


def main():
    voz, saida = sys.argv[1], sys.argv[2]
    vid = v2.ler(voz)
    total = int(v1.DUR * SR)
    mix = np.zeros((2, total), np.float32)
    m = musica(v1.DUR)[:, :total]
    voz_mask = np.zeros(total, np.float32)
    mid = vid.mean(0)
    vozes = []
    for (a, b, quando, cortes, g) in v1.FALAS:
        x = v1.preparar_fala(mid, a, b, cortes) * g
        i = int(quando * SR)
        vozes.append((i, x))
        voz_mask[i:i + len(x)] = 1.0
    jan = np.hanning(int(0.25 * SR))
    suave = sg.fftconvolve(voz_mask, jan / jan.sum(), mode="same")
    duck = 1.0 - 0.55 * np.clip(suave, 0, 1)
    # depois da cena (sem falas) a música é o Flow inteiro: sobe pra ficar no nível das falas
    sobe = np.clip((np.arange(total) / SR - 22.0) / 1.0, 0, 1) * 1.4 + 1.0
    mix[:, :m.shape[1]] += m * duck[:m.shape[1]] * sobe[:m.shape[1]] * 0.8
    for i, x in vozes:
        k = min(len(x), total - i)
        mix[:, i:i + k] += x[:k] * 1.35
    for quando, som, ganho in v1.eventos():
        i = int(quando * SR)
        som = som.astype(np.float32)
        k = min(len(som), total - i)
        if k > 0:
            mix[:, i:i + k] += som[:k] * ganho * 0.5
    mix *= 0.95 / max(np.max(np.abs(mix)), 1e-6)
    v2.gravar_mp3(mix, saida)
    print("ok", saida, v1.DUR, "s")


if __name__ == "__main__":
    main()
