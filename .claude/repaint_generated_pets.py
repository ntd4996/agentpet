import json
import math
import os
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(r'e:/TOOL DUNG CODE/PET-agent')
PETS_DIR = Path(os.environ.get('LOCALAPPDATA', str(Path.home() / 'AppData/Local'))) / 'AgentPet' / 'pets'
PETS_DIR.mkdir(parents=True, exist_ok=True)

CELL_W = 192
CELL_H = 208
COLS = 8
ROWS = 9
SCALE = 4
W = CELL_W * SCALE
H = CELL_H * SCALE

packs = [
    {
        'slug': 'goku-generated',
        'displayName': 'Goku',
        'description': 'Generated local chibi pack inspired by the OpenPets pack style. Original AgentPet art, not official artwork.',
        'colors': {
            'skin': (246, 205, 170, 255),
            'hair': (20, 20, 26, 255),
            'gi': (245, 126, 31, 255),
            'gi_dark': (190, 84, 18, 255),
            'undershirt': (41, 92, 190, 255),
            'boots': (49, 91, 202, 255),
            'belt': (54, 102, 210, 255),
            'outline': (30, 22, 20, 255),
            'aura': (255, 232, 102, 120),
        },
        'mode': 'spiky',
    },
    {
        'slug': 'saitama-generated',
        'displayName': 'Saitama',
        'description': 'Generated local chibi pack inspired by the OpenPets pack style. Original AgentPet art, not official artwork.',
        'colors': {
            'skin': (244, 210, 183, 255),
            'hair': (244, 226, 197, 255),
            'gi': (245, 210, 54, 255),
            'gi_dark': (198, 164, 34, 255),
            'undershirt': (252, 252, 252, 255),
            'boots': (220, 46, 54, 255),
            'belt': (210, 184, 61, 255),
            'cape': (248, 248, 248, 255),
            'outline': (37, 30, 28, 255),
            'aura': (255, 237, 150, 90),
        },
        'mode': 'bald',
    },
    {
        'slug': 'one-punch-man-generated',
        'displayName': 'One-Punch Man',
        'description': 'Generated local chibi pack inspired by the OpenPets pack style. Original AgentPet art, not official artwork.',
        'colors': {
            'skin': (242, 206, 176, 255),
            'hair': (245, 230, 200, 255),
            'gi': (247, 218, 68, 255),
            'gi_dark': (194, 158, 35, 255),
            'undershirt': (255, 255, 255, 255),
            'boots': (231, 49, 57, 255),
            'belt': (222, 198, 79, 255),
            'cape': (253, 253, 253, 255),
            'outline': (35, 27, 25, 255),
            'aura': (255, 245, 175, 100),
        },
        'mode': 'heroic',
    },
    {
        'slug': 'batmeme-generated',
        'displayName': 'Batmeme',
        'description': 'Generated local chibi pack inspired by the OpenPets pack style. Original AgentPet art, not official artwork.',
        'colors': {
            'skin': (232, 204, 180, 255),
            'hair': (25, 30, 42, 255),
            'gi': (52, 58, 88, 255),
            'gi_dark': (22, 27, 44, 255),
            'undershirt': (244, 214, 88, 255),
            'boots': (29, 34, 53, 255),
            'belt': (233, 205, 72, 255),
            'cape': (65, 73, 106, 255),
            'outline': (16, 18, 30, 255),
            'aura': (131, 168, 255, 110),
        },
        'mode': 'bat',
    },
]


def rgba(c, alpha=None):
    if alpha is None:
        return c
    return (c[0], c[1], c[2], alpha)


def draw_centered_text(draw, box, text, fill, font):
    x, y, w, h = box
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    draw.text((x + (w - tw) / 2, y + (h - th) / 2), text, fill=fill, font=font)


def ellipse(draw, box, fill, outline=None, width=1):
    draw.ellipse(box, fill=fill, outline=outline, width=width)


