import json
import os
import time
import math
import urllib.request
import urllib.error
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(r'e:/TOOL DUNG CODE/PET-agent')
manifest = json.loads((root / 'data/openpets-manifest.json').read_text(encoding='utf-8'))['pets']
by_slug = {p['slug']: p for p in manifest}
pets_dir = Path(os.environ.get('LOCALAPPDATA', str(Path.home() / 'AppData/Local'))) / 'AgentPet' / 'pets'
pets_dir.mkdir(parents=True, exist_ok=True)

missing_slugs = [
    'absol-f5b3ff9b', 'alcremie-ec9790dc', 'alucard-2259c89a', 'armin-arlert-7efe7a8b',
    'asuka-langley-94c8c1c5', 'asuna-b2aea8b6', 'celebi-339d49ca', 'cu-chulainn-f006935e',
    'daimao-batiao-cat-336fcfa1', 'denji-549e8659', 'dialga-3f56d925', 'emilia-11076a36',
    'gilgamesh-10000a36', 'guts-bd41ddb6', 'hanamichi-sakuragi-3dc9e22a', 'hawlucha-ebff1966',
    'holo-3431f0d3', 'illyasviel-von-einzbern-35224084', 'inosuke-hashibira-63b9c619',
    'inuyasha-06f4707f', 'johan-liebert-18febdd6', 'kagome-higurashi-11dad78b',
    'killua-zoldyck-e86c922f', 'kirei-kotomine-6e06aefc', 'klee-877ea602', 'kurama-3207604d',
    'mash-kyrielight-76a04625', 'meme-man-2302a57b', 'minato-b0164525',
    'musashi-miyamoto-8129165a', 'nezukocoder-d043bc65', 'rei-ayanami-0389b18d',
    'subaru-natsuki-90767261', 'swoobat-51446296', 'woobat-c54f8bc8',
    'zenitsu-agatsuma-ffe3f869', 'zoroark-57524c95', 'zubat-a760db73',
]

report = []


def fetch(url, retries=3):
    last = None
    for attempt in range(retries):
        req = urllib.request.Request(
            url,
            headers={'User-Agent': 'AgentPet local installer', 'Referer': 'https://petdex.crafter.run/'},
        )
        try:
            with urllib.request.urlopen(req, timeout=45) as r:
                if r.status < 200 or r.status >= 300:
                    raise urllib.error.HTTPError(url, r.status, r.reason, r.headers, None)
                return r.read()
        except Exception as e:
            last = e
            if attempt < retries - 1:
                time.sleep(1.0 * (attempt + 1))
    raise last


def install_manifest_pet(slug):
    p = by_slug.get(slug)
    if not p:
        return ('missing-manifest', slug, '')
    d = pets_dir / slug
    pj = d / 'pet.json'
    png = d / 'spritesheet.png'
    if pj.exists() and png.exists():
        return ('already-installed', p.get('displayName', slug), str(d))
    try:
        d.mkdir(parents=True, exist_ok=True)
        pet_json_bytes = fetch(p['petJsonUrl'])
        meta = json.loads(pet_json_bytes.decode('utf-8'))
        sheet_name = meta.get('spritesheetPath') or meta.get('spritesheet') or 'spritesheet.webp'
        sheet_bytes = fetch(p['spritesheetUrl'])
        raw_path = d / sheet_name
        raw_path.write_bytes(sheet_bytes)
        im = Image.open(raw_path).convert('RGBA')
        im.save(png, 'PNG')
        meta['spritesheetPath'] = 'spritesheet.png'
        meta.pop('spritesheet', None)
        meta.setdefault('id', slug)
        meta.setdefault('displayName', p.get('displayName', slug))
        meta.setdefault('description', 'Imported from the OpenPets manifest for AgentPet Windows.')
        pj.write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding='utf-8')
        return ('installed', p.get('displayName', slug), f'{d} {im.width}x{im.height}')
    except Exception as e:
        return ('failed:' + type(e).__name__, p.get('displayName', slug), str(e)[:240])


for slug in missing_slugs:
    report.append((slug,) + install_manifest_pet(slug))

try:
    font_big = ImageFont.truetype('arial.ttf', 28)
    font_small = ImageFont.truetype('arial.ttf', 16)
except Exception:
    font_big = ImageFont.load_default()
    font_small = ImageFont.load_default()

CELL_W, CELL_H = 192, 208
COLS, ROWS = 8, 9


def draw_center_text(draw, xy, text, font, fill):
    x, y, w, h = xy
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text((x + (w - tw) / 2, y + (h - th) / 2), text, font=font, fill=fill)


