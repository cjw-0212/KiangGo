#!/usr/bin/env bash
# 图标环境检查 + 全量重新生成
#
# 用法（建议在仓库根目录）:
#   bash icons/rebuild_icons.sh              # 检查并通过后重建 stable
#   bash icons/rebuild_icons.sh -i           # 检查并通过后重建 insider
#   bash icons/rebuild_icons.sh --check-only # 只检查，不重建
#   bash icons/rebuild_icons.sh --no-clean   # 检查后直接跑 build（不删旧产物）
#
# 也可在 icons 目录:
#   bash rebuild_icons.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

QUALITY="stable"
CHECK_ONLY=0
NO_CLEAN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--insider)
      QUALITY="insider"
      shift
      ;;
    --check-only)
      CHECK_ONLY=1
      shift
      ;;
    --no-clean)
      NO_CLEAN=1
      shift
      ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      exit 1
      ;;
  esac
done

cd "${REPO_ROOT}"

# Windows/Git Bash: 确保本地包装脚本优先（convert/composite/icotool/png2icns/icns2png/gsed）
if [[ -d "${HOME}/bin" ]]; then
  export PATH="${HOME}/bin:${PATH}"
fi
hash -r 2>/dev/null || true

# 子脚本无法使用 alias；缺 gsed 时用 sed 顶上
if ! command -v gsed >/dev/null 2>&1; then
  if [[ -d "${HOME}/bin" ]]; then
    cat > "${HOME}/bin/gsed" <<'EOF'
#!/usr/bin/env bash
exec sed "$@"
EOF
    chmod +x "${HOME}/bin/gsed"
    hash -r 2>/dev/null || true
  fi
fi

echo "=== 仓库根目录 ==="
echo "${REPO_ROOT}"
echo "QUALITY=${QUALITY}"
echo

echo "=== 必需工具（build_icons.sh check_programs）==="
missing=0
for cmd in icns2png composite convert png2icns icotool rsvg-convert sed; do
  if command -v "${cmd}" >/dev/null 2>&1; then
    echo "OK   ${cmd} -> $(command -v "${cmd}")"
  else
    echo "MISS ${cmd}"
    missing=$((missing + 1))
  fi
done

echo
echo "=== 脚本还会用到 ==="
for cmd in gsed; do
  if command -v "${cmd}" >/dev/null 2>&1; then
    echo "OK   ${cmd} -> $(command -v "${cmd}")"
  else
    echo "MISS ${cmd}"
    missing=$((missing + 1))
  fi
done

echo
echo "=== 关键输入 SVG ==="
ls -la "icons/${QUALITY}/"*.svg

echo
echo "=== 依赖资源 ==="
ls -la utils.sh icons/template_macos.png icons/corner_512.png 2>&1 || true
ls -d vscode/resources/darwin vscode/resources/win32 2>&1 || true

echo
echo "=== 关键工具抽检 ==="
if command -v convert >/dev/null 2>&1; then
  convert -version 2>&1 | head -n 1 || true
  if ! convert -version 2>&1 | head -n 1 | grep -qi 'ImageMagick'; then
    echo "WARN convert 不是 ImageMagick（常见于 Windows 系统自带 convert）"
    missing=$((missing + 1))
  fi
fi
rsvg-convert -v 2>&1 | head -n 1 || true
icotool --help >/dev/null 2>&1 && echo "OK   icotool runs" || echo "WARN icotool 无法运行"

echo
if [[ "${missing}" -gt 0 ]]; then
  echo "结果: 缺少 ${missing} 个必需条件，停止执行"
  exit 1
fi

echo "结果: 环境检查通过"
echo

if [[ "${CHECK_ONLY}" -eq 1 ]]; then
  echo "仅检查模式（--check-only），跳过重建"
  exit 0
fi

clean_outputs() {
  echo "=== 清理旧产物 (${QUALITY}) ==="
  rm -rf \
    "src/${QUALITY}/resources/darwin" \
    "src/${QUALITY}/resources/linux" \
    "src/${QUALITY}/resources/win32" \
    "src/${QUALITY}/resources/server" \
    "build/windows/msi/resources/${QUALITY}"
  rm -f "src/${QUALITY}/src/vs/workbench/browser/media/code-icon.svg"
  rm -f \
    "src/${QUALITY}/src/vs/workbench/browser/parts/editor/media/letterpress-light.svg" \
    "src/${QUALITY}/src/vs/workbench/browser/parts/editor/media/letterpress-dark.svg" \
    "src/${QUALITY}/src/vs/workbench/browser/parts/editor/media/letterpress-hcLight.svg" \
    "src/${QUALITY}/src/vs/workbench/browser/parts/editor/media/letterpress-hcDark.svg"
  # 构建过程中的临时文件
  rm -f code_*.png code_logo.png code_ico_tmp.png ./*_512x512x32.png ./*_1_256x256x32.png
  echo "清理完成"
  echo
}

run_build() {
  echo "=== 重新生成图标 (${QUALITY}) ==="
  if [[ "${QUALITY}" == "insider" ]]; then
    bash "./icons/build_icons.sh" -i
  else
    bash "./icons/build_icons.sh"
  fi
  echo
}

verify_outputs() {
  echo "=== 校验关键产物 ==="
  local failed=0
  local files=(
    "src/${QUALITY}/resources/win32/code.ico"
    "src/${QUALITY}/resources/linux/code.png"
    "src/${QUALITY}/resources/darwin/code.icns"
    "src/${QUALITY}/resources/server/favicon.ico"
    "src/${QUALITY}/src/vs/workbench/browser/media/code-icon.svg"
    "src/${QUALITY}/src/vs/workbench/browser/parts/editor/media/letterpress-light.svg"
    "src/${QUALITY}/src/vs/workbench/browser/parts/editor/media/letterpress-dark.svg"
    "src/${QUALITY}/src/vs/workbench/browser/parts/editor/media/letterpress-hcLight.svg"
    "src/${QUALITY}/src/vs/workbench/browser/parts/editor/media/letterpress-hcDark.svg"
  )

  for f in "${files[@]}"; do
    if [[ -f "${f}" && -s "${f}" ]]; then
      ls -la "${f}"
    else
      echo "MISS/EMPTY ${f}"
      failed=1
    fi
  done

  echo
  local ico_count
  ico_count="$(ls "src/${QUALITY}/resources/win32/"*.ico 2>/dev/null | wc -l | tr -d ' ')"
  echo "win32 *.ico 数量: ${ico_count}"

  if [[ "${failed}" -ne 0 ]]; then
    echo "结果: 部分关键产物缺失"
    exit 1
  fi
  echo "结果: 全流程完成"
}

if [[ "${NO_CLEAN}" -eq 0 ]]; then
  clean_outputs
else
  echo "=== 跳过清理（--no-clean）==="
  echo
fi

run_build
verify_outputs
