#!/usr/bin/env bash
# One-shot dependency check + ./dev/build.sh -s
# Usage (Git Bash, repo root):
#   ./dev/check_and_build.sh
#   ./dev/check_and_build.sh -y   # skip confirmation

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

SKIP_CONFIRM="no"
if [[ "${1:-}" == "-y" ]]; then
  SKIP_CONFIRM="yes"
fi

ok=0
fail=0

pass() { echo "[OK]  $*"; ok=$((ok + 1)); }
warn() { echo "[WARN] $*"; }
die()  { echo "[FAIL] $*"; fail=$((fail + 1)); }

echo "==== Working directory ===="
echo "${ROOT}"
echo

echo "==== Dependency checks ===="

# --- Node / npm ---
if command -v node >/dev/null 2>&1; then
  NODE_VER="$(node --version)"
  pass "node ${NODE_VER}"
  if [[ ! "${NODE_VER}" =~ ^v24\. ]]; then
    warn "recommended Node 24.x (see .nvmrc); current is ${NODE_VER}"
  fi
else
  die "node not found"
fi

if command -v npm >/dev/null 2>&1; then
  pass "npm $(npm --version 2>/dev/null | tail -1)"
else
  die "npm not found"
fi

# --- jq ---
if command -v jq >/dev/null 2>&1; then
  pass "jq $(jq --version)"
else
  die "jq not found"
fi

# --- Python 3.11 (prefer for node-gyp; avoid 3.14+) ---
WIN_USER="${USER:-${USERNAME:-}}"
PYTHON_CANDIDATES=(
  "${PYTHON:-}"
  "/c/Users/${WIN_USER}/AppData/Local/Programs/Python/Python311/python.exe"
  "/c/Program Files/Python311/python.exe"
  "/c/Program Files (x86)/Python311/python.exe"
)

RESOLVED_PYTHON=""
for candidate in "${PYTHON_CANDIDATES[@]}"; do
  if [[ -n "${candidate}" && -x "${candidate}" ]]; then
    RESOLVED_PYTHON="${candidate}"
    break
  fi
done

