class_name ShopTrade
extends Resource
## A recurring item-for-currency exchange offered by a specialty vendor.
##
## Generic vendors buy any item for its `vendor_value`. A ShopTrade is for
## specialty cases — "Mira always accepts 5 Healing Herbs for 4 gold" —
## where the rate is set by the vendor, not the item. The player gives
## `amount` of `item` per trade and receives `payout` of `currency_item`
## (defaults to gold).
##
## Authored on a ShopResource's `accepted_trades` array. Order matters:
## the client lists trades in array order, and the server's trade index
## is the array index.

## What the vendor accepts.
@export var item: Item
## How many of `item` per trade unit (the "bundle size").
@export var amount: int = 1
## How much of `currency_item` the vendor pays per bundle.
@export var payout: int = 1
## What the vendor pays in. Leave empty for the default (gold).
@export var currency_item: Item
