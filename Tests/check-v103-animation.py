#!/usr/bin/env python3
"""Validate Yue v1.0.3 assets without rebuilding them or running a simulator.

The image checks inspect the delivered atlas, not freshly assembled cels.
Joint records supplement the pixels with fixed-length/phase measurements.
Requires Pillow; does not depend on the animation builder's implementation.
"""
import hashlib
import json
import math
from collections import deque
from pathlib import Path

from PIL import Image, ImageChops, ImageOps

ROOT = Path(__file__).resolve().parent.parent
ASSET = ROOT / "Resources/DefaultPet"
ATLAS_PATH = ASSET / "spritesheet.png"
METADATA_PATH = ASSET / "pet.json"
JOINT_PATH = ROOT / "Assets/YueSources/Review/gait-joints.json"
REPORT_PATH = ROOT / "Tests/animation-v103-report.json"
CELL = (192, 208)
EXPECTED_COUNTS = [8 if row in (9, 10) else 10 for row in range(29)]
SEMANTICS = {
    "idle": 0, "tap": 11, "longPress": 12, "petting": 13,
    "sendPet": 14, "receivePet": 15, "sendMiss": 16, "receiveMiss": 17,
    "sendAnger": 18, "receiveAnger": 19, "angerIdle": 20,
    "angerResolved": 21, "drag": 22, "land": 23, "shake": 24,
    "peekLeft": 25, "peekRight": 26, "reveal": 27, "retract": 28,
}

metadata = json.loads(METADATA_PATH.read_text())
joints = json.loads(JOINT_PATH.read_text())
atlas = Image.open(ATLAS_PATH).convert("RGBA")
checks = {}
measurements = {}


def check(name, passed):
    checks[name] = bool(passed)


def cel(row, column):
    x, y = column * CELL[0], row * CELL[1]
    return atlas.crop((x, y, x + CELL[0], y + CELL[1]))


def rgba_same(a, b):
    return a.size == b.size and a.tobytes() == b.tobytes()


def opaque(image, threshold=80):
    return image.getchannel("A").point(lambda value: 255 if value > threshold else 0)


def components(image):
    """Eight-connected opaque component areas; hair antialias dust is recorded."""
    width, height = image.size
    data = bytearray(opaque(image).tobytes())
    sizes = []
    for origin, value in enumerate(data):
        if not value:
            continue
        data[origin] = 0
        pending = deque([origin])
        size = 0
        while pending:
            index = pending.popleft()
            size += 1
            x, y = index % width, index // width
            for yy in range(max(0, y - 1), min(height, y + 2)):
                for xx in range(max(0, x - 1), min(width, x + 2)):
                    neighbor = yy * width + xx
                    if data[neighbor]:
                        data[neighbor] = 0
                        pending.append(neighbor)
        sizes.append(size)
    return sorted(sizes, reverse=True)


check("v4AtlasLayoutAnd286Frames",
      atlas.size == (1920, 6032)
      and metadata.get("spriteVersionNumber") == 4
      and (metadata.get("frameWidth"), metadata.get("frameHeight")) == CELL
      and metadata.get("columns") == 10 and metadata.get("rows") == 29
      and metadata.get("frameCounts") == EXPECTED_COUNTS
      and sum(metadata.get("frameCounts", [])) == 286)
check("semanticRowsRetainRuntimeContract", metadata.get("semanticRows") == SEMANTICS
      and metadata.get("onlinePhoneRow") == 8)
check("newAssetRevisionAndBoundedFile", metadata.get("assetRevision") == "1.0.3"
      and ATLAS_PATH.stat().st_size <= 32 * 1024 * 1024)

blank_cells = [(row, column) for row in (9, 10) for column in (8, 9)]
check("fourUnusedCellsAreTransparent",
      all(cel(row, column).getchannel("A").getbbox() is None for row, column in blank_cells))

