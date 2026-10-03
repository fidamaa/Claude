"""Texturas do Flow do Isagi v120 (referência: vídeo 'O Gênio da Adaptabilidade'
9,1-9,4s = íris de quebra-cabeça; 20,6s = máscara de quebra-cabeça em volta do olho;
YouTube mVkclcc3z-c 0-3s = cabeça se desfazendo em peças ESCURAS sólidas)."""
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = 'C:/Users/fidamaa/AppData/Local/Temp/claude/C--Users-fidamaa-Downloads-Game/27a9423c-473b-4d76-bcef-c66cd66cfd31/scratchpad/img4/up/fx/'
FOLHA = 'C:/Users/fidamaa/AppData/Local/Temp/claude/C--Users-fidamaa-Downloads-Game/27a9423c-473b-4d76-bcef-c66cd66cfd31/scratchpad/fx_isagi_v120.png'


def encaixe(p0, p1, tipo, n=48, alt=0.22):
    """pontos de um lado com pino (tipo +1/-1) no meio — curva de quebra-cabeça"""
    (x0, y0), (x1, y1) = p0, p1
    dx, dy = x1 - x0, y1 - y0
    L = math.hypot(dx, dy) or 1
    nx, ny = -dy / L, dx / L
    pts = []
    for s in range(n + 1):
        u = s / n
        off = 0
        if tipo and 0.3 < u < 0.7:
            k = (u - 0.3) / 0.4
            # pescoço estreito e cabeça redonda
            off = tipo * L * alt * (math.sin(k * math.pi) ** 0.6)
        pts.append((x0 + dx * u + nx * off, y0 + dy * u + ny * off))
    return pts


def encaixe2(p0, p1, tipo):
    """lado de peça com pino de verdade: pescoço estreito + cabeça redonda (com
    a 'barriga' passando por cima do pescoço, como peça real)"""
    (x0, y0), (x1, y1) = p0, p1
    dx, dy = x1 - x0, y1 - y0
    L = math.hypot(dx, dy) or 1
    ux, uy = dx / L, dy / L
    nx, ny = -uy, ux
    def P(u, v):
        return (x0 + ux * u * L + nx * v * L * tipo, y0 + uy * u * L + ny * v * L * tipo)
    if not tipo:
        return [P(0, 0), P(1, 0)]
    r = 0.12
    cy = 0.13 + r * 0.75
    pts = [P(0, 0), P(0.4, 0), P(0.42, 0.06), P(0.415, 0.12)]
    a0 = math.atan2(0.12 - cy, 0.415 - 0.5)
    a1 = math.atan2(0.12 - cy, 0.585 - 0.5)
    # arco por cima, de a0 (esquerda) até a1 (direita), passando pelo topo
    if a1 < a0:
        a1 += 2 * math.pi
    passos = 30
    for k in range(passos + 1):
        a = a0 - (2 * math.pi - (a1 - a0)) * k / passos
        pts.append(P(0.5 + math.cos(a) * r, cy + math.sin(a) * r))
    pts += [P(0.585, 0.12), P(0.58, 0.06), P(0.6, 0), P(1, 0)]
    return pts


def brilhar(a, raio, forca):
    g = np.asarray(Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(raio))).astype(np.float32) / 255
    return np.clip(a + g * forca, 0, 1)


