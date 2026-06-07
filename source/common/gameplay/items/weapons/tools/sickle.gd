class_name Sickle
extends Pickaxe
## A harvesting sickle. Mechanically a tool-swing like the pickaxe — it reuses
## the same swing animation (extends Pickaxe so PickSwingAbility's `is Pickaxe`
## animation hook still fires) and the same PickArc hitbox. Only its item's
## tool_type (&"sickle") and sprite differ, which is what lets it harvest herb
## patches a pickaxe can't work.
