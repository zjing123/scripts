#!/bin/bash

# ==================================================================
# n8n Linux 一键安装脚本
# 这个脚本在 Linux 系统上交互式安装 n8n
# ==================================================================

# ========================== 变量定义部分 ==========================

# -------------------------- 脚本配置 --------------------------
readonly SCRIPT_NAME="n8n_installer.sh"
readonly SCRIPT_VERSION="1.2.0"

# -------------------------- n8n 配置 --------------------------
readonly N8N_VERSION="latest"
readonly N8N_HOST="localhost"
readonly N8N_PORT="5678"

# -------------------------- 依赖版本 --------------------------
readonly DOCKER_COMPOSE_VERSION="v2.23.3"
readonly NVM_VERSION="v0.39.5"
readonly NODE_VERSION="v20"
readonly POSTGRES_VERSION="16"

# -------------------------- 路径配置 --------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="$SCRIPT_DIR/n8n_install.log"

# -------------------------- 其他配置 --------------------------
readonly DEFAULT_TIMEZONE="Asia/Shanghai"
GLOBAL_TIMEZONE="$DEFAULT_TIMEZONE"  # 全局时区变量

# -------------------------- 颜色定义 --------------------------
declare -A COLORS=(
    [RED]='\033[0;31m'
    [GREEN]='\033[0;32m'
    [YELLOW]='\033[1;33m'
    [BLUE]='\033[0;34m'
    [NC]='\033[0m'  # 无颜色
    [DEBUG_RED]='\033[1;31m'  # 红色加粗用于ERROR
    [DEBUG_YELLOW]='\033[1;33m'  # 黄色加粗用于WARN
    [DEBUG_BLUE]='\033[1;34m'  # 蓝色加粗用于DEBUG
    [DEBUG_CYAN]='\033[1;36m'  # 青色加粗用于INFO
)

# -------------------------- 全局开关 --------------------------
DRY_RUN=false
DEBUG=${DEBUG:-false}

# -------------------------- 数据库相关全局变量 - 尽量减少使用 --------------------------
# 注意：这些变量将在后续版本中逐步替换为参数传递

# ========================== 初始化模块 ==========================

# 初始化函数
# 参数: $@ - 命令行参数
# 返回值: 无
initialize() {
    # 检查是否有 dry-run 参数
    if [ "$1" = "--dry-run" ] || [ "$1" = "-d" ]; then
        DRY_RUN=true
        # DRY-RUN 模式下默认开启 DEBUG
        DEBUG=${DEBUG:-true}
        log_message "INFO" "[DRY-RUN MODE] 脚本将只打印执行命令，不会实际执行"
    fi

    # 更严格的错误检查
    set -euo pipefail

    # 注册错误处理
    trap 'handle_error $? $LINENO "$BASH_COMMAND"' ERR

    log_message "DEBUG" "初始化模块完成"
}

# 日志消息函数 - 支持结构化日志
# 参数: $1 - 日志级别 (INFO, WARN, ERROR, DEBUG)
#       $2 - 日志消息
# 返回值: 无
log_message() {
    local level="$1"
    local message="$2"

    # 转换为大写
    level=$(printf "%s" "$level" | tr '[:lower:]' '[:upper:]')

    # 获取当前时间戳
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    # 构建控制台输出(带颜色)
    local console_output
    case "$level" in
        INFO)
            console_output="${COLORS[DEBUG_CYAN]}[$level] ${timestamp} - ${message}${COLORS[NC]}"
            ;;
        WARN)
            console_output="${COLORS[DEBUG_YELLOW]}[$level] ${timestamp} - ${message}${COLORS[NC]}"
            ;;
        ERROR)
            console_output="${COLORS[DEBUG_RED]}[$level] ${timestamp} - ${message}${COLORS[NC]}"
            ;;
        DEBUG)
            # DEBUG 级别仅在 DEBUG 变量为 true 时显示
            if [ "$DEBUG" = true ]; then
                console_output="${COLORS[DEBUG_BLUE]}[$level] ${timestamp} - ${message}${COLORS[NC]}"
            else
                return 0  # 不输出 DEBUG 消息
            fi
            ;;
        *)
            console_output="${COLORS[DEBUG_CYAN]}[INFO] ${timestamp} - ${message}${COLORS[NC]}"
            level="INFO"
            ;;
    esac

    # 构建日志文件输出(纯文本，无颜色)
    local file_output="[$level] ${timestamp} - ${message}"

    # 输出到控制台
    printf "%b\n" "$console_output"

    # 输出到日志文件
    printf "%s\n" "$file_output" >> "$LOG_FILE"
}

# 错误处理函数
# 参数: $1 - 错误代码
#       $2 - 错误行号
#       $3 - 错误命令
# 返回值: 无
handle_error() {
    local exit_code="$1"
    local line_number="$2"
    local command="$3"

    log_message "ERROR" "===================================== 错误发生 ======================================"
    log_message "ERROR" "错误代码: $exit_code"
    log_message "ERROR" "错误行号: $line_number"
    log_message "ERROR" "错误命令: $command"
    log_message "ERROR" "日志文件: $LOG_FILE"
    log_message "ERROR" "====================================================================================="
    log_message "ERROR" "请检查日志文件以获取详细错误信息"

    exit "$exit_code"
}

# 输入验证函数
# 参数: $1 - 验证类型 (port, database_name, yes_no)
#       $2 - 输入值
#       $3 - 字段名称
# 返回值: 0表示验证通过，1表示验证失败
validate_input() {
    local type="$1"
    local input="$2"
    local field_name="$3"

    case "$type" in
        "port")
            if ! [[ "$input" =~ ^[0-9]+$ ]] || [ "$input" -lt 1 ] || [ "$input" -gt 65535 ]; then
                log_message "ERROR" "无效的端口号 '$input'"
                log_message "ERROR" "端口号必须是1-65535之间的整数"
                return 1
            fi
            ;;
        "database_name")
            if ! [[ "$input" =~ ^[a-zA-Z0-9_]+$ ]]; then
                log_message "ERROR" "无效的数据库名称 '$input'"
                log_message "ERROR" "数据库名称只能包含字母、数字和下划线"
                return 1
            fi
            ;;
        "yes_no")
            if [ "$input" != "y" ] && [ "$input" != "Y" ] && [ "$input" != "n" ] && [ "$input" != "N" ]; then
                log_message "ERROR" "无效的输入 '$input'"
                log_message "INFO" "请输入 y (是) 或 n (否)"
                return 1
            fi
            ;;
        *)
            log_message "ERROR" "不支持的验证类型 '$type'"
            return 1
            ;;
    esac
    return 0
}

