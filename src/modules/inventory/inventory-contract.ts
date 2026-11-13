/** API DTOs and RPC contract for EVE-019.1 inventory setup. */
export type InventoryUnit = "piece" | "set" | "liter" | "kg" | "pack";
export type InventoryCondition = "ok" | "needs_repair" | "damaged" | "missing";
export type InventoryTemplateKey = "standard_apartment";
export type InventoryTemplateStrategy = "append_non_duplicate";

export type RoomDto = {
  id: string;
  property_id: string;
  name: string;
  position: number;
  version: number;
  created_at: string;
  updated_at: string;
};

export type InventoryItemDto = {
  id: string;
  property_id: string;
  room_id: string;
  name: string;
  quantity: number;
  unit: InventoryUnit;
  condition: InventoryCondition;
  minimum_stock?: number | null;
  purchase_minor?: number | null;
  purchased_on?: string | null;
  warranty_until?: string | null;
  model?: string | null;
  serial_number?: string | null;
  note?: string;
  media_ids: string[];
  version: number;
  created_at: string;
  updated_at: string;
};

export type InventoryDto = {
  property_id: string;
  rooms: RoomDto[];
  items: InventoryItemDto[];
};

export type CreateRoomInput = { name: string; position?: number };
export type CreateInventoryItemInput = {
  room_id: string;
  name: string;
  quantity: number;
  unit?: InventoryUnit;
  condition?: InventoryCondition;
  minimum_stock?: number | null;
  purchase_minor?: number | null;
  purchased_on?: string | null;
  warranty_until?: string | null;
  model?: string | null;
  serial_number?: string | null;
  note?: string;
  media_ids?: string[];
};

/** Methods resolve only after the server RPC returns an acknowledged DTO. */
export interface InventoryProvider {
  getInventory(propertyId: string): Promise<InventoryDto>;
  createRoom(propertyId: string, input: CreateRoomInput): Promise<RoomDto>;
  createInventoryItem(propertyId: string, input: CreateInventoryItemInput): Promise<InventoryItemDto>;
  applyTemplate(
    propertyId: string,
    templateKey: InventoryTemplateKey,
    strategy: InventoryTemplateStrategy,
  ): Promise<InventoryDto>;
}