# ---------- 1. ÍRIS DE QUEBRA-CABEÇA (colorida de propósito) ----------
def iris():
    N, S = 512, 2
    n = N * S
    c = n / 2
    linhas = Image.new('L', (n, n), 0)
    d = ImageDraw.Draw(linhas)
    R = n * 0.36
    aneis = [R * 0.3, R * 0.55, R * 0.78, R]
    w = int(n * 0.012)
    # anéis: arcos com encaixe em cada setor
    setores = 8
    for ri, r in enumerate(aneis):
        for s in range(setores):
            a0 = (s / setores) * 2 * math.pi + ri * 0.2
            a1 = ((s + 1) / setores) * 2 * math.pi + ri * 0.2
            pts = []
            for k in range(41):
                u = k / 40
                a = a0 + (a1 - a0) * u
                off = 0
                if ri < 3 and 0.35 < u < 0.65:
                    off = ((-1) ** (s + ri)) * r * 0.09 * math.sin((u - 0.35) / 0.3 * math.pi) ** 0.6
                pts.append((c + math.cos(a) * (r + off), c + math.sin(a) * (r + off)))
            d.line(pts, fill=255, width=w, joint='curve')
    # raios: do anel interno até a borda, com encaixe em cada faixa
    for s in range(setores):
        a = (s / setores) * 2 * math.pi + 0.1
        for ri in range(len(aneis) - 1):
            p0 = (c + math.cos(a) * aneis[ri], c + math.sin(a) * aneis[ri])
            p1 = (c + math.cos(a) * aneis[ri + 1], c + math.sin(a) * aneis[ri + 1])
            d.line(encaixe(p0, p1, (-1) ** (s + ri), alt=0.28), fill=255, width=w, joint='curve')
    L = np.asarray(linhas).astype(np.float32) / 255
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    dist = np.hypot(x - c, y - c)
    disco = np.clip((R * 1.04 - dist) / (n * 0.01), 0, 1)
    # riscos escuros radiais dentro (o "traço" do anime)
    ang = np.arctan2(y - c, x - c)
    riscos = 0.5 + 0.5 * np.sin(ang * 90 + np.sin(dist * 0.05) * 2)
    escuro = disco * (0.75 + 0.25 * riscos)
    centro = np.clip((R * 0.34 - dist) / (R * 0.12), 0, 1)  # miolo BRANCO grande (a câmera entra nele)
    luz = brilhar(L * disco, 6 * S, 1.2)
    # esclera branca brilhante em volta (o olho aceso)
    esclera = np.clip(1 - np.abs(dist - R * 1.12) / (R * 0.12), 0, 1)
    rgb = np.zeros((n, n, 3), np.float32)
    base = np.array([18, 24, 42], np.float32)
    for k in range(3):
        rgb[..., k] = base[k] * escuro + 255 * np.clip(luz + centro + esclera, 0, 1) * (1 - 0.1 * (k == 0))
    rgb = np.clip(rgb, 0, 255)
    alfa = np.clip(np.maximum(disco, brilhar(esclera, 10 * S, 1.0)), 0, 1)
    img = np.dstack([rgb, alfa * 255]).astype(np.uint8)
    Image.fromarray(img, 'RGBA').resize((N, N), Image.LANCZOS).save(OUT + 'olho_qc.png')