# 执行命令函数 - 支持 dry-run 模式
# 参数: $@ - 要执行的命令
# 返回值: 命令的执行结果
execute() {
    if [ "$DRY_RUN" = true ]; then
        log_message "INFO" "[DRY-RUN] 将要执行命令: $@"
    else
        eval "$@"
    fi
}

# ========================== 系统检查模块 ==========================

# 欢迎信息
# 参数: 无
# 返回值: 无
print_welcome() {
    log_message "INFO" "================================================================="
    log_message "INFO" "                      n8n 一键安装脚本"
    log_message "INFO" "                        版本: ${SCRIPT_VERSION}"
    log_message "INFO" "================================================================="
    log_message "INFO" "                      支持: Ubuntu/Debian 系统"
    log_message "INFO" "================================================================="
}

# 检查系统是否为 Ubuntu/Debian
# 参数: 无
# 返回值: 0表示支持，1表示不支持
check_system() {
    if [ -z "$(which apt-get 2>/dev/null)" ]; then
        log_message "ERROR" "这个脚本只支持 Ubuntu/Debian 系统!"
        return 1
    fi
    log_message "DEBUG" "系统检查通过"
    return 0
}

# 权限检查函数
# 参数: 无
# 返回值: 0表示权限通过，1表示权限不足
check_permissions() {
    # 检查是否为root用户
    if [ "$(id -u)" -eq 0 ]; then
        log_message "WARN" "您正在以root用户身份运行此脚本"
        log_message "WARN" "强烈建议使用普通用户并通过sudo获取必要权限"

        while true; do
            read -p "是否继续以root用户身份运行？(y/n): " continue_as_root
            validate_input "yes_no" "$continue_as_root" "继续以root用户身份运行"
            if [ $? -eq 0 ]; then
                log_message "INFO" "是否继续以root用户身份运行脚本: $continue_as_root"

                if [ "$continue_as_root" = "n" ] || [ "$continue_as_root" = "N" ]; then
                    log_message "INFO" "请切换到普通用户并再次运行脚本"
                    return 1
                fi

                break
            fi
        done
    fi

    # 检查是否有sudo权限
    if ! sudo -n true 2>/dev/null; then
        log_message "ERROR" "当前用户没有sudo权限，无法完成安装"
        return 1
    fi

    log_message "INFO" "权限检查通过"
    return 0
}

# 更新系统包
# 参数: 无
# 返回值: 无
update_system_packages() {
    log_message "INFO" "📥 正在更新系统包..."
    log_message "INFO" "============================= 系统更新 ============================"
    
    # 更新包列表
    log_message "INFO" "正在更新包列表..."
    execute "sudo apt update"
    
    # 升级所有包
    log_message "INFO" "正在升级系统包..."
    show_progress "正在升级系统包" 20
    execute "sudo apt upgrade -y"
    
    # 清理不需要的包
    log_message "INFO" "正在清理不需要的包..."
    execute "sudo apt autoremove -y"
    execute "sudo apt autoclean -y"
    
    log_message "INFO" "✓ 系统包更新完成!"
    log_message "INFO" "=================================================================="
}

# 依赖检查函数
# 参数: 无
# 返回值: 无
check_dependencies() {
    # 只保留必要的依赖项
    local required_deps=("curl" "wget" "sudo")
    local missing_deps=()

    log_message "INFO" "📋 正在检查系统依赖..."
    log_message "INFO" "============================= 依赖检查 ============================"

    # 检查缺失的依赖项
    for dep in "${required_deps[@]}"; do
        if ! which "$dep" > /dev/null 2>&1; then
            missing_deps+=($dep)
            log_message "ERROR" "❌ 未安装: $dep"
        else
            local version=$(eval "$dep --version 2>&1 | head -1 | cut -d ' ' -f2 2>/dev/null || echo '未知'")
            log_message "INFO" "✓ 已安装: $dep (版本: $version)"
        fi
    done

    # 安装缺失的依赖
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_message "INFO" "📥 正在安装缺失的依赖: ${missing_deps[*]}"
        show_progress "正在安装依赖" 10
        execute "sudo apt-get install -y ${missing_deps[*]}"
        log_message "INFO" "✓ 所有依赖已安装完成!"
    else
        log_message "INFO" "✓ 所有依赖已满足!"
    fi

    log_message "INFO" "=================================================================="
    log_message "DEBUG" "依赖检查模块完成"
}

# ========================== 用户交互模块 ==========================

