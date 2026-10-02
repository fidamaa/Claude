import numpy as np
from PIL import Image, ImageDraw, ImageFilter
import math, random

OUT = 'C:/Users/fidamaa/AppData/Local/Temp/claude/C--Users-fidamaa-Downloads-Game/27a9423c-473b-4d76-bcef-c66cd66cfd31/scratchpad/img4/up/fx/'
random.seed(11)


def brilhar(im, raio=6, forca=1.0):
    """linha nítida + halo desfocado (glow), tudo branco no alfa"""
    a = np.asarray(im).astype(np.float32) / 255
    g = np.asarray(im.filter(ImageFilter.GaussianBlur(raio))).astype(np.float32) / 255
    return np.clip(a + g * 1.6 * forca, 0, 1)


def salvar(nome, alfa):
    a = np.clip(alfa, 0, 1)
    img = np.zeros((a.shape[0], a.shape[1], 4), np.uint8)
    img[..., :3] = 255
    img[..., 3] = (a * 255).astype(np.uint8)
    Image.fromarray(img, 'RGBA').save(OUT + nome + '.png')
    print('ok', nome)


# ---------- olho-mandala (o zoom no olho: engrenagens e raios) ----------
N = 512
im = Image.new('L', (N, N), 0)
d = ImageDraw.Draw(im)
c = N / 2
d.ellipse([c - 240, c - 240, c + 240, c + 240], outline=255, width=10)
d.ellipse([c - 214, c - 214, c + 214, c + 214], outline=190, width=4)
# anel de "engrenagem": 8 dentes em forma de peça
for k in range(8):
    a0 = k * math.pi / 4
    pts = []
    for s in range(0, 31):
        a = a0 - math.pi / 10 + s / 30 * (math.pi / 5)
        r = 150 + 34 * math.sin(s / 30 * math.pi) ** 0.5
        pts.append((c + math.cos(a) * r, c + math.sin(a) * r))
    d.line(pts, fill=255, width=9)
    # raio
    d.line([(c + math.cos(a0) * 60, c + math.sin(a0) * 60), (c + math.cos(a0) * 205, c + math.sin(a0) * 205)], fill=230, width=6)
    # encaixe redondo no fim do raio
    ex, ey = c + math.cos(a0 + math.pi / 8) * 120, c + math.sin(a0 + math.pi / 8) * 120
    d.ellipse([ex - 14, ey - 14, ex + 14, ey + 14], outline=255, width=5)
d.ellipse([c - 105, c - 105, c + 105, c + 105], outline=255, width=7)
for k in range(16):
    a = k * math.pi / 8
    d.line([(c + math.cos(a) * 30, c + math.sin(a) * 30), (c + math.cos(a) * 95, c + math.sin(a) * 95)], fill=200, width=3)
d.ellipse([c - 34, c - 34, c + 34, c + 34], fill=255)
salvar('olho_mandala', brilhar(im, 8))

# ---------- cérebro brilhante (visto de cima/frente, giros sinuosos) ----------
N = 512
im = Image.new('L', (N, N), 0)
d = ImageDraw.Draw(im)
c = N / 2
for lado in (-1, 1):
    cx = c + lado * 102
    # contorno do hemisfério
    pts = []
    for s in range(0, 181):
        a = s / 180 * 2 * math.pi
        rx, ry = 112 + 8 * math.sin(a * 5), 196 + 6 * math.sin(a * 7)
        pts.append((cx + math.cos(a) * rx, c + math.sin(a) * ry))
    d.line(pts + [pts[0]], fill=255, width=8)
    # giros: linhas onduladas dentro
    for g in range(11):
        y0 = c - 170 + g * 34
        largura = 100 * math.sqrt(max(0.0, 1 - ((y0 - c) / 200) ** 2))
        lin = []
        for s in range(0, 61):
            u = s / 60
            x = cx - largura * 0.9 + u * largura * 1.8
            y = y0 + 9 * math.sin(u * math.pi * random.uniform(3, 5) + g) + random.uniform(-2, 2)
            lin.append((x, y))
        d.line(lin, fill=210, width=5)
