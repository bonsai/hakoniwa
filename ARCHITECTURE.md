# ARCHITECTURE.md — 技術構成

## 全体像

```
┌─────────────────────────── Roblox ───────────────────────────┐
│  Client                        Server                         │
│  ┌──────────────────┐   Remote   ┌───────────────────────┐   │
│  │ PlacementController│◄────────►│ PlacementService      │   │
│  │ CatalogGui         │  Events   │ (権威・検証・生成)     │   │
│  │ Ghost / Grid       │           │ SaveService(DataStore)│   │
│  └──────────────────┘            └───────────────────────┘   │
│                shared: Config / Catalog / Grid / Types        │
└───────────────────────────────────────────────────────────────┘
                     ▲ Rojo 同期
┌────────────────────┴──────────────────────────────────────────┐
│  Python ツール: JWW/DXF → Catalog.luau                         │
└───────────────────────────────────────────────────────────────┘
```

---

## コンポーネント

| 層 | モジュール | 役割 |
|---|---|---|
| shared | `Config` | グリッド・上限・土地サイズ |
| shared | `Catalog` | 配置可能パーツ定義（自動生成） |
| shared | `Grid` | スナップ・回転計算 |
| shared | `Types` | 型定義 |
| server | `PlacementService` | 配置/移動/削除の権威処理、検証 |
| server | `SaveService` | DataStore への保存・読込 |
| client | `PlacementController` | レイキャスト・ゴースト・入力 |
| client | `CatalogGui` | パレット UI |

---

## 通信（RemoteEvent / RemoteFunction）

| 名前 | 種別 | 方向 | ペイロード |
|---|---|---|---|
| `PlaceRequest` | RemoteFunction | C→S | `{catalogId, position, rotation}` → `{ok, id}` |
| `MoveRequest` | RemoteEvent | C→S | `{id, position, rotation}` |
| `DeleteRequest` | RemoteEvent | C→S | `{id}` |
| `SaveRequest` | RemoteFunction | C→S | `{slot}` → `{ok}` |
| `LoadRequest` | RemoteFunction | C→S | `{slot}` → `{objects[]}` |
| `Replicate` | RemoteEvent | S→C | `{action, id, ...}` |

サーバ権威：クライアントは「こうしたい」を送るだけ。生成・検証・保存はサーバ。

---

## データモデル

```lua
-- 配置オブジェクト（保存単位）
type PlacedObject = {
    id: string,          -- GUID
    catalogId: string,   -- Catalog のキー
    position: Vector3,   -- スナップ済み
    rotation: number,    -- Y 軸回転（度）
    owner: number,       -- UserId
}

-- カタログ項目（Catalog.luau）
type CatalogItem = {
    id: string,
    name: string,
    kind: string,        -- wall/column/entourage/plant ...
    size: Vector3,       -- studs
    color: Color3,
    material: Enum.Material,
}
```

保存形式（DataStore）: `PlacedObject[]` を JSON 文字列化。

---

## 同期方針

- **サーバ生成 → 全クライアントへ Replicate**（配置はみんなに見える）
- 他人の箱庭を見る場合は「読み取り専用スナップショット」を配信
- 競合回避：配置はサーバが GUID を採番、クライアントは楽観表示しない

---

## 保存（DataStore）

| 項目 | 設計 |
|---|---|
| ストア | `OrderedDataStore` 不採用 / `DataStoreService` |
| キー | `hakoniwa_{userId}_{slot}` |
| スロット | 0..2（3 つ） |
| 上限 | 2000 オブジェクト / スロット |
| サイズ対策 | 座標は 0.01 studs 丸め、圧縮（将来） |
| エラー | `UpdateAsync` + リトライ |

---

## JWW/DXF 取込パイプライン

```
JWW ─jww2luau.py─► パーツ（Luau/JSON）
                     │
       build_catalog.py
                     ▼
        src/shared/Catalog.luau
```

- `recipes/jww2luau/jww2luau.py` の `extract_segments` / `extract_blocks` を再利用
- 種別ごとに代表サイズ・色をカタログ化
- 座標系：DXF(x,y) → Roblox(x,z)、高さ y（既存ルール）

---

## Rojo 構成（default.project.json）

```
ServerScriptService  <- src/server
StarterPlayerScripts <- src/client
ReplicatedStorage.Shared <- src/shared
```

`rojo serve hakoniwa/default.project.json` → Studio プラグインで Connect。

---

## Roblox Studio MCP 経由の描画（任意）

MCP（公式 `studio-rust-mcp-server` 等）を設定すると：

- `insert_model` で生成済み `.rbxmx` を投入
- `run_code` でカタログやゴーストの表示を調整・デバッグ

手順は `recipes/jww2luau/mcp-studio.md` を参照。

---

## 非機能

| 項目 | 目標 |
|---|---|
| 配置レスポンス | < 100 ms（体感即時） |
| 同接 | 1 サーバ 30 人想定 |
| モバイル性能 | パーツ 2000 で 60fps 目標（LOD は将来） |
| 永続性 | 保存失敗時はクライアントに継続リトライを促す |

---

## リスク

| リスク | 対処 |
|---|---|
| パーツ数で重くなる | 結合（Union）/ LOD / 表示上限 |
| DataStore 制限 | 圧縮・差分保存・スロット制限 |
| チート配置 | サーバ検証（範囲・グリッド・上限） |
| 図面ライセンス | 取込はプレイヤー責任、同梱は自作サンプルのみ |