# 密码处理函数 - 改进密码安全性
# 参数: 无
# 返回值: 有效的密码
read_password() {
    local password1
    local password2
    local use_weak

    while true; do
        # 提示输入密码两次
        read -s -p "数据库密码: " password1
        printf "\n"

        read -s -p "请再次输入密码: " password2
        printf "\n"

        # 检查密码是否匹配
        if [ "$password1" != "$password2" ]; then
            log_message "ERROR" "错误: 两次输入的密码不匹配，请重新输入"
            continue
        fi

        # 检查密码长度是否至少8个字符
        if [ ${#password1} -lt 8 ]; then
            log_message "WARN" "⚠️  警告: 密码长度小于8个字符，安全性较低"
            log_message "WARN" "建议使用至少8个字符的强密码，包含字母、数字和特殊字符"
            while true; do
                read -p "是否继续使用该弱密码？(y/n): " use_weak
                if validate_input "yes_no" "$use_weak" "继续使用弱密码"; then
                    break
                fi
            done

            if [ "$use_weak" = "n" ] || [ "$use_weak" = "N" ]; then
                continue  # 让用户重新输入密码
            fi
        else
            log_message "INFO" "✓ 密码强度符合要求"
        fi

        # 返回有效的密码
        printf "%s" "$password1"
        return 0
    done
}

# 进度显示函数
# 参数: $1 - 进度消息
#       $2 - 持续时间(秒)
# 返回值: 无
show_progress() {
    local message="$1"
    local duration="$2"
    local bar_length=40
    local progress=0
    local completed=0

    printf "%b" "${COLORS[YELLOW]}$message ${COLORS[NC]}"

    # Calculate sleep time per progress step
    local sleep_time=$(printf "scale=2; %s / %s" "$duration" "$bar_length" | bc)

    while [ $progress -lt $bar_length ]; do
        # Calculate percentage completed
        completed=$(( (progress + 1) * 100 / bar_length ))

        # Build progress bar
        local bar=$(printf "#%.0s" $(seq 1 $((progress + 1))))
        bar=$(printf "%-${bar_length}s" "$bar")

        # Update progress bar
        printf "\r%b" "${COLORS[YELLOW]}$message [${bar}] ${completed}%${COLORS[NC]}"

        sleep $sleep_time
        progress=$((progress + 1))
    done

    # Final completion message
    printf "\r%b\n" "${COLORS[GREEN]}$message [$(printf "#%.0s" $(seq 1 $bar_length))] 100%${COLORS[NC]}"
    printf "%b\n" "${COLORS[GREEN]}✓ $message 完成!${COLORS[NC]}"
}

# 设置时区的独立函数
# 参数: 无
# 返回值: 无
select_timezone() {
    local TZ_CHOICE

    log_message "INFO" "请选择时区:"
    log_message "INFO" "1) ${DEFAULT_TIMEZONE} (默认)"
    log_message "INFO" "2) Asia/Tokyo"
    log_message "INFO" "3) Europe/London"
    log_message "INFO" "4) America/New_York"
    log_message "INFO" "5) 其他 (请手动输入)"
    read -p "请输入您的选择 (1-5): " TZ_CHOICE
    log_message "INFO" "请选择时区: $TZ_CHOICE"

    # 设置全局时区变量
    case $TZ_CHOICE in
        1) GLOBAL_TIMEZONE="${DEFAULT_TIMEZONE}" ;;
        2) GLOBAL_TIMEZONE="Asia/Tokyo" ;;
        3) GLOBAL_TIMEZONE="Europe/London" ;;
        4) GLOBAL_TIMEZONE="America/New_York" ;;
        5)
            read -p "请输入时区 (例如: Asia/Beijing): " GLOBAL_TIMEZONE
            log_message "INFO" "请输入时区: $GLOBAL_TIMEZONE"
            GLOBAL_TIMEZONE=${GLOBAL_TIMEZONE:-$DEFAULT_TIMEZONE}  # 默认为DEFAULT_TIMEZONE
            ;;
        *) GLOBAL_TIMEZONE="${DEFAULT_TIMEZONE}" ;;
    esac

    # 将选择的时区记录到日志
    log_message "INFO" "选择的时区: $GLOBAL_TIMEZONE"
}

# ========================== Docker 安装模块 ==========================

# Docker 安装函数
# 参数: 无
# 返回值: 无
install_docker() {
    log_message "INFO" "================================================================="
    log_message "INFO" "                     Docker 安装模式"
    log_message "INFO" "================================================================="

    # 安装 Docker 引擎
    log_message "INFO" "正在安装 Docker 引擎..."
    execute "sudo apt-get install -y ca-certificates curl gnupg lsb-release"
    execute "sudo mkdir -p /etc/apt/keyrings"
    execute "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
    execute "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null"
    execute "sudo apt-get update"
    execute "sudo apt-get install -y docker-ce docker-ce-cli containerd.io"

    # 安装 Docker Compose
    log_message "INFO" "正在安装 Docker Compose ${DOCKER_COMPOSE_VERSION}..."
    execute "sudo curl -L \"https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)\" -o /usr/local/bin/docker-compose"
    execute "sudo chmod +x /usr/local/bin/docker-compose"

    # 将用户添加到 docker 组，避免使用 sudo
    log_message "INFO" "正在将当前用户添加到 docker 组..."
    execute "sudo usermod -aG docker $USER"
    log_message "DEBUG" "Docker 安装模块完成"
}

# ========================== npm 安装模块 ==========================

# 安装 NVM
# 参数: 无
# 返回值: 无
install_nvm() {
    log_message "INFO" "正在安装 nvm ${NVM_VERSION}..."
    execute "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash"
    execute "source ~/.bashrc"
}

# 安装 Node.js
# 参数: 无
# 返回值: 无
install_nodejs() {
    log_message "INFO" "正在安装 Node.js ${NODE_VERSION} (长期支持版)..."
    execute "nvm install ${NODE_VERSION}"
    execute "nvm use ${NODE_VERSION}"
}

# 可选安装 pnpm
# 参数: 无
# 返回值: 是否安装了pnpm (true/false)
install_pnpm_optionally() {
    local install_pnpm

    while true; do
        read -p "您想安装 pnpm (比 npm 更快) 吗？(y/n): " install_pnpm
        log_message "INFO" "您想安装 pnpm (比 npm 更快) 吗？(y/n): $install_pnpm"
        validate_input "yes_no" "$install_pnpm" "安装 pnpm" && break
    done

    if [ "$install_pnpm" = "y" ] || [ "$install_pnpm" = "Y" ]; then
        log_message "INFO" "正在安装 pnpm..."
        execute "npm install -g pnpm"
        printf "%s" "true"
    else
        printf "%s" "false"
    fi
}

# 全局安装 n8n
# 参数: $1 - 是否已安装pnpm (true/false)
# 返回值: 无
install_n8n_globally() {
    local pnpm_installed="$1"
    log_message "INFO" "正在全局安装 n8n ${N8N_VERSION}..."
    
    if [ "$pnpm_installed" = "true" ]; then
        execute "pnpm install -g n8n"
    else
        execute "npm install -g n8n"
    fi
}

# 启动 n8n
# 参数: 无
# 返回值: 无
start_n8n() {
    log_message "INFO" "正在启动 n8n..."
    log_message "INFO" "您可以通过 http://${N8N_HOST}:${N8N_PORT} 访问 n8n"
    log_message "INFO" "随时按 Ctrl+C 停止 n8n"
    n8n
}

# npm 安装主函数
# 参数: 无
# 返回值: 无
install_with_npm() {
    log_message "INFO" "================================================================="
    log_message "INFO" "                       npm 安装模式"
    log_message "INFO" "================================================================="

    # 询问是否使用 nvm
    while true; do
        read -p "您想使用 nvm (Node Version Manager) 来管理 Node.js 吗？(y/n): " USE_NVM
        log_message "INFO" "您想使用 nvm (Node Version Manager) 来管理 Node.js 吗？(y/n): $USE_NVM"
        validate_input "yes_no" "$USE_NVM" "使用 nvm" && break
    done

    if [ "$USE_NVM" = "y" ] || [ "$USE_NVM" = "Y" ]; then
        install_nvm
        install_nodejs
    else
        # 通过 nodesource 安装 Node.js
        log_message "INFO" "正在通过 nodesource 安装 Node.js ${NODE_VERSION}..."
        execute "curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -"
        execute "sudo apt-get install -y nodejs"
    fi

    # 安装 build-essential
    log_message "INFO" "正在安装 build-essential..."
    execute "sudo apt install -y build-essential"

    # 验证 Node.js 和 npm
    log_message "INFO" "正在验证 Node.js 和 npm 安装..."
    node --version
    npm --version

    local PNPM_INSTALLED=$(install_pnpm_optionally)
    install_n8n_globally "$PNPM_INSTALLED"
    start_n8n
}

