#!/bin/sh
# On-device soak for a Kindle, run over SSH on the device itself:
#   CYCLES=5 sh kindle_soak.sh
# Needs KOReader running with More tools -> HTTP Inspector started and DPD's
# Help -> Diagnostics -> "Write diagnostic log" on. Each word is opened as a popup
# through the inspector (it skips word selection, so it exercises lookup,
# build and paint only), then closed; between cycles it logs the Lua heap
# after a full collection and samples the process from /proc.
# Keep the Kindle awake: KOReader's auto-suspend stops the inspector, and the
# remaining cycles then silently do nothing. Check the diagnostic log for
# "Popup ready" lines instead of trusting the sample file alone.
# Output: /mnt/us/dpd-diag/soak.out (busybox sleep takes whole seconds only).
U=http://127.0.0.1:8080/koreader/ui/dpd
OUT=${OUT:-/mnt/us/dpd-diag/soak.out}
mkdir -p "$(dirname "$OUT")"
# KOReader's main process is the luajit running reader.lua, the largest by resident memory.
PID=$(for p in $(pidof luajit); do echo "$(grep VmRSS /proc/$p/status | awk '{print $2}') $p"; done | sort -n | tail -1 | awk '{print $2}')
WORDS="pacchima dhammassa vajjakammappabhedanti %E2%88%9Ahar %E2%88%9Agam hot%C4%AB k%C4%81 Buddha dhamm%C4%81 bhikkhux nn%C4%81%E1%B9%AD%E1%B9%AD%C4%81 indakhile dpdtestnomatch timing sajjas%C4%ABti uyyokhajja sa%E1%B9%83mantayitv%C4%81 bhikkhave%E2%80%99ti akata-anudhammena pacchimakattikapu%E1%B9%87%E1%B9%87am%C4%81"
echo "pid=$PID start $(date +%T)" > "$OUT"
sample() {
  curl -s -m20 "$U/logSettledMemory/" >/dev/null 2>&1
  echo "cycle=$1 $(grep -E 'VmRSS|VmHWM' /proc/$PID/status | tr -s ' \t\n' ' ') avail_kB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')" >> "$OUT"
}
sample 0
c=1
while [ "$c" -le "${CYCLES:-10}" ]; do
  for w in $WORDS; do
    curl -s -m20 "$U/showLookup/$w/" >/dev/null 2>&1
    sleep 2
    curl -s -m20 "$U/closeViewers/" >/dev/null 2>&1
    sleep 1
  done
  sample "$c"
  c=$((c+1))
done
echo "done $(date +%T)" >> "$OUT"
