"""Áudio do Flow do Aiku, v2 (⚠️ v126h) — no formato do Shidou (que o Roblox aceitou).
PEDIDO: "faz na sua formatação o áudio, ele não quis aceitar o arquivo, deu que violou os termos".
O v1 (mixar_cena_aiku.py) usava o áudio CRU do vídeo nas falas — com a música e os efeitos do
anime junto. Aqui as falas vêm SÓ da voz separada (demucs --two-stems vocals), em japonês
(sem palavrão: 感度がぶち上がる / 全身で理解できる / 能力のオールマックス / ここに達してこそ見える世界 /
一瞬の時間と空間の狭間 / 狩るのはその間合い / お前らを潰して / 俺が咲く), mais a trilha (link do usuário)
com a batida no DASH e os efeitos sintetizados do v1. Tempos e eventos = os do v1.
Uso: python mixar_cena_aiku_v2.py vocals.wav trilha.webm saida.mp3"""
import os
import sys
import av
import numpy as np
import scipy.signal as sg

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mixar_cena_aiku as v1  # noqa: E402

SR = v1.SR


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


def gravar_mp3(mix, saida):
    c = av.open(saida, "w", format="mp3")
    st = c.add_stream("mp3", rate=SR)
    st.bit_rate = 192000
    st.layout = "stereo"
    dados = np.ascontiguousarray(np.clip(mix, -1, 1).astype(np.float32))
    passo = 1152 * 8
    for i in range(0, dados.shape[1], passo):
        fr = av.AudioFrame.from_ndarray(dados[:, i:i + passo].copy(), format="fltp", layout="stereo")
        fr.sample_rate = SR
        for p in st.encode(fr):
            c.mux(p)
    for p in st.encode(None):
        c.mux(p)
    c.close()


def main():
    voz, ost, saida = sys.argv[1], sys.argv[2], sys.argv[3]
    vid = ler(voz)
    mus = ler(ost)
    total = int(v1.DUR * SR)
    mix = np.zeros((2, total), np.float32)
    ini = v1.OST_BATIDA - v1.DASH
    m = mus[:, int(ini * SR):int(ini * SR) + total].copy()
    n = m.shape[1]
    fi, fo = int(0.35 * SR), int(3.0 * SR)
    m[:, :fi] *= np.linspace(0, 1, fi)
    m[:, n - fo:] *= np.linspace(1, 0, fo)
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
    duck = 1.0 - 0.6 * np.clip(suave, 0, 1)
    mix[:, :n] += m * duck[:n] * 0.85
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
    gravar_mp3(mix, saida)
    print("ok", saida, v1.DUR, "s")


if __name__ == "__main__":
    main()