empty = []
clipped = []
minimum_margins = [CELL[0], CELL[1], CELL[0], CELL[1]]
for row, count in enumerate(EXPECTED_COUNTS):
    for column in range(count):
        bounds = cel(row, column).getchannel("A").getbbox()
        if not bounds:
            empty.append([row, column])
            continue
        margins = [bounds[0], bounds[1], CELL[0] - bounds[2], CELL[1] - bounds[3]]
        minimum_margins = [min(a, b) for a, b in zip(minimum_margins, margins)]
        if min(margins) < 2:
            clipped.append({"row": row, "column": column, "margins": margins})
check("all286ValidCellsAreVisible", not empty)
check("allValidCellsHaveTwoPixelTransparentMargins", not clipped)
measurements["minimumTransparentMarginsLTRB"] = minimum_margins
measurements["emptyValidCells"] = empty
measurements["clippedValidCells"] = clipped

check("allTenLeftFramesAreExactRightMirrors",
      all(rgba_same(cel(2, column), ImageOps.mirror(cel(1, column))) for column in range(10)))

check("tenFiniteJointRecords", len(joints) == 10 and all(
    all(math.isfinite(float(number)) for key in ("hip", "knee", "ankle") for number in frame[leg][key])
    and all(math.isfinite(float(frame[leg][key])) for key in ("angle", "shinAngle"))
    for frame in joints for leg in ("near", "far")))

bone_lengths = {}
for leg in ("near", "far"):
    for segment, start, end in (("thigh", "hip", "knee"), ("shin", "knee", "ankle")):
        lengths = [math.dist(frame[leg][start], frame[leg][end]) for frame in joints]
        bone_lengths[f"{leg}_{segment}"] = lengths
check("allFourBoneLengthsRemainConstant", all(
    min(lengths) > 15 and max(lengths) - min(lengths) < 1e-8
    for lengths in bone_lengths.values()))
check("bothLegsExchangeThighAndShinPhasesAfterFiveFrames", all(
    math.isclose(joints[index]["far"][key], joints[(index + 5) % 10]["near"][key], abs_tol=1e-9)
    for index in range(10) for key in ("angle", "shinAngle")))
check("nearAndFarThighAnglesAreOpposite", all(
    math.isclose(frame["near"]["angle"], -frame["far"]["angle"], abs_tol=1e-9)
    for frame in joints))
check("gaitHasForwardAndBackwardSupport", all(
    min(frame[leg]["angle"] for frame in joints) <= -20
    and max(frame[leg]["angle"] for frame in joints) >= 20
    and max(frame[leg]["shinAngle"] for frame in joints)
        - min(frame[leg]["shinAngle"] for frame in joints) >= 60
    for leg in ("near", "far")))
check("oneCommonIsotropicScaleAndSmallVerticalBob", len(joints) == 10
      and len({frame["scale"] for frame in joints}) == 1
      and max(frame["offset"][1] for frame in joints)
          - min(frame["offset"][1] for frame in joints) <= 3)
measurements["sourceBoneLengths"] = bone_lengths
measurements["thighAnglesNear"] = [frame["near"]["angle"] for frame in joints]
measurements["thighAnglesFar"] = [frame["far"]["angle"] for frame in joints]
measurements["shinAnglesNear"] = [frame["near"]["shinAngle"] for frame in joints]
measurements["shinAnglesFar"] = [frame["far"]["shinAngle"] for frame in joints]

# The head and upper torso lie above all articulated leg cuts. Undo only the
# recorded translation: exact pixels then detect any shrinking or warping.
heads, gait_lower_hashes = [], []
for column, frame in enumerate(joints):
    dx, dy = frame["offset"]
    normalized = cel(1, column).crop((dx, dy, CELL[0] + dx, CELL[1] + dy))
    heads.append(normalized.crop((0, 0, CELL[0], 110)))
    gait_lower_hashes.append(hashlib.sha256(normalized.crop((0, 125, CELL[0], CELL[1])).tobytes()).hexdigest())
check("walkingHeadPixelsIdenticalAfterRemovingTranslation", len(heads) == 10
      and opaque(heads[0]).histogram()[255] > 1000
      and all(rgba_same(heads[0], head) for head in heads[1:]))
check("tenDifferentLegPosesInDeliveredAtlas", len(set(gait_lower_hashes)) == 10)

