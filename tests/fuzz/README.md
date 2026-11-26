# Fuzzers (census)

Random real actions, with every item and round counted before and after: anything created or lost
is a bug (duplication, loss, a rule bypassed). They found most of the bugs of the 25-26/11 night
(log: `private/bughunt-2026-11-25.md`, not in the repository). Not part of the addon.

They need the devkit game (`addons/supermarket/tools/devkit/gmodclient.py start --gamemode darkrp`,
gm_construct) with DarkRP; HL2 weapons and the addon's own gear only.

| File | What it does |
|---|---|
| `fuzz_sv.lua` | server half: setup (a full kit, a crate, optionally a bank and other weapon bases, `BUGFZ_JOB` job items), `census`, `pickup`, `compare`, `die` / `die_check`, `respawn`, `rebase` (`BUGFZ_STEP`) |
| `fuzz_cl.lua` | client half: `BUGFZ_CL.burst(n, seed)` sends n random real inventory actions through the UI's network messages |
| `soak.sh` | 12 rounds x 16 bursts + a death each round; `sh tests/fuzz/soak.sh job` adds job items with DarkRP's `dropspawnedweapons` off (a job item must never leave its player or become ordinary). Log: `$SOAK_LOG`, default `/tmp/advinv_soak.log` |
| `search_fuzz.lua` | the host searches a bot (gear, job items) with random actions on the bot's things, the bot dying now and then. Run `fuzz_sv.lua` once first (`BUGFZ_STEP = 'rebase'`): it uses its census |
| `shared_fuzz.lua` | the host and a bot act in the same tick on one crate and one personal bank |
| `roundtrip_fuzz.lua` | any server (a bot): random saved inventories (gear with contents, carry modes, items of missing addons) loaded, saved and loaded again, random actions, a death in each drop mode; nothing may be created or lost, a second load gives the same record. `RTFUZZ_SEED`, `RTFUZZ_ROUNDS`, `RTFUZZ_PACKS = true` (the extensions' gear, the bot on their playermodels); result in `RTFUZZ` (records `rtfuzz_*` deleted) |
| `jobrounds_fuzz.lua` | any DarkRP server (a bot, dropspawnedweapons off for the run): a bound job SMG and a personal pistol firing SMG1 (a test SWEP registered by the script) share one reserve; random switches, reserve draws (as reloads), unloads, splits, drops: job rounds never leave, never grow, never move with the personal weapon in hand, and every round is accounted for. `JOBFUZZ_SEED`, `JOBFUZZ_STEPS`; result in `JOBFUZZ` |

Run one server script: `gmodclient.py seval "BUGFZ_STEP = 'setup' return 1"` then
`gmodclient.py srun tests/fuzz/fuzz_sv.lua`. The search and shared fuzzers return their result
(`fails` must be empty) and leave nothing behind.

Pitfalls: a map reload loses the client half (the soak loads it again); two soaks at once fight over
the game (check with `ps -W` that none is left before starting one); the listen server has no Lua
autorefresh (reload the map after editing the addon).
