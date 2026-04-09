#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/setup/bootstrap-linux-build.sh [options]

Bootstraps Koharu build on Linux by running:
  1) apt dependency install
  2) conda environment setup
  3) bun install + bun run build

Options:
  --env-name NAME     Conda environment name (default: koharu-build)
  --skip-apt          Skip apt dependency installation
  --skip-env          Skip conda environment setup
  --skip-bun-install  Skip bun install
  --skip-build        Skip bun run build
  -h, --help          Show this help message

Examples:
  scripts/setup/bootstrap-linux-build.sh
  scripts/setup/bootstrap-linux-build.sh --env-name koharu-dev
  scripts/setup/bootstrap-linux-build.sh --skip-apt
  scripts/setup/bootstrap-linux-build.sh --skip-build --skip-bun-install
EOF
}

ENV_NAME="koharu-build"
RUN_APT=1
RUN_ENV=1
RUN_BUN_INSTALL=1
RUN_BUILD=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-name)
      if [[ $# -lt 2 ]]; then
        echo "--env-name requires a value" >&2
        exit 1
      fi
      ENV_NAME="$2"
      shift 2
      ;;
    --skip-apt)
      RUN_APT=0
      shift
      ;;
    --skip-env)
      RUN_ENV=0
      shift
      ;;
    --skip-bun-install)
      RUN_BUN_INSTALL=0
      shift
      ;;
    --skip-build)
      RUN_BUILD=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

cd "$REPO_ROOT"

echo "Repo root: $REPO_ROOT"
echo "Conda env: $ENV_NAME"

if [[ $RUN_APT -eq 1 ]]; then
  echo "[1/3] Installing Linux apt dependencies"
  "$SCRIPT_DIR/install-linux-deps.sh"
else
  echo "[1/3] Skipped apt dependency installation"
fi

if [[ $RUN_ENV -eq 1 ]]; then
  echo "[2/3] Creating/updating conda environment"
  "$SCRIPT_DIR/setup-conda-env.sh" "$ENV_NAME"
else
  echo "[2/3] Skipped conda environment setup"
fi

if [[ $RUN_BUN_INSTALL -eq 1 || $RUN_BUILD -eq 1 ]]; then
  if ! command -v conda >/dev/null 2>&1; then
    echo "conda not found in PATH" >&2
    exit 1
  fi

  CONDA_BASE="$(conda info --base)"
  # shellcheck source=/dev/null
  source "$CONDA_BASE/etc/profile.d/conda.sh"
  conda activate "$ENV_NAME"
fi

if [[ $RUN_BUN_INSTALL -eq 1 ]]; then
  echo "[3/3] Running bun install"
  bun install
else
  echo "[3/3] Skipped bun install"
fi

if [[ $RUN_BUILD -eq 1 ]]; then
  echo "[3/3] Running bun run build"
  bun run build
  echo "Build complete: target/release/koharu"
else
  echo "[3/3] Skipped build"
fi