# ========================== 数据库配置模块 ==========================

# 创建 .env 文件辅助函数
# 参数: $1 - 模式 (existing_postgresql, docker_postgresql, existing_mysql, docker_mysql)
# 返回值: 无
create_env_file() {
    local mode="$1"
    local ENV_CONTENT=""

    log_message "INFO" "正在创建 .env 文件..."

    case "$mode" in
        "existing_postgresql")
            ENV_CONTENT="DB_TYPE=postgresdb\n"
            ENV_CONTENT+="DB_POSTGRESDB_HOST=${DB_HOST}\n"
            ENV_CONTENT+="DB_POSTGRESDB_PORT=${DB_PORT}\n"
            ENV_CONTENT+="DB_POSTGRESDB_DATABASE=${DB_NAME}\n"
            ENV_CONTENT+="DB_POSTGRESDB_USER=${DB_USER}\n"
            ENV_CONTENT+="DB_POSTGRESDB_PASSWORD=${DB_PASSWORD}\n"
            ;;

        "docker_postgresql")
            ENV_CONTENT="POSTGRES_USER=${DB_USER}\n"
            ENV_CONTENT+="POSTGRES_PASSWORD=${DB_PASSWORD}\n"
            ENV_CONTENT+="POSTGRES_DB=${DB_NAME}\n"
            ENV_CONTENT+="POSTGRES_NON_ROOT_USER=${DB_USER}\n"
            ENV_CONTENT+="POSTGRES_NON_ROOT_PASSWORD=${DB_PASSWORD}\n"
            ;;

        "existing_mysql")
            ENV_CONTENT="DB_TYPE=mysqldb\n"
            ENV_CONTENT+="DB_MYSQLDB_HOST=${DB_HOST}\n"
            ENV_CONTENT+="DB_MYSQLDB_PORT=${DB_PORT}\n"
            ENV_CONTENT+="DB_MYSQLDB_DATABASE=${DB_NAME}\n"
            ENV_CONTENT+="DB_MYSQLDB_USER=${DB_USER}\n"
            ENV_CONTENT+="DB_MYSQLDB_PASSWORD=${DB_PASSWORD}\n"
            ;;

        "docker_mysql")
            ENV_CONTENT="MYSQL_ROOT_PASSWORD=${DB_PASSWORD}\n"
            ENV_CONTENT+="MYSQL_DATABASE=${DB_NAME}\n"
            ;;

        *)
            log_message "ERROR" "无效的 .env 文件创建模式!"
            return 1
            ;;
    esac

    if [ "$DRY_RUN" = true ]; then
        log_message "INFO" "[DRY-RUN] 将要创建 .env 文件，内容如下:"
        printf "%b\n" "$ENV_CONTENT"
    else
        printf "%b\n" "$ENV_CONTENT" > .env
        log_message "INFO" ".env 文件创建完成"
    fi

    return 0
}

# 创建 init-data.sh 脚本辅助函数
# 参数: 无
# 返回值: 无
create_init_data_script() {
    log_message "INFO" "正在创建PostgreSQL初始化脚本 init-data.sh..."

    local INIT_SCRIPT_CONTENT='#!/bin/bash
set -e;


if [ -n "${POSTGRES_NON_ROOT_USER:-}" ] && [ -n "${POSTGRES_NON_ROOT_PASSWORD:-}" ]; then
	psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
		CREATE USER ${POSTGRES_NON_ROOT_USER} WITH PASSWORD "${POSTGRES_NON_ROOT_PASSWORD}";
		GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_DB} TO ${POSTGRES_NON_ROOT_USER};
		GRANT CREATE ON SCHEMA public TO ${POSTGRES_NON_ROOT_USER};
	EOSQL
else
	echo "SETUP INFO: No Environment variables given!"
fi'

    if [ "$DRY_RUN" = true ]; then
        log_message "INFO" "[DRY-RUN] 将要创建 init-data.sh 文件，内容如下:"
        printf "%b\n" "$INIT_SCRIPT_CONTENT"
    else
        printf "%b\n" "$INIT_SCRIPT_CONTENT" > init-data.sh
        chmod +x init-data.sh  # Ensure script is executable
        log_message "INFO" "PostgreSQL初始化脚本 init-data.sh 创建完成"
    fi
}

# 生成 SQLite docker-compose.yml 内容
# 参数: 无
# 返回值: SQLite docker-compose.yml 内容
generate_docker_compose_sqlite() {
    local content=$(cat <<EOF
version: '3.8'

services:
  n8n:
    image: docker.n8n.io/n8nio/n8n:${N8N_VERSION}
    restart: always
    ports:
      - ${N8N_PORT}:5678
    volumes:
      - ./n8n_data:/home/node/.n8n
    environment:
      - N8N_HOST=${N8N_HOST}
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - NODE_ENV=production
      - TZ=${GLOBAL_TIMEZONE}
      - GENERIC_TIMEZONE=${GLOBAL_TIMEZONE}
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_RUNNERS_ENABLED=true
EOF
)
    printf "%s" "$content"
}

# 生成 PostgreSQL 现有数据库 docker-compose.yml 内容
# 参数: 无
# 返回值: PostgreSQL 现有数据库 docker-compose.yml 内容
generate_docker_compose_postgres_existing() {
    local content=$(cat <<EOF
version: '3.8'

services:
  n8n:
    image: docker.n8n.io/n8nio/n8n:${N8N_VERSION}
    restart: always
    ports:
      - ${N8N_PORT}:5678
    volumes:
      - ./n8n_data:/home/node/.n8n
    environment:
      - N8N_HOST=${N8N_HOST}
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - NODE_ENV=production
      - TZ=${GLOBAL_TIMEZONE}
      - GENERIC_TIMEZONE=${GLOBAL_TIMEZONE}
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_RUNNERS_ENABLED=true
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=\${DB_POSTGRESDB_HOST}
      - DB_POSTGRESDB_PORT=\${DB_POSTGRESDB_PORT}
      - DB_POSTGRESDB_DATABASE=\${DB_POSTGRESDB_DATABASE}
      - DB_POSTGRESDB_USER=\${DB_POSTGRESDB_USER}
      - DB_POSTGRESDB_PASSWORD=\${DB_POSTGRESDB_PASSWORD}
EOF
)
    printf "%s" "$content"
}

