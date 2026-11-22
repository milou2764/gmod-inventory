# Tests

Not part of the addon (`addon.json` ignores this folder).

## Offline (no game needed)

Python 3 with [lupa](https://pypi.org/project/lupa/) (`pip install lupa`). They run the addon's real
Lua code with stubs:

| Script | Checks |
|---|---|
| `offline/syntax.py` | every Lua file of the addon compiles |
| `offline/net_items.py` | items survive the network format (IDs, rounds, classes, attachments) |
| `offline/carry_rules.py` | carry mode rules: zones, gear blocking zones, the planner, refusals |
| `offline/languages.py` | every language has the keys and placeholders of English |

## On a server (bots)

`server/*.lua` run on a dedicated server: **DarkRP on gm_construct**, with the addon installed
(and CW 2.0 for `cw2.lua`). Each file spawns bots, does things through the addon's real code and
returns a table of results to compare with the expected behaviour (the file's comments say what
each value means).

They expect a global `ASYNC(seconds)` that returns the function to call with the results. The
simplest one, in the server console:

```
lua_run ASYNC = function() return function(r) print(util.TableToJSON(r, true)) end end
```

then copy the files to `garrysmod/lua/advinv_tests/` and run one:

```
lua_openscript advinv_tests/body.lua
```

They kick bots, empty inventories, change settings for a moment and spawn entities: **never run
them on a server with players.** Run `generic.lua` on a freshly loaded map (it spawns weapons where
other tests leave things). Loot tables are random: `storage.lua` and `perm.lua` give other items
at every run.

| File | Feature |
|---|---|
| `generic.lua` | taking any weapon or entity with Use, generic items, saving and loading |
| `chars.lua` | the calls a character system makes (records, previews, respawn, deletion) |
| `body.lua` | lootable bodies |
| `admin.lua` | admin actions and settings |
| `use.lua`, `unload2.lua` | using items, unloading weapons |
| `search.lua` | searching players |
| `storage.lua`, `perm.lua` | crates, shared and personal stores, banks, locks, loot, permanence |
| `stacks.lua` | amounts, ground stacks |
| `bases.lua`, `cw2.lua` | other weapon bases, attachments, CW 2.0 |
| `darkrp.lua`, `darkrp2.lua` | DarkRP purchases, shipments, /drop, death |
| `small.lua` | crafting, tool, chat commands, armour... |
| `ui.lua` | spawn menu categories, crafting switch, ground items disappearing |
