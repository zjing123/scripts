#!/usr/bin/env bash
set -euo pipefail

build_sqlite_env() {
  local tz="$1" pool="$2" webhook="$3" user="$4" pass="$5" key_file="$6"
  local key="$(cat "$key_file" 2>/dev/null || echo)"
  cat <<EOF
TZ=${tz}
GENERIC_TIMEZONE=${tz}
DB_TYPE=sqlite
DB_SQLITE_POOL_SIZE=${pool}
N8N_RUNNERS_ENABLED=true
N8N_ENCRYPTION_KEY=${key}
${webhook:+WEBHOOK_URL=${webhook}}
${user:+N8N_BASIC_AUTH_ACTIVE=true}
${user:+N8N_BASIC_AUTH_USER=${user}}
${pass:+N8N_BASIC_AUTH_PASSWORD=${pass}}
EOF
}

build_postgres_env() {
  local tz="$1" webhook="$2" user="$3" pass="$4" key_file="$5"
  local host="$6" port="$7" db="$8" pguser="$9" pgpass="${10}" pgpassfile="${11}" schema="${12}" pool="${13}" cto="${14}" ito="${15}" ssl_enabled="${16}" ssl_ca="${17}" ssl_cert="${18}" ssl_key="${19}" ssl_reject="${20}"
  local key="$(cat "$key_file" 2>/dev/null || echo)"
  local pass_line=""
  if [[ -n "$pgpass" ]]; then pass_line="DB_POSTGRESDB_PASSWORD=${pgpass}"; fi
  if [[ -z "$pgpass" && -n "$pgpassfile" ]]; then pass_line="DB_POSTGRESDB_PASSWORD_FILE=${pgpassfile}"; fi
  cat <<EOF
TZ=${tz}
GENERIC_TIMEZONE=${tz}
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=${host}
DB_POSTGRESDB_PORT=${port}
DB_POSTGRESDB_DATABASE=${db}
DB_POSTGRESDB_USER=${pguser}
DB_POSTGRESDB_SCHEMA=${schema}
DB_POSTGRESDB_POOL_SIZE=${pool}
DB_POSTGRESDB_CONNECTION_TIMEOUT=${cto}
DB_POSTGRESDB_IDLE_CONNECTION_TIMEOUT=${ito}
${pass_line}
${ssl_enabled:+DB_POSTGRESDB_SSL_ENABLED=${ssl_enabled}}
${ssl_ca:+DB_POSTGRESDB_SSL_CA=${ssl_ca}}
${ssl_cert:+DB_POSTGRESDB_SSL_CERT=${ssl_cert}}
${ssl_key:+DB_POSTGRESDB_SSL_KEY=${ssl_key}}
${ssl_reject:+DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=${ssl_reject}}
N8N_RUNNERS_ENABLED=true
N8N_ENCRYPTION_KEY=${key}
${webhook:+WEBHOOK_URL=${webhook}}
${user:+N8N_BASIC_AUTH_ACTIVE=true}
${user:+N8N_BASIC_AUTH_USER=${user}}
${pass:+N8N_BASIC_AUTH_PASSWORD=${pass}}
EOF
}

