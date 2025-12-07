#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

docker_install() {
  local root="$1" port="$2" dry="$3"
  if ! command -v docker >/dev/null 2>&1; then
    print_error "未检测到 Docker，请先安装 Docker 或在交互中添加安装步骤"
    exit 1
  fi
  if ! docker compose version >/dev/null 2>&1; then
    print_error "未检测到 docker compose 插件"
    exit 1
  fi
  print_info "启动 Docker Compose"
  if ! $dry; then
    (cd "$root/n8n" && docker compose up -d)
  else
    print_info "dry run: 跳过 compose up"
  fi
  print_info "验证容器与端口"
  if ! $dry; then
    sleep 3
    docker ps --format '{{.Names}} {{.Status}}' | grep -i n8n || print_warn "容器未就绪，稍后再试"
  fi
}

