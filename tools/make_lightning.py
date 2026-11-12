"""Generate a forking-lightning beam body spritesheet for Factorio.

Each frame is a horizontal beam segment. Frame k of every variation (and of the
head and tail) enters and exits at the same anchor height, so segments always
join up while the whole bolt jumps around from frame to frame. Black background,
meant to be drawn with blend_mode = "additive".
"""
import math
import random
import sys

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

FRAME_W, FRAME_H = 64, 96       # hi-res body frame (1 tile long in-game at scale 0.5)
END_W = 32                      # end pieces are half a tile, so short path segments still fit
VARIATIONS = 6                  # rows: one variation per row
FRAMES_PER_VARIATION = 8        # columns: frame k uses anchor height ANCHORS[k] in every row
ANCHOR_RANGE = 16               # max px the anchor moves up/down from centre
SECOND_STRAND_CHANCE = 0.4     # chance of a faint second strand that splits off and rejoins
EDGE_MARGIN = 14                # keep the main bolt this far from the top/bottom of a frame
SS = 4                          # supersampling factor for the core lines
PAD = 32                        # extra canvas so glow isn't clipped at frame edges
SEED = int(sys.argv[1]) if len(sys.argv) > 1 else 7

CORE = np.array([1.0, 1.0, 1.0])
INNER = np.array([0.55, 0.75, 1.0])
OUTER = np.array([0.25, 0.35, 1.0])


def displace(p0, p1, rough, depth, rng):
    """Midpoint displacement between two points -> list of points."""
    pts = [p0, p1]
    offset = rough
    for _ in range(depth):
        new = [pts[0]]
        for a, b in zip(pts, pts[1:]):
            mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
            dx, dy = b[0] - a[0], b[1] - a[1]
            length = math.hypot(dx, dy) or 1
            nx, ny = -dy / length, dx / length
            d = rng.uniform(-offset, offset)
            new += [(mx + nx * d, my + ny * d), b]
        pts = new
        offset *= 0.55
    return pts


def draw_polyline(canvas, pts, width, intensity):
    """Rasterise a polyline into a float canvas (supersampled coords)."""
    h, w = canvas.shape
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        steps = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for t in np.linspace(0, 1, steps):
            x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            r = width
            xi0, xi1 = int(x - r), int(x + r) + 1
            yi0, yi1 = int(y - r), int(y + r) + 1
            for yy in range(max(yi0, 0), min(yi1, h)):
                for xx in range(max(xi0, 0), min(xi1, w)):
                    if (xx - x) ** 2 + (yy - y) ** 2 <= r * r:
                        canvas[yy, xx] = max(canvas[yy, xx], intensity)


