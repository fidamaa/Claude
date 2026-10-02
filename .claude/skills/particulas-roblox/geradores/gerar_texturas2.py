import numpy as np
from PIL import Image

OUT = 'C:/Users/fidamaa/AppData/Local/Temp/claude/C--Users-fidamaa-Downloads-Game/27a9423c-473b-4d76-bcef-c66cd66cfd31/scratchpad/img4/up/fx/'
N = 256
y, x = np.mgrid[0:N, 0:N].astype(np.float32)
c = (N - 1) / 2
x, y = (x - c) / c, (y - c) / c
r = np.sqrt(x * x + y * y)


def salvar(nome, a):
    a = np.clip(a, 0, 1)
    img = np.zeros((N, N, 4), np.uint8)
    img[..., :3] = 255
    img[..., 3] = (a * 255).astype(np.uint8)
    Image.fromarray(img, 'RGBA').save(OUT + nome + '.png')
    print('ok', nome)


# brilho mais cheio: miolo forte + halo largo que vai até a borda
salvar('brilho2', np.clip(1 - r, 0, 1) ** 1.2 * 0.75 + np.clip(1 - r / 0.35, 0, 1) ** 1.5 * 0.5)

# estrela de 4 pontas ocupando o quadro todo
ax, ay = np.abs(x) + 1e-4, np.abs(y) + 1e-4
raios = np.clip(1 - (ax * ay) ** 0.5 * 6, 0, 1) * np.clip(1 - r, 0, 1) ** 0.8
miolo = np.clip(1 - r / 0.32, 0, 1) ** 1.6
salvar('estrela4b', raios * 0.9 + miolo)
