#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

docker_install() {
  local root="$1" port="$2" dry="$3"
  if ! command -v docker >/dev/null 2>&1; then
    if $dry; then
      print_info "dry run: 未检测到 Docker，略过启动"
      return 0
    fi
    print_warn "未检测到 Docker"
    if confirm_yes "是否自动安装 Docker 与 compose 插件？"; then
      sudo apt-get update -y || true
      sudo apt-get install -y docker.io docker-compose-plugin || {
        print_error "Docker 安装失败"; exit 1;
      }
    else
      print_error "未安装 Docker，无法继续"; exit 1
    fi
  fi
  if ! docker compose version >/dev/null 2>&1; then
    if $dry; then
      print_info "dry run: 未检测到 docker compose 插件，略过启动"
      return 0
    fi
    print_warn "未检测到 docker compose 插件"
    if confirm_yes "是否安装 docker compose 插件？"; then
      sudo apt-get update -y || true
      sudo apt-get install -y docker-compose-plugin || {
        print_error "compose 插件安装失败"; exit 1;
      }
    else
      print_error "未安装 compose 插件，无法继续"; exit 1
    fi
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
