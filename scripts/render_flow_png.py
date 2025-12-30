#!/usr/bin/env python3
from __future__ import annotations

import argparse
import math
import os
import textwrap
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from typing import Dict, Iterable, List, Optional, Tuple

from PIL import Image, ImageDraw, ImageFont


SF_NS = {"sf": "http://soap.sforce.com/2006/04/metadata"}


@dataclass
class Node:
    key: str
    type: str
    label: str
    x: float
    y: float
    w: int = 220
    h: int = 92
    meta: Dict[str, str] = field(default_factory=dict)


@dataclass
class Edge:
    src: str
    dst: str
    label: str = ""


def _t(el: Optional[ET.Element]) -> str:
    return (el.text or "").strip() if el is not None else ""


def _get(el: ET.Element, path: str) -> str:
    return _t(el.find(path, SF_NS))


def _get_int(el: ET.Element, path: str, default: int = 0) -> int:
    s = _get(el, path)
    try:
        return int(float(s))
    except Exception:
        return default


def parse_flow(xml_path: str) -> Tuple[Dict[str, Node], List[Edge], str]:
    tree = ET.parse(xml_path)
    root = tree.getroot()

    flow_label = _get(root, "sf:label") or os.path.basename(xml_path)

    nodes: Dict[str, Node] = {}
    edges: List[Edge] = []

    # Start
    start = root.find("sf:start", SF_NS)
    if start is not None:
        sx = _get_int(start, "sf:locationX", 50)
        sy = _get_int(start, "sf:locationY", 0)
        obj = _get(start, "sf:object") or "Record"
        trig = _get(start, "sf:triggerType")
        rtt = _get(start, "sf:recordTriggerType")
        # Make the start card more Flow-Builder-like and compact.
        trig_map = {
            "RecordAfterSave": "After Save",
            "RecordBeforeSave": "Before Save",
        }
        rtt_map = {
            "CreateAndUpdate": "Create & Update",
            "CreateOnly": "Create Only",
            "UpdateOnly": "Update Only",
        }
        start_label = f"Start\n{obj}"
        if trig:
            start_label += f"\n{trig_map.get(trig, trig)}"
        if rtt:
            start_label += f"\n{rtt_map.get(rtt, rtt)}"

        nodes["Start"] = Node(
            key="Start",
            type="Start",
            label=start_label,
            x=sx,
            y=sy,
            w=190,
            h=112,
        )

        start_target = _get(start, "sf:connector/sf:targetReference")
        if start_target:
            edges.append(Edge("Start", start_target, ""))

    # Decisions
    for d in root.findall("sf:decisions", SF_NS):
        name = _get(d, "sf:name")
        if not name:
            continue
        nodes[name] = Node(
            key=name,
            type="Decision",
            label=_get(d, "sf:label") or name,
            x=_get_int(d, "sf:locationX"),
            y=_get_int(d, "sf:locationY"),
            w=180,
            h=120,
        )

        # Default outcome
        default_target = _get(d, "sf:defaultConnector/sf:targetReference")
        default_label = _get(d, "sf:defaultConnectorLabel") or "Default Outcome"
        if default_target:
            edges.append(Edge(name, default_target, default_label))

        # Rules outcomes
        for rule in d.findall("sf:rules", SF_NS):
            out_label = _get(rule, "sf:label") or _get(rule, "sf:name") or "Outcome"
            out_target = _get(rule, "sf:connector/sf:targetReference")
            if out_target:
                edges.append(Edge(name, out_target, out_label))
            else:
                # Terminal outcome -> implicit End node
                end_key = f"End__{name}__{out_label}".replace(" ", "_")
                nodes[end_key] = Node(
                    key=end_key,
                    type="End",
                    label="End",
                    x=nodes[name].x - 240,
                    y=nodes[name].y + 160,
                    w=56,
                    h=56,
                )
                edges.append(Edge(name, end_key, out_label))

    # Record Lookups
    for rl in root.findall("sf:recordLookups", SF_NS):
        name = _get(rl, "sf:name")
        if not name:
            continue
        nodes[name] = Node(
            key=name,
            type="Get Records",
            label=_get(rl, "sf:label") or name,
            x=_get_int(rl, "sf:locationX"),
            y=_get_int(rl, "sf:locationY"),
        )
        target = _get(rl, "sf:connector/sf:targetReference")
        if target:
            edges.append(Edge(name, target, ""))
        else:
            end_key = f"End__{name}"
            nodes[end_key] = Node(
                key=end_key, type="End", label="End", x=nodes[name].x, y=nodes[name].y + 160, w=56, h=56
            )
            edges.append(Edge(name, end_key, ""))

    # Record Creates
    for rc in root.findall("sf:recordCreates", SF_NS):
        name = _get(rc, "sf:name")
        if not name:
            continue
        nodes[name] = Node(
            key=name,
            type="Create Records",
            label=_get(rc, "sf:label") or name,
            x=_get_int(rc, "sf:locationX"),
            y=_get_int(rc, "sf:locationY"),
        )
        target = _get(rc, "sf:connector/sf:targetReference")
        if target:
            edges.append(Edge(name, target, ""))
        else:
            end_key = f"End__{name}"
            nodes[end_key] = Node(
                key=end_key, type="End", label="End", x=nodes[name].x, y=nodes[name].y + 160, w=56, h=56
            )
            edges.append(Edge(name, end_key, ""))

    # Record Updates
    for ru in root.findall("sf:recordUpdates", SF_NS):
        name = _get(ru, "sf:name")
        if not name:
            continue
        nodes[name] = Node(
            key=name,
            type="Update Records",
            label=_get(ru, "sf:label") or name,
            x=_get_int(ru, "sf:locationX"),
            y=_get_int(ru, "sf:locationY"),
        )
        target = _get(ru, "sf:connector/sf:targetReference")
        if target:
            edges.append(Edge(name, target, ""))
        else:
            end_key = f"End__{name}"
            nodes[end_key] = Node(
                key=end_key, type="End", label="End", x=nodes[name].x, y=nodes[name].y + 160, w=56, h=56
            )
            edges.append(Edge(name, end_key, ""))

    # Nudge any generated End nodes if they overlap too much (simple de-overlap).
    ends = [n for n in nodes.values() if n.type == "End"]
    ends.sort(key=lambda n: (n.x, n.y))
    for i, n in enumerate(ends):
        for j in range(i):
            o = ends[j]
            if abs(n.x - o.x) < 80 and abs(n.y - o.y) < 80:
                n.y += 90

    return nodes, edges, flow_label


