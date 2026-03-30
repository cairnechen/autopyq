#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
import sys
from collections import deque
from dataclasses import dataclass
from pathlib import Path
from statistics import median
from typing import Iterable, Sequence

from PIL import Image


@dataclass(frozen=True)
class Rect:
    x: int
    y: int
    w: int
    h: int

    @property
    def x2(self) -> int:
        return self.x + self.w

    @property
    def y2(self) -> int:
        return self.y + self.h

    def clamp(self, width: int, height: int) -> "Rect":
        if self.w <= 0 or self.h <= 0:
            raise ValueError("Rectangle width and height must be positive.")
        if self.x < 0 or self.y < 0:
            raise ValueError("Rectangle x and y must be non-negative.")
        if self.x2 > width or self.y2 > height:
            raise ValueError(
                f"Rectangle {self.x},{self.y},{self.w},{self.h} exceeds image bounds {width}x{height}."
            )
        return self

    def to_json(self) -> dict[str, int]:
        return {"x": self.x, "y": self.y, "w": self.w, "h": self.h}


@dataclass(frozen=True)
class Component:
    x: int
    y: int
    w: int
    h: int
    area: int

    @property
    def x2(self) -> int:
        return self.x + self.w

    @property
    def y2(self) -> int:
        return self.y + self.h

    def to_json(self) -> dict[str, int]:
        return {"x": self.x, "y": self.y, "w": self.w, "h": self.h, "area": self.area}


def emit(payload: dict, exit_code: int = 0) -> int:
    print(json.dumps(payload, ensure_ascii=False))
    return exit_code


def fail(message: str, **extra: object) -> int:
    payload: dict[str, object] = {"ok": False, "error": message}
    payload.update(extra)
    return emit(payload, 1)


def load_rgb(path: str | Path) -> Image.Image:
    with Image.open(path) as image:
        return image.convert("RGB")


def parse_region(region: str) -> Rect:
    try:
        x, y, w, h = [int(part.strip()) for part in region.split(",")]
    except Exception as exc:  # pragma: no cover - defensive path
        raise ValueError(f"Invalid region '{region}'. Expected x,y,w,h.") from exc
    return Rect(x, y, w, h)


def pixel_luma(pixel: Sequence[int]) -> float:
    r, g, b = pixel
    return 0.299 * r + 0.587 * g + 0.114 * b


def color_distance(a: Sequence[int], b: Sequence[int]) -> int:
    return abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])


def percentile(values: Sequence[float], pct: float) -> float:
    if not values:
        raise ValueError("Cannot compute percentile of empty values.")
    if len(values) == 1:
        return float(values[0])
    ordered = sorted(values)
    index = max(0.0, min(1.0, pct / 100.0)) * (len(ordered) - 1)
    lower = math.floor(index)
    upper = math.ceil(index)
    if lower == upper:
        return float(ordered[lower])
    ratio = index - lower
    return float(ordered[lower] * (1.0 - ratio) + ordered[upper] * ratio)


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def border_pixels(image: Image.Image) -> list[tuple[int, int, int]]:
    width, height = image.size
    pixels = image.load()
    samples: list[tuple[int, int, int]] = []
    for x in range(width):
        samples.append(pixels[x, 0])
        if height > 1:
            samples.append(pixels[x, height - 1])
    for y in range(1, max(1, height - 1)):
        samples.append(pixels[0, y])
        if width > 1:
            samples.append(pixels[width - 1, y])
    return samples


def estimate_background(image: Image.Image) -> tuple[int, int, int]:
    border = border_pixels(image)
    if not border:
        pixels = list(image.getdata())
        border = pixels if pixels else [(255, 255, 255)]
    channels = list(zip(*border))
    return tuple(int(round(median(channel))) for channel in channels)  # type: ignore[arg-type]


def build_component_mask(
    image: Image.Image,
    polarity: str,
    distance_threshold: int = 18,
    luma_delta: float = 8.0,
) -> list[list[bool]]:
    pixels = image.load()
    width, height = image.size
    background = estimate_background(image)
    background_luma = pixel_luma(background)
    mask = [[False for _ in range(width)] for _ in range(height)]
    for y in range(height):
        for x in range(width):
            pixel = pixels[x, y]
            dist = color_distance(pixel, background)
            if dist < distance_threshold:
                continue
            luma = pixel_luma(pixel)
            if polarity == "dark":
                if luma <= background_luma - luma_delta:
                    mask[y][x] = True
            else:
                if luma >= background_luma + luma_delta:
                    mask[y][x] = True
    return mask


