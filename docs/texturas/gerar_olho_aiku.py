"""Íris do Flow do Aiku DESENHADA (v126d): mesmo desenho do anime (degradê, riscos radiais
pretos, halo branco no centro, anel colorido e pupila branca), nítida — no lugar do recorte
do quadro do vídeo (borrado). Gera aiku_olho_verde.png e aiku_olho_azul.png (512x512)."""
import math
import os
import random
from PIL import Image, ImageDraw, ImageFilter

AQUI = os.path.dirname(os.path.abspath(__file__))
G = 4  # desenha 4x maior e reduz (antisserrilhado)
S = 512 * G
C = S / 2
R = S * 0.48


def olho(nome, borda, meio, claro, anel, semente):
    rnd = random.Random(semente)
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # degradê radial (borda escura -> meio -> claro perto do centro)
    passos = 220
    for i in range(passos):
        u = i / (passos - 1)  # 0 = borda, 1 = centro
        r = R * (1 - u)
        if u < 0.55:
            k = u / 0.55
            cor = tuple(int(borda[j] + (meio[j] - borda[j]) * k) for j in range(3))
        else:
            k = (u - 0.55) / 0.45
            cor = tuple(int(meio[j] + (claro[j] - meio[j]) * k) for j in range(3))
        d.ellipse((C - r, C - r, C + r, C + r), fill=cor + (255,))
    # riscos radiais pretos (de fora pra dentro), alguns com quebra (raio)
    for _ in range(64):
        ang = rnd.uniform(0, 2 * math.pi)
        r0 = R * rnd.uniform(0.86, 0.99)
        r1 = R * rnd.uniform(0.42, 0.75)
        larg = int(rnd.uniform(1.4, 3.2) * G)
        pts = []
        n = 4
        for k in range(n + 1):
            rr = r0 + (r1 - r0) * k / n
            a = ang + (rnd.uniform(-0.03, 0.03) if 0 < k < n else 0)
            pts.append((C + math.cos(a) * rr, C + math.sin(a) * rr))
        d.line(pts, fill=(12, 20, 16, 235), width=larg, joint='curve')
    # tracinhos curtos na borda
    for k in range(90):
        a = 2 * math.pi * k / 90 + rnd.uniform(-0.01, 0.01)
        r0, r1 = R * 0.995, R * rnd.uniform(0.9, 0.95)
        d.line([(C + math.cos(a) * r0, C + math.sin(a) * r0), (C + math.cos(a) * r1, C + math.sin(a) * r1)],
               fill=(10, 16, 12, 255), width=int(1.6 * G))
    # halo branco do centro (com raios finos)
    halo = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    dh = ImageDraw.Draw(halo)
    rh = R * 0.42
    dh.ellipse((C - rh, C - rh, C + rh, C + rh), fill=(255, 255, 255, 235))
    for _ in range(140):
        a = rnd.uniform(0, 2 * math.pi)
        r1 = rh * rnd.uniform(1.05, 1.35)
        dh.line([(C + math.cos(a) * rh * 0.8, C + math.sin(a) * rh * 0.8), (C + math.cos(a) * r1, C + math.sin(a) * r1)],
                fill=(255, 255, 255, 200), width=int(1.2 * G))
    halo = halo.filter(ImageFilter.GaussianBlur(5 * G))
    img.alpha_composite(halo)
    # anel colorido e pupila branca
    d = ImageDraw.Draw(img)
    ra, re = R * 0.205, R * 0.15
    d.ellipse((C - ra, C - ra, C + ra, C + ra), fill=anel + (255,))
    d.ellipse((C - re, C - re, C + re, C + re), fill=(255, 255, 255, 255))
    # recorte redondo com borda escura fina
    mascara = Image.new('L', (S, S), 0)
    ImageDraw.Draw(mascara).ellipse((C - R, C - R, C + R, C + R), fill=255)
    img.putalpha(Image.composite(img.getchannel('A'), mascara, mascara))
    ImageDraw.Draw(img).ellipse((C - R, C - R, C + R, C + R), outline=(8, 14, 10, 255), width=int(3 * G))
    img = img.resize((512, 512), Image.LANCZOS)
    img.save(os.path.join(AQUI, nome))


olho('aiku_olho_verde.png', borda=(40, 110, 45), meio=(95, 185, 90), claro=(190, 245, 170), anel=(80, 190, 170), semente=7)
olho('aiku_olho_azul.png', borda=(30, 70, 140), meio=(80, 135, 210), claro=(180, 215, 250), anel=(90, 130, 230), semente=11)
print('ok')
