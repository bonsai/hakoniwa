--!strict
-- S3 設備 MEP — 配管・ダクト・配線・器具
-- 契約: { runs = { { kind = "pipe"|"duct"|"wire", points = {{x,y,z},...}, size = {x,y,z} } } }
-- 由来: JWW《設備》《電気》レイヤ（bake_mep.py）

local Types = require(script.Parent.Types)

local Source: Types.Source = {
	id = "mep",
	name = "設備",
	category = "architecture",
	schema = "hakoniwa-mep/v1",
} :: Types.Source

local MATERIAL = {
	pipe = "Metal",
	duct = "Metal",
	wire = "SmoothPlastic",
}

function Source.load(ctx: Types.Context)
	return ctx.getData("mep") or { runs = {} }
end

function Source.validate(data: any): (boolean, string?)
	if type(data) ~= "table" or type(data.runs) ~= "table" then
		return false, "runs 配列が必要"
	end
	return true
end

function Source.apply(world: Types.World, data: any): ()
	for _, run in ipairs(data.runs) do
		for i = 1, #run.points - 1 do
			world.placePart({
				id = ("mep_%s_%d"):format(run.kind, i),
				kind = run.kind,
				material = MATERIAL[run.kind] or "Metal",
				pos = run.points[i],
				size = run.size,
			})
		end
	end
	world.log(("設備: %d 系統"):format(#data.runs))
end

return Source
