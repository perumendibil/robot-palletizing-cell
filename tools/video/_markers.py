# --- 4. Tapar el marcador (solo con la cámara fija, tras la vuelta) ---
# Placa limpia: un fotograma de referencia (41 s, robot lejos) con el marcador sustituido por el suelo.
RX0, RX1, RY0, RY1 = 598, 636, 154, 192            # zona de trabajo (coords del recorte)
STATIC_FROM = int(18.6 * FPS)
def _grab(t):
    b = subprocess.run(["ffmpeg", "-v", "error", "-ss", str(t), "-i", SRC, "-frames:v", "1", "-vf",
                        f"crop={CW}:{CH}:{CX}:{CY}", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], capture_output=True).stdout
    return np.frombuffer(b, np.uint8).reshape(CH, CW, 3)
_ref = _grab(41.0)[RY0:RY1, RX0:RX1].astype(np.int16)
_floor = np.array([230, 226, 235], np.int16)
_mm = np.zeros(_ref.shape[:2], bool)
_mm[164 - RY0:181 - RY0, 608 - RX0:625 - RX0] = np.abs(_ref[164 - RY0:181 - RY0, 608 - RX0:625 - RX0] - _floor).sum(2) > 8
_d = _mm.copy()                                     # dilatar 1 px
_d[1:] |= _mm[:-1]; _d[:-1] |= _mm[1:]; _d[:, 1:] |= _mm[:, :-1]; _d[:, :-1] |= _mm[:, 1:]
MARK = _d
CLEAN = _ref.copy(); CLEAN[MARK] = _floor
CHECK = ~MARK
patched = skipped = 0
AX_MASK = np.load(os.path.join(WORK, "axes_mask.npy"))      # ejes de SC_Conveyor2 sobre la base del robot
AX0, AX1, AY0, AY1 = 540, 660, 380, 510
AX_FROM = int(102.9 * FPS)
def _dil(m, n):
    m = m.copy()
    for _ in range(n):
        d = m.copy(); d[1:] |= m[:-1]; d[:-1] |= m[1:]; d[:, 1:] |= m[:, :-1]; d[:, :-1] |= m[:, 1:]; m = d
    return m
AX_WIDE = _dil(AX_MASK, 3)
AX_NEAR_RED = _dil(AX_MASK, 1)
AX_MASK = _dil(AX_MASK, 1)

def inpaint(img, x0, x1, y0, y1, mask):
    """Rellena los pixeles de la mascara con el color de sus vecinos (difusion)."""
    reg = img[y0:y1, x0:x1].astype(np.float32)
    known = ~mask
    reg[mask] = 0
    for _ in range(60):
        acc = np.zeros_like(reg); cnt = np.zeros(reg.shape[:2], np.float32)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)):
            sh = np.roll(np.roll(reg, dy, 0), dx, 1); kn = np.roll(np.roll(known, dy, 0), dx, 1)
            acc += sh * kn[..., None]; cnt += kn
        fill = (~known) & (cnt > 0)
        if not fill.any(): break
        reg[fill] = acc[fill] / cnt[fill][:, None]
        known = known | fill
    for _ in range(6):
        sm = (np.roll(reg, 1, 0) + np.roll(reg, -1, 0) + np.roll(reg, 1, 1) + np.roll(reg, -1, 1)) / 4
        reg[mask] = sm[mask]
    img[y0:y1, x0:x1] = reg.clip(0, 255).astype(np.uint8)

def patch(img, src_frame):
    global patched
    if src_frame < STATIC_FROM:
        return img
    out = img.copy()
    inpaint(out, RX0, RX1, RY0, RY1, MARK)
    if src_frame >= AX_FROM:
        reg = out[AY0:AY1, AX0:AX1].astype(np.int16)
        r, g, b = reg[..., 0], reg[..., 1], reg[..., 2]
        colored = ((g - np.maximum(r, b)) > 35) | ((b - np.maximum(r, g)) > 35) | (((r - np.maximum(g, b)) > 60) & AX_NEAR_RED)
        inpaint(out, AX0, AX1, AY0, AY1, AX_MASK | (AX_WIDE & colored))
    patched += 1
    return out