# ---------- 2. MÁSCARA DE QUEBRA-CABEÇA EM VOLTA DO OLHO (branca, tingível) ----------
def mascara():
    N, S = 512, 2
    n = N * S
    c = n / 2
    def amendoa(esc):
        pts = []
        for k in range(181):
            a = k / 180 * 2 * math.pi
            x = math.cos(a) * n * 0.42 * esc
            y = math.sin(a) * n * 0.2 * esc * (1.0 if math.sin(a) > 0 else 1.15)
            pts.append((c + x, c + y + n * 0.02))
        return pts
    fora = Image.new('L', (n, n), 0)
    ImageDraw.Draw(fora).polygon(amendoa(1.18), fill=255)
    dentro = Image.new('L', (n, n), 0)
    ImageDraw.Draw(dentro).polygon(amendoa(0.86), fill=255)
    faixa = np.clip(np.asarray(fora).astype(np.float32) - np.asarray(dentro).astype(np.float32), 0, 255) / 255
    # grade de peças (linhas com encaixe)
    grade = Image.new('L', (n, n), 0)
    d = ImageDraw.Draw(grade)
    passo = n / 11
    w = int(n * 0.008)
    for i in range(12):
        for j in range(11):
            p0, p1 = (i * passo, j * passo), (i * passo, (j + 1) * passo)
            d.line(encaixe(p0, p1, (-1) ** (i + j)), fill=255, width=w, joint='curve')
            p0, p1 = (j * passo, i * passo), ((j + 1) * passo, i * passo)
            d.line(encaixe(p0, p1, (-1) ** (i * 3 + j)), fill=255, width=w, joint='curve')
    G = np.asarray(grade).astype(np.float32) / 255
    contorno = Image.new('L', (n, n), 0)
    dc = ImageDraw.Draw(contorno)
    dc.line(amendoa(0.86) + [amendoa(0.86)[0]], fill=255, width=int(n * 0.016), joint='curve')
    dc.line(amendoa(1.18) + [amendoa(1.18)[0]], fill=255, width=int(n * 0.008), joint='curve')
    C = np.asarray(contorno).astype(np.float32) / 255
    # íris clarinha com 4 linhas de peça (fica dentro do olho)
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    dist = np.hypot(x - c, y - c - n * 0.02)
    irisAnel = np.clip(1 - np.abs(dist - n * 0.13) / (n * 0.006), 0, 1)
    a = np.clip(G * faixa + C + irisAnel * 0.8, 0, 1)
    a = brilhar(a, 5 * S, 0.9)
    rgba = np.zeros((n, n, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = (a * 255).astype(np.uint8)
    Image.fromarray(rgba, 'RGBA').resize((N, N), Image.LANCZOS).save(OUT + 'mascara_qc.png')


# ---------- 3. VINHETA (visão fechando): branca, miolo transparente ----------
def vinheta():
    N = 512
    y, x = np.mgrid[0:N, 0:N].astype(np.float32)
    dist = np.hypot(x - N / 2, y - N / 2) / (N / 2)
    a = np.clip((dist - 0.42) / 0.5, 0, 1) ** 1.3
    rgba = np.zeros((N, N, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = (a * 255).astype(np.uint8)
    Image.fromarray(rgba, 'RGBA').save(OUT + 'vinheta.png')


# ---------- 4. PEÇAS SÓLIDAS (a cabeça se desfazendo): miolo cinza, borda branca ----------
def pecas_solidas():
    N, S = 256, 2
    n = N * S
    tipos = [(1, -1, 1, -1), (-1, 1, 1, 1), (1, 1, -1, 0)]
    for i, tt in enumerate(tipos):
        m = n * 0.22
        cs = [(m, m), (n - m, m), (n - m, n - m), (m, n - m)]
        pts = []
        for k in range(4):
            # (encaixe() põe o pino pra um lado fixo; o sinal escolhe fora/dentro)
            pts += encaixe2(cs[k], cs[(k + 1) % 4], -tt[k])
        forma = Image.new('L', (n, n), 0)
        ImageDraw.Draw(forma).polygon(pts, fill=255)
        a = np.asarray(forma).astype(np.float32) / 255
        miolo = np.asarray(forma.filter(ImageFilter.MinFilter(9))).astype(np.float32) / 255
        borda = np.clip(a - miolo, 0, 1)
        rgba = np.zeros((n, n, 4), np.float32)
        v = 150 + 105 * borda
        rgba[..., 0] = v
        rgba[..., 1] = v
        rgba[..., 2] = v
        rgba[..., 3] = a * 255
        Image.fromarray(rgba.astype(np.uint8), 'RGBA').resize((N, N), Image.LANCZOS).save(OUT + f'peca_solida{i + 1}.png')


iris()
mascara()
vinheta()
pecas_solidas()

# folha de conferência: fundo escuro e fundo branco
nomes = ['olho_qc', 'mascara_qc', 'vinheta', 'peca_solida1', 'peca_solida2', 'peca_solida3']
folha = Image.new('RGBA', (6 * 260, 520), (0, 0, 0, 255))
for k, nome in enumerate(nomes):
    im = Image.open(OUT + nome + '.png').convert('RGBA').resize((256, 256))
    escuro = Image.new('RGBA', (256, 256), (25, 30, 50, 255))
    claro = Image.new('RGBA', (256, 256), (235, 240, 250, 255))
    if nome.startswith('peca'):
        # tingida escura, como no jogo
        arr = np.asarray(im).astype(np.float32)
        arr[..., :3] *= np.array([30, 36, 55]) / 255
        im = Image.fromarray(arr.astype(np.uint8), 'RGBA')
    folha.paste(Image.alpha_composite(escuro, im), (k * 260, 0))
    folha.paste(Image.alpha_composite(claro, im), (k * 260, 260))
folha.save(FOLHA)
print('ok')
