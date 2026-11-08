--!strict
-- S7 ハザード Hazard — 洪水・津波・土砂・地震
-- 契約: { layers = { { type, cells = {{i,j},...}, depth, level } } }
-- 由来: 国土数値情報 / 自治体ハザードマップ（bake_hazard.py）
-- 備考: 危険物テスト（D6 爆発）の前提条件としても使う。

local Types = require(script.Parent.Types)

local Source: Types.Source = {
	id = "hazard",
	name = "ハザード",
	category = "disaster",
	schema = "hakoniwa-hazard/v1",
} :: Types.Source

local COLOR = {
	flood = "BrightBlue",
	tsunami = "Cyan",
	landslide = "Brown",
	quake = "ReddishBrown",
}

function Source.load(ctx: Types.Context)
	return ctx.getData("hazard") or { layers = {} }
end

function Source.validate(data: any): (boolean, string?)
	if type(data) ~= "table" or type(data.layers) ~= "table" then
		return false, "layers 配列が必要"
	end
	return true
end

function Source.apply(world: Types.World, data: any): ()
	for _, layer in ipairs(data.layers) do
		world.paintZone({
			type = layer.type,
			cells = layer.cells,
			color = COLOR[layer.type] or "BrightRed",
			level = layer.level or "warn",
			depth = layer.depth or 0,
		})
	end
	world.log(("ハザード: %d レイヤ"):format(#data.layers))
end

return Source
