#!/usr/bin/env bash
set -euo pipefail
MSG=$(cat /home/runner/work/aeon/aeon/.tmp-digest.md)
/home/runner/work/aeon/aeon/notify "$MSG"
