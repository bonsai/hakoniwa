--!strict
-- S1 図面 Drawing — JWW/DXF 建物を配置
-- 契約: { parts = { { id, kind, size={x,y,z}, pos={x,y,z}, rotY, color={r,g,b} } } }
-- 由来: dxf-llm の jww2luau --emit-json（疎結合・データ契約のみ）

local Types = require(script.Parent.Types)

local Source: Types.Source = {
	id = "drawing",
	name = "図面",
	category = "architecture",
	schema = "hakoniwa-parts/v1",
} :: Types.Source

function Source.load(ctx: Types.Context)
	return ctx.getData("drawing") or { parts = {} }
end

function Source.validate(data: any): (boolean, string?)
	if type(data) ~= "table" or type(data.parts) ~= "table" then
		return false, "parts 配列が必要"
	end
	return true
end

function Source.apply(world: Types.World, data: any): ()
	for _, p in ipairs(data.parts) do
		world.placePart(p)
	end
	world.log(("図面: %d パーツ配置"):format(#data.parts))
end

return Source
