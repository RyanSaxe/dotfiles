#!/usr/bin/env -S uv run -q --script
# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = ["pillow"]
# ///
"""Extract a two-hue accent pair from a mascot's image.

A mascot identity is provider-qualified ("pokemon:raikou"). Each registered
provider supplies two things: an identity list for the picker, and the
images for one identity — the sprite the rail displays plus the image
accent extraction reads. Extraction itself is core and identical for every
provider.

Prints key=value lines consumed by the `theme` command:

    mascot=<provider:id>      sprite=<png path the rail paints>
    accent_dark=#...          notify_dark=#...
    accent_light=#...         notify_light=#...

Every color must actually exist on the mascot. The accent is the dominant
vivid hue cluster; the bright accent is the most distinct OTHER hue present,
searched in relaxing tiers (vivid at 45°+, vivid at 30°+, pale clusters like
cream fins). A truly single-hue mascot gets two brightnesses of its one hue
— never a synthesized complement. Wallpaper-palette tools fail here: small
identity areas (gengar's red eyes) vanish under frequency-based extraction.
"""

from __future__ import annotations

import colorsys
import json
import sys
import urllib.request
from collections.abc import Callable
from dataclasses import dataclass
from os import environ
from pathlib import Path
from typing import TypeVar
from urllib.error import HTTPError, URLError

from PIL import Image

HUE_BUCKETS = 24  # 15 degrees each
MIN_HUE_SEPARATION = 3  # buckets: 45 degrees
# A second cluster this much weaker than the primary is noise, not a hue.
SECOND_CLUSTER_MIN_WEIGHT = 0.02

Hsv = tuple[float, float, float]


T = TypeVar("T")


def fetch_or_exit(action: Callable[[], T], what: str) -> T:
    """Run a network-backed action; a fetch failure exits with a one-line
    error instead of a urllib traceback."""
    try:
        return action()
    except HTTPError as error:
        raise SystemExit(
            f"error: cannot fetch {what}: HTTP {error.code} {error.reason}"
        ) from error
    except URLError as error:
        raise SystemExit(f"error: cannot fetch {what}: {error.reason}") from error


def _get(url: str) -> bytes:
    # PokeAPI rejects urllib's default User-Agent with a 403.
    request = urllib.request.Request(url, headers={"User-Agent": "dotfiles-theme/1.0"})
    with urllib.request.urlopen(request) as response:
        return response.read()


MASCOT_SCALE = 2  # crisp on retina: image pixels = 2x the canvas points