def rounded(draw, box, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def line(draw, pts, fill, width=1):
    draw.line(pts, fill=fill, width=width, joint='curve')


def poly(draw, pts, fill, outline=None):
    draw.polygon(pts, fill=fill, outline=outline)


def base_canvas():
    return Image.new('RGBA', (W, H), (0, 0, 0, 0))


def mood_pose(mood, frame):
    t = frame / 7.0 * math.tau
    bob = math.sin(t * 2.0) * 5
    sway = math.sin(t * 1.5 + 0.7) * 4
    blink = (frame in (2, 6))
    return {'bob': bob, 'sway': sway, 'blink': blink, 'phase': t, 'mood': mood}


def add_aura(layer, cx, cy, palette, strength=1.0):
    # The procedural renderer may call this from an ImageDraw context. If we do not
    # have the backing Image object, skip this local aura; draw_frame adds a second
    # post-composite glow pass that still appears in the final sprite.
    if not hasattr(layer, 'alpha_composite'):
        return
    aura = Image.new('RGBA', layer.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(aura)
    c = palette['aura']
    for i, r in enumerate((112, 92, 74)):
        alpha = max(0, int(c[3] * strength * (0.48 - i * 0.11)))
        ellipse(d, (cx - r, cy - r, cx + r, cy + r), fill=(c[0], c[1], c[2], alpha), outline=None)
    aura = aura.filter(ImageFilter.GaussianBlur(10))
    layer.alpha_composite(aura)


def draw_shadow(draw, cx, cy, w=78, h=16):
    ellipse(draw, (cx - w, cy - h, cx + w, cy + h), fill=(0, 0, 0, 42))


def draw_goku(draw, pose, p):
    c = p['colors']
    cx = W // 2 + int(pose['sway'] * 0.9)
    cy = int(H * 0.59 + pose['bob'] * 1.1)
    outline = c['outline']
    if pose['mood'] in ('working', 'celebrate'):
        add_aura(draw.im, cx, cy, c, 1.0)
    draw_shadow(draw, cx, cy + 95)

    # Hair spikes
    head_y = cy - 72
    spike_pts = [
        (cx - 84, head_y - 18), (cx - 62, head_y - 108), (cx - 36, head_y - 46),
        (cx - 12, head_y - 136), (cx + 6, head_y - 52), (cx + 32, head_y - 116),
        (cx + 58, head_y - 38), (cx + 86, head_y - 98), (cx + 92, head_y - 10),
        (cx + 44, head_y + 18), (cx - 48, head_y + 20)
    ]
    poly(draw, spike_pts, fill=c['hair'], outline=outline)
    ellipse(draw, (cx - 60, head_y - 52, cx + 60, head_y + 66), fill=c['skin'], outline=outline, width=4)
    # hair front bangs
    poly(draw, [(cx - 28, head_y - 40), (cx - 4, head_y - 4), (cx - 54, head_y + 6)], fill=c['hair'])
    poly(draw, [(cx + 30, head_y - 38), (cx + 10, head_y + 4), (cx + 58, head_y + 8)], fill=c['hair'])
    # eyes
    eye_y = head_y + 8
    if pose['blink']:
        line(draw, [(cx - 28, eye_y), (cx - 8, eye_y)], outline, 4)
        line(draw, [(cx + 8, eye_y), (cx + 28, eye_y)], outline, 4)
    else:
        ellipse(draw, (cx - 30, eye_y - 6, cx - 20, eye_y + 4), outline)
        ellipse(draw, (cx + 20, eye_y - 6, cx + 30, eye_y + 4), outline)
        line(draw, [(cx - 28, eye_y - 10), (cx - 10, eye_y - 16)], outline, 3)
        line(draw, [(cx + 10, eye_y - 16), (cx + 28, eye_y - 10)], outline, 3)
    # mouth
    if pose['mood'] == 'waiting':
        line(draw, [(cx - 10, head_y + 28), (cx + 10, head_y + 28)], outline, 4)
    elif pose['mood'] in ('done', 'celebrate'):
        line(draw, [(cx - 14, head_y + 24), (cx, head_y + 34), (cx + 14, head_y + 24)], outline, 4)
    else:
        line(draw, [(cx - 10, head_y + 28), (cx, head_y + 32), (cx + 10, head_y + 28)], outline, 3)

    # body / gi
    body_y = cy - 4
    rounded(draw, (cx - 66, body_y - 4, cx + 66, body_y + 104), 26, fill=c['gi'], outline=outline, width=4)
    rounded(draw, (cx - 46, body_y + 10, cx + 46, body_y + 72), 20, fill=c['undershirt'], outline=outline, width=3)
    line(draw, [(cx - 34, body_y + 70), (cx + 34, body_y + 70)], c['gi_dark'], 6)
    line(draw, [(cx - 34, body_y + 70), (cx - 12, body_y + 94)], c['gi_dark'], 5)
    line(draw, [(cx + 34, body_y + 70), (cx + 12, body_y + 94)], c['gi_dark'], 5)
    line(draw, [(cx - 34, body_y + 34), (cx - 90, body_y + 48 + int(pose['sway']))], outline, 10)
    line(draw, [(cx + 34, body_y + 34), (cx + 92, body_y + 48 - int(pose['sway']))], outline, 10)
    ellipse(draw, (cx - 112, body_y + 26, cx - 68, body_y + 70), fill=c['gi'], outline=outline, width=4)
    ellipse(draw, (cx + 68, body_y + 26, cx + 112, body_y + 70), fill=c['gi'], outline=outline, width=4)
    # belt
    rounded(draw, (cx - 72, body_y + 60, cx + 72, body_y + 84), 10, fill=c['belt'], outline=outline, width=3)
    # legs
    line(draw, [(cx - 26, body_y + 98), (cx - 42, body_y + 140)], outline, 10)
    line(draw, [(cx + 26, body_y + 98), (cx + 42, body_y + 140)], outline, 10)
    ellipse(draw, (cx - 60, body_y + 132, cx - 16, body_y + 164), fill=c['boots'], outline=outline, width=4)
    ellipse(draw, (cx + 16, body_y + 132, cx + 60, body_y + 164), fill=c['boots'], outline=outline, width=4)
    if pose['mood'] in ('working', 'celebrate'):
        # punch / ki effect
        for r in (26, 40, 54):
            ellipse(draw, (cx + 88 - r, body_y + 6 - r, cx + 88 + r, body_y + 6 + r), fill=None, outline=c['aura'], width=6)


def draw_saitama(draw, pose, p):
    c = p['colors']
    cx = W // 2 + int(pose['sway'] * 0.75)
    cy = int(H * 0.59 + pose['bob'] * 1.0)
    outline = c['outline']
    if pose['mood'] in ('working', 'celebrate'):
        add_aura(draw.im, cx, cy, c, 0.9)
    draw_shadow(draw, cx, cy + 97)

    # cape behind
    cape = [(cx - 92, cy - 18), (cx - 126, cy + 78), (cx - 48, cy + 142), (cx - 2, cy + 34), (cx - 8, cy - 10)]
    cape_r = [(cx + 8, cy - 10), (cx + 2, cy + 34), (cx + 48, cy + 142), (cx + 126, cy + 78), (cx + 92, cy - 18)]
    poly(draw, cape, fill=c['cape'], outline=outline)
    poly(draw, cape_r, fill=c['cape'], outline=outline)

    # head
    head_y = cy - 72
    ellipse(draw, (cx - 60, head_y - 52, cx + 60, head_y + 66), fill=c['skin'], outline=outline, width=4)
    # bald shine
    ellipse(draw, (cx - 20, head_y - 34, cx + 10, head_y - 10), fill=(255, 255, 255, 120), outline=None)
    # eyes / mouth
    eye_y = head_y + 10
    if pose['blink']:
        line(draw, [(cx - 28, eye_y), (cx - 10, eye_y)], outline, 4)
        line(draw, [(cx + 10, eye_y), (cx + 28, eye_y)], outline, 4)
    else:
        ellipse(draw, (cx - 30, eye_y - 6, cx - 20, eye_y + 4), outline)
        ellipse(draw, (cx + 20, eye_y - 6, cx + 30, eye_y + 4), outline)
    if pose['mood'] == 'waiting':
        line(draw, [(cx - 12, head_y + 30), (cx + 12, head_y + 30)], outline, 4)
    elif pose['mood'] in ('done', 'celebrate'):
        line(draw, [(cx - 14, head_y + 24), (cx + 14, head_y + 30)], outline, 4)
    else:
        line(draw, [(cx - 12, head_y + 28), (cx, head_y + 30), (cx + 12, head_y + 28)], outline, 3)

    # body
    body_y = cy - 4
    rounded(draw, (cx - 62, body_y - 4, cx + 62, body_y + 104), 26, fill=c['gi'], outline=outline, width=4)
    rounded(draw, (cx - 48, body_y + 6, cx + 48, body_y + 66), 20, fill=c['undershirt'], outline=outline, width=3)
    rounded(draw, (cx - 70, body_y + 58, cx + 70, body_y + 82), 10, fill=c['belt'], outline=outline, width=3)
    # gloves and boots
    arm_up = -18 if pose['mood'] == 'celebrate' else 8
    line(draw, [(cx - 30, body_y + 32), (cx - 82, body_y + 48 + int(pose['sway']))], outline, 10)
    line(draw, [(cx + 30, body_y + 32), (cx + 84, body_y + 48 - int(pose['sway']))], outline, 10)
    ellipse(draw, (cx - 104, body_y + 32 + arm_up, cx - 58, body_y + 78 + arm_up), fill=c['boots'], outline=outline, width=4)
    ellipse(draw, (cx + 58, body_y + 32 + arm_up, cx + 104, body_y + 78 + arm_up), fill=c['boots'], outline=outline, width=4)
    line(draw, [(cx - 28, body_y + 98), (cx - 36, body_y + 140)], outline, 10)
    line(draw, [(cx + 28, body_y + 98), (cx + 36, body_y + 140)], outline, 10)
    ellipse(draw, (cx - 56, body_y + 132, cx - 12, body_y + 164), fill=c['boots'], outline=outline, width=4)
    ellipse(draw, (cx + 12, body_y + 132, cx + 56, body_y + 164), fill=c['boots'], outline=outline, width=4)
    if pose['mood'] in ('working', 'celebrate'):
        ellipse(draw, (cx + 74, body_y + 10, cx + 136, body_y + 72), fill=None, outline=c['aura'], width=6)


def draw_one_punch(draw, pose, p):
    c = p['colors']
    cx = W // 2 + int(pose['sway'] * 0.8)
    cy = int(H * 0.58 + pose['bob'] * 1.0)
    outline = c['outline']
    if pose['mood'] in ('working', 'celebrate'):
        add_aura(draw.im, cx, cy, c, 1.0)
    draw_shadow(draw, cx, cy + 98)

    # cape / hero silhouette more dramatic
    cape = [(cx - 90, cy - 6), (cx - 130, cy + 66), (cx - 40, cy + 150), (cx - 6, cy + 42), (cx - 10, cy - 8)]
    cape_r = [(cx + 10, cy - 8), (cx + 6, cy + 42), (cx + 40, cy + 150), (cx + 130, cy + 66), (cx + 90, cy - 6)]
    poly(draw, cape, fill=c['cape'], outline=outline)
    poly(draw, cape_r, fill=c['cape'], outline=outline)

    head_y = cy - 74
    ellipse(draw, (cx - 60, head_y - 52, cx + 60, head_y + 66), fill=c['skin'], outline=outline, width=4)
    ellipse(draw, (cx - 18, head_y - 34, cx + 8, head_y - 12), fill=(255, 255, 255, 110), outline=None)
    eye_y = head_y + 10
    if pose['blink']:
        line(draw, [(cx - 28, eye_y), (cx - 10, eye_y)], outline, 4)
        line(draw, [(cx + 10, eye_y), (cx + 28, eye_y)], outline, 4)
    else:
        ellipse(draw, (cx - 29, eye_y - 6, cx - 19, eye_y + 4), outline)
        ellipse(draw, (cx + 19, eye_y - 6, cx + 29, eye_y + 4), outline)
    if pose['mood'] == 'waiting':
        line(draw, [(cx - 10, head_y + 30), (cx + 10, head_y + 30)], outline, 4)
    elif pose['mood'] in ('done', 'celebrate'):
        line(draw, [(cx - 12, head_y + 24), (cx + 12, head_y + 30)], outline, 4)
    else:
        line(draw, [(cx - 12, head_y + 28), (cx, head_y + 31), (cx + 12, head_y + 28)], outline, 3)

    body_y = cy - 2
    rounded(draw, (cx - 64, body_y - 4, cx + 64, body_y + 104), 24, fill=c['gi'], outline=outline, width=4)
    rounded(draw, (cx - 44, body_y + 8, cx + 44, body_y + 64), 18, fill=c['undershirt'], outline=outline, width=3)
    rounded(draw, (cx - 76, body_y + 58, cx + 76, body_y + 84), 10, fill=c['belt'], outline=outline, width=3)
    # stronger punch arm
    if pose['mood'] in ('working', 'celebrate'):
        line(draw, [(cx + 32, body_y + 32), (cx + 106, body_y + 22 - int(pose['sway']))], outline, 12)
        ellipse(draw, (cx + 98, body_y + 12, cx + 146, body_y + 58), fill=c['boots'], outline=outline, width=4)
        for r in (18, 32, 46):
            ellipse(draw, (cx + 136 - r, body_y + 32 - r, cx + 136 + r, body_y + 32 + r), fill=None, outline=c['aura'], width=5)
    else:
        line(draw, [(cx + 32, body_y + 32), (cx + 84, body_y + 48 - int(pose['sway']))], outline, 10)
        ellipse(draw, (cx + 72, body_y + 30, cx + 116, body_y + 72), fill=c['boots'], outline=outline, width=4)
    line(draw, [(cx - 32, body_y + 32), (cx - 82, body_y + 48 + int(pose['sway']))], outline, 10)
    ellipse(draw, (cx - 106, body_y + 32, cx - 60, body_y + 76), fill=c['boots'], outline=outline, width=4)
    line(draw, [(cx - 28, body_y + 98), (cx - 38, body_y + 140)], outline, 10)
    line(draw, [(cx + 28, body_y + 98), (cx + 38, body_y + 140)], outline, 10)
    ellipse(draw, (cx - 58, body_y + 132, cx - 12, body_y + 164), fill=c['boots'], outline=outline, width=4)
    ellipse(draw, (cx + 12, body_y + 132, cx + 58, body_y + 164), fill=c['boots'], outline=outline, width=4)


def draw_batmeme(draw, pose, p):
    c = p['colors']
    cx = W // 2 + int(pose['sway'] * 0.65)
    cy = int(H * 0.58 + pose['bob'] * 1.0)
    outline = c['outline']
    if pose['mood'] in ('working', 'celebrate'):
        add_aura(draw.im, cx, cy, c, 1.0)
    draw_shadow(draw, cx, cy + 95)

    # bat ears and cowl
    head_y = cy - 74
    poly(draw, [(cx - 56, head_y - 10), (cx - 74, head_y - 72), (cx - 32, head_y - 40)], fill=c['hair'], outline=outline)
    poly(draw, [(cx + 56, head_y - 10), (cx + 74, head_y - 72), (cx + 32, head_y - 40)], fill=c['hair'], outline=outline)
    ellipse(draw, (cx - 60, head_y - 52, cx + 60, head_y + 66), fill=c['skin'], outline=outline, width=4)
    poly(draw, [(cx - 60, head_y - 16), (cx - 22, head_y - 76), (cx + 22, head_y - 76), (cx + 60, head_y - 16), (cx + 48, head_y + 28), (cx - 48, head_y + 28)], fill=c['hair'], outline=outline)
    # eyes and grin
    eye_y = head_y + 8
    if pose['blink']:
        line(draw, [(cx - 28, eye_y), (cx - 8, eye_y)], c['undershirt'], 4)
        line(draw, [(cx + 8, eye_y), (cx + 28, eye_y)], c['undershirt'], 4)
    else:
        ellipse(draw, (cx - 28, eye_y - 5, cx - 18, eye_y + 5), c['undershirt'])
        ellipse(draw, (cx + 18, eye_y - 5, cx + 28, eye_y + 5), c['undershirt'])
    line(draw, [(cx - 18, head_y + 28), (cx, head_y + 36), (cx + 18, head_y + 28)], outline, 4)
    # body and cape
    cape = [(cx - 92, cy - 4), (cx - 128, cy + 74), (cx - 54, cy + 148), (cx - 10, cy + 36), (cx - 6, cy + 0)]
    cape_r = [(cx + 6, cy + 0), (cx + 10, cy + 36), (cx + 54, cy + 148), (cx + 128, cy + 74), (cx + 92, cy - 4)]
    poly(draw, cape, fill=c['cape'], outline=outline)
    poly(draw, cape_r, fill=c['cape'], outline=outline)
    rounded(draw, (cx - 64, cy - 2, cx + 64, cy + 100), 24, fill=c['gi'], outline=outline, width=4)
    rounded(draw, (cx - 44, cy + 10, cx + 44, cy + 62), 18, fill=c['undershirt'], outline=outline, width=3)
    rounded(draw, (cx - 70, cy + 56, cx + 70, cy + 82), 10, fill=c['belt'], outline=outline, width=3)
    # icon emblem
    poly(draw, [(cx, cy + 20), (cx - 18, cy + 42), (cx - 4, cy + 42), (cx - 12, cy + 62), (cx + 18, cy + 32), (cx + 4, cy + 32), (cx + 12, cy + 20)], fill=c['belt'], outline=outline)
    # arms and legs
    if pose['mood'] in ('working', 'celebrate'):
        line(draw, [(cx + 32, cy + 36), (cx + 104, cy + 22 - int(pose['sway']))], outline, 10)
        ellipse(draw, (cx + 92, cy + 16, cx + 140, cy + 60), fill=c['boots'], outline=outline, width=4)
        for r in (22, 36, 50):
            ellipse(draw, (cx + 132 - r, cy + 30 - r, cx + 132 + r, cy + 30 + r), fill=None, outline=c['aura'], width=5)
    else:
        line(draw, [(cx + 32, cy + 36), (cx + 82, cy + 48 - int(pose['sway']))], outline, 10)
        ellipse(draw, (cx + 72, cy + 32, cx + 116, cy + 72), fill=c['boots'], outline=outline, width=4)
    line(draw, [(cx - 32, cy + 36), (cx - 86, cy + 48 + int(pose['sway']))], outline, 10)
    ellipse(draw, (cx - 116, cy + 32, cx - 72, cy + 72), fill=c['boots'], outline=outline, width=4)
    line(draw, [(cx - 30, cy + 98), (cx - 40, cy + 140)], outline, 10)
    line(draw, [(cx + 30, cy + 98), (cx + 40, cy + 140)], outline, 10)
    ellipse(draw, (cx - 58, cy + 132, cx - 12, cy + 164), fill=c['boots'], outline=outline, width=4)
    ellipse(draw, (cx + 12, cy + 132, cx + 58, cy + 164), fill=c['boots'], outline=outline, width=4)


def draw_frame(spec, mood, frame_index):
    pose = mood_pose(mood, frame_index)
    base = base_canvas()
    hi = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(hi)

    if spec['mode'] == 'spiky':
        draw_goku(d, pose, spec)
    elif spec['mode'] == 'bald':
        draw_saitama(d, pose, spec)
    elif spec['mode'] == 'heroic':
        draw_one_punch(d, pose, spec)
    elif spec['mode'] == 'bat':
        draw_batmeme(d, pose, spec)
    else:
        raise ValueError(spec['mode'])

    # subtle motion and highlights
    if mood in ('working', 'celebrate'):
        glow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow)
        x = W // 2
        y = int(H * 0.52 + pose['bob'] * 1.2)
        for r in (160, 130, 105):
            alpha = 35 if r == 160 else 25 if r == 130 else 18
            gd.ellipse((x - r, y - r, x + r, y + r), outline=(255, 245, 160, alpha), width=8)
        glow = glow.filter(ImageFilter.GaussianBlur(10))
        hi.alpha_composite(glow)

    # composite and downsample for anti-aliased look
    result = hi.resize((CELL_W, CELL_H), Image.Resampling.LANCZOS)
    base.alpha_composite(result, (0, 0))
    return base


def make_sheet(spec):
    sheet = Image.new('RGBA', (CELL_W * COLS, CELL_H * ROWS), (0, 0, 0, 0))
    for row in range(ROWS):
        # map the first 5 rows to gameplay moods; remaining rows are alternate variants.
        if row == 0:
            mood = 'idle'
        elif row == 1:
            mood = 'working'
        elif row == 2:
            mood = 'waiting'
        elif row == 3:
            mood = 'done'
        elif row == 4:
            mood = 'celebrate'
        elif row == 5:
            mood = 'idle'
        elif row == 6:
            mood = 'working'
        elif row == 7:
            mood = 'waiting'
        else:
            mood = 'celebrate'

        for col in range(COLS):
            frame = draw_frame(spec, mood, col + row * 2)
            sheet.alpha_composite(frame, (col * CELL_W, row * CELL_H))
    return sheet


for spec in packs:
    folder = PETS_DIR / spec['slug']
    folder.mkdir(parents=True, exist_ok=True)
    sheet = make_sheet(spec)
    sheet_path = folder / 'spritesheet.png'
    sheet.save(sheet_path, 'PNG')
    manifest = {
        'id': spec['slug'],
        'displayName': spec['displayName'],
        'description': spec['description'],
        'spritesheetPath': 'spritesheet.png',
    }
    (folder / 'pet.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    # remove old webp if any remains from previous generated attempts
    old_webp = folder / 'spritesheet.webp'
    if old_webp.exists():
        try:
            old_webp.unlink()
        except Exception:
            pass

print(f'generated {len(packs)} packs at {PETS_DIR}')
