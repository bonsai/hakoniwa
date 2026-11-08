--!strict
-- Types — 共有型定義

export type CatalogItem = {
	id: string,
	name: string,
	kind: string,           -- "wall" | "column" | "window" | "entourage" | "plant" ...
	size: Vector3,
	color: Color3,
	material: Enum.Material,
}

export type PlacedObject = {
	id: string,
	catalogId: string,
	position: Vector3,
	rotation: number,       -- Y 軸回転（度）
	owner: number,          -- UserId
}

export type PlaceRequest = {
	catalogId: string,
	position: Vector3,
	rotation: number,
}

export type ReplicateAction = {
	action: "add" | "move" | "delete" | "clear",
	id: string?,
	catalogId: string?,
	position: Vector3?,
	rotation: number?,
}

return {}
