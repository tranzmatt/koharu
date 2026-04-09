#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="${1:-koharu-build}"
ENV_FILE="environment.koharu-build.yml"

if ! command -v conda >/dev/null 2>&1; then
  echo "conda not found in PATH" >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Expected $ENV_FILE in repo root" >&2
  exit 1
fi

# Load conda shell functions in non-interactive shells.
CONDA_BASE="$(conda info --base)"
# shellcheck source=/dev/null
source "$CONDA_BASE/etc/profile.d/conda.sh"

if conda env list | awk '{print $1}' | grep -Fxq "$ENV_NAME"; then
  echo "Updating existing conda env: $ENV_NAME"
  conda env update -n "$ENV_NAME" -f "$ENV_FILE" --prune
else
  echo "Creating conda env: $ENV_NAME"
  conda env create -n "$ENV_NAME" -f "$ENV_FILE"
fi

conda activate "$ENV_NAME"

ACTIVATE_D="$CONDA_PREFIX/etc/conda/activate.d"
DEACTIVATE_D="$CONDA_PREFIX/etc/conda/deactivate.d"
mkdir -p "$ACTIVATE_D" "$DEACTIVATE_D"

cat > "$ACTIVATE_D/koharu-build-env.sh" <<'EOF'
# Koharu build environment tweaks for Linux conda sandbox.

# Ensure CUDA toolkit is visible.
export CUDA_HOME=/usr/local/cuda
case ":$PATH:" in
  *":/usr/local/cuda/bin:"*) ;;
  *) export PATH="/usr/local/cuda/bin:$PATH" ;;
esac

# Keep CUDA libs in loader path without duplicate entries.
case ":${LD_LIBRARY_PATH:-}:" in
  *":/usr/local/cuda/lib64:"*) ;;
  *) export LD_LIBRARY_PATH="/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ;;
esac

# Make conda pkg-config see system .pc files for GTK/Tauri libs.
SYS_PC="/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig"
case ":${PKG_CONFIG_PATH:-}:" in
  *":/usr/lib/x86_64-linux-gnu/pkgconfig:"*) ;;
  *) export PKG_CONFIG_PATH="$SYS_PC${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" ;;
esac

# bindgen/libclang in conda may miss libc headers unless include dirs are explicit.
GCC_VER="$(ls /usr/lib/gcc/x86_64-linux-gnu 2>/dev/null | sort -V | tail -n1)"
if [[ -n "$GCC_VER" && -d "/usr/lib/gcc/x86_64-linux-gnu/$GCC_VER/include" ]]; then
  export BINDGEN_EXTRA_CLANG_ARGS="-I/usr/lib/gcc/x86_64-linux-gnu/$GCC_VER/include -I/usr/include/x86_64-linux-gnu -I/usr/include"
fi
EOF

cat > "$DEACTIVATE_D/koharu-build-env.sh" <<'EOF'
unset CUDA_HOME
unset BINDGEN_EXTRA_CLANG_ARGS
EOF

echo "Conda env '$ENV_NAME' is ready."
echo "Next steps:"
echo "  conda activate $ENV_NAME"
echo "  bun install"
echo "  bun run build"