areas = [components(cel(1, column)) for column in range(10)]
check("walkingBodyAndLegsStayConnectedAboveAlpha80", all(
    len([area for area in sizes if area > 20]) == 1 and sizes[0] > 3000 for sizes in areas))
measurements["walkingOpaqueComponentAreas"] = areas
measurements["componentConnectivity"] = 8
measurements["componentAlphaThreshold"] = 80
measurements["ignoredComponentMaximumArea"] = 20

phone = [cel(8, column) for column in range(10)]
check("phoneSilhouetteNeverChangesSizeOrShape", all(
    rgba_same(opaque(phone[0]), opaque(frame)) for frame in phone[1:]))
check("phoneTorsoAndLegPixelsNeverRescale", all(
    rgba_same(phone[0].crop((0, 105, CELL[0], CELL[1])),
              frame.crop((0, 105, CELL[0], CELL[1]))) for frame in phone[1:]))

# Interior expression edits may change eyes and mouth. The hair/skull outline
# and all pixels outside this generous interior face box must remain fixed.
face_interior = (58, 44, 138, 105)
phone_outside = []
for frame in phone:
    outside = frame.copy()
    outside.paste((0, 0, 0, 0), face_interior)
    phone_outside.append(outside)
check("phoneHeadOutlineAndBodyPixelsStayFixed", all(
    rgba_same(phone_outside[0], frame) for frame in phone_outside[1:]))
eye_box = (66, 52, 128, 92)
blink_difference = ImageChops.difference(phone[0].crop(eye_box).convert("RGB"),
                                       phone[4].crop(eye_box).convert("RGB"))
blink_changed_pixels = sum(any(channel > 5 for channel in pixel) for pixel in blink_difference.getdata())
check("phoneHasRealBlinkAtFramesFourAndFive", blink_changed_pixels >= 40
      and rgba_same(phone[4], phone[5])
      and all(rgba_same(phone[0], phone[index]) for index in (1, 2, 3, 6, 7, 8, 9)))
measurements["phoneBlinkChangedEyePixels"] = blink_changed_pixels
measurements["phoneOpaqueBounds"] = [opaque(frame).getbbox() for frame in phone]

passive = metadata.get("passiveAnimations", {})
rate = metadata.get("frameRate", 0)
valid_passive = rate == 15
passive_metrics = {}
for name, row in (("idle", 0), ("onlinePhone", 8)):
    config = passive.get(name, {})
    interval = config.get("intervalSeconds", 0)
    rest, blink = config.get("restFrames", []), config.get("blinkFrames", [])
    sequences_valid = bool(rest) and bool(blink) and all(
        isinstance(index, int) and not isinstance(index, bool) and 0 <= index < EXPECTED_COUNTS[row]
        for index in rest + blink)
    # Neither repeated rest cels nor a fast row loop may include closed-eye
    # frames; only the slow scheduled blink traverses the closed-eye keys.
    valid_passive &= (4 <= interval <= 8 and sequences_valid
                      and not ({4, 5} & set(rest)) and {4, 5} <= set(blink)
                      and len(blink) / max(1, rate) <= 0.8
                      and interval * rate > len(blink))
    passive_metrics[name] = {"intervalSeconds": interval,
                             "blinkSequenceSeconds": len(blink) / max(1, rate),
                             "closedEyeSeconds": sum(index in (4, 5) for index in blink) / max(1, rate)}
check("idleAndPhoneUseSlowScheduledBlinks", valid_passive)
measurements["passiveTiming"] = passive_metrics

report = {
    "allPassed": all(checks.values()), "caseCount": len(checks),
    "passedCount": sum(checks.values()), "results": checks,
    "measurements": measurements,
    "inputs": {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
               for path in (ATLAS_PATH, METADATA_PATH, JOINT_PATH)},
    "scope": "Delivered atlas, metadata, and recorded gait geometry only; no device or simulator run.",
}
REPORT_PATH.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print(f"{REPORT_PATH.name}: {report['passedCount']}/{report['caseCount']} passed")
for name, passed in checks.items():
    if not passed:
        print(f"FAIL: {name}")
raise SystemExit(0 if report["allPassed"] else 1)