def normalize(sprite: Image.Image, margin_fraction: float = 0.05) -> Image.Image:
    """Crop to visible content and pad to a square with a small margin.

    Sources put the subject at arbitrary size and offset on their canvas;
    without this, each mascot displays at a different size. Scaled up with
    NEAREST so the pixel art stays crisp.
    """
    rgba = sprite.convert("RGBA")
    content_box = rgba.getchannel("A").getbbox()
    if content_box:
        rgba = rgba.crop(content_box)
    side = max(round(max(rgba.size) * (1 + 2 * margin_fraction)), 1)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(rgba, ((side - rgba.width) // 2, (side - rgba.height) // 2))
    return canvas.resize(
        (side * MASCOT_SCALE, side * MASCOT_SCALE), Image.Resampling.NEAREST
    )


def mascot_cache(provider: str) -> Path:
    root = (
        Path(environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "dotfiles/mascots"
    )
    # One-time migration from the pre-provider layout, where the pokemon
    # cache WAS the whole cache.
    legacy = root.parent / "pokemon"
    migrated = root / "pokemon"
    if legacy.is_dir() and not migrated.exists():
        root.mkdir(parents=True, exist_ok=True)
        try:
            legacy.rename(migrated)
        except OSError:
            # Concurrent invocations (theme sync, the rail's extractor)
            # race this rename; losing means the other process migrated.
            if not migrated.exists():
                raise
    path = root / provider
    path.mkdir(parents=True, exist_ok=True)
    return path


# ----- provider registry --------------------------------------------------


@dataclass(frozen=True)
class MascotImages:
    sprite: Path  # what the rail paints (the accents.conf pointer)
    palette: Path  # what extraction reads (may be a richer rendering of
    # the same character than the displayed sprite)


@dataclass(frozen=True)
class Provider:
    identities: Callable[[], list[str]]
    fetch: Callable[[str], MascotImages]


PROVIDERS: dict[str, Provider] = {}


def register(name: str, provider: Provider) -> None:
    PROVIDERS[name] = provider


def resolve(value: str) -> tuple[Provider, str]:
    provider_name, sep, identity = value.partition(":")
    if not sep or not identity:
        raise SystemExit(
            f"error: '{value}' is not provider-qualified (e.g. pokemon:raikou)"
        )
    provider = PROVIDERS.get(provider_name)
    if provider is None:
        known = ", ".join(PROVIDERS)
        raise SystemExit(f"error: unknown provider '{provider_name}' (have: {known})")
    return provider, identity


# ----- pokemon provider ---------------------------------------------------

POKEAPI = "https://pokeapi.co/api/v2/pokemon/"


def _pokemon_fetch(name: str, *, shiny: bool) -> MascotImages:
    """Cache all renderings of one pokemon.

    One fetch, distinct roles: the official ARTWORK is the palette source —
    it carries identity details the 96px game sprite drops (gengar's sprite
    has literally zero red pixels, losing the eyes) — while the game SPRITE
    is what the mascot displays, with a normalized square variant cached
    alongside as <base>-mascot.png. Same character, same color family, so
    the mascot matches its accents. Shiny variants have their own artwork
    and sprite, cached under <name>-shiny.
    """
    name = name.lower()
    cache = mascot_cache("pokemon")
    base = f"{name}-shiny" if shiny else name
    artwork = cache / f"{base}.png"
    sprite = cache / f"{base}-sprite.png"
    mascot = cache / f"{base}-mascot.png"
    if artwork.exists() and sprite.exists() and mascot.exists():
        return MascotImages(sprite=sprite, palette=artwork)

    data = json.loads(_get(f"{POKEAPI}{name}"))
    variant = "front_shiny" if shiny else "front_default"
    artwork_url = data["sprites"]["other"]["official-artwork"][variant]
    sprite_url = data["sprites"][variant]
    if not artwork_url or not sprite_url:
        raise SystemExit(
            f"error: missing {'shiny ' if shiny else ''}images for '{name}'"
        )
    if not artwork.exists():
        artwork.write_bytes(_get(artwork_url))
    if not sprite.exists():
        sprite.write_bytes(_get(sprite_url))
    normalize(Image.open(sprite)).save(mascot)
    return MascotImages(sprite=sprite, palette=artwork)


def _pokemon_identities() -> list[str]:
    """Every pokemon name, fetched once and cached for picker completion."""
    names_file = mascot_cache("pokemon") / "names.txt"
    if not names_file.exists():
        data = json.loads(_get(f"{POKEAPI}?limit=100000"))
        names = [entry["name"] for entry in data["results"]]
        names_file.write_text("\n".join(names) + "\n")
    return names_file.read_text().splitlines()


register(
    "pokemon",
    Provider(_pokemon_identities, lambda name: _pokemon_fetch(name, shiny=False)),
)
# Shiny is its own picker entry — a cheap wrapper over the pokemon source,
# sharing its cache under the -shiny suffix.
register(
    "shiny-pokemon",
    Provider(_pokemon_identities, lambda name: _pokemon_fetch(name, shiny=True)),
)


# ----- extraction (core, provider-blind) ----------------------------------


def gather_pixels(image_path: Path) -> tuple[list[Hsv], list[Hsv]]:
    """Split usable pixels into vivid and pale-but-tinted.

    Pale pixels (cream fins, pastel markings) are too washed to lead, but
    when a mascot has no second vivid hue they are the honest source of an
    accent — shiny gyarados is red plus cream-gold, not red plus anything
    invented.
    """
    img = Image.open(image_path).convert("RGBA")
    img.thumbnail((96, 96))
    vivid: list[Hsv] = []
    pale: list[Hsv] = []
    raw = img.tobytes()
    for i in range(0, len(raw), 4):
        r, g, b, a = raw[i : i + 4]
        if a < 128:
            continue
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        # Blacks and whites carry no hue information.
        if v < 0.2 or v > 0.98:
            continue
        if s >= 0.25:
            vivid.append((h, s, v))
        elif s >= 0.10:
            pale.append((h, s, v))
    if not vivid:
        raise SystemExit("error: image has no vivid pixels to extract from")
    return vivid, pale


def cluster_weights(pixels: list[Hsv]) -> list[float]:
    weights = [0.0] * HUE_BUCKETS
    for h, s, v in pixels:
        weights[int(h * HUE_BUCKETS) % HUE_BUCKETS] += s * v
    return weights


def bucket_distance(a: int, b: int) -> int:
    d = abs(a - b)
    return min(d, HUE_BUCKETS - d)


def representative(pixels: list[Hsv], bucket: int) -> Hsv:
    """The vivid heart of a cluster: mean of its most saturated quartile."""
    members = [
        p
        for p in pixels
        if bucket_distance(int(p[0] * HUE_BUCKETS) % HUE_BUCKETS, bucket) <= 1
    ]
    members.sort(key=lambda p: p[1] * p[2], reverse=True)
    top = members[: max(1, len(members) // 4)]
    # Hues within one bucket of each other never wrap far; recenter around the
    # bucket midpoint so the mean is safe at the 0/1 boundary.
    center = (bucket + 0.5) / HUE_BUCKETS
    hue = sum(((p[0] - center + 0.5) % 1.0) - 0.5 for p in top) / len(top) + center
    sat = sum(p[1] for p in top) / len(top)
    val = sum(p[2] for p in top) / len(top)
    return (hue % 1.0, sat, val)


def _best_secondary(
    weights: list[float], threshold: float, primary: int, min_separation: int
) -> int | None:
    candidates = [
        i
        for i in range(HUE_BUCKETS)
        if bucket_distance(i, primary) >= min_separation and weights[i] > threshold
    ]
    return max(candidates, key=lambda i: weights[i]) if candidates else None


def pick_pair(vivid: list[Hsv], pale: list[Hsv]) -> tuple[Hsv, Hsv]:
    """Accent = dominant vivid hue; notify = the most distinct OTHER
    hue actually present, searched in relaxing tiers: vivid at 45°+, vivid at
    30°+ (red-vs-gold pokemon), then pale clusters. Every color must exist on
    the mascot — with a single-hue mascot the pair is two brightnesses of
    its one hue, never an invented complement.
    """
    vivid_weights = cluster_weights(vivid)
    primary = max(range(HUE_BUCKETS), key=lambda i: vivid_weights[i])
    threshold = vivid_weights[primary] * SECOND_CLUSTER_MIN_WEIGHT
    accent = representative(vivid, primary)

    tiers: list[tuple[list[Hsv], list[float], int]] = [
        (vivid, vivid_weights, MIN_HUE_SEPARATION),
        (vivid, vivid_weights, MIN_HUE_SEPARATION - 1),
        (pale, cluster_weights(pale), MIN_HUE_SEPARATION - 1),
    ]
    for pixels, weights, separation in tiers:
        secondary = _best_secondary(weights, threshold, primary, separation)
        if secondary is not None:
            return accent, representative(pixels, secondary)
    return accent, accent


def styled(color: Hsv, *, dark_background: bool, bright: bool) -> str:
    """Pastel-but-vibrant, tuned per background mode."""
    h, s, _ = color
    if dark_background:
        s = min(max(s, 0.55), 0.85)
        v = 0.92 if bright else 0.85
    else:
        s = min(max(s, 0.65), 1.0)
        v = 0.70 if bright else 0.60
    r, g, b = colorsys.hsv_to_rgb(h, s, v)
    return f"#{int(r * 255):02x}{int(g * 255):02x}{int(b * 255):02x}"


USAGE = (
    "usage: mascot-accents <provider:id>"
    " | --providers | --identities <provider> | --values"
)


def qualified_values(providers: dict[str, Provider]) -> list[str]:
    """Every valid <provider:id> value; shell completion consumes this."""
    return [
        f"{name}:{identity}"
        for name, provider in providers.items()
        for identity in fetch_or_exit(provider.identities, f"identities for '{name}'")
    ]


def main() -> None:
    args = sys.argv[1:]
    if args == ["--providers"]:
        print("\n".join(PROVIDERS))
        return
    if args == ["--values"]:
        print("\n".join(qualified_values(PROVIDERS)))
        return
    if len(args) == 2 and args[0] == "--identities":
        provider = PROVIDERS.get(args[1])
        if provider is None:
            known = ", ".join(PROVIDERS)
            raise SystemExit(f"error: unknown provider '{args[1]}' (have: {known})")
        names = fetch_or_exit(provider.identities, f"identities for '{args[1]}'")
        print("\n".join(names))
        return
    if len(args) != 1:
        raise SystemExit(USAGE)
    value = args[0]
    provider, identity = resolve(value)
    images = fetch_or_exit(lambda: provider.fetch(identity), f"'{value}'")
    accent, notify = pick_pair(*gather_pixels(images.palette))
    print(f"mascot={value}")
    print(f"sprite={images.sprite}")
    print(f"accent_dark={styled(accent, dark_background=True, bright=False)}")
    print(f"notify_dark={styled(notify, dark_background=True, bright=True)}")
    print(f"accent_light={styled(accent, dark_background=False, bright=False)}")
    print(f"notify_light={styled(notify, dark_background=False, bright=True)}")


if __name__ == "__main__":
    main()
