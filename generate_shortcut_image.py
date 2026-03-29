#!/usr/bin/env python3
"""Generate a Catppuccin Mocha-themed shortcut cheatsheet image."""

from PIL import Image, ImageDraw, ImageFont
import subprocess, sys

# Catppuccin Mocha palette
BG       = (30, 30, 46)      # base
SURFACE  = (49, 50, 68)      # surface0
OVERLAY  = (69, 71, 90)      # surface1
TEXT     = (205, 214, 244)    # text
SUBTEXT  = (166, 173, 200)   # subtext0
MAUVE    = (203, 166, 247)   # mauve
BLUE     = (137, 180, 250)   # blue
GREEN    = (166, 227, 161)   # green
PEACH    = (250, 179, 135)   # peach
PINK     = (245, 194, 231)   # pink
YELLOW   = (249, 226, 175)   # yellow
TEAL     = (148, 226, 213)   # teal
LAVENDER = (180, 190, 254)   # lavender

# Try to find a good monospace font
def find_font(size):
    paths = [
        "/System/Library/Fonts/SFMono-Regular.otf",
        "/System/Library/Fonts/Menlo.ttc",
        "/System/Library/Fonts/Monaco.dfont",
        "/Library/Fonts/SF-Mono-Regular.otf",
    ]
    for p in paths:
        try:
            return ImageFont.truetype(p, size)
        except (OSError, IOError):
            continue
    return ImageFont.load_default()

def find_bold_font(size):
    paths = [
        "/System/Library/Fonts/SFMono-Bold.otf",
        "/System/Library/Fonts/Menlo.ttc",
        "/Library/Fonts/SF-Mono-Bold.otf",
    ]
    for p in paths:
        try:
            return ImageFont.truetype(p, size)
        except (OSError, IOError):
            continue
    return find_font(size)

font_sm = find_font(14)
font_md = find_font(16)
font_lg = find_bold_font(22)
font_title = find_bold_font(28)
font_key = find_bold_font(15)

sections = [
    ("Workspaces", MAUVE, [
        ("⌥ 1–9", "Switch workspace"),
        ("⌥ ⇧ 1–9", "Move window to workspace"),
        ("⌥ Tab", "Last workspace"),
        ("⌥ ⇧ Tab", "Workspace → next monitor"),
    ]),
    ("Focus", BLUE, [
        ("⌥ H J K L", "Focus left/down/up/right"),
    ]),
    ("Move", GREEN, [
        ("⌥ ⇧ H J K L", "Move window"),
        ("⌥ ⌃ ⇧ H / L", "Move to left/right monitor"),
    ]),
    ("Resize", PEACH, [
        ("⌥ ⌃ H / L", "Shrink / grow width"),
        ("⌥ ⌃ K / J", "Shrink / grow height"),
    ]),
    ("Layout", PINK, [
        ("⌥ F", "Fullscreen"),
        ("⌥ E", "Toggle split direction"),
        ("⌥ S", "Accordion (stacked)"),
        ("⌥ ⇧ Space", "Float / tile toggle"),
        ("⌥ ⇧ Q", "Close window"),
    ]),
    ("Apps", YELLOW, [
        ("⌥ Return", "Terminal"),
        ("⌥ ⇧ B", "Browser"),
        ("⌥ ⇧ N", "Editor"),
        ("⌥ ⇧ F", "Finder"),
        ("⌥ ⇧ M", "Music"),
        ("⌥ ⇧ G", "Chat"),
        ("⌥ ⇧ /", "Passwords"),
    ]),
    ("Misc", TEAL, [
        ("⌥ ⇧ S", "Screenshot (region)"),
        ("⌥ P", "Screenshot (full)"),
        ("⌥ ⇧ R", "Reload Aerospace"),
        ("⌥ ⇧ C", "Reload skhd"),
        ("⌥ Space", "Raycast launcher"),
    ]),
]

# Layout constants
COL_WIDTH = 340
PADDING = 30
SECTION_GAP = 18
ROW_HEIGHT = 26
HEADER_HEIGHT = 32
KEY_COL = 140  # width for key column

# Calculate dimensions - 2 columns
col_heights = [0, 0]
col_sections = [[], []]
for i, (title, color, rows) in enumerate(sections):
    h = HEADER_HEIGHT + len(rows) * ROW_HEIGHT + SECTION_GAP
    # Put in shorter column
    target = 0 if col_heights[0] <= col_heights[1] else 1
    col_sections[target].append((title, color, rows))
    col_heights[target] += h

max_height = max(col_heights)
IMG_W = PADDING * 3 + COL_WIDTH * 2
IMG_H = max_height + PADDING * 2 + 60  # extra for title

img = Image.new("RGBA", (IMG_W, IMG_H), BG)
draw = ImageDraw.Draw(img)

# Title
title_text = "omarchy-macos shortcuts"
bbox = draw.textbbox((0, 0), title_text, font=font_title)
tw = bbox[2] - bbox[0]
draw.text(((IMG_W - tw) // 2, PADDING - 5), title_text, fill=LAVENDER, font=font_title)

# Subtitle
sub = "modifier: ⌥ Option"
bbox = draw.textbbox((0, 0), sub, font=font_sm)
sw = bbox[2] - bbox[0]
draw.text(((IMG_W - sw) // 2, PADDING + 28), sub, fill=SUBTEXT, font=font_sm)

# Draw sections
for col_idx in range(2):
    x = PADDING + col_idx * (COL_WIDTH + PADDING)
    y = PADDING + 60

    for title, color, rows in col_sections[col_idx]:
        # Section header with accent bar
        draw.rounded_rectangle(
            [x, y, x + COL_WIDTH, y + HEADER_HEIGHT - 4],
            radius=6, fill=SURFACE
        )
        draw.rectangle([x, y, x + 4, y + HEADER_HEIGHT - 4], fill=color)
        draw.text((x + 14, y + 6), title, fill=color, font=font_lg)
        y += HEADER_HEIGHT + 2

        for key, action in rows:
            # Key badge
            key_bbox = draw.textbbox((0, 0), key, font=font_key)
            kw = key_bbox[2] - key_bbox[0]
            badge_x = x + 8
            badge_w = min(kw + 16, KEY_COL - 8)
            draw.rounded_rectangle(
                [badge_x, y + 2, badge_x + badge_w, y + ROW_HEIGHT - 4],
                radius=4, fill=OVERLAY
            )
            draw.text((badge_x + 8, y + 4), key, fill=TEXT, font=font_key)

            # Action text
            draw.text((x + KEY_COL + 8, y + 5), action, fill=SUBTEXT, font=font_md)
            y += ROW_HEIGHT

        y += SECTION_GAP

# Round the corners of the whole image
mask = Image.new("L", (IMG_W, IMG_H), 0)
mask_draw = ImageDraw.Draw(mask)
mask_draw.rounded_rectangle([0, 0, IMG_W, IMG_H], radius=16, fill=255)
img.putalpha(mask)

output = "/Users/zach/Desktop/omarchy-shortcuts.png"
img.save(output, "PNG")
print(f"Saved to {output}")