def connected_components(mask: list[list[bool]]) -> list[Component]:
    height = len(mask)
    width = len(mask[0]) if height else 0
    visited = [[False for _ in range(width)] for _ in range(height)]
    components: list[Component] = []
    neighbors = (
        (-1, -1), (0, -1), (1, -1),
        (-1, 0),           (1, 0),
        (-1, 1),  (0, 1),  (1, 1),
    )

    for start_y in range(height):
        for start_x in range(width):
            if not mask[start_y][start_x] or visited[start_y][start_x]:
                continue
            queue: deque[tuple[int, int]] = deque([(start_x, start_y)])
            visited[start_y][start_x] = True
            min_x = max_x = start_x
            min_y = max_y = start_y
            area = 0

            while queue:
                x, y = queue.popleft()
                area += 1
                min_x = min(min_x, x)
                max_x = max(max_x, x)
                min_y = min(min_y, y)
                max_y = max(max_y, y)
                for dx, dy in neighbors:
                    nx = x + dx
                    ny = y + dy
                    if 0 <= nx < width and 0 <= ny < height and mask[ny][nx] and not visited[ny][nx]:
                        visited[ny][nx] = True
                        queue.append((nx, ny))

            components.append(Component(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1, area))

    return components


def select_component(components: list[Component], select: str) -> Component:
    if not components:
        raise ValueError("No component found.")
    if select == "largest":
        return max(components, key=lambda item: (item.area, item.w * item.h, item.y, item.x))
    if select == "topmost":
        return min(components, key=lambda item: (item.y, item.x, -item.area))
    if select == "bottommost":
        return max(components, key=lambda item: (item.y2, item.area, -item.x))
    if select == "leftmost":
        return min(components, key=lambda item: (item.x, item.y, -item.area))
    if select == "rightmost":
        return max(components, key=lambda item: (item.x2, item.area, -item.y))
    raise ValueError(f"Unsupported select mode '{select}'.")


def union_bbox(components: Iterable[Component]) -> Rect:
    items = list(components)
    if not items:
        raise ValueError("No components available for union.")
    min_x = min(item.x for item in items)
    min_y = min(item.y for item in items)
    max_x = max(item.x2 for item in items)
    max_y = max(item.y2 for item in items)
    return Rect(min_x, min_y, max_x - min_x, max_y - min_y)


def detect_template_pattern(template: Image.Image) -> tuple[str, float, float]:
    background = estimate_background(template)
    background_luma = pixel_luma(background)
    distances: list[float] = []
    luma_deltas: list[float] = []
    dark_votes = 0
    light_votes = 0
    pixels = template.load()
    width, height = template.size
    for y in range(height):
        for x in range(width):
            pixel = pixels[x, y]
            dist = color_distance(pixel, background)
            if dist < 4:
                continue
            delta = pixel_luma(pixel) - background_luma
            if delta <= 0:
                dark_votes += 1
            else:
                light_votes += 1
            distances.append(float(dist))
            luma_deltas.append(abs(delta))

    if not distances:
        return ("dark", 4.0, 1.0)

    polarity = "dark" if dark_votes >= light_votes else "light"
    return (
        polarity,
        max(4.0, percentile(distances, 5.0) * 0.75),
        max(1.0, percentile(luma_deltas, 5.0) * 0.5),
    )


def build_text_mask(
    image: Image.Image,
    template: Image.Image,
) -> list[list[bool]]:
    polarity, distance_threshold, luma_delta = detect_template_pattern(template)
    pixels = image.load()
    width, height = image.size
    background = estimate_background(image)
    background_luma = pixel_luma(background)
    mask = [[False for _ in range(width)] for _ in range(height)]
    for y in range(height):
        for x in range(width):
            pixel = pixels[x, y]
            dist = color_distance(pixel, background)
            if dist < distance_threshold:
                continue
            delta = pixel_luma(pixel) - background_luma
            if polarity == "dark":
                if delta <= -luma_delta:
                    mask[y][x] = True
            else:
                if delta >= luma_delta:
                    mask[y][x] = True
    return mask


