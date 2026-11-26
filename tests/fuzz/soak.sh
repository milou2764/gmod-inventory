#!/bin/sh
# Census soak (see README.md): 12 rounds of 16 bursts of random client actions (plain, mixed weapon
# bases, personal bank), a death each round; every item and round counted before and after.
#   sh tests/fuzz/soak.sh        default config
#   sh tests/fuzz/soak.sh job    with job items, DarkRP's dropspawnedweapons off
# SOAK_SEED=1000 sh tests/fuzz/soak.sh   other random sequences (default 0)
DIR=$(cd "$(dirname "$0")" && pwd)
cd "$DIR/../../../supermarket/tools" || exit 1 # (the devkit: gmodclient.py)
G=".venv/Scripts/python.exe devkit/gmodclient.py"
S="$DIR/fuzz_sv.lua"
LOG="${SOAK_LOG:-${TMPDIR:-/tmp}/advinv_soak.log}"
JOB="BUGFZ_JOB = false"
[ "$1" = "job" ] && JOB="BUGFZ_JOB = true GAMEMODE.Config.dropspawnedweapons = false"
: > "$LOG"
$G run "$DIR/fuzz_cl.lua" >/dev/null 2>&1 # (the client half is lost at every map load)
sv() { $G seval "BUGFZ_STEP = '$1' return 1" >/dev/null 2>&1; $G srun "$S" 2>&1 | grep -o "résultat.*\|rreur.*\|ÉCHEC.*" | head -2; }
fails=0; total=0
for round in $(seq 1 12); do
  case $((round % 3)) in 0) cfg="BUGFZ_BASES = false BUGFZ_BANK = false";; 1) cfg="BUGFZ_BASES = true BUGFZ_BANK = false";; 2) cfg="BUGFZ_BASES = false BUGFZ_BANK = true";; esac
  $G seval "$cfg $JOB for _, e in ipairs(ents.FindByClass('advinv_bank')) do e:Remove() end if not Entity(1):Alive() then Entity(1):Spawn() end return 1" >/dev/null 2>&1
  sleep 1; sv setup >/dev/null; sleep 2
  for k in $(seq 1 16); do
    seed=$((5000 + ${SOAK_SEED:-0} + round * 100 + k)); total=$((total+1))
    out=$($G eval "return BUGFZ_CL.burst(7, $seed)" 2>&1 | grep -o "résultat.*\|rreur.*")
    [ -z "$out" ] && echo "round $round seed $seed: NO ACTIONS SENT (client fuzzer missing?)" >> "$LOG"
    sleep 1; sv pickup >/dev/null; sleep 0.6
    cmp=$(sv compare)
    if ! echo "$cmp" | grep -q '"OK"'; then fails=$((fails+1)); echo "round $round seed $seed: $cmp | $out" >> "$LOG"; sv rebase >/dev/null; fi
  done
  sv die >/dev/null; sleep 1
  dc=$(sv die_check); echo "$dc" | grep -q '"OK"' || { fails=$((fails+1)); echo "round $round death: $dc" >> "$LOG"; }
  sv respawn >/dev/null; sleep 2
  echo "round $round done ($fails differences so far)" >> "$LOG"
done
echo "SOAK END: $fails differences in $total bursts + 12 deaths; client errors: $($G errors 2>&1 | tail -1)" >> "$LOG"
