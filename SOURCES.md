# SOURCES.md — 建築・防災 7ソースを Luau で扱う構成

> 箱庭に効く **建築（4）＋ 防災（3）＝ 7 つのソース**を定義し、
> それぞれを **Luau モジュール**として扱う。

---

## 7 ソース

| # | ソース | 区分 | 由来（一次データ） | 箱庭での役割 |
|---|---|---|---|---|
| S1 | **図面** Drawing | 建築 | JWW/DXF（dxf-llm 契約JSON / rbxmx） | 建物・壁・柱・開口 |
| S2 | **構造** Structure | 建築 | 内部 FEM（`Fem.luau`） | 応力・変形・折れる |
| S3 | **設備** MEP | 建築 | JWW《設備》《電気》レイヤ | 配管・ダクト・配線・器具 |
| S4 | **法規** Code | 建築 | 建築基準法/消防法（ルールセット） | 防火・避難・用途制限 |
| S5 | **地象** Geospatial | 防災 | 国土地理院 標高/基盤地図 | 地形・地盤・標高 |
| S6 | **気象** Weather | 防災 | 気象庁（JMA）オープンデータ | 雨・風・気温・注意報 |
| S7 | **ハザード** Hazard | 防災 | 国土数値情報/自治体ハザードマップ | 洪水・津波・土砂・地震 |

分類: **S1–S4 = 建築**, **S5–S7 = 防災**。

---

## 2 フェーズ構成（Roblox 制約への対応）

Roblox は実行時に任意の外部 HTTP を叩けない（`HttpService` は allowlist）。
そこで **bake（ビルド時）→ apply（実行時）** の 2 段にする。

```
┌── bake（ビルド時 / Python・tools）──────────────────────────┐
│  一次データ取得 → 正規化 → Luau データモジュールへ出力        │
│  tools/bake_*.py → src/shared/sources/data/<source>.luau      │
└──────────────────────────────────────────────────────────────┘
                          │ Rojo 同期
                          ▼
┌── apply（実行時 / Roblox・Luau）────────────────────────────┐
│  Source.load() → Source.apply(world)                          │
│  7 ソースを Bundle に集約して箱庭へ適用                        │
└──────────────────────────────────────────────────────────────┘
```

**ポイント**: 各ソースは「焼き込み済み Luau モジュール」を持つ。実行時は
ネット不要・決定的。更新は bake を再実行して同期。

---

## Luau インターフェース（共通）

```lua
--!strict
export type SourceCategory = "architecture" | "disaster"

export type Source = {
    id: string,
    name: string,
    category: SourceCategory,
    schema: string,                          -- 契約スキーマ名
    load: (ctx: Context) -> any,             -- 焼き込みデータを読む
    apply: (world: World, data: any) -> (),  -- 箱庭へ反映
    validate: (data: any) -> (boolean, string?),
}

export type Bundle = { [string]: any }       -- sourceId -> data
```

---

## フォルダ構成

```
src/shared/sources/
├── init.luau              SourceRegistry（登録・取得・loadAll/applyAll）
├── Types.luau             共通型（Source / Bundle）
├── Config.luau            有効化・バインド設定
├── DrawingSource.luau     S1 図面
├── StructureSource.luau   S2 構造（Fem 利用）
├── MepSource.luau         S3 設備・電気
├── CodeSource.luau        S4 法規
├── GeospatialSource.luau  S5 地象
├── WeatherSource.luau     S6 気象
├── HazardSource.luau      S7 ハザード
└── data/                  焼き込み済みデータ（bake 生成物）
```

```
tools/
├── build_catalog.py       S1 図面 → Catalog.luau
├── bake_structure.py      S2（レポート/初期モデル）
├── bake_mep.py            S3 設備・電気
├── bake_legal.py          S4 法規ルール
├── bake_terrain.py        S5 地象（標高タイル）
├── bake_weather.py        S6 気象（JMA）
└── bake_hazard.py         S7 ハザード
```

---

## 各ソースのデータ契約（概要）

### S1 図面 Drawing
```lua
{ parts = { { id, kind, size = {x,y,z}, pos = {x,y,z}, rotY, color } } }
```
※ dxf-llm の `jww2luau --emit-json` と同一契約（疎結合）

### S2 構造 Structure
```lua
{ model = { nodes = {...}, elements = {...} }, results = { elements = {...} } }
```

### S3 設備 MEP
```lua
{ runs = { { kind = "pipe"|"duct"|"wire", points = {...}, size = {...} } } }
```

### S4 法規 Code
```lua
{ rules = { { id, type = "fire"|"egress"|"use", region = {...}, level } } }
```

### S5 地象 Geospatial
```lua
{ grid = { origin, spacing, size = {w,h}, heights = {number} } }
```

### S6 気象 Weather
```lua
{ now = {...}, forecast = { {...} } }   -- 雨量・風速・気温・警報
```

### S7 ハザード Hazard
```lua
{ layers = { { type = "flood"|"tsunami"|"landslide"|"quake", cells = {...}, depth } } }
```

---

## 適用の順序（例）

```
S5 地象（地形を敷く）
 → S7 ハザード（危険区域を塗る）
 → S6 気象（雨/風の演出）
 → S1 図面（建物を配置）
 → S3 設備（配管・配線）
 → S4 法規（違反箇所をハイライト）
 → S2 構造（応力 → 折れる）
 → S7b 爆発（危険物テスト：S2 を破壊で再利用）
```

---

## ドメイン対応（DOMAINS.md との関係）

| ソース | 主に効くドメイン |
|---|---|
| S1 図面 | D1 取込 / D2 配置 |
| S2 構造 | D3 構造・破壊 |
| S3 設備 | D5 設備・電気 |
| S4 法規 | D5 / D6（テスト判定） |
| S5 地象 | D4 添景・環境 |
| S6 気象 | D4 環境 / D6 爆発条件 |
| S7 ハザード | D6 危険物・爆発 |

---

## 疎結合の原則

- ソース間は **Bundle（sourceId→data）** 経由でのみ受け渡す
- 各 Source は他ソースを直接 require しない
- dxf-llm（S1 の生成元）とは **データ契約のみ**（BOUNDARY.md）
- 焼き込み（bake）は各 tools が独立。失敗しても他ソースに影響しない
