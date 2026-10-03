import numpy as np
from PIL import Image, ImageFilter

OUT = 'C:/Users/fidamaa/AppData/Local/Temp/claude/C--Users-fidamaa-Downloads-Game/27a9423c-473b-4d76-bcef-c66cd66cfd31/scratchpad/img4/up/fx/'
N = 512
rng = np.random.default_rng(5)
y, x = np.mgrid[0:N, 0:N].astype(np.float32)
x, y = (x - N / 2) / (N / 2), (y - N / 2) / (N / 2)

# campo suave (soma de ondas) -> curvas de nÃ­vel = dobras do cÃ©rebro
campo = np.zeros_like(x)
for _ in range(14):
    f = rng.uniform(2.5, 7)
    ang = rng.uniform(0, np.pi)
    fase = rng.uniform(0, 6.3)
    campo += np.sin((x * np.cos(ang) + y * np.sin(ang)) * f + fase) / 14
campo += 0.15 * np.sin(x * 9) * np.cos(y * 11)
frac = (campo * 18) % 1
linhas = np.clip(1 - np.abs(frac - 0.5) / 0.11, 0, 1)

# dois hemisfÃ©rios (elipses) com a fissura no meio
def hemi(cx):
    return ((x - cx) / 0.44) ** 2 + (y / 0.8) ** 2
mascara = np.zeros_like(x)
contorno = np.zeros_like(x)
for cx in (-0.45, 0.45):
    h = hemi(cx)
    mascara = np.maximum(mascara, (h < 1).astype(np.float32))
    contorno = np.maximum(contorno, np.clip(1 - np.abs(h - 1) / 0.05, 0, 1))
fissura = np.clip(1 - np.abs(x) / 0.012, 0, 1) * (np.abs(y) < 0.78)
alfa = np.clip(linhas * mascara * 0.85 + contorno + fissura, 0, 1)
img = Image.fromarray((alfa * 255).astype(np.uint8), 'L')
halo = np.asarray(img.filter(ImageFilter.GaussianBlur(10))).astype(np.float32) / 255
alfa = np.clip(alfa + halo * 1.5 + mascara * 0.12, 0, 1)
rgba = np.zeros((N, N, 4), np.uint8)
rgba[..., :3] = 255
rgba[..., 3] = (alfa * 255).astype(np.uint8)
Image.fromarray(rgba, 'RGBA').save(OUT + 'cerebro.png')
prev = Image.new('RGBA', (300, 300), (20, 30, 50, 255))
prev.alpha_composite(Image.fromarray(rgba, 'RGBA').resize((300, 300)))
prev.save('C:/Users/fidamaa/AppData/Local/Temp/claude/C--Users-fidamaa-Downloads-Game/27a9423c-473b-4d76-bcef-c66cd66cfd31/scratchpad/fx_cerebro.png')
print('ok')

