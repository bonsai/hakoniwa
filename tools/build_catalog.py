#!/usr/bin/env python
"""build_catalog — 契約 JSON または DXF から Catalog.luau を生成（hakoniwa 側）

dxf-llm とは **コード非依存**（契約 JSON のみ / BOUNDARY.md）。
契約 JSON は dxf-llm 側で生成:
    python recipes/jww2luau/jww2luau.py plan.dxf --emit-json

使い方（本リポジトリ）:
    python tools/build_catalog.py parts.json -o src/shared/Catalog.luau
    python tools/build_catalog.py plan.dxf   -o src/shared/Catalog.luau

ライセンス: MIT / PyDXF Japan
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

# kind -> Roblox Material 名
MATERIAL = {
    "wall": "Concrete",
    "column": "Concrete",
    "window": "Glass",
    "door": "Wood",
    "beam": "WoodPlanks",
    "slab": "Concrete",
    "stair": "Concrete",
    "entourage": "SmoothPlastic",
    "plant": "Grass",
    "vehicle": "Metal",
    "marker": "SmoothPlastic",
}

NAME_JA = {
    "wall": "壁",
    "column": "柱",
    "window": "窓",
    "door": "扉",
    "beam": "梁",
    "slab": "床",
    "stair": "階段",
    "entourage": "人物",
    "plant": "植栽",
    "vehicle": "車",
    "marker": "その他",
}

# レイヤ名 -> kind（DXF 直読み時のフォールバック）
LAYER_RULES = {
    "wall": "wall", "壁": "wall",
    "column": "column", "柱": "column",
    "window": "window", "窓": "window",
    "door": "door", "扉": "door", "ドア": "door",
    "beam": "beam", "梁": "beam",
    "slab": "slab", "床": "slab",
    "stair": "stair", "階段": "stair",
    "添景": "entourage", "人物": "entourage", "person": "entourage",
    "植栽": "plant", "樹": "plant", "木": "plant", "tree": "plant",
    "車": "vehicle", "car": "vehicle",
}

DEFAULT_COLOR = (163, 162, 165)


# --- 入力読み込み ------------------------------------------------------------

def _piece(kind: str, size, pos, rot_y, rgb, layer: str = "") -> Dict[str, Any]:
    return {
        "kind": kind,
        "layer": layer,
        "size": [float(v) for v in size],
        "pos": [float(v) for v in pos],
        "rot_y": float(rot_y),
        "rgb": [int(v) for v in rgb],
    }


def load_contract_json(path: str) -> List[Dict[str, Any]]:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, list):
        raise ValueError("契約 JSON は配列である必要があります（hakoniwa-parts/v1）")
    return data


def load_dxf(dxf_path: str, studs_per_meter: float = 3.571) -> List[Dict[str, Any]]:
    """DXF を直接読んで代表パーツを作る（standalone / ezdxf）。"""
    try:
        import ezdxf
        import math
    except ImportError:
        print("DXF 直読みには ezdxf が必要です: pip install ezdxf", file=sys.stderr)
        raise

    f = studs_per_meter / 1000.0  # mm -> studs
    doc = ezdxf.readfile(dxf_path)
    pieces: List[Dict[str, Any]] = []

    def kind_of(layer: str) -> str:
        low = (layer or "").lower()
        for k, v in LAYER_RULES.items():
            if k.lower() in low:
                return v
        return "marker"

    def emit(kind: str, length_mm: float, mm_per_axis: float, layer: str, height_mm: float, thick_mm: float) -> None:
        if length_mm < 10:
            return
        pieces.append(_piece(
            kind,
            size=(length_mm * f, height_mm * f, thick_mm * f),
            pos=(mm_per_axis, height_mm / 2.0 * f, 0.0),
            rot_y=0.0,
            rgb=DEFAULT_COLOR,
            layer=layer,
        ))

    for e in doc.modelspace():
        t = e.dxftype()
        layer = e.dxf.get("layer", "0")
        kind = kind_of(layer)
        if t == "LINE":
            s, en = e.dxf.start, e.dxf.end
            length = ((en.x - s.x) ** 2 + (en.y - s.y) ** 2) ** 0.5
            pieces.append(_piece(
                kind,
                size=(length * f, 2.4 * 3.571, 0.12 * 3.571),
                pos=((s.x + en.x) / 2 * f, 1.2 * 3.571, (s.y + en.y) / 2 * f),
                rot_y=0.0, rgb=DEFAULT_COLOR, layer=layer,
            ))
        elif t in ("LWPOLYLINE", "POLYLINE"):
            try:
                pts = list(e.get_points("xy")) if t == "LWPOLYLINE" else [(v.dxf.location.x, v.dxf.location.y) for v in e.vertices]
            except Exception:
                pts = []
            for i in range(len(pts) - 1):
                (x1, y1), (x2, y2) = pts[i], pts[i + 1]
                length = ((x2 - x1) ** 2 + (y2 - y1) ** 2) ** 0.5
                pieces.append(_piece(
                    kind,
                    size=(length * f, 2.4 * 3.571, 0.12 * 3.571),
                    pos=((x1 + x2) / 2 * f, 1.2 * 3.571, (y1 + y2) / 2 * f),
                    rot_y=0.0, rgb=DEFAULT_COLOR, layer=layer,
                ))
    return pieces


def load_parts(path: str) -> List[Dict[str, Any]]:
    p = path.lower()
    if p.endswith(".json"):
        return load_contract_json(path)
    if p.endswith(".dxf"):
        return load_dxf(path)
    raise ValueError(f"未対応の入力: {path}（.json または .dxf）")


# --- 集約 → カタログ項目 ------------------------------------------------------

def to_catalog_items(parts: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """kind ごとに代表 1 件（最長）をカタログ項目にする。"""
    groups: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
    for p in parts:
        groups[p.get("kind", "marker")].append(p)

    items = []
    for kind, ps in sorted(groups.items()):
        rep = max(ps, key=lambda x: float(x["size"][0]) * float(x["size"][1]) * float(x["size"][2]))
        size = [round(float(v), 4) for v in rep["size"]]
        rgb = [int(v) for v in rep.get("rgb", DEFAULT_COLOR)]
        items.append({
            "id": f"{kind}_1",
            "name": NAME_JA.get(kind, kind),
            "kind": kind,
            "size": size,
            "rgb": rgb,
            "material": MATERIAL.get(kind, "SmoothPlastic"),
        })
    return items


# --- Luau 出力 ---------------------------------------------------------------

HEADER = """--!strict
-- Catalog — 配置可能パーツ定義（tools/build_catalog.py で自動生成。手書き編集しない）
-- 契約: hakoniwa-parts/v1  (BOUNDARY.md)
-- items: {n}

