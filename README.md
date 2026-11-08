# hakoniwa — JWWで箱庭をつくる Roblox ゲーム

> **JWW（Jw_cad）の図面オブジェクトをそのまま使って、Roblox 上に自分だけの箱庭（ジオラマ）を組み立てるゲーム。**

プレイヤーは JWW/DXF から取り込まれた「壁・柱・窓・添景（人物・植栽・車）」などの
パーツをグリッド上に配置し、自由に街や庭をつくる。建築図面のスケール感を保ったまま、
「本物の図面」で遊べるサンドボックス。

---

## コンセプト

| 項目 | 内容 |
|---|---|
| ジャンル | 建築サンドボックス / 箱庭クリエイター |
| プラットフォーム | Roblox（PC / モバイル / コンソール） |
| コア体験 | 図面パーツを選んで置くだけ。グリッドが吸着。 |
| 差別化 | **実在の建築図面（JWW）がアセットになる** |
| ターゲット | 建築好き・街づくり好き・教育（建築・図面の学習） |

---

## 遊びのループ

```
① パレットからパーツ選択（壁 / 窓 / 添景 ...）
② グリッド上に配置（ゴースト表示 → クリックで確定）
③ 回転・削除・移動で調整
④ 保存（DataStore）／ 他人の箱庭を訪問
```

---

## 図面 → ゲームへの流れ

```
JWW/DXF ──jww2luau──► パーツ抽出 ──build_catalog──► Catalog.luau ──Rojo──► Roblox
```

- `recipes/jww2luau/` の変換ロジックを再利用
- 図面 1 枚から「置けるパーツのカタログ」を自動生成
- プレイヤー配置データは JSON で保存（座標・回転・パーツID）

---

## ドキュメント

| ファイル | 内容 |
|---|---|
| [DOMAINS.md](DOMAINS.md) | 7ドメイン整理（現状 4/7） |
| [SOURCES.md](SOURCES.md) | 建築・防災 7ソースを Luau で扱う構成 |
| [BOUNDARY.md](BOUNDARY.md) | dxf-llm との境界（疎結合・契約 JSON） |
| [DESIGN.md](DESIGN.md) | ゲームデザイン |
| [ARCHITECTURE.md](ARCHITECTURE.md) | 技術構成（同期・保存・MCP） |

## ディレクトリ

```
hakoniwa/
├── README.md              ← 本ファイル（コンセプト）
├── DOMAINS.md             ← 7ドメイン整理
├── SOURCES.md             ← 7ソース構成
├── BOUNDARY.md            ← dxf-llm との境界（契約）
├── DESIGN.md              ← ゲームデザイン（ルール・UX）
├── ARCHITECTURE.md        ← 技術構成（同期・保存・MCP）
├── default.project.json   ← Rojo プロジェクト定義
├── contract/              契約スキーマ（hakoniwa-parts/v1）
├── src/
│   ├── server/            サーバ権威の配置・保存
│   ├── client/            配置操作・カタログUI
│   └── shared/            設定・カタログ・型・FEM・sources/
├── tools/
│   └── build_catalog.py   契約JSON/DXF → Catalog.luau 生成
└── assets/                モデル・サムネイル置き場
```

---

## クイックスタート（開発）

```bash
# 1. Rojo を入れる
cargo install rojo   # or: aftman / foreman

# 2. JWW/DXF からカタログ生成
python hakoniwa/tools/build_catalog.py path/to/plan.dxf \
    -o hakoniwa/src/shared/Catalog.luau

# 3. Rojo で Studio に同期
rojo serve hakoniwa/default.project.json
#   → Studio の Rojo プラグインで Connect
```

MCP 経由の描画は別リポジトリ dxf-llm の `recipes/jww2luau/mcp-studio.md` を参照。
境界（契約）は [BOUNDARY.md](BOUNDARY.md)。

---

## ロードマップ

| フェーズ | 内容 |
|---|---|
| PoC | 1 種のパーツをグリッド配置・保存できる |
| MVP | カタログ UI・回転・削除・保存・訪問 |
| 発展 | 図面の一括取込・共同編集・コンテスト・教育モード |

詳細は [DESIGN.md](DESIGN.md) / [ARCHITECTURE.md](ARCHITECTURE.md)。