def command_crop(args: argparse.Namespace) -> int:
    image = load_rgb(args.input)
    region = Rect(args.x, args.y, args.w, args.h).clamp(*image.size)
    crop = image.crop((region.x, region.y, region.x2, region.y2))
    output = Path(args.output)
    ensure_parent(output)
    crop.save(output)
    return emit({"ok": True, "out": str(output), **region.to_json()})


def command_info(args: argparse.Namespace) -> int:
    image = load_rgb(args.input)
    width, height = image.size
    return emit({"ok": True, "w": width, "h": height})


def command_find_component(args: argparse.Namespace) -> int:
    image = load_rgb(args.input)
    region = parse_region(args.region).clamp(*image.size)
    cropped = image.crop((region.x, region.y, region.x2, region.y2))
    mask = build_component_mask(cropped, args.polarity)
    components = [component for component in connected_components(mask) if component.area >= args.min_area]
    if not components:
        return fail("No matching component found.", command="find-component", region=region.to_json())

    component = select_component(components, args.select)
    absolute = Component(
        region.x + component.x,
        region.y + component.y,
        component.w,
        component.h,
        component.area,
    )
    return emit({"ok": True, **absolute.to_json(), "region": region.to_json(), "components": len(components)})


def command_find_text_bbox(args: argparse.Namespace) -> int:
    image = load_rgb(args.input)
    template = load_rgb(args.template)
    region = parse_region(args.region).clamp(*image.size)
    cropped = image.crop((region.x, region.y, region.x2, region.y2))
    mask = build_text_mask(cropped, template)
    components = connected_components(mask)
    if not components:
        return fail("No text-like pixels found.", command="find-text-bbox", region=region.to_json())

    largest_area = max(component.area for component in components)
    keep = [
        component
        for component in components
        if component.area >= max(2, int(math.ceil(largest_area * 0.03)))
    ]
    if not keep:
        return fail("No usable text components found.", command="find-text-bbox", region=region.to_json())

    bbox = union_bbox(keep)
    padding = max(0, min(1, int(args.padding)))
    x = max(0, bbox.x - padding)
    y = max(0, bbox.y - padding)
    x2 = min(cropped.size[0], bbox.x2 + padding)
    y2 = min(cropped.size[1], bbox.y2 + padding)
    absolute = Rect(region.x + x, region.y + y, x2 - x, y2 - y)
    return emit({"ok": True, **absolute.to_json(), "region": region.to_json(), "components": len(keep)})


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Image helper for WeChat Moments template capture.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    info_parser = subparsers.add_parser("info", help="Read image dimensions.")
    info_parser.add_argument("--in", dest="input", required=True)
    info_parser.set_defaults(func=command_info)

    crop_parser = subparsers.add_parser("crop", help="Crop an image by rectangle.")
    crop_parser.add_argument("--in", dest="input", required=True)
    crop_parser.add_argument("--out", dest="output", required=True)
    crop_parser.add_argument("--x", type=int, required=True)
    crop_parser.add_argument("--y", type=int, required=True)
    crop_parser.add_argument("--w", type=int, required=True)
    crop_parser.add_argument("--h", type=int, required=True)
    crop_parser.set_defaults(func=command_crop)

    component_parser = subparsers.add_parser("find-component", help="Find a dark or light connected component in a small region.")
    component_parser.add_argument("--in", dest="input", required=True)
    component_parser.add_argument("--region", required=True, help="x,y,w,h")
    component_parser.add_argument("--polarity", choices=("dark", "light"), required=True)
    component_parser.add_argument("--min-area", type=int, default=20)
    component_parser.add_argument(
        "--select",
        choices=("largest", "topmost", "bottommost", "leftmost", "rightmost"),
        default="largest",
    )
    component_parser.set_defaults(func=command_find_component)

    text_parser = subparsers.add_parser("find-text-bbox", help="Find a text bounding box inside a narrowed region.")
    text_parser.add_argument("--in", dest="input", required=True)
    text_parser.add_argument("--region", required=True, help="x,y,w,h")
    text_parser.add_argument("--template", required=True)
    text_parser.add_argument("--padding", type=int, default=0)
    text_parser.set_defaults(func=command_find_text_bbox)

    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return int(args.func(args))
    except Exception as exc:
        return fail(str(exc), command=getattr(args, "command", None))


if __name__ == "__main__":
    sys.exit(main())