def make_pack(slug, display, palette, badge, description):
    d = pets_dir / slug
    d.mkdir(parents=True, exist_ok=True)
    img = Image.new('RGBA', (CELL_W * COLS, CELL_H * ROWS), (0, 0, 0, 0))
    for row in range(ROWS):
        for col in range(COLS):
            frame = Image.new('RGBA', (CELL_W, CELL_H), (0, 0, 0, 0))
            dr = ImageDraw.Draw(frame)
            cx = CELL_W // 2 + int(math.sin((col / 7) * math.pi * 2 + row * 0.35) * 8)
            cy = CELL_H // 2 + int(math.sin((col / 7) * math.pi * 2 + row) * 5)
            main, accent, dark, glow = palette
            dr.ellipse((cx - 50, cy + 50, cx + 50, cy + 66), fill=(0, 0, 0, 55))
            if row in (1, 4):
                dr.ellipse((cx - 65, cy - 82, cx + 65, cy + 70), outline=glow, width=5)
            dr.rounded_rectangle((cx - 42, cy - 8, cx + 42, cy + 58), radius=22, fill=main, outline=dark, width=4)
            dr.ellipse((cx - 48, cy - 68, cx + 48, cy + 18), fill=main, outline=dark, width=4)
            eye_y = cy - 30 + (1 if col % 4 == 0 else 0)
            dr.ellipse((cx - 24, eye_y - 5, cx - 14, eye_y + 5), fill=dark)
            dr.ellipse((cx + 14, eye_y - 5, cx + 24, eye_y + 5), fill=dark)
            if row == 2:
                dr.line((cx - 14, cy - 4, cx + 14, cy - 4), fill=dark, width=4)
            elif row in (3, 4):
                dr.arc((cx - 18, cy - 12, cx + 18, cy + 18), 0, 180, fill=dark, width=4)
            else:
                dr.arc((cx - 16, cy - 10, cx + 16, cy + 14), 0, 180, fill=dark, width=3)
            if badge == 'G':
                spikes = [(cx - 42, cy - 58), (cx - 30, cy - 98), (cx - 12, cy - 64), (cx, cy - 106), (cx + 12, cy - 64), (cx + 30, cy - 98), (cx + 42, cy - 58)]
                dr.line(spikes, fill=accent, width=10, joint='curve')
                dr.rounded_rectangle((cx - 34, cy + 8, cx + 34, cy + 42), radius=12, outline=accent, width=5)
            elif badge == 'S':
                dr.ellipse((cx - 42, cy - 72, cx + 42, cy - 2), fill=(250, 250, 235, 255), outline=dark, width=3)
                dr.line((cx - 50, cy + 0, cx - 74, cy + 38), fill=accent, width=8)
                dr.line((cx + 50, cy + 0, cx + 74, cy + 38), fill=accent, width=8)
            elif badge == 'OP':
                dr.rectangle((cx - 56, cy - 78, cx + 56, cy - 58), fill=accent, outline=dark, width=3)
                dr.line((cx - 48, cy + 34, cx - 70, cy + 58), fill=accent, width=7)
                dr.line((cx + 48, cy + 34, cx + 70, cy + 58), fill=accent, width=7)
            elif badge == 'BM':
                dr.polygon([(cx - 44, cy - 52), (cx - 68, cy - 92), (cx - 20, cy - 66)], fill=dark)
                dr.polygon([(cx + 44, cy - 52), (cx + 68, cy - 92), (cx + 20, cy - 66)], fill=dark)
                dr.arc((cx - 58, cy - 72, cx + 58, cy + 34), 200, 340, fill=accent, width=6)
            draw_center_text(dr, (cx - 30, cy + 26, 60, 28), badge, font_small, dark)
            if col in (1, 2, 5, 6):
                dr.arc((cx - 72, cy - 36, cx - 52, cy - 8), 80, 240, fill=glow, width=3)
                dr.arc((cx + 52, cy - 36, cx + 72, cy - 8), -60, 100, fill=glow, width=3)
            img.alpha_composite(frame, (col * CELL_W, row * CELL_H))
    png = d / 'spritesheet.png'
    img.save(png, 'PNG')
    pack_manifest = {
        'id': slug,
        'displayName': display,
        'description': description,
        'spritesheetPath': 'spritesheet.png',
    }
    (d / 'pet.json').write_text(json.dumps(pack_manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    return str(png)


generated = [
    ('goku-generated', 'Goku', ((245, 124, 28, 255), (255, 205, 64, 255), (49, 38, 28, 255), (255, 218, 80, 190)), 'G', 'Generated local placeholder pack for Goku; original AgentPet sprite, not official artwork.'),
    ('saitama-generated', 'Saitama', ((250, 238, 176, 255), (210, 40, 34, 255), (45, 38, 32, 255), (255, 255, 180, 170)), 'S', 'Generated local placeholder pack for Saitama; original AgentPet sprite, not official artwork.'),
    ('one-punch-man-generated', 'One-Punch Man', ((248, 222, 82, 255), (210, 40, 34, 255), (45, 38, 32, 255), (255, 245, 130, 170)), 'OP', 'Generated local placeholder pack for One-Punch Man; original AgentPet sprite, not official artwork.'),
    ('batmeme-generated', 'Batmeme', ((72, 76, 96, 255), (245, 210, 80, 255), (18, 22, 35, 255), (150, 180, 255, 170)), 'BM', 'Generated local placeholder pack for Batmeme; original AgentPet sprite, not official artwork.'),
]
for args in generated:
    try:
        path = make_pack(*args)
        report.append((args[0], 'generated', args[1], path))
    except Exception as e:
        report.append((args[0], 'generate-failed:' + type(e).__name__, args[1], str(e)[:240]))

validation = []
for slug in missing_slugs + [g[0] for g in generated]:
    d = pets_dir / slug
    pj = d / 'pet.json'
    png = d / 'spritesheet.png'
    ok = pj.exists() and png.exists()
    validation.append((slug, ok, str(png if png.exists() else d)))

out = root / '.claude' / 'windows-pet-missing-install-report.md'
lines = ['# Windows missing pet install report', '', f'Target: {pets_dir}', '', '## Actions']
for slug, status, name, detail in report:
    lines.append(f'- **{status}** — {name} ({slug}) — {detail}')
lines += ['', '## Validation']
for slug, ok, path in validation:
    lines.append(f'- {"OK" if ok else "MISSING"} — {slug} — {path}')
out.write_text('\n'.join(lines) + '\n', encoding='utf-8')
print('\n'.join(lines))