def fork(canvas, start, angle, length, width, intensity, depth, rng):
    end = (start[0] + math.cos(angle) * length, start[1] + math.sin(angle) * length)
    pts = displace(start, end, length * 0.22, 5, rng)
    draw_polyline(canvas, pts, width, intensity)
    if depth > 0:
        for _ in range(rng.randint(0, 2)):
            i = rng.randint(len(pts) // 4, len(pts) - 2)
            a = angle + rng.choice([-1, 1]) * rng.uniform(0.3, 0.9)
            fork(canvas, pts[i], a, length * rng.uniform(0.4, 0.65),
                 max(width * 0.75, SS * 0.4), intensity * 0.8, depth - 1, rng)


def make_frame(rng, anchor, brightness=1.0, pinch=None, width=None):
    """pinch='left'/'right': that edge goes to dead centre (the beam's real endpoint)."""
    W = width or FRAME_W
    cw, ch = (W + 2 * PAD) * SS, (FRAME_H + 2 * PAD) * SS
    core = np.zeros((ch, cw), dtype=np.float32)
    cy = ch / 2 + anchor * SS
    yl = ch / 2 if pinch == "left" else cy
    yr = ch / 2 if pinch == "right" else cy
    x0, x1 = PAD * SS, (PAD + W) * SS

    # Main bolt: fixed at centre line on both frame edges so segments tile.
    lead = 2 * SS
    lo, hi = (PAD + EDGE_MARGIN) * SS, (PAD + FRAME_H - EDGE_MARGIN) * SS

    def bolt():
        pts = displace((x0 + lead, yl), (x1 - lead, yr), W * SS * 0.35, 6, rng)
        # Bounce off the margins instead of clamping (clamping draws flat lines).
        out = []
        for x, y in pts:
            if y < lo:
                y = lo + (lo - y) * 0.5
            elif y > hi:
                y = hi - (y - hi) * 0.5
            out.append((x, y))
        return out

    middle = bolt()
    main = [(0, yl), (x0, yl)] + middle + [(x1, yr), (cw, yr)]
    draw_polyline(core, main, 0.8 * SS, 1.0)

    # Faint second strand: same entry/exit, different path, so the beam splits and rejoins.
    if rng.random() < SECOND_STRAND_CHANCE:
        draw_polyline(core, bolt(), 0.5 * SS, rng.uniform(0.35, 0.6))

    # Forks branching off the main bolt, drawn separately so they can fade
    # out before crossing into the neighbouring segment.
    forks = np.zeros_like(core)
    for _ in range(rng.randint(1, 3) if W >= FRAME_W else rng.randint(0, 1)):
        i = rng.randint(len(middle) // 8, len(middle) - len(middle) // 8)
        sx, sy = middle[i]
        direction = rng.choice([-1, 1])
        angle = direction * rng.uniform(0.35, 1.1) + (0 if rng.random() < 0.7 else math.pi)
        fork(forks, (sx, sy), angle, FRAME_H * SS * rng.uniform(0.25, 0.45),
             0.6 * SS, 0.85, 2, rng)

    xs = np.arange(cw)
    hfade = np.clip(np.minimum(xs - x0, x1 - xs) / (min(12, W / 4) * SS), 0, 1)
    core = np.maximum(core, forks * hfade[None, :])

    # Downsample core, then build glow layers.
    small = core.reshape(ch // SS, SS, cw // SS, SS).mean(axis=(1, 3))
    inner = gaussian_filter(small, 1.5) * 1.6
    outer = gaussian_filter(small, 5.0) * 2.4
    rgb = (small[..., None] * CORE + inner[..., None] * INNER + outer[..., None] * OUTER)
    rgb = np.clip(rgb, 0, 1)[PAD:PAD + FRAME_H, PAD:PAD + W]
    # Fade forks out near the top/bottom so they don't hit a hard frame edge.
    y = np.arange(FRAME_H)
    edge = np.minimum(y, FRAME_H - 1 - y)
    fade = np.clip(edge / 12.0, 0, 1) ** 1.5
    return rgb * fade[:, None, None] * brightness


SPARK_SIZE = 96                 # start/ending spark burst frame (hi-res, scale 0.5)


def make_spark(rng, strength):
    """A flickering burst of short forked rays from the centre."""
    pad = 16
    size = (SPARK_SIZE + 2 * pad) * SS
    c = size / 2
    core = np.zeros((size, size), dtype=np.float32)
    for _ in range(rng.randint(5, 8)):
        angle = rng.uniform(0, 2 * math.pi)
        length = SPARK_SIZE * SS * rng.uniform(0.18, 0.42) * strength
        fork(core, (c, c), angle, length, 0.6 * SS, rng.uniform(0.7, 1.0), 1, rng)
    small = core.reshape(size // SS, SS, size // SS, SS).mean(axis=(1, 3))
    # Hot glowing centre.
    yy, xx = np.mgrid[0:small.shape[0], 0:small.shape[1]]
    r = np.hypot(yy - small.shape[0] / 2, xx - small.shape[1] / 2)
    small = np.maximum(small, np.clip(1 - r / (6 * strength), 0, 1))
    inner = gaussian_filter(small, 1.5) * 1.6
    outer = gaussian_filter(small, 6.0) * 2.6
    rgb = small[..., None] * CORE + inner[..., None] * INNER + outer[..., None] * OUTER
    rgb = np.clip(rgb, 0, 1)[pad:pad + SPARK_SIZE, pad:pad + SPARK_SIZE]
    # Radial fade so nothing touches the frame edge.
    yy, xx = np.mgrid[0:SPARK_SIZE, 0:SPARK_SIZE]
    r = np.hypot(yy - SPARK_SIZE / 2, xx - SPARK_SIZE / 2) / (SPARK_SIZE / 2)
    return rgb * (np.clip((1 - r) / 0.25, 0, 1) ** 1.5)[..., None]


def save_row(frames, w, h, name):
    sheet = np.zeros((h, w * len(frames), 3), dtype=np.float32)
    for c, f in enumerate(frames):
        sheet[:, c * w:(c + 1) * w] = f
    Image.fromarray((sheet * 255).astype(np.uint8)).save(name)


def main():
    rng = random.Random(SEED)
    # One anchor height per frame index, shared by all variations. Consecutive
    # anchors are pushed apart so the beam visibly jumps every frame.
    anchors = []
    for k in range(FRAMES_PER_VARIATION):
        while True:
            a = rng.uniform(-ANCHOR_RANGE, ANCHOR_RANGE)
            if not anchors or abs(a - anchors[-1]) > ANCHOR_RANGE * 0.6:
                break
        anchors.append(a)
    print("anchor offsets (px):", [round(a, 1) for a in anchors])
    # Per-frame strobe, shared by every piece so the whole beam flickers together.
    bright = [rng.choice([1.0, 1.0, 0.85, 0.65]) for _ in range(FRAMES_PER_VARIATION)]
    print("frame brightness:", bright)

    frames = [[make_frame(rng, anchors[k], bright[k]) for k in range(FRAMES_PER_VARIATION)]
              for _ in range(VARIATIONS)]
    sheet = np.zeros((VARIATIONS * FRAME_H, FRAMES_PER_VARIATION * FRAME_W, 3), dtype=np.float32)
    for r, row in enumerate(frames):
        for c, f in enumerate(row):
            sheet[r * FRAME_H:(r + 1) * FRAME_H, c * FRAME_W:(c + 1) * FRAME_W] = f
    Image.fromarray((sheet * 255).astype(np.uint8)).save("wp-tesla-beam-body.png")

    # End pieces: join the body at the anchor height on the inside edge, and pinch to
    # dead centre on the outside edge so the bolt really touches the shooter and target.
    # Beams are drawn source -> target along +x, so the source piece pinches left.
    src = [make_frame(rng, anchors[k], bright[k], "left", END_W) for k in range(FRAMES_PER_VARIATION)]
    dst = [make_frame(rng, anchors[k], bright[k], "right", END_W) for k in range(FRAMES_PER_VARIATION)]
    save_row(src, END_W, FRAME_H, "wp-tesla-beam-source-end.png")
    save_row(dst, END_W, FRAME_H, "wp-tesla-beam-target-end.png")

    # Start (small, at the shooter) and ending (big, at the target) spark bursts.
    start = [make_spark(rng, 0.6) for _ in range(FRAMES_PER_VARIATION)]
    ending = [make_spark(rng, 1.0) for _ in range(FRAMES_PER_VARIATION)]
    save_row(start, SPARK_SIZE, SPARK_SIZE, "wp-tesla-beam-start.png")
    save_row(ending, SPARK_SIZE, SPARK_SIZE, "wp-tesla-beam-ending.png")

    # Preview: one straight path piece (end + 4 body + end) with sparks, all on the same frame.
    # In-game the script chains several of these pieces at angles to make the jagged path.
    nbody = 4
    total = END_W * 2 + FRAME_W * nbody
    box = max(FRAME_H, SPARK_SIZE)
    ground = np.zeros((box + 20, total + 40 + SPARK_SIZE, 3), dtype=np.float32)
    ground[:] = (0.13, 0.12, 0.09)
    gif = []
    prng = random.Random(SEED + 1)
    seg_var = [prng.randrange(VARIATIONS) for _ in range(nbody)]
    ox = 20 + SPARK_SIZE // 2
    oy = 10 + (box - FRAME_H) // 2
    sy = 10 + (box - SPARK_SIZE) // 2
    for t in range(FRAMES_PER_VARIATION * 3):
        img = ground.copy()
        k = t % FRAMES_PER_VARIATION
        parts = [src[k]] + [frames[v][k] for v in seg_var] + [dst[k]]
        x = ox
        for f in parts:
            img[oy:oy + FRAME_H, x:x + f.shape[1]] += f
            x += f.shape[1]
        for f, cx in ((start[k], ox), (ending[k], ox + total)):
            img[sy:sy + SPARK_SIZE, cx - SPARK_SIZE // 2:cx + SPARK_SIZE // 2] += f
        gif.append(Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)))
    gif[0].save("preview.gif", save_all=True, append_images=gif[1:], duration=83, loop=0)
    gif[0].resize((gif[0].width * 2, gif[0].height * 2), Image.LANCZOS).save("preview.png")


if __name__ == "__main__":
    main()
