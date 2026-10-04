"""Áudio do Flow do Aiku — as DUAS versões pra comparar (⚠️ v126j).
PEDIDO: "faz pra mim as duas versões, tanto a que eu pedi quanto a que você recomendou, pra eu
poder ver qual que é a melhor".

  A) cover   — falas (voz separada) + efeitos + o COVER do tema do Aiku (Void Rhythm,
               youtube gQHf6erxwnY). A pausa do cover (12.7-13.0s) e a batida em 13.1s caem no
               DASH (17.3s); antes disso, os 4.2s iniciais da cena usam o trecho 8.5-12.7s do
               cover (que vai crescendo) com fade. ⚠️ cover = mesma composição da OST oficial:
               o Roblox pode restringir igual ao v2.
  B) falas   — só falas + efeitos (SEM música). A música vem da faixa LICENCIADA do Roblox
               ("No Half Measures 60 B", APM, rbxassetid://9045142177) tocada junto pelo
               MusicClient (Cosmeticos: Musica.Fundo).

Uso: python mixar_cena_aiku_ab.py vocals.wav cover.webm saida_A.mp3 saida_B.mp3"""
import os
import sys
import numpy as np
import scipy.signal as sg

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mixar_cena_aiku as v1  # noqa: E402
import mixar_cena_aiku_v2 as v2  # noqa: E402

SR = v1.SR
COVER_BATIDA = 13.1         # a batida depois da pausa do cover
PRE_DE, PRE_ATE = 8.5, 12.7  # trecho do cover que toca antes do cover "começar"


def trilha_cover(mus, total):
    ini = COVER_BATIDA - v1.DASH  # = -4.2: o cover começa aos 4.2s da cena
    m = np.zeros((2, total), np.float32)
    i0 = int(-ini * SR)
    corpo = mus[:, :total - i0]
    m[:, i0:i0 + corpo.shape[1]] = corpo
    pre = mus[:, int(PRE_DE * SR):int(PRE_ATE * SR)].copy()
    pre = pre[:, -i0:] if pre.shape[1] >= i0 else np.pad(pre, ((0, 0), (i0 - pre.shape[1], 0)))
    cf = int(0.3 * SR)
    pre[:, :int(0.4 * SR)] *= np.linspace(0, 1, int(0.4 * SR))
    pre[:, -cf:] *= np.linspace(1, 0, cf)
    m[:, i0:i0 + cf] *= np.linspace(0, 1, cf)
    m[:, :i0] += pre[:, :i0]
    fo = int(3.0 * SR)
    m[:, total - fo:] *= np.linspace(1, 0, fo)
    return m


def mixar(vid, trilha, total, ganho_trilha):
    mix = np.zeros((2, total), np.float32)
    voz_mask = np.zeros(total, np.float32)
    mid = vid.mean(0)
    vozes = []
    for (a, b, quando, cortes, g) in v1.FALAS:
        x = v1.preparar_fala(mid, a, b, cortes) * g
        i = int(quando * SR)
        vozes.append((i, x))
        voz_mask[i:i + len(x)] = 1.0
    if trilha is not None:
        jan = np.hanning(int(0.25 * SR))
        suave = sg.fftconvolve(voz_mask, jan / jan.sum(), mode="same")
        duck = 1.0 - 0.6 * np.clip(suave, 0, 1)
        # depois da cena (sem falas) a música é o Flow inteiro: sobe pro nível das falas
        sobe = np.clip((np.arange(total) / SR - 22.0) / 1.0, 0, 1) * 1.1 + 1.0
        mix += trilha * duck * sobe * ganho_trilha
    for i, x in vozes:
        k = min(len(x), total - i)
        mix[:, i:i + k] += x[:k] * 1.35
    for quando, som, ganho in v1.eventos():
        i = int(quando * SR)
        som = som.astype(np.float32)
        k = min(len(som), total - i)
        if k > 0:
            mix[:, i:i + k] += som[:k] * ganho * 0.5
    return mix * (0.95 / max(np.max(np.abs(mix)), 1e-6))


def main():
    voz, cover, saida_a, saida_b = sys.argv[1:5]
    vid = v2.ler(voz)
    total = int(v1.DUR * SR)
    a = mixar(vid, trilha_cover(v2.ler(cover), total), total, 0.85)
    v2.gravar_mp3(a, saida_a)
    b = mixar(vid, None, total, 0)
    v2.gravar_mp3(b, saida_b)
    print("ok", saida_a, saida_b)


if __name__ == "__main__":
    main()