# fissura central
d.line([(c, c - 200), (c, c + 200)], fill=255, width=6)
salvar('cerebro', brilhar(im, 9, 1.2))

# ---------- olho de gênio (iris rendada com estrelas) ----------
N = 256
im = Image.new('L', (N, N), 0)
d = ImageDraw.Draw(im)
c = N / 2
d.ellipse([c - 118, c - 118, c + 118, c + 118], outline=255, width=6)
d.ellipse([c - 60, c - 60, c + 60, c + 60], outline=255, width=5)
for k in range(12):
    a = k * math.pi / 6
    # pontas de estrela saindo da íris
    p1 = (c + math.cos(a) * 62, c + math.sin(a) * 62)
    p2 = (c + math.cos(a + 0.18) * 100, c + math.sin(a + 0.18) * 100)
    p3 = (c + math.cos(a + 0.36) * 62, c + math.sin(a + 0.36) * 62)
    d.line([p1, p2, p3], fill=255, width=4)
    bx, by = c + math.cos(a + 0.26) * 108, c + math.sin(a + 0.26) * 108
    d.ellipse([bx - 5, by - 5, bx + 5, by + 5], fill=255)
for k in range(24):
    a = k * math.pi / 12
    d.line([(c + math.cos(a) * 22, c + math.sin(a) * 22), (c + math.cos(a) * 54, c + math.sin(a) * 54)], fill=180, width=2)
d.ellipse([c - 16, c - 16, c + 16, c + 16], fill=255)
salvar('olho_genio', brilhar(im, 4))

# ---------- chão de quebra-cabeça (azulejo 2x2 peças, repete) ----------
N = 256
im = Image.new('L', (N, N), 0)
d = ImageDraw.Draw(im)
P = N // 2


def borda(x0, y0, x1, y1, sinal):
    # segmento com encaixe redondo no meio (sinal = lado do encaixe)
    mx, my = (x0 + x1) / 2, (y0 + y1) / 2
    vx, vy = (x1 - x0), (y1 - y0)
    L = math.hypot(vx, vy)
    ux, uy = vx / L, vy / L
    nx, ny = -uy * sinal, ux * sinal
    pts = [(x0, y0), (mx - ux * 18, my - uy * 18)]
    for s in range(0, 25):
        a = math.pi + s / 24 * math.pi
        pts.append((mx + ux * math.cos(a) * 18 + nx * (14 + math.sin(a) * -18),
                    my + uy * math.cos(a) * 18 + ny * (14 + math.sin(a) * -18)))
    pts += [(mx + ux * 18, my + uy * 18), (x1, y1)]
    d.line(pts, fill=255, width=6)


for i in range(2):
    for j in range(2):
        x, y = i * P, j * P
        borda(x, y, x + P, y, 1 if (i + j) % 2 == 0 else -1)
        borda(x, y, x, y + P, -1 if (i + j) % 2 == 0 else 1)
salvar('quebracabeca', brilhar(im, 4, 0.8))

# ---------- redemoinho escuro (braços em espiral) ----------
N = 512
y, x = np.mgrid[0:N, 0:N].astype(np.float32)
x, y = (x - N / 2) / (N / 2), (y - N / 2) / (N / 2)
r = np.sqrt(x * x + y * y)
a = np.arctan2(y, x)
esp = 0.5 + 0.5 * np.sin(a * 3 + np.log(r + 1e-3) * 9)
alfa = (esp ** 3) * np.clip(1 - r, 0, 1) ** 0.4 * np.clip(r * 6, 0, 1)
salvar('redemoinho', alfa)

# ---------- riscos verticais (fundo da cena dos olhos vazios) ----------
W, H = 256, 512
alfa = np.zeros((H, W), np.float32)
for _ in range(38):
    cx = random.uniform(0, W)
    w = random.uniform(1.5, 9)
    forca = random.uniform(0.35, 1)
    xs = np.arange(W)
    perfil = np.clip(1 - np.abs(xs - cx) / w, 0, 1) * forca
    vert = np.clip(np.sin(np.linspace(0, math.pi, H)) * random.uniform(0.8, 1.4), 0, 1)
    alfa = np.maximum(alfa, vert[:, None] * perfil[None, :])
salvar('riscos', alfa)
