#!/usr/bin/env bash
# Runs convert_minilm.py in a dedicated Python 3.12 venv.
#
# coremltools does not support the system Python (3.14 on this machine), and
# it pins to older torch/numpy than a general-purpose environment wants. Keeping
# it isolated here means the rest of the pipeline stays on plain Node.
set -euo pipefail

cd "$(dirname "$0")"
VENV=".venv"

if ! command -v uv >/dev/null 2>&1; then
  echo "uv is required (brew install uv)." >&2
  exit 1
fi

if [ ! -d "$VENV" ]; then
  echo "Creating Python 3.12 venv for coremltools..."
  uv venv --python 3.12 "$VENV"
  uv pip install --python "$VENV/bin/python" -r requirements.txt
fi

exec "$VENV/bin/python" convert_minilm.py "$@"
