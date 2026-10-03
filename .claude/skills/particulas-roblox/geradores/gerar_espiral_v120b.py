"""Espiral de pinceladas pro Flow do Isagi (vídeo 10,9-12,0s: pinceladas escuras
entram pelas bordas girando e fecham a visão até ficar tudo escuro com a espiral).
espiral_borda.png = só o anel de fora (miolo vazado): encolhendo, ela FECHA a visão.
espiral_cheia.png = a espiral inteira, do centro à borda (o estado fechado).
Branco no RGB, forma no alfa (tinge no ImageColor3)."""
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = 'C:/Users/fidamaa/AppData/Local/Temp/claude/C--Users-fidamaa-Downloads-Game/27a9423c-473b-4d76-bcef-c66cd66cfd31/scratchpad/img4/up/fx/'
FOLHA = 'C:/Users/fidamaa/AppData/Local/Temp/claude/C--Users-fidamaa-Downloads-Game/27a9423c-473b-4d76-bcef-c66cd66cfd31/scratchpad/fx_espiral.png'
N = 1024
rng = np.random.default_rng(11)


def pinceladas(rmin, rmax, n, seed):
    r_ = np.random.default_rng(seed)
    S = 2
    n2 = N * S
    c = n2 / 2
    img = Image.new('L', (n2, n2), 0)
    d = ImageDraw.Draw(img)
    for _ in range(n):
        # espiral logarítmica: r = r0 * e^(k*theta), girando pra dentro
        a0 = r_.uniform(0, 2 * math.pi)
        r0 = r_.uniform(rmin, rmax) * n2 / 2
        k = r_.uniform(0.10, 0.18)
        comprimento = r_.uniform(1.2, 3.2)  # radianos
        larg = r_.uniform(0.004, 0.02) * n2
        brilho = int(r_.uniform(140, 255))
        pts = []
        passos = 60
        for i in range(passos + 1):
            u = i / passos
            th = a0 + u * comprimento
            r = r0 * math.exp(-k * u * comprimento)
            if r < rmin * n2 / 2 * 0.92:
                break
            pts.append((c + math.cos(th) * r, c + math.sin(th) * r))
        if len(pts) < 3:
            continue
        # pincelada afinando nas pontas
        for i in range(len(pts) - 1):
            u = i / (len(pts) - 1)
            w = max(1, int(larg * math.sin(math.pi * min(1, u * 1.1 + 0.05))))
            d.line([pts[i], pts[i + 1]], fill=brilho, width=w)
    img = img.filter(ImageFilter.GaussianBlur(S * 1.2))
    return np.asarray(img.resize((N, N), Image.LANCZOS)).astype(np.float32) / 255


y, x = np.mgrid[0:N, 0:N].astype(np.float32)
dist = np.hypot(x - N / 2, y - N / 2) / (N / 2)

# BORDA: anel de pinceladas de 0.38 a 1.0 + fundo escuro só fora do anel interno
riscos_b = pinceladas(0.36, 1.05, 900, 3)
fundo_b = np.clip((dist - 0.42) / 0.25, 0, 1) ** 1.2  # escuro cresce pra fora
alfa_b = np.clip(np.maximum(fundo_b * 0.92, riscos_b), 0, 1)
alfa_b *= np.clip((dist - 0.34) / 0.06, 0, 1)  # miolo vazado (pontas das pinceladas)
# RGB: fundo escuro (vai ser tingido), riscos mais claros
rgb_b = np.clip(60 + 195 * riscos_b, 0, 255)

# CHEIA: espiral do centro à borda sobre fundo escuro
riscos_c = pinceladas(0.02, 1.05, 1300, 5)
alfa_c = np.clip(0.94 + riscos_c * 0.06, 0, 1) * np.clip((1.45 - dist) / 0.1, 0, 1)
rgb_c = np.clip(40 + 215 * riscos_c, 0, 255)


def salvar(rgb, alfa, nome):
    a = np.zeros((N, N, 4), np.uint8)
    a[..., 0] = rgb
    a[..., 1] = rgb
    a[..., 2] = rgb
    a[..., 3] = (alfa * 255).astype(np.uint8)
    Image.fromarray(a, 'RGBA').save(OUT + nome)


# MIOLO (⚠️ v120c): a espiral cheia com borda REDONDA e macia — nasce pequena no
# centro e cresce até tapar o buraco da borda (fecha a visão inteira)
alfa_m = np.clip(0.95 + riscos_c * 0.05, 0, 1) * np.clip((0.98 - dist) / 0.14, 0, 1)
salvar(rgb_c, alfa_m, 'espiral_miolo.png')
salvar(rgb_b, alfa_b, 'espiral_borda.png')
salvar(rgb_c, alfa_c, 'espiral_cheia.png')

# folha de conferência (sobre branco, tingido escuro como no jogo)
folha = Image.new('RGBA', (1040, 520), (240, 244, 250, 255))
for k, nome in enumerate(['espiral_borda.png', 'espiral_cheia.png']):
    im = Image.open(OUT + nome).convert('RGBA').resize((512, 512))
    arr = np.asarray(im).astype(np.float32)
    arr[..., :3] *= np.array([70, 80, 100]) / 255
    folha.alpha_composite(Image.fromarray(arr.astype(np.uint8), 'RGBA'), (k * 520, 4))
folha.save(FOLHA)
print('ok')
