#!/usr/bin/env python3
"""Assemble Yue's calm idle and phone cels in the original v4 sprite layout.

Only idle row 0 and online phone row 8 are changed. Every other row, including
both run directions and all 19 semantic actions, is copied from the v4 atlas.
"""

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


HERE = Path(__file__).resolve().parent
DEFAULT = HERE.parent.parent / "Resources" / "DefaultPet"
CELL = (192, 208)
SUBJECT_BOUNDS = (49, 13, 143, 202)
PHONE_ROW = 8
IDLE_ROW = 0
COUNT = 10


def normalized_frame(path: Path, height: int) -> Image.Image:
    source = Image.open(path).convert("RGBA")
    alpha = source.getchannel("A")
    solid = alpha.point(lambda value: 255 if value > 16 else 0)
    bounds = solid.getbbox()
    if bounds is None:
        raise ValueError(f"No opaque subject in {path}")
    cropped = source.crop(bounds)
    cropped.putalpha(cropped.getchannel("A").point(lambda value: value if value > 16 else 0))
    width = SUBJECT_BOUNDS[2] - SUBJECT_BOUNDS[0]
    scaled = cropped.resize((width, height), Image.Resampling.LANCZOS)
    frame = Image.new("RGBA", CELL)
    # Anchor the shoes at the same baseline as Yue's existing animation.
    frame.alpha_composite(scaled, (SUBJECT_BOUNDS[0], SUBJECT_BOUNDS[3] - height))
    return frame


def normalized_idle_blink() -> Image.Image:
    source = Image.open(HERE / "idle-blink.png").convert("RGBA")
    bounds = source.getchannel("A").point(lambda value: 255 if value > 16 else 0).getbbox()
    if bounds is None:
        raise ValueError("No opaque subject in idle-blink.png")
    frame = Image.new("RGBA", CELL)
    # Match the neighboring open-eye cel's exact width, height and shoe baseline.
    frame.alpha_composite(source.crop(bounds).resize((95, 187), Image.Resampling.LANCZOS), (49, 14))
    return frame


def half_blink(open_frame: Image.Image, closed_frame: Image.Image) -> Image.Image:
    # Change only the face during the transition: the body and hair stay still.
    eye_mask = Image.new("L", CELL)
    ImageDraw.Draw(eye_mask).ellipse((68, 46, 125, 82), fill=145)
    eye_mask = eye_mask.filter(ImageFilter.GaussianBlur(4))
    return Image.composite(closed_frame, open_frame, eye_mask)


def main() -> None:
    DEFAULT.mkdir(parents=True, exist_ok=True)
    sheet = Image.open(HERE / "original-spritesheet.png").convert("RGBA")
    if sheet.size != (1920, 6032):
        raise ValueError(f"Unexpected Yue atlas size: {sheet.size}")
    closed = normalized_idle_blink()
    for column in (3, 4, 5, 6):
        x, y = column * CELL[0], IDLE_ROW * CELL[1]
        original = sheet.crop((x, y, x + CELL[0], y + CELL[1]))
        updated = half_blink(original, closed) if column in (3, 6) else closed
        sheet.paste(Image.new("RGBA", CELL), (x, y))
        sheet.alpha_composite(updated, (x, y))

    # Phone cels keep hands and feet anchored. Renderer spaces the blink apart.
    frames = [
        ("phone-open.png", 189),
        ("phone-open.png", 188),
        ("phone-tap.png", 187),
        ("phone-tap.png", 188),
        ("phone-blink.png", 189),
        ("phone-blink.png", 188),
        ("phone-tap.png", 190),
        ("phone-tap.png", 189),
        ("phone-open.png", 187),
        ("phone-open.png", 190),
    ]
    assert len(frames) == COUNT
    for column, (filename, height) in enumerate(frames):
        x, y = column * CELL[0], PHONE_ROW * CELL[1]
        sheet.paste(Image.new("RGBA", CELL), (x, y))
        sheet.alpha_composite(normalized_frame(HERE / filename, height), (x, y))
    sheet.save(DEFAULT / "spritesheet.png", optimize=True)

    metadata = json.loads((HERE / "original-pet.json").read_text(encoding="utf-8"))
    metadata["onlinePhoneRow"] = PHONE_ROW
    metadata["passiveAnimations"] = {
        "idle": {
            "intervalSeconds": 4.8,
            "restFrames": [0, 0, 1, 1, 2, 1],
            "blinkFrames": [2, 3, 4, 5, 6, 7],
        },
        "onlinePhone": {
            "intervalSeconds": 5.2,
            "restFrames": [0, 1, 2, 3, 2, 1, 0, 1, 2, 3, 2, 1, 0, 1],
            "blinkFrames": [2, 3, 4, 5, 6, 7, 8, 9],
        },
    }
    metadata["description"] = "周游专属默认桌宠玥；静止时自然眨眼，在线时玩手机。"
    (DEFAULT / "pet.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Wrote {DEFAULT / 'spritesheet.png'} and pet.json")


if __name__ == "__main__":
    main()