def _load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ]
    for p in candidates:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size=size)
            except Exception:
                pass
    return ImageFont.load_default()


def _rounded_rect(draw: ImageDraw.ImageDraw, box: Tuple[int, int, int, int], r: int, fill, outline, width: int = 2):
    draw.rounded_rectangle(box, radius=r, fill=fill, outline=outline, width=width)


def _shadow(draw: ImageDraw.ImageDraw, box: Tuple[int, int, int, int], r: int, offset: Tuple[int, int] = (3, 3)):
    x0, y0, x1, y1 = box
    ox, oy = offset
    draw.rounded_rectangle((x0 + ox, y0 + oy, x1 + ox, y1 + oy), radius=r, fill=(0, 0, 0, 28), outline=None)


def _wrap(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.ImageFont, max_w: int) -> List[str]:
    text = (text or "").strip()
    if not text:
        return [""]
    # Respect explicit newlines first
    parts = []
    for para in text.splitlines():
        para = para.rstrip()
        if not para:
            parts.append("")
            continue
        words = para.split(" ")
        line = ""
        for w in words:
            cand = (line + " " + w).strip()
            if draw.textlength(cand, font=font) <= max_w or not line:
                line = cand
            else:
                parts.append(line)
                line = w
        if line:
            parts.append(line)
    return parts


