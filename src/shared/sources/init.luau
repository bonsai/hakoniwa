--!strict
-- SourceRegistry — 7 ソースの登録・取得・一括ロード/適用
--
-- 使い方:
--   local Sources = require(ReplicatedStorage.Shared.sources)
--   local bundle = Sources.loadAll(ctx)
--   Sources.applyAll(world, bundle)

local Types = require(script.Types)
local Config = require(script.Config)

local Registry = {}

local order: { string } = Config.order
local modules: { [string]: Types.Source } = {}
local loaded = false

local FUNCTIONAL = {
	DrawingSource = script.DrawingSource,
	StructureSource = script.StructureSource,
	MepSource = script.MepSource,
	CodeSource = script.CodeSource,
	GeospatialSource = script.GeospatialSource,
	WeatherSource = script.WeatherSource,
	HazardSource = script.HazardSource,
}

local function ensureLoaded()
	if loaded then
		return
	end
	for _, name in ipairs(order) do
		local mod = FUNCTIONAL[name]
		if mod then
			local src = require(mod)
			modules[src.id] = src
		end
	end
	loaded = true
end

function Registry.get(id: string): Types.Source?
	ensureLoaded()
	return modules[id]
end

function Registry.list(): { string }
	ensureLoaded()
	local ids = {}
	for id in pairs(modules) do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

-- 有効なソースだけを順序どおりロードして Bundle を作る
function Registry.loadAll(ctx: Types.Context): Types.Bundle
	ensureLoaded()
	local bundle: Types.Bundle = {}
	for _, id in ipairs(order) do
		local src = modules[id]
		if src and Config.enabled[id] then
			local ok, data = pcall(src.load, ctx)
			if ok then
				local valid, err = src.validate(data)
				if valid then
					bundle[id] = data
				else
					warn(("[sources] %s invalid: %s"):format(id, tostring(err)))
				end
			else
				warn(("[sources] %s load failed: %s"):format(id, tostring(data)))
			end
		end
	end
	return bundle
end

-- Bundle を順序どおり世界へ適用
function Registry.applyAll(world: Types.World, bundle: Types.Bundle): ()
	ensureLoaded()
	for _, id in ipairs(order) do
		local src = modules[id]
		local data = bundle[id]
		if src and data ~= nil then
			local ok, err = pcall(src.apply, world, data)
			if not ok then
				warn(("[sources] %s apply failed: %s"):format(id, tostring(err)))
			end
		end
	end
end

return Registry
