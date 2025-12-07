#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODULE_DIR="$ROOT_DIR/modules"
TEMPLATE_DIR="$ROOT_DIR/templates"
DOCS_DIR="$ROOT_DIR/docs"

DRY_RUN=false
YES=false
VERBOSE=false

METHOD="${N8N_INSTALL_METHOD:-}"
DB_TYPE="${N8N_DB_TYPE:-}"
N8N_VERSION="${N8N_VERSION:-latest}"
PORT="${N8N_PORT:-5678}"
TZ_INPUT="${N8N_TZ:-}"
WEBHOOK_URL="${WEBHOOK_URL:-}"
BASIC_AUTH_USER="${N8N_BASIC_AUTH_USER:-}"
BASIC_AUTH_PASS="${N8N_BASIC_AUTH_PASSWORD:-}"
ENCRYPTION_KEY_FILE="${N8N_ENCRYPTION_KEY_FILE:-}"
AUTO_INSTALL_NODE="${N8N_AUTO_INSTALL_NODE:-false}"

PG_HOST="${DB_POSTGRESDB_HOST:-}"
PG_PORT="${DB_POSTGRESDB_PORT:-}"
PG_DB="${DB_POSTGRESDB_DATABASE:-}"
PG_USER="${DB_POSTGRESDB_USER:-}"
PG_PASS="${DB_POSTGRESDB_PASSWORD:-}"
PG_PASS_FILE="${DB_POSTGRESDB_PASSWORD_FILE:-}"
PG_SCHEMA="${DB_POSTGRESDB_SCHEMA:-public}"
PG_POOL_SIZE="${DB_POSTGRESDB_POOL_SIZE:-2}"
PG_CONN_TIMEOUT="${DB_POSTGRESDB_CONNECTION_TIMEOUT:-20000}"
PG_IDLE_TIMEOUT="${DB_POSTGRESDB_IDLE_CONNECTION_TIMEOUT:-30000}"
PG_SSL_ENABLED="${DB_POSTGRESDB_SSL_ENABLED:-false}"
PG_SSL_CA="${DB_POSTGRESDB_SSL_CA:-}"
PG_SSL_CERT="${DB_POSTGRESDB_SSL_CERT:-}"
PG_SSL_KEY="${DB_POSTGRESDB_SSL_KEY:-}"
PG_SSL_REJECT_UNAUTHORIZED="${DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED:-true}"

SQLITE_POOL_SIZE="${DB_SQLITE_POOL_SIZE:-0}"

mkdir -p "$ROOT_DIR/logs" "$ROOT_DIR/reports" "$ROOT_DIR/n8n" "$ROOT_DIR/n8n/local-files"

source "$MODULE_DIR/common.sh"
source "$MODULE_DIR/validation.sh"
source "$MODULE_DIR/db_config.sh"

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --method) METHOD="$2"; shift 2;;
      --db) DB_TYPE="$2"; shift 2;;
      --n8n-version) N8N_VERSION="$2"; shift 2;;
      --port) PORT="$2"; shift 2;;
      --tz) TZ_INPUT="$2"; shift 2;;
      --webhook-url) WEBHOOK_URL="$2"; shift 2;;
      --basic-auth-user) BASIC_AUTH_USER="$2"; shift 2;;
      --basic-auth-pass) BASIC_AUTH_PASS="$2"; shift 2;;
      --encryption-key-file) ENCRYPTION_KEY_FILE="$2"; shift 2;;
      --sqlite-pool-size) SQLITE_POOL_SIZE="$2"; shift 2;;
      --db-host) PG_HOST="$2"; shift 2;;
      --db-port) PG_PORT="$2"; shift 2;;
      --db-name) PG_DB="$2"; shift 2;;
      --db-user) PG_USER="$2"; shift 2;;
      --db-pass) PG_PASS="$2"; shift 2;;
      --db-pass-file) PG_PASS_FILE="$2"; shift 2;;
      --db-schema) PG_SCHEMA="$2"; shift 2;;
      --pg-pool-size) PG_POOL_SIZE="$2"; shift 2;;
      --pg-conn-timeout) PG_CONN_TIMEOUT="$2"; shift 2;;
      --pg-idle-timeout) PG_IDLE_TIMEOUT="$2"; shift 2;;
      --pg-ssl) PG_SSL_ENABLED="true"; shift 1;;
      --pg-ssl-ca) PG_SSL_CA="$2"; shift 2;;
      --pg-ssl-cert) PG_SSL_CERT="$2"; shift 2;;
      --pg-ssl-key) PG_SSL_KEY="$2"; shift 2;;
      --pg-ssl-reject-unauthorized) PG_SSL_REJECT_UNAUTHORIZED="$2"; shift 2;;
      --auto-install-node) AUTO_INSTALL_NODE="true"; shift 1;;
      --dry-run) DRY_RUN=true; shift 1;;
      --yes) YES=true; shift 1;;
      --verbose) VERBOSE=true; shift 1;;
      *) shift 1;;
    esac
  done
}