local Types = require(script.Parent.Types)

local Catalog = {{}}

Catalog.items = {{
{body}
}} :: {{ Types.CatalogItem }}

function Catalog.get(id: string): Types.CatalogItem?
	for _, item in ipairs(Catalog.items) do
		if item.id == id then
			return item
		end
	end
	return nil
end

function Catalog.all(): {{ Types.CatalogItem }}
	return Catalog.items
end

return Catalog
"""


def to_luau(items: List[Dict[str, Any]]) -> str:
    lines = []
    for it in items:
        x, y, z = it["size"]
        r, g, b = it["rgb"]
        lines.append(
            "\t{\n"
            f"\t\tid = {it['id']!r}, name = {it['name']!r}, kind = {it['kind']!r},\n"
            f"\t\tsize = Vector3.new({x}, {y}, {z}),\n"
            f"\t\tcolor = Color3.fromRGB({r}, {g}, {b}),\n"
            f"\t\tmaterial = Enum.Material.{it['material']},\n"
            "\t},"
        )
    return HEADER.format(n=len(items), body="\n".join(lines))


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description="契約 JSON / DXF -> Catalog.luau")
    ap.add_argument("input", help="契約 JSON (hakoniwa-parts/v1) または DXF")
    ap.add_argument("-o", "--output", default="src/shared/Catalog.luau")
    ap.add_argument("--emit-json", action="store_true", help="集約後の JSON も出力")
    args = ap.parse_args(argv)

    parts = load_parts(args.input)
    items = to_catalog_items(parts)

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(to_luau(items), encoding="utf-8")
    print(f"Catalog 出力: {out} ({len(items)} 項目 / {len(parts)} パーツ)")

    if args.emit_json:
        jpath = out.with_suffix(".json")
        jpath.write_text(json.dumps(items, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"JSON 出力: {jpath}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
