"""Base v4: momentos clave a x1, rampas largas, mezcla de fotogramas y vuelta interpolada a 120 fps.

Uso: venv/python build_base3.py <video_origen> <carpeta_trabajo>
"""
import json, math, os, re, subprocess, sys
import numpy as np

SRC, WORK = sys.argv[1], sys.argv[2]
FPS = 30
CW, CH, CX, CY = 1304, 734, 298, 226
SIM_RATE = 4.6
FRAME = CW * CH * 3
RAMP = 1.5                      # s de video final por cambio de velocidad

INTRO_FRAME, INTRO_DUR = 1.95, 2.5
ORBIT_A, ORBIT_B, ORBIT_DUR = 1.95, 18.6, 8.0
PLAN = [
    (18.6, 20.3, 1, "two_products"),
    (20.3, 23.8, 1, "block"),
    (23.8, 36.4, 8, "fill1"),
    (36.4, 39.4, 1, "euro_full"),
    (39.4, 45.2, 8, "fill2"),
    (45.2, 48.0, 1, "euro_swap"),
    (48.0, 138.8, 20, "fill_half1"),
    (138.8, 142.2, 1, "liner"),
    (142.2, 197.6, 20, "fill_half2"),
    (197.6, 199.6, 1, "half_full"),
    (199.6, 215.45, 8, "both_full"),
    (215.45, 218.6, 1, "new_pallet"),
    (218.6, 224.0, 1, "back"),
    (224.0, 229.0, 1, "end"),
]

# ---------- 1. Vuelta: clip interpolado a 120 fps y mapa a velocidad visual constante ----------
ORB = os.path.join(WORK, "orbit120.mp4")
if not os.path.exists(ORB):
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{ORBIT_A:.3f}", "-i", SRC, "-t", f"{ORBIT_B - ORBIT_A:.3f}",
                    "-vf", f"crop={CW}:{CH}:{CX}:{CY},minterpolate=fps=120:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1:scd=none",
                    "-an", "-c:v", "libx264", "-crf", "12", "-preset", "fast", ORB], check=True)
OM = os.path.join(WORK, "orbit120_motion.txt")
if not os.path.exists(OM):
    subprocess.run(["ffmpeg", "-v", "error", "-i", ORB, "-vf",
                    "scale=320:-2,format=gray,tblend=all_mode=difference,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=orbit120_motion.txt",
                    "-f", "null", "-"], check=True, cwd=WORK)