# 生成 PostgreSQL Docker 数据库 docker-compose.yml 内容
# 参数: 无
# 返回值: PostgreSQL Docker 数据库 docker-compose.yml 内容
generate_docker_compose_postgres_docker() {
    local content=$(cat <<EOF
version: '3.8'

volumes:
  db_storage:
  n8n_storage:

services:
  postgres:
    image: postgres:${POSTGRES_VERSION}
    restart: always
    environment:
      - POSTGRES_USER
      - POSTGRES_PASSWORD
      - POSTGRES_DB
      - POSTGRES_NON_ROOT_USER
      - POSTGRES_NON_ROOT_PASSWORD
    volumes:
      - db_storage:/var/lib/postgresql/data
      - ./init-data.sh:/docker-entrypoint-initdb.d/init-data.sh
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -h localhost -U \${POSTGRES_USER} -d \${POSTGRES_DB}']
      interval: 5s
      timeout: 5s
      retries: 10
      start_period: 30s

  n8n:
    image: docker.n8n.io/n8nio/n8n:${N8N_VERSION}
    restart: always
    ports:
      - ${N8N_PORT}:5678
    volumes:
      - n8n_storage:/home/node/.n8n
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      - N8N_HOST=${N8N_HOST}
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - NODE_ENV=production
      - TZ=${GLOBAL_TIMEZONE}
      - GENERIC_TIMEZONE=${GLOBAL_TIMEZONE}
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_RUNNERS_ENABLED=true
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=\${POSTGRES_DB}
      - DB_POSTGRESDB_USER=\${POSTGRES_NON_ROOT_USER}
      - DB_POSTGRESDB_PASSWORD=\${POSTGRES_NON_ROOT_PASSWORD}
EOF
)
    printf "%s" "$content"
}

# 生成 MySQL 现有数据库 docker-compose.yml 内容
# 参数: 无
# 返回值: MySQL 现有数据库 docker-compose.yml 内容
generate_docker_compose_mysql_existing() {
    local content=$(cat <<EOF
version: '3.8'

services:
  n8n:
    image: docker.n8n.io/n8nio/n8n:${N8N_VERSION}
    restart: always
    ports:
      - ${N8N_PORT}:5678
    volumes:
      - ./n8n_data:/home/node/.n8n
    environment:
      - N8N_HOST=${N8N_HOST}
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - NODE_ENV=production
      - TZ=${GLOBAL_TIMEZONE}
      - GENERIC_TIMEZONE=${GLOBAL_TIMEZONE}
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_RUNNERS_ENABLED=true
      - DB_TYPE=mysqldb
      - DB_MYSQLDB_HOST=\${DB_MYSQLDB_HOST}
      - DB_MYSQLDB_PORT=\${DB_MYSQLDB_PORT}
      - DB_MYSQLDB_DATABASE=\${DB_MYSQLDB_DATABASE}
      - DB_MYSQLDB_USER=\${DB_MYSQLDB_USER}
      - DB_MYSQLDB_PASSWORD=\${DB_MYSQLDB_PASSWORD}
EOF
)
    printf "%s" "$content"
}

# 生成 MySQL Docker 数据库 docker-compose.yml 内容
# 参数: 无
# 返回值: MySQL Docker 数据库 docker-compose.yml 内容
generate_docker_compose_mysql_docker() {
    local content=$(cat <<EOF
version: '3.8'

volumes:
  mysql_storage:
  n8n_storage:

services:
  mysql:
    image: mysql:8.0
    restart: always
    environment:
      - MYSQL_ROOT_PASSWORD
      - MYSQL_DATABASE
    volumes:
      - mysql_storage:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "--password=\${MYSQL_ROOT_PASSWORD}"]
      interval: 5s
      timeout: 5s
      retries: 10
      start_period: 30s

  n8n:
    image: docker.n8n.io/n8nio/n8n:${N8N_VERSION}
    restart: always
    ports:
      - ${N8N_PORT}:5678
    volumes:
      - n8n_storage:/home/node/.n8n
    depends_on:
      mysql:
        condition: service_healthy
    environment:
      - N8N_HOST=${N8N_HOST}
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - NODE_ENV=production
      - TZ=${GLOBAL_TIMEZONE}
      - GENERIC_TIMEZONE=${GLOBAL_TIMEZONE}
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_RUNNERS_ENABLED=true
      - DB_TYPE=mysqldb
      - DB_MYSQLDB_HOST=mysql
      - DB_MYSQLDB_PORT=3306
      - DB_MYSQLDB_DATABASE=\${MYSQL_DATABASE}
      - DB_MYSQLDB_USER=root
      - DB_MYSQLDB_PASSWORD=\${MYSQL_ROOT_PASSWORD}
EOF
)
    printf "%s" "$content"
}

# 生成 docker-compose.yml 内容
# 参数: $1 - 数据库类型 (sqlite, postgres_docker, postgres_existing, mysql_docker, mysql_existing)
# 返回值: docker-compose.yml 内容
generate_docker_compose_content() {
    local db_type="$1"
    local content=""

    case "$db_type" in
        "sqlite")
            content=$(generate_docker_compose_sqlite)
            ;;

        "postgres_existing")
            content=$(generate_docker_compose_postgres_existing)
            ;;

        "postgres_docker")
            content=$(generate_docker_compose_postgres_docker)
            ;;

        "mysql_existing")
            content=$(generate_docker_compose_mysql_existing)
            ;;

        "mysql_docker")
            content=$(generate_docker_compose_mysql_docker)
            ;;

        *)
            log_message "ERROR" "无效的数据库类型"
            return 1
            ;;
    esac

    printf "%s" "$content"
}

# 创建 docker-compose.yml 文件函数
# 参数: $1 - docker-compose.yml 内容
# 返回值: 无
create_docker_compose_file() {
    local content="$1"
    log_message "INFO" "正在创建 docker-compose.yml 文件..."

    if [ "$DRY_RUN" = true ]; then
        log_message "INFO" "[DRY-RUN] 将要创建 docker-compose.yml 文件，内容如下:"
        printf "%b\n" "$content"
    else
        printf "%b\n" "$content" > docker-compose.yml
        log_message "INFO" "docker-compose.yml 文件创建完成"
    fi
}

