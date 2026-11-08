--!strict
-- Config — ソースの有効化・適用順序
--
-- order: load/apply の順序（地形→ハザード→気象→図面→設備→法規→構造）
-- enabled: ソース単位の ON/OFF

local Config = {}

Config.order = {
	"GeospatialSource", -- S5 地象（最初に地形を敷く）
	"HazardSource",     -- S7 ハザード（危険区域を塗る）
	"WeatherSource",    -- S6 気象（雨/風の演出）
	"DrawingSource",    -- S1 図面（建物）
	"MepSource",        -- S3 設備
	"CodeSource",       -- S4 法規
	"StructureSource",  -- S2 構造（最後に応力→折れる）
}

Config.enabled = {
	GeospatialSource = true,
	HazardSource = true,
	WeatherSource = true,
	DrawingSource = true,
	MepSource = true,
	CodeSource = true,
	StructureSource = true,
}

-- ソース ID（データキー）。tools の bake 出力と一致させる。
Config.ids = {
	GeospatialSource = "geospatial",
	HazardSource = "hazard",
	WeatherSource = "weather",
	DrawingSource = "drawing",
	MepSource = "mep",
	CodeSource = "code",
	StructureSource = "structure",
}

return Config
