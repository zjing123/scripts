#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

validate_required() {
  local val="$1" name="$2"
  if [[ -z "$val" ]]; then print_error "缺少必要参数: $name"; exit 1; fi
}

validate_port_free() {
  local port="$1"
  if ss -ltn | awk '{print $4}' | grep -q ":$port$"; then
    print_error "端口 ${port} 已被占用"; exit 1
  fi
}

pg_test_connection() {
  local host="$1" port="$2" db="$3" user="$4" pass="$5" pass_file="$6"
  local pw="$pass"
  if [[ -z "$pw" && -n "$pass_file" && -f "$pass_file" ]]; then pw="$(cat "$pass_file")"; fi
  print_info "测试 PostgreSQL 连接 ${host}:${port}/${db}"
  if command -v pg_isready >/dev/null 2>&1; then
    pg_isready -h "$host" -p "$port" -d "$db" -U "$user" || print_warn "pg_isready 测试失败"
  fi
  if command -v psql >/dev/null 2>&1; then
    PGPASSWORD="$pw" psql -h "$host" -p "$port" -U "$user" -d "$db" -c "SELECT version();" -tA || print_warn "psql 测试失败"
  else
    if command -v nc >/dev/null 2>&1; then
      nc -z "$host" "$port" || print_warn "端口探测失败"
    fi
  fi
}