# 创建 n8n_data 目录函数
# 参数: 无
# 返回值: 无
create_n8n_data_directory() {
    log_message "INFO" "正在创建 n8n_data 目录..."
    execute "mkdir -p ./n8n_data"
}

# 启动服务函数
# 参数: 无
# 返回值: 无
start_services() {
    log_message "INFO" "正在使用 Docker Compose 启动 n8n..."
    execute "docker-compose up -d"

    # 等待服务启动
    show_progress "正在等待 n8n 服务启动" 10

    log_message "INFO" "n8n 已成功安装!"
    log_message "INFO" "您可以通过 http://${N8N_HOST}:${N8N_PORT} 访问 n8n"

    log_message "INFO" "有用的 Docker 命令:"
    log_message "INFO" "- 停止 n8n: docker-compose down"
    log_message "INFO" "- 重启 n8n: docker-compose restart"
    log_message "INFO" "- 查看日志: docker-compose logs -f"
}

# SQLite 数据库配置函数
# 参数: 无
# 返回值: 0表示成功，非0表示失败
configure_database_sqlite() {
    log_message "INFO" "================================================================="
    log_message "INFO" "                     SQLite 安装模式"
    log_message "INFO" "================================================================="

    # 准备 docker-compose.yml 内容
    local DOCKER_COMPOSE_CONTENT=$(generate_docker_compose_content "sqlite")
    create_docker_compose_file "$DOCKER_COMPOSE_CONTENT"
    return 0
}

# PostgreSQL 数据库配置函数
# 参数: 无
# 返回值: 0表示成功，非0表示失败
configure_database_postgresql() {
    local PG_INSTALLED=false
    local USE_EXISTING_PG="n"
    local local_db_host
    local local_db_port
    local local_db_name
    local local_db_user
    local local_db_password

    # 检查本地是否已安装 PostgreSQL
    if dpkg -l | grep -q "postgresql\s" 2>/dev/null; then
        PG_INSTALLED=true
    fi

    # 如果本地已安装 PostgreSQL，询问用户选择
    if [ "$PG_INSTALLED" = true ]; then
        log_message "INFO" "检测到本地已安装 PostgreSQL!"
        while true; do
            read -p "是否使用已安装的 PostgreSQL？(y/n，默认: n): " USE_EXISTING_PG_TMP
            USE_EXISTING_PG=${USE_EXISTING_PG_TMP:-n}

            if validate_input "yes_no" "$USE_EXISTING_PG" "使用已安装的 PostgreSQL"; then
                log_message "INFO" "是否使用已安装的 PostgreSQL: $USE_EXISTING_PG"
                break
            fi
        done
    fi

    # 收集所有 PostgreSQL 参数
    log_message "INFO" "请输入 PostgreSQL 数据库信息:"

    if [ "$USE_EXISTING_PG" = "y" ] || [ "$USE_EXISTING_PG" = "Y" ]; then
        read -p "数据库主机 (默认: localhost): " local_db_host
        local_db_host=${local_db_host:-localhost}
    else
        read -p "数据库主机: " local_db_host
    fi
    log_message "INFO" "PostgreSQL 数据库信息: 数据库主机: $local_db_host"

    # 验证数据库端口
    while true; do
        read -p "数据库端口 (默认: 5432): " local_db_port_tmp
        local_db_port=${local_db_port_tmp:-5432}  # 设置默认端口

        if validate_input "port" "$local_db_port" "数据库端口"; then
            log_message "INFO" "PostgreSQL 数据库信息: 数据库端口: $local_db_port"
            break
        fi
    done

    # 验证数据库名称
    while true; do
        read -p "数据库名称 (默认: n8n): " local_db_name_tmp
        local_db_name=${local_db_name_tmp:-n8n}  # 设置默认数据库名称

        if validate_input "database_name" "$local_db_name" "数据库名称"; then
            log_message "INFO" "PostgreSQL 数据库信息: 数据库名称: $local_db_name"
            break
        fi
    done

    read -p "数据库用户 (默认: postgres): " local_db_user
    local_db_user=${local_db_user:-postgres}  # 设置默认用户
    log_message "INFO" "PostgreSQL 数据库信息: 数据库用户: $local_db_user"

    local_db_password=$(read_password)
    log_message "INFO" "PostgreSQL 数据库信息: 数据库密码: ****"
    printf "\n\n"

    # 处理已安装的 PostgreSQL 逻辑
    if [ "$USE_EXISTING_PG" = "y" ] || [ "$USE_EXISTING_PG" = "Y" ]; then
        handle_existing_postgresql "$timezone" "$local_db_host" "$local_db_port" "$local_db_name" "$local_db_user" "$local_db_password"
    else
        handle_docker_postgresql "$timezone" "$local_db_host" "$local_db_port" "$local_db_name" "$local_db_user" "$local_db_password"
    fi

    return 0
}

