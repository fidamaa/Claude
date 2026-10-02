import numpy as np
from PIL import Image, ImageDraw, ImageFilter
import math

OUT = 'C:/Users/fidamaa/AppData/Local/Temp/claude/C--Users-fidamaa-Downloads-Game/27a9423c-473b-4d76-bcef-c66cd66cfd31/scratchpad/img4/up/fx/'
W, H = 512, 400
S = 2  # supersample
w, h = W * S, H * S

# silhueta da coroa: base + 5 pontas (a do meio mais alta), com curvas entre elas
def silhueta():
    pts = []
    base_y, topo_base = h * 0.86, h * 0.56
    xs = [0.08, 0.27, 0.5, 0.73, 0.92]
    alturas = [0.24, 0.12, 0.04, 0.12, 0.24]
    pts.append((w * 0.06, base_y))
    pts.append((w * 0.06, topo_base))
    for i, fx in enumerate(xs):
        px, py = w * fx, h * alturas[i]
        # vale antes da ponta
        if i > 0:
            vx = w * (xs[i - 1] + fx) / 2
            for s in range(8):
                u = s / 7
                pts.append((w * xs[i - 1] + (vx - w * xs[i - 1]) * u, h * alturas[i - 1] + (topo_base - h * alturas[i - 1]) * math.sin(u * math.pi / 2)))
            for s in range(8):
                u = s / 7
                pts.append((vx + (px - vx) * u, topo_base + (py - topo_base) * (1 - math.cos(u * math.pi / 2))))
        else:
            pts.append((px, py))
    pts.append((w * 0.94, topo_base))
    pts.append((w * 0.94, base_y))
    return pts

forma = Image.new('L', (w, h), 0)
ImageDraw.Draw(forma).polygon(silhueta(), fill=255)
mask = np.asarray(forma).astype(np.float32) / 255

# ouro com sombreado vertical + brilho diagonal
y, x = np.mgrid[0:h, 0:w].astype(np.float32)
v = y / h
ouro = np.zeros((h, w, 3), np.float32)
ouro[..., 0] = 255 * (0.95 - 0.25 * v)
ouro[..., 1] = 215 * (0.98 - 0.35 * v)
ouro[..., 2] = 70 * (1.0 - 0.5 * v)
brilho = np.clip(1 - np.abs((x / w - 0.35) + (y / h - 0.3) * 0.6) / 0.08, 0, 1) * 0.6
ouro = np.clip(ouro + brilho[..., None] * 255, 0, 255)

img = np.zeros((h, w, 4), np.float32)
img[..., :3] = ouro
img[..., 3] = mask * 255

pil = Image.fromarray(img.astype(np.uint8), 'RGBA')
d = ImageDraw.Draw(pil)
# faixa da base (mais escura) com joias
d.rectangle([w * 0.06, h * 0.7, w * 0.94, h * 0.86], fill=(205, 145, 30, 255))
d.line([(w * 0.06, h * 0.7), (w * 0.94, h * 0.7)], fill=(255, 240, 170, 255), width=6 * S)
d.line([(w * 0.06, h * 0.86), (w * 0.94, h * 0.86)], fill=(140, 90, 15, 255), width=5 * S)
for fx in (0.2, 0.5, 0.8):
    cx, cy, r = w * fx, h * 0.78, h * 0.055
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(150, 60, 230, 255), outline=(255, 235, 160, 255), width=3 * S)
    d.ellipse([cx - r * 0.45, cy - r * 0.6, cx - r * 0.05, cy - r * 0.2], fill=(235, 210, 255, 255))
for fx in (0.35, 0.65):
    cx, cy, r = w * fx, h * 0.78, h * 0.035
    d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=(120, 200, 255, 255))
# joias nas pontas
for fx, fy in ((0.08, 0.24), (0.27, 0.12), (0.5, 0.04), (0.73, 0.12), (0.92, 0.24)):
    cx, cy, r = w * fx, h * fy, h * (0.06 if fx == 0.5 else 0.045)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 245, 210, 255), outline=(170, 110, 20, 255), width=3 * S)
# joia grande no meio
cx, cy, r = w * 0.5, h * 0.47, h * 0.09
d.polygon([(cx, cy - r * 1.3), (cx + r, cy), (cx, cy + r * 1.3), (cx - r, cy)], fill=(160, 70, 240, 255), outline=(255, 235, 160, 255))
d.polygon([(cx, cy - r * 1.3), (cx + r * 0.35, cy), (cx, cy + r * 0.2), (cx - r * 0.35, cy)], fill=(215, 170, 255, 255))
# contorno escuro
borda = Image.fromarray((mask * 255).astype(np.uint8), 'L').filter(ImageFilter.MaxFilter(9))
borda_a = (np.asarray(borda).astype(np.float32) / 255) * (1 - mask)
arr = np.asarray(pil).astype(np.float32)
arr[..., :3] = arr[..., :3] * (1 - borda_a[..., None]) + np.array([90, 45, 10]) * borda_a[..., None]
arr[..., 3] = np.maximum(arr[..., 3], borda_a * 255)
pil = Image.fromarray(arr.astype(np.uint8), 'RGBA').resize((W, H), Image.LANCZOS)
pil.save(OUT + 'coroa.png')
prev = Image.new('RGBA', (W, H), (25, 20, 40, 255))
prev.alpha_composite(pil)
prev.save('C:/Users/fidamaa/AppData/Local/Temp/claude/C--Users-fidamaa-Downloads-Game/27a9423c-473b-4d76-bcef-c66cd66cfd31/scratchpad/fx_coroa.png')
print('ok')
