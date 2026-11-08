--!strict
-- Types — ソース共通型定義
-- SOURCES.md のインターフェースを Luau 型で表現する。

export type SourceCategory = "architecture" | "disaster"

-- apply に渡る「箱庭ワールド」への最小インターフェース
-- （実体は World サービス。ソースはここ経由でのみ世界を触る）
export type World = {
	setTerrain: (heights: { number }, size: Vector2, origin: Vector3) -> (),
	paintZone: (zone: any) -> (),
	placePart: (spec: any) -> any?,
	highlight: (target: any, level: string) -> (),
	setWeather: (weather: any) -> (),
	log: (msg: string) -> (),
}

export type Context = {
	-- 焼き込みデータの取得関数（bake 生成物を返す）
	getData: (sourceId: string) -> any,
	config: { [string]: any },
}

export type Source = {
	id: string,
	name: string,
	category: SourceCategory,
	schema: string,                                 -- 契約スキーマ名
	load: (ctx: Context) -> any,                    -- データ取得
	validate: (data: any) -> (boolean, string?),    -- 最低限の検証
	apply: (world: World, data: any) -> (),         -- 世界へ反映
}

export type Bundle = { [string]: any }              -- sourceId -> data

return {}
