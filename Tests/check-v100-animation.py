#!/usr/bin/env python3
"""Check that the v1.0.0 blink update leaves the other action rows intact."""
import json
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parent.parent
original = Image.open(root / "Assets/YueSources/original-spritesheet.png").convert("RGBA")
current = Image.open(root / "Resources/DefaultPet/spritesheet.png").convert("RGBA")
metadata = json.loads((root / "Resources/DefaultPet/pet.json").read_text())


def widths(row):
    result = []
    for col in range(10):
        alpha = current.crop((col * 192, row * 208, (col + 1) * 192, (row + 1) * 208)).getchannel("A")
        bounds = alpha.getbbox()
        result.append(bounds[2] - bounds[0] if bounds else 0)
    return result


other_rows_unchanged = all(
    original.crop((0, row * 208, 1920, (row + 1) * 208)).tobytes()
    == current.crop((0, row * 208, 1920, (row + 1) * 208)).tobytes()
    for row in range(29) if row not in (0, 8)
)
passive = metadata.get("passiveAnimations", {})
valid_timing = all(
    4 <= passive.get(name, {}).get("intervalSeconds", 0) <= 8
    and all(0 <= frame < metadata["frameCounts"][row]
            for key in ("restFrames", "blinkFrames")
            for frame in passive.get(name, {}).get(key, []))
    and bool(passive.get(name, {}).get("blinkFrames"))
    for name, row in (("idle", 0), ("onlinePhone", 8))
)
idle_widths, phone_widths = widths(0), widths(8)
results = {
    "atlasAndActionLayout": current.size == original.size == (1920, 6032)
    and metadata.get("rows") == 29 and metadata.get("columns") == 10
    and len(metadata.get("semanticRows", {})) == 19,
    "other27RowsPixelIdentical": other_rows_unchanged,
    "idleCharacterWidthStable": max(idle_widths) - min(idle_widths) <= 2,
    "phoneCharacterWidthStable": max(phone_widths) - min(phone_widths) <= 2,
    "blinkIntervalsAtLeastFourSeconds": valid_timing,
    "leftAndRightRunFramesUnchanged": all(
        original.crop((0, row * 208, 1920, (row + 1) * 208)).tobytes()
        == current.crop((0, row * 208, 1920, (row + 1) * 208)).tobytes()
        for row in (1, 2)
    ),
}
report = {
    "allPassed": all(results.values()),
    "caseCount": len(results),
    "results": results,
    "idleFrameWidths": idle_widths,
    "phoneFrameWidths": phone_widths,
}
destination = root / "Tests/animation-v100-report.json"
destination.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print(f"{destination.name}: {sum(results.values())}/{len(results)} passed")
raise SystemExit(0 if report["allPassed"] else 1)
