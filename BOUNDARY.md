# BOUNDARY.md — dxf-llm と hakoniwa の境界（疎結合）

> **hakoniwa は独立プロジェクト。** dxf-llm（図面→パーツ変換）とは
> **データ契約のみ**でつながり、コードは相互 import しない。

---

## 依存の向き（片方向）

```
dxf-llm（生産者）                 hakoniwa（消費者）
  JWW/DXF ─► parts.json  ──────►  build_catalog ─► Catalog.luau ─► Roblox
             (.rbxmx)  契約               契約
```

- dxf-llm は **hakoniwa を知らない**（下流非依存）
- hakoniwa は **dxf-llm のコードを知らない**（生成物だけを読む）
- 接点は **契約 JSON / .rbxmx** のみ

---

## 契約: `hakoniwa-parts/v1`

スキーマ: [`contract/hakoniwa-parts.schema.json`](contract/hakoniwa-parts.schema.json)

```jsonc
// parts.json（配列）
[
  {
    "kind": "wall",                 // wall|column|window|door|beam|slab|stair|entourage|plant|vehicle|marker
    "layer": "wall",
    "size": [14.284, 8.5704, 0.4285],  // [x, y, z] studs
    "pos":  [7.142, 4.2852, 0.0],      // [x, y, z] studs
    "rot_y": 0.0,                      // 度（Y 軸回転）
    "rgb": [163, 162, 165]             // 0-255
  }
]
```

生成（dxf-llm 側）:
```bash
python recipes/jww2luau/jww2luau.py plan.dxf -o out/Building.luau --emit-json
#  → out/Building.json（= 契約 JSON）, out/Building.luau, （--rbxmx で .rbxmx）
```

消費（hakoniwa 側・本リポジトリ）:
```bash
python tools/build_catalog.py out/Building.json -o src/shared/Catalog.luau
```

---

## 規約（契約で固定する事項）

| 項目 | 規約 |
|---|---|
| 座標系 | DXF(x, y) → Roblox(x, z)、高さ y（変換は**生産者側**で完了） |
| 単位 | `size`/`pos` は **studs**（`studs_per_meter` で換算済み） |
| 色 | `rgb` 0–255（Roblox 側で `Color3.fromRGB`） |
| 回転 | `rot_y` は **度**、Y 軸回り |
| kind | 文字列 enum（[`src/shared/Types.luau`](src/shared/Types.luau) と一致） |
| 配列順 | `[x, y, z]` 固定（オブジェクト形式にしない） |

---

## バージョニング

- 契約名に版を含む: `hakoniwa-parts/v1`
- 破壊的変更は `v2` を新設し、`build_catalog` が両対応
- 生成側（dxf-llm）は `schema` フィールドを出力に含めてもよい（任意）

---

## 禁止事項（疎結合の維持）

- ❌ hakoniwa から `dxf_llm`（Python）を import する
- ❌ dxf-llm から `hakoniwa` のコードを参照する
- ❌ 共有の Python パッケージを作る（契約 JSON で足りる）
- ✅ 共有するのは **契約 JSON / スキーマ / .rbxmx** のみ

---

## 別経路（MCP / 手動）

- Roblox Studio MCP 経由で `.rbxmx` を投入（`recipes/jww2luau/mcp-studio.md` 相当）
- どちらの経路でも契約（`.rbxmx` の中身 = 契約の変換結果）は同じ
