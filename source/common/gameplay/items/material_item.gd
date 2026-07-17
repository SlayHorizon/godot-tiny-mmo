class_name MaterialItem
extends Item
# Pure data item for crafting; no runtime hooks needed (not yet?).
# Keep recipes & crafting logic elsewhere.


func inventory_tab() -> InventoryTab:
	return InventoryTab.MATERIAL


func group_key() -> StringName:
	return &"materials"