generate_random_key() {
  if [[ -z "$ENCRYPTION_KEY_FILE" ]]; then
    ENCRYPTION_KEY_FILE="$ROOT_DIR/n8n/.n8n_encryption_key"
  fi
  if [[ ! -f "$ENCRYPTION_KEY_FILE" ]]; then
    if ! $DRY_RUN; then
      openssl rand -hex 32 > "$ENCRYPTION_KEY_FILE"
      chmod 600 "$ENCRYPTION_KEY_FILE"
    fi
  fi
}

build_config() {
  TZ_VAL="$(detect_timezone "$TZ_INPUT")"
  validate_required "$METHOD" "method"
  validate_required "$DB_TYPE" "db"
  validate_port_free "$PORT"
  case "$DB_TYPE" in
    sqlite)
      DB_ENV_CONTENT="$(build_sqlite_env "$TZ_VAL" "$SQLITE_POOL_SIZE" "$WEBHOOK_URL" "$BASIC_AUTH_USER" "$BASIC_AUTH_PASS" "$ENCRYPTION_KEY_FILE")"
      ;;
    postgres)
      validate_required "$PG_HOST" "db-host"
      validate_required "$PG_PORT" "db-port"
      validate_required "$PG_DB" "db-name"
      validate_required "$PG_USER" "db-user"
      if [[ -z "$PG_PASS" && -z "$PG_PASS_FILE" ]]; then
        print_error "缺少数据库密码"; exit 1
      fi
      DB_ENV_CONTENT="$(build_postgres_env "$TZ_VAL" "$WEBHOOK_URL" "$BASIC_AUTH_USER" "$BASIC_AUTH_PASS" "$ENCRYPTION_KEY_FILE" "$PG_HOST" "$PG_PORT" "$PG_DB" "$PG_USER" "$PG_PASS" "$PG_PASS_FILE" "$PG_SCHEMA" "$PG_POOL_SIZE" "$PG_CONN_TIMEOUT" "$PG_IDLE_TIMEOUT" "$PG_SSL_ENABLED" "$PG_SSL_CA" "$PG_SSL_CERT" "$PG_SSL_KEY" "$PG_SSL_REJECT_UNAUTHORIZED")"
      ;;
    *) print_error "无效数据库类型"; exit 1;;
  esac
}

write_docker_files() {
  ensure_dir "$ROOT_DIR/n8n"
  if ! $DRY_RUN; then
    printf "%s\n" "$DB_ENV_CONTENT" > "$ROOT_DIR/n8n/.env"
    chmod 600 "$ROOT_DIR/n8n/.env"
    render_template "$TEMPLATE_DIR/compose.yaml.tpl" "$ROOT_DIR/n8n/compose.yaml" \
      PORT "$PORT" \
      N8N_VERSION "$N8N_VERSION"
  else
    print_info "dry run: 将生成 n8n/.env 与 compose.yaml（未写入）"
  fi
}

do_install_docker() {
  source "$MODULE_DIR/docker_install.sh"
  docker_install "$ROOT_DIR" "$PORT" "$DRY_RUN"
}

do_install_node() {
  source "$MODULE_DIR/node_install.sh"
  node_install "$ROOT_DIR" "$PORT" "$DRY_RUN" "$AUTO_INSTALL_NODE" "$N8N_VERSION" "$DB_ENV_CONTENT"
}

run_pg_test() {
  if [[ "$DB_TYPE" == "postgres" ]]; then
    source "$MODULE_DIR/validation.sh"
    pg_test_connection "$PG_HOST" "$PG_PORT" "$PG_DB" "$PG_USER" "$PG_PASS" "$PG_PASS_FILE"
  fi
}

generate_report() {
  TS="$(date +%Y%m%d-%H%M%S)"
  JSON="$ROOT_DIR/reports/install-$TS.json"
  MD="$ROOT_DIR/reports/install-$TS.md"
  METHOD_STR="$METHOD"
  DB_STR="$DB_TYPE"
  VERSION_STR="$N8N_VERSION"
  TZ_VAL="$(detect_timezone "$TZ_INPUT")"
  echo "{\n  \"method\": \"$METHOD_STR\",\n  \"db\": \"$DB_STR\",\n  \"port\": $PORT,\n  \"timezone\": \"$TZ_VAL\",\n  \"n8nVersion\": \"$VERSION_STR\"\n}" > "$JSON"
  echo "n8n 安装报告\n- 安装方式: $METHOD_STR\n- 数据库: $DB_STR\n- 端口: $PORT\n- 时区: $TZ_VAL\n- 版本: $VERSION_STR" > "$MD"
}

main() {
  parse_args "$@"
  build_config
  generate_random_key
  if [[ "$METHOD" == docker ]]; then
    write_docker_files
    do_install_docker
  elif [[ "$METHOD" == node ]]; then
    do_install_node
  else
    print_error "无效安装方式"; exit 1
  fi
  run_pg_test
  service_health_check "$PORT"
  generate_report
  print_info "安装完成"
}

main "$@"
