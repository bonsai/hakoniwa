--!strict
-- Catalog — 配置可能パーツ定義
-- このファイルは tools/build_catalog.py で JWW/DXF から自動生成できます。
--   python hakoniwa/tools/build_catalog.py plan.dxf -o hakoniwa/src/shared/Catalog.luau
-- 以下は手書きのサンプル（生成前のフォールバック）。

local Types = require(script.Parent.Types)

local Catalog = {}

Catalog.items = {
	{
		id = "wall_4000",
		name = "壁 4m",
		kind = "wall",
		size = Vector3.new(14.28, 8.57, 0.43),
		color = Color3.fromRGB(163, 162, 165),
		material = Enum.Material.Concrete,
	},
	{
		id = "column_300",
		name = "柱 300",
		kind = "column",
		size = Vector3.new(1.07, 10.0, 1.07),
		color = Color3.fromRGB(99, 95, 98),
		material = Enum.Material.Concrete,
	},
	{
		id = "window_2000",
		name = "窓 2m",
		kind = "window",
		size = Vector3.new(7.14, 4.29, 0.36),
		color = Color3.fromRGB(4, 175, 236),
		material = Enum.Material.Glass,
	},
	{
		id = "entourage_person",
		name = "人物",
		kind = "entourage",
		size = Vector3.new(0.9, 6.07, 0.9),
		color = Color3.fromRGB(17, 17, 17),
		material = Enum.Material.SmoothPlastic,
	},
	{
		id = "plant_tree",
		name = "樹木",
		kind = "plant",
		size = Vector3.new(2.5, 8.93, 2.5),
		color = Color3.fromRGB(40, 127, 71),
		material = Enum.Material.Grass,
	},
} :: { Types.CatalogItem }

function Catalog.get(id: string): Types.CatalogItem?
	for _, item in ipairs(Catalog.items) do
		if item.id == id then
			return item
		end
	end
	return nil
end

function Catalog.all(): { Types.CatalogItem }
	return Catalog.items
end

return Catalog
