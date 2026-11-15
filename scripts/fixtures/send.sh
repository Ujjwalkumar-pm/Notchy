#!/bin/bash
# Usage: scripts/fixtures/send.sh <fixture-name-without-.json> ...  (posts each to /hooks/event)
cd "$(dirname "$0")"
for f in "$@"; do curl -s -d @"$f.json" http://127.0.0.1:7850/hooks/event; echo; done
