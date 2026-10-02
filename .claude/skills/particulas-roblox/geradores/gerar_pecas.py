import numpy as np
from PIL import Image, ImageDraw, ImageFilter
import math

OUT = 'C:/Users/fidamaa/AppData/Local/Temp/claude/C--Users-fidamaa-Downloads-Game/27a9423c-473b-4d76-bcef-c66cd66cfd31/scratchpad/img4/up/fx/'
N = 256
S = 2
n = N * S

# encaixe de cada lado: +1 = pino pra fora, -1 = buraco pra dentro, 0 = liso
PECAS = [
    (1, -1, 1, -1), (1, 1, -1, -1), (-1, 1, 1, 0), (1, 0, -1, 1), (-1, -1, 1, 1), (0, 1, 1, -1),
]


def lado(p0, p1, tipo, centro):
    (x0, y0), (x1, y1) = p0, p1
    pts = []
    dx, dy = x1 - x0, y1 - y0
    L = math.hypot(dx, dy)
    ux, uy = dx / L, dy / L
    # normal apontando pra FORA da peça
    nx, ny = uy, -ux
    mx, my = (x0 + x1) / 2, (y0 + y1) / 2
    if (mx + nx - centro[0]) ** 2 + (my + ny - centro[1]) ** 2 < (mx - centro[0]) ** 2 + (my - centro[1]) ** 2:
        nx, ny = -nx, -ny
    for s in range(0, 61):
        u = s / 60
        bx, by = x0 + dx * u, y0 + dy * u
        off = 0
        if tipo != 0 and 0.32 < u < 0.68:
            k = (u - 0.32) / 0.36
            off = tipo * L * 0.2 * math.sin(k * math.pi) ** 0.7
        pts.append((bx + nx * off, by + ny * off))
    return pts


for i, (t1, t2, t3, t4) in enumerate(PECAS):
    m = n * 0.22
    c = [(m, m), (n - m, m), (n - m, n - m), (m, n - m)]
    centro = (n / 2, n / 2)
    pts = lado(c[0], c[1], t1, centro) + lado(c[1], c[2], t2, centro) + lado(c[2], c[3], t3, centro) + lado(c[3], c[0], t4, centro)
    forma = Image.new('L', (n, n), 0)
    ImageDraw.Draw(forma).polygon(pts, fill=255)
    a = np.asarray(forma).astype(np.float32) / 255
    # miolo semitransparente + borda forte + brilho (glow) por fora
    dentro = np.asarray(forma.filter(ImageFilter.MinFilter(13))).astype(np.float32) / 255
    borda = np.clip(a - dentro, 0, 1)
    glow = np.asarray(Image.fromarray((borda * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(10))).astype(np.float32) / 255
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    reflexo = np.clip(1 - np.abs((x + y) / n - 0.75) / 0.12, 0, 1) * dentro * 0.25
    alfa = np.clip(dentro * 0.38 + borda + glow * 1.3 + reflexo, 0, 1)
    rgba = np.zeros((n, n, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = (alfa * 255).astype(np.uint8)
    Image.fromarray(rgba, 'RGBA').resize((N, N), Image.LANCZOS).save(OUT + f'peca{i + 1}.png')
    print('ok peca', i + 1)

folha = Image.new('RGBA', (6 * 130, 130), (20, 30, 55, 255))
for i in range(6):
    folha.alpha_composite(Image.open(OUT + f'peca{i + 1}.png').resize((120, 120)), (i * 130 + 5, 5))
folha.save('C:/Users/fidamaa/AppData/Local/Temp/claude/C--Users-fidamaa-Downloads-Game/27a9423c-473b-4d76-bcef-c66cd66cfd31/scratchpad/fx_pecas.png')
