#!/bin/bash
set -Eeuo pipefail
cd /workspace/computeroll
if [ "$#" -gt 0 ]; then exec "$@"; fi
: "${CROLL_WALLET:?Set CROLL_WALLET to the PUBLIC eligible BSC address}"
: "${CROLL_SECONDS:=3600}"
case "$CROLL_SECONDS" in ''|*[!0-9]*) echo 'Duration must be an integer' >&2; exit 2;; esac
if [ "$CROLL_SECONDS" -lt 1 ] || [ "$CROLL_SECONDS" -gt 3600 ]; then
  echo 'Duration must be 1..3600 seconds' >&2; exit 2
fi
node test-keccak.mjs ./keccak-gpu
exec timeout --signal=TERM --kill-after=10 "$CROLL_SECONDS" node worker.mjs "$CROLL_WALLET" "$CROLL_SECONDS"