def _arrowhead(p1: Tuple[int, int], p2: Tuple[int, int], size: int = 9) -> List[Tuple[int, int]]:
    x1, y1 = p1
    x2, y2 = p2
    ang = math.atan2(y2 - y1, x2 - x1)
    left = (x2 - size * math.cos(ang - math.pi / 6), y2 - size * math.sin(ang - math.pi / 6))
    right = (x2 - size * math.cos(ang + math.pi / 6), y2 - size * math.sin(ang + math.pi / 6))
    return [(x2, y2), (int(left[0]), int(left[1])), (int(right[0]), int(right[1]))]


def _bbox_centered(node: Node, sx: float, sy: float) -> Tuple[int, int, int, int]:
    cx = int(node.x * sx)
    cy = int(node.y * sy)
    return (cx - node.w // 2, cy - node.h // 2, cx + node.w // 2, cy + node.h // 2)


def _anchor(node: Node, other: Node, sx: float, sy: float) -> Tuple[int, int]:
    """Pick an attachment point based on relative position."""
    box = _bbox_centered(node, sx, sy)
    x0, y0, x1, y1 = box
    cx = (x0 + x1) // 2
    cy = (y0 + y1) // 2

    obox = _bbox_centered(other, sx, sy)
    ocx = (obox[0] + obox[2]) // 2
    ocy = (obox[1] + obox[3]) // 2

    dx = ocx - cx
    dy = ocy - cy
    if abs(dx) > abs(dy):
        return (x1, cy) if dx > 0 else (x0, cy)
    return (cx, y1) if dy > 0 else (cx, y0)


def render(nodes: Dict[str, Node], edges: List[Edge], title: str, out_png: str, scale: float = 1.35):
    sx = sy = scale

    # Compute extents
    minx = min(n.x - (n.w / 2) / sx for n in nodes.values())
    miny = min(n.y - (n.h / 2) / sy for n in nodes.values())
    maxx = max(n.x + (n.w / 2) / sx for n in nodes.values())
    maxy = max(n.y + (n.h / 2) / sy for n in nodes.values())

    pad = 90
    w = int((maxx - minx) * sx) + pad * 2
    h = int((maxy - miny) * sy) + pad * 2 + 70

    # Rebase positions so min is within padding
    for n in nodes.values():
        n.x = (n.x - minx) + (pad / sx)
        n.y = (n.y - miny) + ((pad + 70) / sy)

    img = Image.new("RGBA", (w, h), (243, 242, 242, 255))  # SLDS-ish canvas
    draw = ImageDraw.Draw(img, "RGBA")

    # Grid (subtle, Flow Builder-like)
    grid = 48
    for x in range(0, w, grid):
        draw.line((x, 0, x, h), fill=(0, 0, 0, 3))
    for y in range(0, h, grid):
        draw.line((0, y, w, y), fill=(0, 0, 0, 3))

    # Title bar
    draw.rectangle((0, 0, w, 56), fill=(255, 255, 255, 255))
    draw.line((0, 56, w, 56), fill=(0, 0, 0, 40), width=1)
    font_title = _load_font(18)
    draw.text((18, 18), title, fill=(24, 24, 24, 255), font=font_title)

    font_header = _load_font(12)
    font_body = _load_font(13)
    font_small = _load_font(11)

    palette = {
        "Decision": (1, 118, 211),
        "Get Records": (125, 85, 199),
        "Create Records": (0, 161, 164),
        "Update Records": (254, 147, 57),
        "Start": (45, 157, 80),
        "End": (108, 117, 125),
    }

    # Draw edges under nodes
    for e in edges:
        if e.src not in nodes or e.dst not in nodes:
            continue
        a = nodes[e.src]
        b = nodes[e.dst]
        p1 = _anchor(a, b, sx, sy)
        p2 = _anchor(b, a, sx, sy)
        x1, y1 = p1
        x2, y2 = p2

        # Orthogonal route
        midy = (y1 + y2) // 2
        points = [(x1, y1), (x1, midy), (x2, midy), (x2, y2)]
        draw.line(points, fill=(90, 90, 90, 255), width=2, joint="curve")

        ah = _arrowhead(points[-2], points[-1], size=10)
        draw.polygon(ah, fill=(90, 90, 90, 255))

        if (e.label or "").strip():
            # label pill near center segment
            lx, ly = points[1]
            lx2, ly2 = points[2]
            cx = (lx + lx2) // 2
            cy = (ly + ly2) // 2 - 14
            txt = e.label.strip()
            tw = int(draw.textlength(txt, font=font_small))
            box = (cx - tw // 2 - 10, cy - 8, cx + tw // 2 + 10, cy + 10)
            _shadow(draw, box, r=10, offset=(2, 2))
            _rounded_rect(draw, box, r=10, fill=(255, 255, 255, 245), outline=(0, 0, 0, 40), width=1)
            draw.text((box[0] + 10, box[1] + 1), txt, fill=(45, 45, 45, 255), font=font_small)

    # Draw nodes
    for n in nodes.values():
        box = _bbox_centered(n, sx, sy)
        x0, y0, x1, y1 = box

        if n.type == "Decision":
            # shadow
            cx = (x0 + x1) // 2
            cy = (y0 + y1) // 2
            hw = (x1 - x0) // 2
            hh = (y1 - y0) // 2
            diamond = [(cx, y0), (x1, cy), (cx, y1), (x0, cy)]
            diamond_shadow = [(px + 3, py + 3) for px, py in diamond]
            draw.polygon(diamond_shadow, fill=(0, 0, 0, 28))

            col = palette["Decision"]
            draw.polygon(diamond, fill=(255, 255, 255, 255), outline=col)
            draw.line(diamond, fill=col, width=2)

            # label
            lines = _wrap(draw, n.label, font_body, max_w=150)
            total_h = len(lines) * 16
            ty = cy - total_h // 2
            draw.text((cx - 58, y0 + 8), "Decision", fill=(col[0], col[1], col[2], 255), font=font_header)
            for i, line in enumerate(lines[:4]):
                tw = int(draw.textlength(line, font=font_body))
                draw.text((cx - tw // 2, ty + i * 16 + 10), line, fill=(24, 24, 24, 255), font=font_body)

        elif n.type == "End":
            r = min(n.w, n.h) // 2
            cx = (x0 + x1) // 2
            cy = (y0 + y1) // 2
            draw.ellipse((cx - r + 3, cy - r + 3, cx + r + 3, cy + r + 3), fill=(0, 0, 0, 28))
            draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(255, 255, 255, 255), outline=(0, 0, 0, 70), width=2)
            txt = "End"
            tw = int(draw.textlength(txt, font=font_small))
            draw.text((cx - tw // 2, cy - 6), txt, fill=(60, 60, 60, 255), font=font_small)

        else:
            col = palette.get(n.type, (1, 118, 211))
            _shadow(draw, box, r=14, offset=(3, 3))
            _rounded_rect(draw, box, r=14, fill=(255, 255, 255, 255), outline=(0, 0, 0, 55), width=2)

            # Header band
            header_h = 24
            _rounded_rect(draw, (x0, y0, x1, y0 + header_h), r=14, fill=(*col, 255), outline=None, width=0)
            draw.rectangle((x0, y0 + header_h - 10, x1, y0 + header_h), fill=(*col, 255))
            draw.text((x0 + 12, y0 + 6), n.type, fill=(255, 255, 255, 255), font=font_header)

            # Body label
            lines = _wrap(draw, n.label, font_body, max_w=(x1 - x0 - 24))
            ty = y0 + header_h + 10
            for i, line in enumerate(lines[:4]):
                draw.text((x0 + 12, ty + i * 18), line, fill=(24, 24, 24, 255), font=font_body)

    img.convert("RGBA").save(out_png, format="PNG")


def main():
    ap = argparse.ArgumentParser(description="Render a Salesforce Flow XML into a Flow Builder-style PNG.")
    ap.add_argument("--in", dest="inp", required=True, help="Path to Flow XML (flow-meta.xml).")
    ap.add_argument("--out", dest="out", required=True, help="Output PNG path.")
    ap.add_argument("--scale", dest="scale", type=float, default=1.35, help="Canvas scale factor.")
    args = ap.parse_args()

    nodes, edges, title = parse_flow(args.inp)
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    render(nodes, edges, title=title, out_png=args.out, scale=args.scale)


if __name__ == "__main__":
    main()

