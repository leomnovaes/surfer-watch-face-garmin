#!/usr/bin/env python3
"""Annotate the Surf Mode (tide curve view) screenshot with labeled manhattan-style arrows."""
from PIL import Image, ImageDraw, ImageFont

img = Image.open("screenshot-surf-tide.png").convert("RGBA")
orig_w, orig_h = img.size

CX, CY = 97, 161

MARGIN_LEFT = 280
MARGIN_RIGHT = 280
MARGIN_TOP = 40
MARGIN_BOTTOM = 40
new_w = orig_w + MARGIN_LEFT + MARGIN_RIGHT
new_h = orig_h + MARGIN_TOP + MARGIN_BOTTOM

canvas = Image.new("RGBA", (new_w, new_h), (255, 255, 255, 255))
canvas.paste(img, (MARGIN_LEFT, MARGIN_TOP))
draw = ImageDraw.Draw(canvas)

OX = MARGIN_LEFT + CX
OY = MARGIN_TOP + CY

try:
    font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 14)
except:
    font = ImageFont.load_default()

LABEL_COLOR = (40, 40, 40, 255)
LINE_WIDTH = 2

COLORS = [
    (220, 60, 60, 255),
    (60, 140, 220, 255),
    (60, 180, 80, 255),
    (200, 140, 40, 255),
    (160, 60, 200, 255),
    (40, 180, 180, 255),
    (200, 60, 140, 255),
    (120, 120, 60, 255),
]

def draw_arrowhead(tip, direction, color):
    s = 5
    if direction == "right":
        draw.polygon([tip, (tip[0]-s, tip[1]-s), (tip[0]-s, tip[1]+s)], fill=color)
    elif direction == "left":
        draw.polygon([tip, (tip[0]+s, tip[1]-s), (tip[0]+s, tip[1]+s)], fill=color)

def manhattan_left(label_text, label_y, target_x, target_y, lane_x, color):
    bbox = draw.textbbox((0, 0), label_text, font=font)
    label_w = bbox[2] - bbox[0]
    label_x = lane_x - 20 - label_w
    draw.text((label_x, label_y - 8), label_text, fill=LABEL_COLOR, font=font)
    draw.line([(label_x + label_w + 4, label_y), (lane_x, label_y)], fill=color, width=LINE_WIDTH)
    draw.line([(lane_x, label_y), (lane_x, target_y)], fill=color, width=LINE_WIDTH)
    draw.line([(lane_x, target_y), (target_x, target_y)], fill=color, width=LINE_WIDTH)
    draw_arrowhead((target_x, target_y), "right", color)

def manhattan_right(label_text, label_y, target_x, target_y, lane_x, color):
    label_x = lane_x + 20
    draw.text((label_x, label_y - 8), label_text, fill=LABEL_COLOR, font=font)
    draw.line([(label_x - 4, label_y), (lane_x, label_y)], fill=color, width=LINE_WIDTH)
    draw.line([(lane_x, label_y), (lane_x, target_y)], fill=color, width=LINE_WIDTH)
    draw.line([(lane_x, target_y), (target_x, target_y)], fill=color, width=LINE_WIDTH)
    draw_arrowhead((target_x, target_y), "left", color)

# --- Left side labels ---
left_items = [
    ("Battery",           50,   8),
    ("Water Temp",        70,  30),
    ("Next Tide",         50,  55),
    ("Wind Arrow",        22,  82),
    ("Wind Speed",        22,  98),
    ("Tide Curve",        88, 145),
    ("Now Marker",        88, 135),
]

# --- Right side labels ---
right_items = [
    ("Solar Intensity Arc", 158,  12),
    ("Tide Height",         144,  38),
    ("Tide Direction",      144,  18),
    ("Moon Phase",          138,  78),
    ("AM/PM + Seconds",     155,  98),
    ("Time",                 88,  90),
    ("Event Times",          50, 120),
]

def even_ys(count, start, end):
    if count <= 1:
        return [int((start + end) / 2)]
    step = (end - start) / (count - 1)
    return [int(start + i * step) for i in range(count)]

left_label_ys = even_ys(len(left_items), OY - 15, OY + 176 + 15)
right_label_ys = even_ys(len(right_items), OY - 15, OY + 176 + 15)

LEFT_LANE_CLOSEST = MARGIN_LEFT - 25
LANE_STEP = 12

def v_lane_left(index, count):
    if index <= count // 2:
        return LEFT_LANE_CLOSEST - index * LANE_STEP
    else:
        mirror = count - 1 - index
        return LEFT_LANE_CLOSEST - mirror * LANE_STEP

RIGHT_LANE_CLOSEST = MARGIN_LEFT + orig_w + 25

def v_lane_right(index, count):
    if index <= count // 2:
        return RIGHT_LANE_CLOSEST + index * LANE_STEP
    else:
        mirror = count - 1 - index
        return RIGHT_LANE_CLOSEST + mirror * LANE_STEP

for i, (label, wx, wy) in enumerate(left_items):
    label_y = left_label_ys[i]
    target_x = OX + wx - 3
    target_y = OY + wy
    lane_x = v_lane_left(i, len(left_items))
    color = COLORS[i % len(COLORS)]
    manhattan_left(label, label_y, target_x, target_y, lane_x, color)

for i, (label, wx, wy) in enumerate(right_items):
    label_y = right_label_ys[i]
    target_x = OX + wx + 3
    target_y = OY + wy
    lane_x = v_lane_right(i, len(right_items))
    color = COLORS[i % len(COLORS)]
    manhattan_right(label, label_y, target_x, target_y, lane_x, color)

canvas.save("screenshot-surf-tide-annotated.png")
print(f"Saved screenshot-surf-tide-annotated.png ({new_w}x{new_h})")
