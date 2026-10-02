import numpy as np
from PIL import Image, ImageDraw, ImageFilter
import math, os

OUT = 'C:/Users/fidamaa/AppData/Local/Temp/claude/C--Users-fidamaa-Downloads-Game/27a9423c-473b-4d76-bcef-c66cd66cfd31/scratchpad/img4/up/fx/'
os.makedirs(OUT, exist_ok=True)
N = 256


def grade(n=N):
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    c = (n - 1) / 2
    return (x - c) / c, (y - c) / c


def salvar(nome, alfa, rgb=None):
    a = np.clip(alfa, 0, 1)
    img = np.zeros((a.shape[0], a.shape[1], 4), np.uint8)
    if rgb is None:
        img[..., :3] = 255
    else:
        img[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    img[..., 3] = (a * 255).astype(np.uint8)
    Image.fromarray(img, 'RGBA').save(OUT + nome + '.png')
    print('ok', nome)


x, y = grade()
r = np.sqrt(x * x + y * y)

# brilho: círculo macio
salvar('brilho', np.clip(1 - r, 0, 1) ** 2.2)

# quadrado (confete): branco sólido, cantos levemente arredondados, borda suave
q = np.maximum(np.abs(x), np.abs(y))
salvar('quadrado', np.clip((0.92 - q) / 0.04, 0, 1))

# gota (chuva): risco vertical fino e com degradê
g = np.clip(1 - np.abs(x) / 0.12, 0, 1) * np.clip(1 - np.abs(y), 0, 1) ** 0.6
salvar('gota', g)

# anel fino (onda/anel do planeta/anel de fótons)
salvar('anel', np.clip(1 - np.abs(r - 0.88) / 0.07, 0, 1) ** 1.5)

# bolha: borda clara + reflexo, miolo quase transparente
borda = np.clip(1 - np.abs(r - 0.9) / 0.1, 0, 1)
miolo = np.where(r < 0.95, 0.08 + 0.25 * r ** 4, 0)
refl = np.clip(1 - np.sqrt((x + 0.38) ** 2 + (y + 0.42) ** 2) / 0.22, 0, 1) ** 1.5
rgb = np.zeros((N, N, 3), np.float32)
ang = np.arctan2(y, x)
rgb[..., 0] = 200 + 55 * np.sin(ang * 2)
rgb[..., 1] = 225 + 30 * np.sin(ang * 2 + 2)
rgb[..., 2] = 255
rgb = rgb * (1 - refl[..., None]) + 255 * refl[..., None]
salvar('bolha', np.clip(borda + miolo + refl, 0, 1) * (r < 1), rgb)

# esfera sombreada (planeta) — cinza claro com luz em cima à esquerda (ImageColor3 tinge)
dentro = r < 1
z = np.sqrt(np.clip(1 - r * r, 0, 1))
luz = np.array([-0.45, -0.5, 0.74])
luz = luz / np.linalg.norm(luz)
d = np.clip(x * luz[0] + y * luz[1] + z * luz[2], 0, 1)
sh = 0.18 + 0.82 * d ** 0.9
# faixas de nuvem/relevo leves
faixas = 0.08 * np.sin(y * 9 + np.sin(x * 4) * 1.5)
sh = np.clip(sh + faixas * z, 0, 1)
# borda de atmosfera
atm = np.clip((r - 0.86) / 0.14, 0, 1) * 0.35
v = np.clip(sh + atm, 0, 1) * 255
salvar('esfera', np.clip((1 - r) / 0.012, 0, 1), np.stack([v, v, v], -1))

# coração
t = np.linspace(0, 2 * math.pi, 400)
hx = 16 * np.sin(t) ** 3
hy = -(13 * np.cos(t) - 5 * np.cos(2 * t) - 2 * np.cos(3 * t) - np.cos(4 * t))
pts = [(N / 2 + px * 7.2, N / 2 + 10 + py * 7.2) for px, py in zip(hx, hy)]
im = Image.new('L', (N, N), 0)
ImageDraw.Draw(im).polygon(pts, fill=255)
im = im.filter(ImageFilter.GaussianBlur(1.2))
a = np.asarray(im).astype(np.float32) / 255
# brilho interno leve (mais claro em cima à esquerda)
lum = 205 + 50 * np.clip(1 - np.sqrt((x + 0.3) ** 2 + (y + 0.35) ** 2) / 0.6, 0, 1)
salvar('coracao', a, np.stack([lum, lum, lum], -1))

# pétala de cerejeira (branca; cor no Color da partícula)
im = Image.new('L', (N, N), 0)
dr = ImageDraw.Draw(im)
pts = []
for i in range(200):
    tt = i / 199 * math.pi
    w = math.sin(tt) ** 0.8 * 70
    yy = 28 + tt / math.pi * 200
    pts.append((N / 2 + w, yy))
for i in range(200):
    tt = (1 - i / 199) * math.pi
    w = math.sin(tt) ** 0.8 * 70
    yy = 28 + tt / math.pi * 200
    pts.append((N / 2 - w, yy))
dr.polygon(pts, fill=255)
dr.polygon([(N / 2 - 14, 20), (N / 2, 44), (N / 2 + 14, 20)], fill=0)  # entalhe da ponta
im = im.filter(ImageFilter.GaussianBlur(1.5))
a = np.asarray(im).astype(np.float32) / 255
lum = 255 - 40 * np.clip((y + 1) / 2, 0, 1)
salvar('petala', a, np.stack([lum, lum, lum], -1))

# floco de neve: 6 braços com galhos
im = Image.new('L', (N, N), 0)
dr = ImageDraw.Draw(im)
c = N / 2
for k in range(6):
    a0 = k * math.pi / 3
    ex, ey = c + math.cos(a0) * 110, c + math.sin(a0) * 110
    dr.line([(c, c), (ex, ey)], fill=255, width=10)
    for f in (0.45, 0.72):
        bx, by = c + math.cos(a0) * 110 * f, c + math.sin(a0) * 110 * f
        for s in (-1, 1):
            a1 = a0 + s * math.pi / 4
            dr.line([(bx, by), (bx + math.cos(a1) * 34, by + math.sin(a1) * 34)], fill=255, width=8)
dr.ellipse([c - 16, c - 16, c + 16, c + 16], fill=255)
im = im.filter(ImageFilter.GaussianBlur(1.5))
salvar('floco', np.asarray(im).astype(np.float32) / 255)

# nuvem/nebulosa: blob macio com ruído
rng = np.random.default_rng(7)
ruido = np.zeros((N, N), np.float32)
for oit, amp in ((8, 0.5), (16, 0.3), (32, 0.2)):
    base = rng.random((oit, oit)).astype(np.float32)
    big = np.asarray(Image.fromarray((base * 255).astype(np.uint8)).resize((N, N), Image.BICUBIC)).astype(np.float32) / 255
    ruido += big * amp
neb = np.clip(1 - r, 0, 1) ** 1.4 * (0.45 + 0.75 * ruido)
salvar('nuvem', np.clip(neb, 0, 1))

# estrela de 4 pontas nítida (brilho de estrela/cintilar)
s4 = np.clip(1 - (np.abs(x) ** 0.5 + np.abs(y) ** 0.5) / 0.7, 0, 1) ** 1.2 + np.clip(1 - r / 0.25, 0, 1) ** 2
salvar('estrela4', np.clip(s4, 0, 1))

# moeda (frente): disco dourado com borda e "$" — para billboard/partícula
im = Image.new('RGBA', (N, N), (0, 0, 0, 0))
dr = ImageDraw.Draw(im)
dr.ellipse([8, 8, N - 8, N - 8], fill=(255, 196, 40, 255))
dr.ellipse([30, 30, N - 30, N - 30], fill=(255, 220, 90, 255))
dr.ellipse([40, 40, N - 40, N - 40], fill=(250, 205, 60, 255))
try:
    from PIL import ImageFont
    fnt = ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf', 150)
    dr.text((N / 2, N / 2 + 4), '$', font=fnt, fill=(205, 140, 20, 255), anchor='mm')
except Exception as e:
    print('sem fonte', e)
im = im.filter(ImageFilter.GaussianBlur(0.8))
im.save(OUT + 'moeda.png')
print('ok moeda')
