# Classify playermodels' gear for the Advanced Inventory System (AIS)

You review Garry's Mod playermodels downloaded from the Steam Workshop (models only; you never run any of
their Lua) and decide, per model, which kinds of gear it already has and how. AIS lets a player wear inventory
gear items in slots, drawn on any playermodel: **Helmet** (any headgear: helmet, hat, cap, beanie, a hood pulled
up over the head, a sealed suit's helmet), **Gasmask** (gas mask, respirator, full face mask, a closed visor
or face shield), **Vest** (body armour, plate carrier, chest rig, webbing or harness with pouches, an armoured
suit's torso: exoskeleton, power armour), **Rucksack** (backpack, bag worn on the back, tank or battery pack on
the back). (NVGs and Radio slots exist too but are not classified here.)

The owner's rules:
1. **Built-in**: if the model has gear of a slot as part of its mesh (no bodygroup choice shows the body without
   it), that slot is built-in: AIS refuses our item there ("impossible to put headgear on another headgear").
   If only some choices of a bodygroup have that gear (an armoured outfit among plain ones), it is built-in
   only for those choices (conditional).
2. **Removable**: if the gear is a bodygroup with a choice that shows the body without it (an empty submodel,
   marked `*` by look.py, or a submodel named like "nohelmet", "none", "off", "bare"), our item of that slot
   takes it off: give the bodypart index and the "none" value.
3. Not gear: faces, heads, hair, beards, ranks, patches, decals, gloves, boots, scarves, a balaclava or a
   headband (a helmet can go over them), a hood lying down on the shoulders, holsters on the thigh.
4. Robots, creatures, power armour, full hazard suits with a sealed helmet: every slot built-in
   (Helmet, Gasmask, Vest, Rucksack) unless clearly not (say why).
5. Models without the needed skeleton were already left out.

## Your material
- Contact sheets `sheets/sheet_NN.jpg` (12 models each: the model "bare" = every bodypart that has an empty
  choice set to it, front and back) and `sheets/index.txt` (sheet, cell, Workshop id, model path, its
  bodyparts as `name:count[:e]`, `:e` = has an empty choice).
- `look.py` for a close look (four views, large) at any selection:
  `PY look.py "<model path>" <out.jpg> [index=value ...] [--bare] [--head]` (it prints each bodypart's
  submodels, `*` = empty, `<` = selected). PY and the environment variable are given in your task. Write
  your images only in your own scratch folder (given in your task).
Look at every model at least on the sheet; use look.py whenever a bodypart's name or the sheet leaves a
doubt (what a submodel shows, whether gear stays when bare, front vs back).

## Output
A TSV file (path in your task), one line per model, with these tab-separated fields:
`model path` `builtin` `removable` `conditional` `skip` `note`
- builtin: slots built into the mesh, comma-separated (`Helmet,Vest`), or `-`.
- removable: `Slot:bodypart=none_value` separated by `;` (`Helmet:2=1;Gasmask:3=0`), or `-`.
- conditional: `Slot:bodypart=v1,v2` separated by `;` (built-in only for those values), or `-`.
- skip: `-`, or a reason the model can't wear gear at all (not humanoid, broken).
- note: a few words: what the gear is, any doubt (then the owner decides).
Then a short summary: counts, and the judgment calls you made (so they can be checked). Be accurate: a wrong
"built-in" blocks players from wearing gear; a missed one lets a helmet sit on a helmet.

## Conventions already decided (batch 1): follow them
- A full armour shell (Gears of War COG armour, power armour, exoskeleton) with a raised back unit: that back
  unit counts as a built-in Rucksack; a flat back panel does not.
- A closed full-face helmet (no bare-face choice) is built-in Helmet AND Gasmask.
- A tight knit or camo hood that hugs the head like a balaclava is NOT a Helmet; a bulky parka hood up IS.
- A head bodygroup whose choice shows a gas mask on the face: conditional Gasmask on that value.
- A removable gear bodygroup whose "none" choice is a submodel named like "nohelmet" counts as removable
  (that value), not built-in.
- Several bodyparts may need checking: give every slot's real bodypart index for that model (indexes can
  differ between models of one pack).
- Many packs repeat one suit with different heads: classify the suit once carefully, then check each
  variant's bodypart list matches before copying the answer.