# MySQL 数据库配置函数
# 参数: 无
# 返回值: 0表示成功，非0表示失败
configure_database_mysql() {
    local MYSQL_INSTALLED=false
    local USE_EXISTING_MYSQL="n"
    local local_db_host
    local local_db_port
    local local_db_name
    local local_db_user
    local local_db_password

    # 检查本地是否已安装 MySQL
    if dpkg -l | grep -q "mysql-server\s" 2>/dev/null || dpkg -l | grep -q "mariadb-server\s" 2>/dev/null; then
        MYSQL_INSTALLED=true
    fi

    # 如果本地已安装 MySQL，询问用户选择
    if [ "$MYSQL_INSTALLED" = true ]; then
        log_message "INFO" "检测到本地已安装 MySQL/MariaDB!"
        while true; do
            read -p "是否使用已安装的 MySQL/MariaDB？(y/n，默认: n): " USE_EXISTING_MYSQL_TMP
            USE_EXISTING_MYSQL=${USE_EXISTING_MYSQL_TMP:-n}

            if validate_input "yes_no" "$USE_EXISTING_MYSQL" "使用已安装的 MySQL/MariaDB"; then
                log_message "INFO" "是否使用已安装的 MySQL/MariaDB: $USE_EXISTING_MYSQL"
                break
            fi
        done
    fi

    # 收集所有 MySQL 参数
    log_message "INFO" "请输入 MySQL 数据库信息:"

    if [ "$USE_EXISTING_MYSQL" = "y" ] || [ "$USE_EXISTING_MYSQL" = "Y" ]; then
        read -p "数据库主机 (默认: localhost): " local_db_host
        local_db_host=${local_db_host:-localhost}  # 设置默认主机为 localhost
    else
        read -p "数据库主机: " local_db_host
    fi
    log_message "INFO" "MySQL 数据库信息: 数据库主机: $local_db_host"

    # 验证数据库端口
    while true; do
        read -p "数据库端口 (默认: 3306): " local_db_port_tmp
        local_db_port=${local_db_port_tmp:-3306}  # 设置默认端口

        if validate_input "port" "$local_db_port" "数据库端口"; then
            log_message "INFO" "MySQL 数据库信息: 数据库端口: $local_db_port"
            break
        fi
    done

    # 验证数据库名称
    while true; do
        read -p "数据库名称 (默认: n8n): " local_db_name_tmp
        local_db_name=${local_db_name_tmp:-n8n}  # 设置默认数据库名称

        if validate_input "database_name" "$local_db_name" "数据库名称"; then
            log_message "INFO" "MySQL 数据库信息: 数据库名称: $local_db_name"
            break
        fi
    done

    read -p "数据库用户 (默认: root): " local_db_user
    local_db_user=${local_db_user:-root}  # 设置默认用户
    log_message "INFO" "MySQL 数据库信息: 数据库用户: $local_db_user"

    local_db_password=$(read_password)
    log_message "INFO" "MySQL 数据库信息: 数据库密码: ****"
    printf "\n\n"

    # 处理已安装的 MySQL 逻辑
    if [ "$USE_EXISTING_MYSQL" = "y" ] || [ "$USE_EXISTING_MYSQL" = "Y" ]; then
        handle_existing_mysql "$local_db_host" "$local_db_port" "$local_db_name" "$local_db_user" "$local_db_password"
    else
        handle_docker_mysql "$local_db_host" "$local_db_port" "$local_db_name" "$local_db_user" "$local_db_password"
    fi

    return 0
}

# 处理已安装的 PostgreSQL 辅助函数
# 参数: $1 - 时区
#       $2 - 数据库主机
#       $3 - 数据库端口
#       $4 - 数据库名称
#       $5 - 数据库用户
#       $6 - 数据库密码
# 返回值: 无
handle_existing_postgresql() {
    local db_host="$1"
    local db_port="$2"
    local db_name="$3"
    local db_user="$4"
    local db_password="$5"
    local max_retries=3
    local retry_count=0

    # 检查数据库是否存在，如果不存在则创建
    log_message "INFO" "正在检查并创建数据库..."
    log_message "INFO" "当前正在执行 PostgreSQL 权限配置..."

    # 权限配置提示
    log_message "INFO" "📋 PostgreSQL 权限配置计划:"
    log_message "INFO" "- 将创建数据库(如果不存在): $db_name"
    log_message "INFO" "- 将创建用户(如果不存在): $db_user"
    log_message "INFO" "- 将授予用户对数据库的所有权限"
    log_message "INFO" "- 将授予用户对public模式的CREATE权限"

    # 保存到全局变量，以便create_env_file使用 - 后续版本将改进此设计
    DB_HOST="$db_host"
    DB_PORT="$db_port"
    DB_NAME="$db_name"
    DB_USER="$db_user"
    DB_PASSWORD="$db_password"

    # 尝试连接到PostgreSQL服务器并执行操作，支持重试
    while [ $retry_count -lt $max_retries ]; do
        log_message "INFO" "正在尝试连接到PostgreSQL服务器... (尝试 $((retry_count+1))/$max_retries)"
        
        if [ "$DRY_RUN" = true ]; then
            # DRY-RUN模式下跳过实际执行
            log_message "INFO" "[DRY-RUN] 将要执行数据库配置命令"
            break
        else
            # 测试PostgreSQL连接
            if sudo -u postgres psql -c "SELECT 1;" > /dev/null 2>&1; then
                log_message "INFO" "✓ 成功连接到PostgreSQL服务器"
                
                # 执行数据库配置命令
                log_message "INFO" "正在配置数据库..."
                if sudo -u postgres psql -c "CREATE DATABASE IF NOT EXISTS $db_name;" && \
                   sudo -u postgres psql -c "CREATE USER IF NOT EXISTS $db_user WITH PASSWORD '$db_password';" && \
                   sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $db_name TO $db_user;" && \
                   sudo -u postgres psql -c "GRANT CREATE ON SCHEMA public TO $db_user;"; then
                    
                    log_message "INFO" "✓ PostgreSQL数据库配置成功!"
                    break
                else
                    log_message "ERROR" "❌ 数据库配置失败，请检查您的PostgreSQL权限设置"
                fi
            else
                log_message "ERROR" "❌ 无法连接到PostgreSQL服务器"
                log_message "INFO" "可能的原因:" 
                log_message "INFO" "- PostgreSQL服务未启动" 
                log_message "INFO" "- 当前用户没有sudo权限" 
                log_message "INFO" "- postgres系统用户不存在"
            fi
        fi
        
        retry_count=$((retry_count+1))
        
        if [ $retry_count -lt $max_retries ]; then
            log_message "INFO" "将在3秒后重试..."
            sleep 3
        else
            log_message "ERROR" "❌ 数据库配置失败，已达到最大重试次数" 
            log_message "INFO" "建议解决方法:" 
            log_message "INFO" "- 手动检查PostgreSQL服务状态: sudo systemctl status postgresql" 
            log_message "INFO" "- 确保当前用户有sudo权限: sudo -l" 
            log_message "INFO" "- 手动创建数据库和用户: sudo -u postgres psql"
            return 1
        fi
    done

    # 创建 .env 文件
    create_env_file "existing_postgresql"

    # 准备 docker-compose.yml 内容
    local docker_compose_content=$(generate_docker_compose_content "postgres_existing" "$timezone")
    create_docker_compose_file "$docker_compose_content"
}

