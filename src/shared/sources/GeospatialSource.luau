--!strict
-- S5 地象 Geospatial — 地形・地盤・標高
-- 契約: { grid = { origin = {x,y,z}, spacing, size = {w,h}, heights = {number} } }
-- 由来: 国土地理院 標高タイル / 基盤地図（bake_terrain.py）

local Types = require(script.Parent.Types)

local Source: Types.Source = {
	id = "geospatial",
	name = "地象",
	category = "disaster",
	schema = "hakoniwa-geospatial/v1",
} :: Types.Source

function Source.load(ctx: Types.Context)
	return ctx.getData("geospatial") or { grid = nil }
end

function Source.validate(data: any): (boolean, string?)
	if type(data) ~= "table" or type(data.grid) ~= "table" then
		return false, "grid が必要"
	end
	return true
end

function Source.apply(world: Types.World, data: any): ()
	local g = data.grid
	world.setTerrain(
		g.heights,
		Vector2.new(g.size.w, g.size.h),
		Vector3.new(g.origin.x, g.origin.y, g.origin.z)
	)
	world.log(("地象: %d セル"):format(#g.heights))
end

return Source