if [[ -z "${RESOLVED_PYTHON}" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    RESOLVED_PYTHON="$(command -v python3)"
  elif command -v python >/dev/null 2>&1; then
    RESOLVED_PYTHON="$(command -v python)"
  fi
fi

if [[ -n "${RESOLVED_PYTHON}" ]]; then
  PY_VER_RAW="$("${RESOLVED_PYTHON}" --version 2>&1 || true)"
  if [[ "${PY_VER_RAW}" =~ Python\ 3\.11 ]]; then
    pass "python ${PY_VER_RAW} (${RESOLVED_PYTHON})"
  elif [[ "${PY_VER_RAW}" =~ Python\ 3\. ]]; then
    warn "found ${PY_VER_RAW}; docs recommend Python 3.11 (node-gyp may pick a wrong version)"
    pass "python ${PY_VER_RAW} (${RESOLVED_PYTHON})"
  else
    die "python exists but version is unreadable: ${RESOLVED_PYTHON}"
  fi
  export PYTHON="${RESOLVED_PYTHON}"
  export npm_config_python="${RESOLVED_PYTHON}"

  # Ensure `python3` works for child scripts
  mkdir -p "${TMPDIR:-/tmp}/kianggo-bin"
  cat > "${TMPDIR:-/tmp}/kianggo-bin/python3" <<EOF
#!/usr/bin/env bash
exec "${RESOLVED_PYTHON}" "\$@"
EOF
  chmod +x "${TMPDIR:-/tmp}/kianggo-bin/python3"
  export PATH="${TMPDIR:-/tmp}/kianggo-bin:${PATH}"
else
  die "python / python3 not found (need Python 3.11)"
fi

# --- Rust toolchain ---
if command -v rustc >/dev/null 2>&1; then
  pass "rustc $(rustc --version)"
else
  die "rustc not found (install rustup)"
fi

if command -v cargo >/dev/null 2>&1; then
  pass "cargo $(cargo --version)"
else
  die "cargo not found (install rustup)"
fi

if command -v rustup >/dev/null 2>&1; then
  pass "rustup $(rustup --version 2>/dev/null | head -1)"
  if ! rustup target list --installed 2>/dev/null | grep -qx "x86_64-pc-windows-msvc"; then
    warn "rust target x86_64-pc-windows-msvc not installed; build_cli.sh will try: rustup target add x86_64-pc-windows-msvc"
  else
    pass "rust target x86_64-pc-windows-msvc installed"
  fi
else
  die "rustup not found (CLI build needs: rustup target add ...)"
fi

# --- Git ---
if command -v git >/dev/null 2>&1; then
  pass "git $(git --version)"
else
  die "git not found"
fi

# --- 7-Zip (packaging only) ---
if command -v 7z >/dev/null 2>&1; then
  pass "7z found ($(command -v 7z))"
elif [[ -x "/c/Program Files/7-Zip/7z.exe" ]]; then
  pass "7z found at /c/Program Files/7-Zip/7z.exe"
  export PATH="/c/Program Files/7-Zip:${PATH}"
else
  warn "7z not found (only needed if packaging with -p)"
fi

# --- Visual Studio / MSVC (Windows native modules) ---
VS_CANDIDATES=(
  "${vs2022_install:-}"
  "/c/Program Files/Microsoft Visual Studio/2022/BuildTools"
  "/c/Program Files/Microsoft Visual Studio/2022/Community"
  "/c/Program Files/Microsoft Visual Studio/2022/Professional"
  "/c/Program Files/Microsoft Visual Studio/2022/Enterprise"
  "/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools"
  "/c/Program Files (x86)/Microsoft Visual Studio/2022/Community"
  "/c/Program Files (x86)/Microsoft Visual Studio/2022/Professional"
  "/c/Program Files (x86)/Microsoft Visual Studio/2022/Enterprise"
)

VS_PATH=""
for candidate in "${VS_CANDIDATES[@]}"; do
  if [[ -n "${candidate}" && -d "${candidate}" ]]; then
    VS_PATH="${candidate}"
    break
  fi
done

if [[ -n "${VS_PATH}" ]]; then
  pass "Visual Studio 2022 found: ${VS_PATH}"
  export vs2022_install="${VS_PATH}"
else
  die "Visual Studio 2022 / Build Tools not found (needed for C/C++ native modules)"
  echo "       Install: winget install --id Microsoft.VisualStudio.2022.BuildTools -e --override \"--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended\""
fi

# Spectre-mitigated libs (MSB8040)
SPECTRE_FOUND="no"
if [[ -n "${VS_PATH}" ]]; then
  if find "${VS_PATH}/VC/Tools/MSVC" -type d -name "spectre" 2>/dev/null | grep -q .; then
    SPECTRE_FOUND="yes"
  fi
fi

if [[ "${SPECTRE_FOUND}" == "yes" ]]; then
  pass "MSVC Spectre-mitigated libraries found"
else
  die "MSVC Spectre libraries missing (MSB8040 during npm ci)"
  echo "       Fix (Admin PowerShell):"
  echo "       & \"\${env:ProgramFiles(x86)}\\Microsoft Visual Studio\\Installer\\setup.exe\" modify \\"
  echo "         --installPath \"C:\\Program Files (x86)\\Microsoft Visual Studio\\2022\\BuildTools\" \\"
  echo "         --add Microsoft.VisualStudio.Component.VC.Runtimes.x86.x64.Spectre \\"
  echo "         --add Microsoft.VisualStudio.Component.VC.ATL.Spectre \\"
  echo "         --passive --wait"
fi

echo
echo "==== Project checks ===="

if [[ -f "dev/build.env" ]]; then
  pass "dev/build.env exists"
  # shellcheck disable=SC1091
  source "dev/build.env"
  echo "       MS_TAG=${MS_TAG:-<empty>}"
  echo "       MS_COMMIT=${MS_COMMIT:-<empty>}"
  echo "       RELEASE_VERSION=${RELEASE_VERSION:-<empty>}"
else
  die "dev/build.env missing"
fi

if [[ -d "vscode" ]]; then
  pass "vscode/ directory exists"
else
  die "vscode/ directory missing"
fi

if [[ -d "vscode/.git" ]]; then
  pass "vscode/ is a git repo"
  HEAD_SHA="$(git -C vscode rev-parse HEAD 2>/dev/null || true)"
  if [[ -n "${HEAD_SHA}" ]]; then
    echo "       HEAD=${HEAD_SHA}"
    if [[ -n "${MS_COMMIT:-}" && "${HEAD_SHA}" != "${MS_COMMIT}" ]]; then
      warn "vscode HEAD != MS_COMMIT in build.env (archive init is OK if source matches tag)"
    fi
  else
    die "vscode/ has .git but HEAD is invalid (need at least one commit)"
  fi
else
  die "vscode/ is not a git repo (run git init && git add . && git commit)"
fi

# --- Electron download mirror (GitHub often times out in CN) ---
if [[ -z "${ELECTRON_MIRROR:-}" ]]; then
  export ELECTRON_MIRROR="https://npmmirror.com/mirrors/electron/"
  pass "ELECTRON_MIRROR defaulted to npmmirror"
else
  pass "ELECTRON_MIRROR=${ELECTRON_MIRROR}"
fi
# npmmirror path layout uses bare version dirs (not vX.Y.Z)
if [[ -z "${ELECTRON_CUSTOM_DIR:-}" ]]; then
  export ELECTRON_CUSTOM_DIR="{{ version }}"
fi

echo
echo "==== Environment for build ===="
echo "PYTHON=${PYTHON:-}"
echo "npm_config_python=${npm_config_python:-}"
echo "vs2022_install=${vs2022_install:-}"
echo "ELECTRON_MIRROR=${ELECTRON_MIRROR:-}"
echo "ELECTRON_CUSTOM_DIR=${ELECTRON_CUSTOM_DIR:-}"
echo

echo "==== Summary: ${ok} passed, ${fail} failed ===="

if [[ "${fail}" -gt 0 ]]; then
  echo "Fix the failures above, then re-run: ./dev/check_and_build.sh"
  exit 1
fi

echo
echo "About to run: ./dev/build.sh -s"
if [[ "${SKIP_CONFIRM}" != "yes" ]]; then
  read -r -p "Continue? [y/N] " ans
  case "${ans}" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

echo
echo "==== Building ===="
exec ./dev/build.sh -s
