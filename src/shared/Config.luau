--!strict
-- Config — ゲーム全体の設定値（サーバ・クライアント共有）

local Config = {}

-- 配置グリッド（studs）。JWW の mm スケールとは独立に「遊びやすさ」優先で調整
Config.GridSize = 4

-- 1 箱庭あたりの上限パーツ数
Config.MaxParts = 2000

-- 土地プレート（studs, 正方形）
Config.PlotSize = 256

-- 土台からの最大高さ（studs）
Config.MaxHeight = 512

-- 図面スケール（1 m = 何 studs）
Config.StudsPerMeter = 3.571

-- 保存スロット数 / プレイヤー
Config.SaveSlots = 3

-- 回転ステップ（度）
Config.RotationStep = 15

-- カメラ・操作
Config.PlaceRange = 200          -- レイキャスト距離（studs）
Config.GhostTransparency = 0.5

return Config
