#!/usr/bin/env bash
# ==============================================================================
# 脚本名称: run-arc-manager.sh
# 作用: 启动已修复 Secret 调谐死循环 Bug 的 ARC Controller Manager，直接面向
#       Karmada 控制面执行 AutoscalingRunnerSet 与 EphemeralRunner 调谐。
#
# 【核心机制 ④：Secret 调谐死循环修复】
# 必须使用包含 PR #4492 修复补丁的代码，并在构建时注入当前 Helm Chart 匹配的
# 版本号: -ldflags "-X github.com/actions/actions-runner-controller/build.Version=0.14.2"
# ==============================================================================
set -euo pipefail

KUBECONFIG_KARMADA="${KUBECONFIG_KARMADA:-$HOME/karmada-data/karmada-apiserver.config}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

if [ -z "${GITHUB_TOKEN}" ]; then
    if [ -f "$HOME/actions-runner-controller/gh-token.txt" ]; then
        GITHUB_TOKEN=$(cat "$HOME/actions-runner-controller/gh-token.txt")
    elif [ -f "./gh-token.txt" ]; then
        GITHUB_TOKEN=$(cat "./gh-token.txt")
    else
        echo "[ERROR] 请提供 GitHub Token (PAT 或 App Token):"
        echo "export GITHUB_TOKEN=ghp_xxxx 或创建 gh-token.txt 文件"
        exit 1
    fi
fi

# 寻找已编译的修复版控制器二进制
ARC_BIN=""
if [ -f "$HOME/arc-manager-fixed" ]; then
    ARC_BIN="$HOME/arc-manager-fixed"
elif [ -f "./bin/arc-manager-fixed" ]; then
    ARC_BIN="./bin/arc-manager-fixed"
elif command -v arc-manager-fixed &>/dev/null; then
    ARC_BIN=$(command -v arc-manager-fixed)
fi

if [ -z "${ARC_BIN}" ]; then
    echo "==> 未找到 arc-manager-fixed 二进制，正在从源码构建..."
    if [ -d "$HOME/actions-runner-controller" ]; then
        ARC_SRC="$HOME/actions-runner-controller"
    else
        echo "[ERROR] 未找到 ARC 源码仓库，请先克隆: git clone https://github.com/actions/actions-runner-controller"
        exit 1
    fi
    mkdir -p ./bin
    (cd "${ARC_SRC}" && go build -trimpath -ldflags "-s -w -X github.com/actions/actions-runner-controller/build.Version=0.14.2" -o "$OLDPWD/bin/arc-manager-fixed" main.go)
    ARC_BIN="./bin/arc-manager-fixed"
    echo "==> 构建成功: ${ARC_BIN}"
fi

echo "==> 启动 ARC Controller Manager (针对 Karmada 控制面)..."
echo "    Kubeconfig: ${KUBECONFIG_KARMADA}"
echo "    Binary:     ${ARC_BIN}"

export CONTROLLER_MANAGER_POD_NAMESPACE="arc-systems"
export CONTROLLER_MANAGER_CONTAINER_IMAGE="ghcr.io/actions/gha-runner-scale-set-controller:0.14.2"
export NO_PROXY="*"
export no_proxy="*"

exec "${ARC_BIN}" \
  --auto-scaling-runner-set-only \
  --kubeconfig="${KUBECONFIG_KARMADA}" \
  --github-token="${GITHUB_TOKEN}" \
  --metrics-addr="127.0.0.1:8090" \
  --health-probe-bind-address="127.0.0.1:8091" \
  --listener-metrics-addr="127.0.0.1:8092"