# 处理 Docker PostgreSQL 辅助函数
# 参数: $1 - 时区
#       $2 - 数据库主机
#       $3 - 数据库端口
#       $4 - 数据库名称
#       $5 - 数据库用户
#       $6 - 数据库密码
# 返回值: 无
handle_docker_postgresql() {
    local db_host="$1"
    local db_port="$2"
    local db_name="$3"
    local db_user="$4"
    local db_password="$5"

    # 保存到全局变量，以便create_env_file使用 - 后续版本将改进此设计
    DB_HOST="$db_host"
    DB_PORT="$db_port"
    DB_NAME="$db_name"
    DB_USER="$db_user"
    DB_PASSWORD="$db_password"

    if [ "$db_host" = "localhost" ] || [ "$db_host" = "127.0.0.1" ] || [ -z "$db_host" ]; then
        # Local Docker PostgreSQL
        log_message "INFO" "注意: 本地PostgreSQL安装已替换为Docker方式，将自动创建PostgreSQL容器..."

        # Create .env file for Docker
        create_env_file "docker_postgresql"

        # Create init-data.sh script
        create_init_data_script

        # Create docker-compose.yml with PostgreSQL service
        local docker_compose_content=$(generate_docker_compose_content "postgres_docker" "$timezone")
        create_docker_compose_file "$docker_compose_content"
    else
        # External PostgreSQL
        # Create .env file
        create_env_file "existing_postgresql"

        # Create docker-compose.yml content
        local docker_compose_content=$(generate_docker_compose_content "postgres_existing" "$timezone")
        create_docker_compose_file "$docker_compose_content"
    fi
}

# 处理已安装的 MySQL 辅助函数
# 参数: $1 - 时区
#       $2 - 数据库主机
#       $3 - 数据库端口
#       $4 - 数据库名称
#       $5 - 数据库用户
#       $6 - 数据库密码
# 返回值: 无
handle_existing_mysql() {
    local db_host="$1"
    local db_port="$2"
    local db_name="$3"
    local db_user="$4"
    local db_password="$5"

    # 保存到全局变量，以便create_env_file使用 - 后续版本将改进此设计
    DB_HOST="$db_host"
    DB_PORT="$db_port"
    DB_NAME="$db_name"
    DB_USER="$db_user"
    DB_PASSWORD="$db_password"

    # 创建 .env 文件
    create_env_file "existing_mysql"

    # 准备 docker-compose.yml 内容
    local docker_compose_content=$(generate_docker_compose_content "mysql_existing")
    create_docker_compose_file "$docker_compose_content"
}

# 处理 Docker MySQL 辅助函数
# 参数: $1 - 时区
#       $2 - 数据库主机
#       $3 - 数据库端口
#       $4 - 数据库名称
#       $5 - 数据库用户
#       $6 - 数据库密码
# 返回值: 无
handle_docker_mysql() {
    local db_host="$1"
    local db_port="$2"
    local db_name="$3"
    local db_user="$4"
    local db_password="$5"

    # 保存到全局变量，以便create_env_file使用 - 后续版本将改进此设计
    DB_HOST="$db_host"
    DB_PORT="$db_port"
    DB_NAME="$db_name"
    DB_USER="$db_user"
    DB_PASSWORD="$db_password"

    if [ "$db_host" = "localhost" ] || [ "$db_host" = "127.0.0.1" ] || [ -z "$db_host" ]; then
        # Local Docker MySQL
        log_message "INFO" "注意: 将自动创建MySQL容器..."

        # Create .env file for Docker
        create_env_file "docker_mysql"

        # Create docker-compose.yml with MySQL service
        local docker_compose_content=$(generate_docker_compose_content "mysql_docker")
        create_docker_compose_file "$docker_compose_content"
    else
        # External MySQL
        # Create .env file
        create_env_file "existing_mysql"

        # Create docker-compose.yml content
        local docker_compose_content=$(generate_docker_compose_content "mysql_existing")
        create_docker_compose_file "$docker_compose_content"
    fi
}

# 主数据库配置函数 - 根据用户选择调用不同的数据库配置函数
# 参数: 无
# 返回值: 0表示成功，非0表示失败
configure_database() {
    # 询问数据库选择
    log_message "INFO" "请选择数据库类型:"
    log_message "INFO" "1) SQLite (默认，无需凭证)"
    log_message "INFO" "2) PostgreSQL (需要数据库凭证)"
    log_message "INFO" "3) MySQL (需要数据库凭证)"
    read -p "请输入您的选择 (1/2/3): " DB_CHOICE
    log_message "INFO" "请选择数据库类型: $DB_CHOICE"

    case $DB_CHOICE in
        1)
            configure_database_sqlite
            ;;
        2)
            configure_database_postgresql
            ;;
        3)
            configure_database_mysql
            ;;
        *)
            log_message "ERROR" "无效的选择!"
            return 1
            ;;
    esac
}

# 安装完成提示函数
# 参数: 无
# 返回值: 无
print_install_completion() {
    log_message "INFO" "================================================================="
    log_message "INFO" "                    安装完成!"
    log_message "INFO" "================================================================="
    log_message "INFO" "安装后步骤:"
    log_message "INFO" "1. 通过 http://${N8N_HOST}:${N8N_PORT} 访问 n8n"
    log_message "INFO" "2. 使用您的电子邮件创建一个账户"
    log_message "INFO" "3. 开始构建工作流!"

    log_message "INFO" "如需更多信息，请访问: https://docs.n8n.io/"
    log_message "INFO" "================================================================="
}

# ========================== 主函数 ==========================

# 主函数负责调用所有模块并集中处理错误
# 参数: $@ - 命令行参数
# 返回值: 0表示成功，非0表示失败
main() {
    # 调用初始化函数
    initialize "$@"

    # 打印欢迎信息
    print_welcome

    # 检查系统
    check_system || handle_error $? $LINENO "check_system"

    # 权限检查
    check_permissions || handle_error $? $LINENO "check_permissions"

    # 检查依赖
    check_dependencies || handle_error $? $LINENO "check_dependencies"

    # 更新系统包
    update_system_packages || handle_error $? $LINENO "update_system_packages"
    
    # 选择时区
    select_timezone

    # 询问安装方式
    log_message "INFO" "请选择安装方式:"
    log_message "INFO" "1) npm (推荐用于开发环境)"
    log_message "INFO" "2) Docker (推荐用于生产环境)"
    read -p "请输入您的选择 (1/2): " INSTALL_METHOD
    log_message "INFO" "请选择安装方式: $INSTALL_METHOD"

    case $INSTALL_METHOD in
        1)
            install_with_npm || handle_error $? $LINENO "install_with_npm"
            print_install_completion || handle_error $? $LINENO "print_install_completion"
            ;;
        2)
            install_docker || handle_error $? $LINENO "install_docker"
            configure_database || handle_error $? $LINENO "configure_database"
            create_n8n_data_directory || handle_error $? $LINENO "create_n8n_data_directory"
            start_services || handle_error $? $LINENO "start_services"
            print_install_completion || handle_error $? $LINENO "print_install_completion"
            ;;
        *)
            log_message "ERROR" "无效的选择!"
            handle_error 1 $LINENO "Invalid installation method choice"
            ;;
    esac

    return 0
}

# 调用主函数
main "$@"