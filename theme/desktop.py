"""Paints one mode's desktop picture from its colors.

    desktop.py COLORS.json OUT.png

A planet's curved horizon fills the lower part of the screen, with a thin
rim of the accent's light and a glow rising over it, on a sky that leans
toward the accent near the horizon.
"""

import json
import sys

import numpy as np
from PIL import Image

W, H = 3840, 2160
WHITE = np.array([255.0, 255.0, 255.0])


def rgb(hex_color: str) -> np.ndarray:
    return np.array([int(hex_color[i : i + 2], 16) for i in (1, 3, 5)], dtype=float)


def mix(a, b, amount):
    amount = np.clip(amount, 0, 1)
    if np.ndim(amount):
        amount = amount[..., None]
    return a * (1 - amount) + b * amount


colors = json.load(open(sys.argv[1]))
dark = colors["mode"] == "dark"
background, chrome = rgb(colors["background"]), rgb(colors["chrome"])
accent, second, info = rgb(colors["accent"]), rgb(colors["second"]), rgb(colors["info"])

# The light mode leans on tints of the accent and blue, so nothing reads as
# flat gray.
if dark:
    sky_top, ground, deep = chrome, chrome, chrome
else:
    sky_top = mix(background, info, 0.06)
    ground = mix(background, accent, 0.07)
    deep = mix(background, info, 0.12)

yy, xx = np.mgrid[0:H, 0:W].astype(float)
u, v = xx / W, yy / H

sky_low = mix(sky_top, accent, 0.10 if dark else 0.14)
image = mix(np.broadcast_to(sky_top, (H, W, 3)), np.broadcast_to(sky_low, (H, W, 3)), v**1.2)

# The planet is a circle far below the screen, measured in screen heights.
cx, cy, radius = 0.5, 2.35, 1.72
distance = np.sqrt(((u - cx) * W / H) ** 2 + (v - cy) ** 2)
planet = mix(np.broadcast_to(ground, (H, W, 3)), np.broadcast_to(deep, (H, W, 3)), np.clip((v - 0.6) / 0.4, 0, 1))
image = np.where((distance < radius)[..., None], planet, image)

rim = np.exp(-(((distance - radius) / 0.0022) ** 2))
glow = np.exp(-((np.clip(distance - radius, 0, None) / 0.09) ** 1.2)) * (distance > radius)
light_side = np.exp(-(((u - 0.62) / 0.33) ** 2))
strength = 1.0 if dark else 0.9
image = mix(image, np.broadcast_to(mix(accent, second, 0.3), (H, W, 3)), 0.55 * strength * glow * light_side)
rim_color = mix(accent, WHITE, 0.3) if dark else accent
image = mix(image, np.broadcast_to(rim_color, (H, W, 3)), 0.95 * rim * (0.35 + 0.65 * light_side))

# A little noise keeps the gradients from banding.
image += np.random.default_rng(1).normal(0, 0.7, image.shape)
Image.fromarray(image.clip(0, 255).astype(np.uint8)).save(sys.argv[2])
