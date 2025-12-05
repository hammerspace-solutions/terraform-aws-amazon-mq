#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/../.venv"

# Create venv if it doesn't exist
if [ ! -d "${VENV_DIR}" ]; then
  echo "Creating Python venv at ${VENV_DIR}..."
  python3 -m venv "${VENV_DIR}"
  "${VENV_DIR}/bin/pip" install --upgrade pip
  "${VENV_DIR}/bin/pip" install -r "${SCRIPT_DIR}/requirements.txt"
fi

# Run the Python script inside the venv, passing through all args
"${VENV_DIR}/bin/python" "${SCRIPT_DIR}/configure_rabbitmq.py" "$@"