om = np.array([float(x) for x in re.findall(r"YAVG=([\d.]+)", open(OM).read())])
om = np.concatenate([[om[0]], om])
k = 9; om_s = np.convolve(np.pad(om, k // 2, mode="edge"), np.ones(k) / k, mode="valid")   # ~0,5 s
cum = np.cumsum(om_s + 0.02); cum = (cum - cum[0]) / (cum[-1] - cum[0])
n_orb = int(round(ORBIT_DUR * FPS))
u = np.linspace(0, 1, n_orb)
e = 0.18
vel = np.ones(n_orb)
r = u < e;      vel[r] = 0.5 - 0.5 * np.cos(np.pi * u[r] / e)
r = u > 1 - e;  vel[r] = 0.5 - 0.5 * np.cos(np.pi * (1 - u[r]) / e)
prog = np.cumsum(vel); prog = (prog - prog[0]) / (prog[-1] - prog[0])
orbit_pos = np.interp(prog, cum, np.arange(len(cum)))           # posicion fraccional en el clip de 120 fps

# ---------- 2. Rampas en tiempo de video ----------
def ramp(v1, v2):
    n = int(round(RAMP * FPS))
    x = (np.arange(n) + 0.5) / n
    x = x * x * (3 - 2 * x)
    v = np.exp(np.log(v1) + (np.log(v2) - np.log(v1)) * x)
    return np.concatenate([[0], np.cumsum(v / FPS)]), v

_m = np.array([float(x) for x in re.findall(r"YAVG=([\d.]+)", open(os.path.join(WORK, "src_motion.txt")).read())])
_still = np.convolve((_m < 0.03).astype(float), np.ones(15) / 15, mode="same")
def still_at(t):
    return float(_still[min(max(int(t * FPS), 0), len(_still) - 1)])

# tramos rapidos demasiado cortos para dos rampas: bajar su velocidad hasta que quepan
def need(i, v):
    a0, b0 = PLAN[i][0], PLAN[i][1]
    tot = 0.0
    if i > 0 and PLAN[i - 1][2] < v: tot += ramp(PLAN[i - 1][2], v)[0][-1]
    if i + 1 < len(PLAN) and PLAN[i + 1][2] < v: tot += ramp(v, PLAN[i + 1][2])[0][-1]
    return tot <= (b0 - a0) * 0.9
for i in range(len(PLAN)):
    a0, b0, v0, sid = PLAN[i]
    while v0 > 1.05 and not need(i, v0):
        v0 *= 0.95
    if v0 != PLAN[i][2]:
        print("velocidad de", sid, "bajada a", round(v0, 2))
        PLAN[i] = (a0, b0, v0, sid)
pieces = []
for i, (a0, b0, v0, sid) in enumerate(PLAN):
    s0, s1 = a0, b0
    if i > 0 and PLAN[i - 1][2] < v0:
        off, _ = ramp(PLAN[i - 1][2], v0); pieces.append(("ramp", a0, (PLAN[i - 1][2], v0), sid)); s0 = a0 + off[-1]
    tail = None
    if i + 1 < len(PLAN) and PLAN[i + 1][2] < v0:
        off, _ = ramp(v0, PLAN[i + 1][2]); tail = ("ramp", b0 - off[-1], (v0, PLAN[i + 1][2]), sid); s1 = b0 - off[-1]
    assert s1 >= s0 - 1e-6, (sid, s0, s1)
    pieces.append(("const", (s0, s1), v0, sid))
    if tail: pieces.append(tail)

# ---------- 3. Lista de salida: (fuente, tiempo, velocidad) ----------
out = []                      # ("main", t_src, v) | ("orbit", pos120, None)
scenes = [{"id": "intro", "from": 0}]
out += [("orbit", 0.0, None)] * int(round(INTRO_DUR * FPS))
scenes.append({"id": "orbit", "from": len(out)})
out += [("orbit", float(p), None) for p in orbit_pos]
cur = None
for pc in pieces:
    sid = pc[-1]
    if sid != cur:
        scenes.append({"id": sid, "from": len(out)}); cur = sid
    if pc[0] == "const":
        (s0, s1), v = pc[1], pc[2]
        t = s0
        while t < s1 - 1e-9:
            boost = 1.0 + (5.0 if v < 2 else 1.5) * still_at(t)
            out.append(("main", t, v * boost)); t += v * boost / FPS
    else:
        s0, (v1, v2) = pc[1], pc[2]
        off, vv = ramp(v1, v2)
        s_end = s0 + off[-1]
        t = s0
        for j in range(len(vv)):
            if t >= s_end - 1e-9: break
            vj = float(vv[j])
            boost = 1.0 + (5.0 if vj < 2 else 1.5) * still_at(t)
            out.append(("main", t, vj)); t += vj * boost / FPS
for i, sc in enumerate(scenes):
    sc["to"] = scenes[i + 1]["from"] if i + 1 < len(scenes) else len(out)
nominal = [None if o[0] != "main" or o[2] == 0 else
           min((1, 5, 8, 20), key=lambda c: abs(math.log(c) - math.log(max(o[2], 1e-3)))) * SIM_RATE for o in out]
for i in range(int(round(INTRO_DUR * FPS))): nominal[i] = None
print("fotogramas", len(out), "=", round(len(out) / FPS, 1), "s")

# ---------- 4. Marcadores ----------
exec(open(os.path.join(os.path.dirname(__file__), "_markers.py"), encoding="utf-8").read())

# ---------- 5. Lectores con cache ----------
def reader(path, vf=None):
    cmd = ["ffmpeg", "-v", "error", "-i", path] + (["-vf", vf] if vf else []) + ["-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
    return subprocess.Popen(cmd, stdout=subprocess.PIPE, bufsize=FRAME * 4)

class Cache:
    def __init__(self, path, vf, patch_src=None):
        self.p, self.idx, self.buf, self.patch_src = reader(path, vf), -1, {}, patch_src
    def frame(self, i):
        while self.idx < i:
            b = self.p.stdout.read(FRAME)
            if len(b) < FRAME: break
            self.idx += 1
            if self.idx < i - 10:          # fotogramas que se saltan: no guardarlos
                continue
            img = np.frombuffer(b, np.uint8).reshape(CH, CW, 3)
            if self.patch_src: img = self.patch_src(img, self.idx)
            self.buf[self.idx] = img.astype(np.float32)
        j = min(i, self.idx)
        return self.buf[j] if j in self.buf else self.buf[max(self.buf)]
    def drop_before(self, i):
        for k in [k for k in self.buf if k < i]: del self.buf[k]
    def at(self, x):                       # posicion fraccional -> mezcla lineal de vecinos
        i0 = int(math.floor(x)); w = x - i0
        a = self.frame(i0)
        if w < 1e-3: return a
        return a * (1 - w) + self.frame(i0 + 1) * w

main = Cache(SRC, f"crop={CW}:{CH}:{CX}:{CY}", lambda img, i: patch(img, i))
orbc = Cache(ORB, None)
writer = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{CW}x{CH}",
                           "-r", str(FPS), "-i", "-", "-vf", "scale=1920:1080:flags=lanczos,format=yuv420p",
                           "-c:v", "libx264", "-crf", "15", "-preset", "medium", "-movflags", "+faststart",
                           os.path.join(WORK, "base.mp4")], stdin=subprocess.PIPE)
for n, (src, x, v) in enumerate(out):
    if src == "orbit":
        img = orbc.at(x); orbc.drop_before(int(x) - 2)
    else:
        f = x * FPS
        if v is None or v < 1.5:
            img = main.at(f)
        else:
            # "obturador" de medio intervalo: media de las posiciones que cubre este fotograma
            span = min(0.5 * v, 6.0)
            kk = max(2, int(math.ceil(span)) + 1)
            img = sum(main.at(f - span / 2 + span * j / (kk - 1)) for j in range(kk)) / kk
        main.drop_before(int(f - 8))
    writer.stdin.write(np.clip(img + 0.5, 0, 255).astype(np.uint8).tobytes())
writer.stdin.close(); writer.wait()
main.p.kill(); orbc.p.kill()
json.dump({"fps": FPS, "frames": len(out), "scenes": scenes, "nominal": nominal}, open(os.path.join(WORK, "timeline.json"), "w"))
print("ok")
