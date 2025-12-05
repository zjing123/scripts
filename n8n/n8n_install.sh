#!/bin/bash

# ==================================================================
# n8n Linux 一键安装脚本
# 这个脚本在 Linux 系统上交互式安装 n8n
# ==================================================================

# ========================== 配置变量 ==========================
# 脚本配置
readonly SCRIPT_NAME="n8n_installer.sh"
readonly SCRIPT_VERSION="1.2.0"

# n8n 配置
readonly N8N_VERSION="latest"
readonly N8N_HOST="localhost"
readonly N8N_PORT="5678"

# 依赖版本
readonly DOCKER_COMPOSE_VERSION="v2.23.3"
readonly NVM_VERSION="v0.39.5"
readonly NODE_VERSION="v20"
readonly POSTGRES_VERSION="16"

# 路径配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="$SCRIPT_DIR/n8n_install.log"

# 其他配置
readonly DEFAULT_TIMEZONE="Asia/Shanghai"
# 全局时区变量，所有函数将使用这个变量
GLOBAL_TIMEZONE=""

# ========================== 初始化模块 ==========================
# 颜色定义 - 使用数组统一管理
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

# 默认关闭 dry-run 模式
DRY_RUN=false

# 默认关闭 DEBUG 模式
DEBUG=${DEBUG:-false}

# 日志消息函数 - 支持结构化日志
# 支持的日志级别: INFO, WARN, ERROR, DEBUG
# DEBUG 消息仅在 DEBUG 变量设置为 true 时显示
# 同时输出到控制台(带颜色)和日志文件(纯文本)
log_message() {
    local level=$1
    local message=$2

    # 转换为大写
    level=$(echo "$level" | tr '[:lower:]' '[:upper:]')

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
    echo -e "$console_output"

    # 输出到日志文件
    echo "$file_output" >> "$LOG_FILE"
}

# Progress indicator function
show_progress() {
    local message="$1"
    local duration="$2"
    local bar_length=40
    local progress=0
    local completed=0

    echo -e -n "${COLORS[YELLOW]}$message ${COLORS[NC]}"

    # Calculate sleep time per progress step
    local sleep_time=$(echo "scale=2; $duration / $bar_length" | bc)

    while [ $progress -lt $bar_length ]; do
        # Calculate percentage completed
        completed=$(( (progress + 1) * 100 / bar_length ))

        # Build progress bar
        local bar=$(printf "#%.0s" $(seq 1 $((progress + 1))))
        bar=$(printf "%-${bar_length}s" "$bar")

        # Update progress bar
        echo -e -n "\r${COLORS[YELLOW]}$message [${bar}] ${completed}%${COLORS[NC]}"

        sleep $sleep_time
        progress=$((progress + 1))
    done

    # Final completion message
    echo -e "\r${COLORS[GREEN]}$message [$(printf "#%.0s" $(seq 1 $bar_length))] 100%${COLORS[NC]}"
    echo -e "${COLORS[GREEN]}✓ $message 完成!${COLORS[NC]}"
}

# Dependency check function
# 检查并安装必要的依赖项
check_dependencies() {
    # 只保留必要的依赖项
    local required_deps=("curl" "wget" "sudo")
    local missing_deps=()

    log_message "INFO" "============================= 依赖检查 ============================"

    # Check for missing dependencies
    for dep in "${required_deps[@]}"; do
        if ! which "$dep" > /dev/null 2>&1; then
            missing_deps+=("$dep")
        else
            log_message "INFO" "✓ 已安装: $dep"
        fi
    done

    # Install missing dependencies
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_message "INFO" "正在安装缺失的依赖: ${missing_deps[*]}"
        execute "sudo apt-get install -y ${missing_deps[*]}"
        log_message "INFO" "所有依赖已安装完成!"
    else
        log_message "INFO" "所有依赖已满足!"
    fi

    log_message "INFO" "=================================================================="
    log_message "DEBUG" "依赖检查模块完成"
}

# 密码处理函数 - 改进密码安全性
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
            printf "${COLORS[RED]}错误: 两次输入的密码不匹配，请重新输入${COLORS[NC]}\n"
            continue
        fi

        # 检查密码长度是否至少8个字符
        if [ ${#password1} -lt 8 ]; then
            printf "${COLORS[YELLOW]}警告: 密码长度小于8个字符，安全性较低${COLORS[NC]}\n"
            while true; do
                read -p "是否继续使用该弱密码？(y/n): " use_weak
                if validate_input "yes_no" "$use_weak" "继续使用弱密码"; then
                    break
                fi
            done

            if [ "$use_weak" = "n" ] || [ "$use_weak" = "N" ]; then
                continue  # 让用户重新输入密码
            fi
        fi

        # 返回有效的密码
        echo "$password1"
        return 0
    done
}

# 权限检查函数 - 检查root用户和sudo权限
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
                    return 1  # 返回错误码，不在函数内直接exit
                fi

                break
            fi
        done
    fi

    # 检查是否有sudo权限
    if ! sudo -n true 2>/dev/null; then
        log_message "ERROR" "当前用户没有sudo权限，无法完成安装"
        return 1  # 返回错误码，不在函数内直接exit
    fi

    log_message "INFO" "权限检查通过"
    return 0
}

# 错误处理函数
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
validate_input() {
    local type="$1"
    local input="$2"
    local field_name="$3"

    case "$type" in
        "port")
            if ! [[ "$input" =~ ^[0-9]+$ ]] || [ "$input" -lt 1 ] || [ "$input" -gt 65535 ]; then
                echo -e "${COLORS[RED]}错误: 无效的端口号 '$input'${COLORS[NC]}"
                echo -e "${COLORS[YELLOW]}端口号必须是1-65535之间的整数${COLORS[NC]}"
                return 1
            fi
            ;;
        "database_name")
            if ! [[ "$input" =~ ^[a-zA-Z0-9_]+$ ]]; then
                echo -e "${COLORS[RED]}错误: 无效的数据库名称 '$input'${COLORS[NC]}"
                echo -e "${COLORS[YELLOW]}数据库名称只能包含字母、数字和下划线${COLORS[NC]}"
                return 1
            fi
            ;;
        "yes_no")
            if [ "$input" != "y" ] && [ "$input" != "Y" ] && [ "$input" != "n" ] && [ "$input" != "N" ]; then
                echo -e "${COLORS[RED]}错误: 无效的输入 '$input'${COLORS[NC]}"
                echo -e "${COLORS[YELLOW]}请输入 y (是) 或 n (否)${COLORS[NC]}"
                return 1
            fi
            ;;
        *)
            echo -e "${COLORS[RED]}错误: 不支持的验证类型 '$type'${COLORS[NC]}"
            return 1
            ;;
    esac
    return 0
}

# 初始化函数
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

# 执行命令函数 - 支持 dry-run 模式
execute() {
    if [ "$DRY_RUN" = true ]; then
        log_message "INFO" "[DRY-RUN] 将要执行命令: $@"
    else
        eval "$@"
    fi
}

# ========================== 系统检查模块 ==========================
# 欢迎信息
print_welcome() {
    log_message "INFO" "================================================================="
    log_message "INFO" "                      n8n 一键安装脚本"
    log_message "INFO" "                        版本: ${SCRIPT_VERSION}"
    log_message "INFO" "================================================================="
    log_message "INFO" "                      支持: Ubuntu/Debian 系统"
    log_message "INFO" "================================================================="
}

# 检查系统是否为 Ubuntu/Debian
check_system() {
    if [ -z "$(which apt-get 2>/dev/null)" ]; then
        log_message "ERROR" "这个脚本只支持 Ubuntu/Debian 系统!"
        return 1  # 返回错误码，不在函数内直接exit
    fi
    log_message "DEBUG" "系统检查通过"
    return 0
}

# 更新系统包
update_system_packages() {
    # Note: We can't show real-time progress for apt commands, but we can show a loading indicator
    log_message "INFO" "正在更新系统包..."
    # The actual update happens in execute, but we'll show a progress indicator that runs concurrently
    execute "sudo apt update && sudo apt upgrade -y"
}

# ========================== npm 安装模块 ==========================
# npm 安装函数
install_npm() {
    log_message "INFO" "================================================================="
    log_message "INFO" "                       npm 安装模式"
    log_message "INFO" "================================================================="

    # 询问是否使用 nvm
    while true; do
        read -p "您想使用 nvm (Node Version Manager) 来管理 Node.js 吗？(y/n): " USE_NVM
        echo "您想使用 nvm (Node Version Manager) 来管理 Node.js 吗？(y/n): $USE_NVM" >> "$LOG_FILE"
        validate_input "yes_no" "$USE_NVM" "使用 nvm" && break
    done

    if [ "$USE_NVM" = "y" ] || [ "$USE_NVM" = "Y" ]; then
        # 安装 nvm
        echo -e "${COLORS[YELLOW]}正在安装 nvm ${NVM_VERSION}...${COLORS[NC]}"
        execute "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash"
        execute "source ~/.bashrc"

        # 安装 Node.js
        echo -e "${COLORS[YELLOW]}正在安装 Node.js ${NODE_VERSION} (长期支持版)...${COLORS[NC]}"
        execute "nvm install ${NODE_VERSION}"
        execute "nvm use ${NODE_VERSION}"
    else
        # 通过 nodesource 安装 Node.js
        echo -e "${COLORS[YELLOW]}正在通过 nodesource 安装 Node.js ${NODE_VERSION}...${COLORS[NC]}"
        execute "curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -"
        execute "sudo apt-get install -y nodejs"
    fi

    # 验证 Node.js 和 npm
    echo -e "${COLORS[YELLOW]}正在验证 Node.js 和 npm 安装...${COLORS[NC]}"
    node --version
    npm --version

    # 安装 build-essential
    echo -e "${COLORS[YELLOW]}正在安装 build-essential...${COLORS[NC]}"
    execute "sudo apt install -y build-essential"

    # 询问是否安装 pnpm
    while true; do
        read -p "您想安装 pnpm (比 npm 更快) 吗？(y/n): " INSTALL_PNPM
        echo "您想安装 pnpm (比 npm 更快) 吗？(y/n): $INSTALL_PNPM" >> "$LOG_FILE"
        validate_input "yes_no" "$INSTALL_PNPM" "安装 pnpm" && break
    done

    PNPM_INSTALLED="false"
    if [ "$INSTALL_PNPM" = "y" ] || [ "$INSTALL_PNPM" = "Y" ]; then
        echo -e "${COLORS[YELLOW]}正在安装 pnpm...${COLORS[NC]}"
        execute "npm install -g pnpm"
        PNPM_INSTALLED="true"
    fi

    # 安装 n8n
    echo -e "${COLORS[YELLOW]}正在全局安装 n8n ${N8N_VERSION}...${COLORS[NC]}"
    if [ "$PNPM_INSTALLED" = "true" ]; then
        execute "pnpm install -g n8n"
    else
        execute "npm install -g n8n"
    fi

    # 启动 n8n
    echo -e "\n${COLORS[GREEN]}正在启动 n8n...${COLORS[NC]}"
    echo -e "${COLORS[YELLOW]}您可以通过 http://${N8N_HOST}:${N8N_PORT} 访问 n8n${COLORS[NC]}"
    echo -e "${COLORS[YELLOW]}随时按 Ctrl+C 停止 n8n${COLORS[NC]}"
    n8n
}

# ========================== Docker 安装模块 ==========================
# Docker 安装函数
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

# ========================== 数据库模块 ==========================

# 设置时区的独立函数
# 参数: 无
# 将选择的时区保存到全局变量 GLOBAL_TIMEZONE
select_timezone() {
    log_message "INFO" "请选择时区:"
    log_message "INFO" "1) ${DEFAULT_TIMEZONE} (默认)"
    log_message "INFO" "2) Asia/Tokyo"
    log_message "INFO" "3) Europe/London"
    log_message "INFO" "4) America/New_York"
    log_message "INFO" "5) 其他 (请手动输入)"
    read -p "请输入您的选择 (1-5): " TZ_CHOICE
    log_message "INFO" "请选择时区: $TZ_CHOICE"

    # 设置时区变量
    case $TZ_CHOICE in
        1) GLOBAL_TIMEZONE="${DEFAULT_TIMEZONE}" ;;
        2) GLOBAL_TIMEZONE="Asia/Tokyo" ;;
        3) GLOBAL_TIMEZONE="Europe/London" ;;
        4) GLOBAL_TIMEZONE="America/New_York" ;;
        5)
            read -p "请输入时区 (例如: Asia/Beijing): " GLOBAL_TIMEZONE
            echo "请输入时区: $GLOBAL_TIMEZONE" >> "$LOG_FILE"
            GLOBAL_TIMEZONE=${GLOBAL_TIMEZONE:-$DEFAULT_TIMEZONE}  # 默认为DEFAULT_TIMEZONE
            ;;
        *) GLOBAL_TIMEZONE="${DEFAULT_TIMEZONE}" ;;  # 默认值
    esac

    # 将选择的时区记录到日志
    echo "选择的时区: $GLOBAL_TIMEZONE" >> "$LOG_FILE"
}

# SQLite 数据库配置函数
configure_database_sqlite() {
    echo -e "\n${COLORS[BLUE]}=================================================================${COLORS[NC]}"
    echo -e "${COLORS[BLUE]}                     SQLite 安装模式${COLORS[NC]}"
    echo -e "${COLORS[BLUE]}=================================================================${COLORS[NC]}"

    # 准备 docker-compose.yml 内容，直接使用全局时区变量
    DOCKER_COMPOSE_CONTENT=$(generate_docker_compose_content "sqlite")
    return 0
}

# PostgreSQL 数据库配置函数
configure_database_postgresql() {

    # 检查本地是否已安装 PostgreSQL
    PG_INSTALLED=false
    if dpkg -l | grep -q "postgresql\s" 2>/dev/null; then
        PG_INSTALLED=true
    fi

    # 如果本地已安装 PostgreSQL，询问用户选择
    USE_EXISTING_PG="n"
    if [ "$PG_INSTALLED" = true ]; then
        echo -e "\n${COLORS[BLUE]}检测到本地已安装 PostgreSQL!${COLORS[NC]}"
        while true; do
            read -p "是否使用已安装的 PostgreSQL？(y/n，默认: n): " USE_EXISTING_PG_TMP
            USE_EXISTING_PG=${USE_EXISTING_PG_TMP:-n}

            if validate_input "yes_no" "$USE_EXISTING_PG" "使用已安装的 PostgreSQL"; then
                echo "是否使用已安装的 PostgreSQL: $USE_EXISTING_PG" >> "$LOG_FILE"
                break
            fi
        done
    fi

    # 收集所有 PostgreSQL 参数
    echo -e "\n${COLORS[BLUE]}请输入 PostgreSQL 数据库信息:${COLORS[NC]}"

    if [ "$USE_EXISTING_PG" = "y" ] || [ "$USE_EXISTING_PG" = "Y" ]; then
        read -p "数据库主机 (默认: localhost): " DB_HOST
        DB_HOST=${DB_HOST:-localhost}  # 设置默认主机为 localhost
    else
        read -p "数据库主机: " DB_HOST
    fi
    echo "PostgreSQL 数据库信息: 数据库主机: $DB_HOST" >> "$LOG_FILE"

    # 验证数据库端口
    while true; do
        read -p "数据库端口 (默认: 5432): " DB_PORT_TMP
        DB_PORT=${DB_PORT_TMP:-5432}  # 设置默认端口

        if validate_input "port" "$DB_PORT" "数据库端口"; then
            echo "PostgreSQL 数据库信息: 数据库端口: $DB_PORT" >> "$LOG_FILE"
            break
        fi
    done

    # 验证数据库名称
    while true; do
        read -p "数据库名称 (默认: n8n): " DB_NAME_TMP
        DB_NAME=${DB_NAME_TMP:-n8n}  # 设置默认数据库名称

        if validate_input "database_name" "$DB_NAME" "数据库名称"; then
            echo "PostgreSQL 数据库信息: 数据库名称: $DB_NAME" >> "$LOG_FILE"
            break
        fi
    done

    read -p "数据库用户 (默认: postgres): " DB_USER
    DB_USER=${DB_USER:-postgres}  # 设置默认用户
    echo "PostgreSQL 数据库信息: 数据库用户: $DB_USER" >> "$LOG_FILE"

    DB_PASSWORD=$(read_password)
    echo "PostgreSQL 数据库信息: 数据库密码: ****" >> "$LOG_FILE"
    echo -e "\n"

    # 处理已安装的 PostgreSQL 逻辑
    if [ "$USE_EXISTING_PG" = "y" ] || [ "$USE_EXISTING_PG" = "Y" ]; then
        handle_existing_postgresql
    else
        handle_docker_postgresql
    fi

    return 0
}

# MySQL 数据库配置函数
configure_database_mysql() {

    # 检查本地是否已安装 MySQL
    MYSQL_INSTALLED=false
    if dpkg -l | grep -q "mysql-server\s" 2>/dev/null || dpkg -l | grep -q "mariadb-server\s" 2>/dev/null; then
        MYSQL_INSTALLED=true
    fi

    # 如果本地已安装 MySQL，询问用户选择
    USE_EXISTING_MYSQL="n"
    if [ "$MYSQL_INSTALLED" = true ]; then
        echo -e "\n${COLORS[BLUE]}检测到本地已安装 MySQL/MariaDB!${COLORS[NC]}"
        while true; do
            read -p "是否使用已安装的 MySQL/MariaDB？(y/n，默认: n): " USE_EXISTING_MYSQL_TMP
            USE_EXISTING_MYSQL=${USE_EXISTING_MYSQL_TMP:-n}

            if validate_input "yes_no" "$USE_EXISTING_MYSQL" "使用已安装的 MySQL/MariaDB"; then
                echo "是否使用已安装的 MySQL/MariaDB: $USE_EXISTING_MYSQL" >> "$LOG_FILE"
                break
            fi
        done
    fi

    # 收集所有 MySQL 参数
    echo -e "\n${COLORS[BLUE]}请输入 MySQL 数据库信息:${COLORS[NC]}"

    if [ "$USE_EXISTING_MYSQL" = "y" ] || [ "$USE_EXISTING_MYSQL" = "Y" ]; then
        read -p "数据库主机 (默认: localhost): " DB_HOST
        DB_HOST=${DB_HOST:-localhost}  # 设置默认主机为 localhost
    else
        read -p "数据库主机: " DB_HOST
    fi
    echo "MySQL 数据库信息: 数据库主机: $DB_HOST" >> "$LOG_FILE"

    # 验证数据库端口
    while true; do
        read -p "数据库端口 (默认: 3306): " DB_PORT_TMP
        DB_PORT=${DB_PORT_TMP:-3306}  # 设置默认端口

        if validate_input "port" "$DB_PORT" "数据库端口"; then
            echo "MySQL 数据库信息: 数据库端口: $DB_PORT" >> "$LOG_FILE"
            break
        fi
    done

    # 验证数据库名称
    while true; do
        read -p "数据库名称 (默认: n8n): " DB_NAME_TMP
        DB_NAME=${DB_NAME_TMP:-n8n}  # 设置默认数据库名称

        if validate_input "database_name" "$DB_NAME" "数据库名称"; then
            echo "MySQL 数据库信息: 数据库名称: $DB_NAME" >> "$LOG_FILE"
            break
        fi
    done

    read -p "数据库用户 (默认: root): " DB_USER
    DB_USER=${DB_USER:-root}  # 设置默认用户
    echo "MySQL 数据库信息: 数据库用户: $DB_USER" >> "$LOG_FILE"

    DB_PASSWORD=$(read_password)
    echo "MySQL 数据库信息: 数据库密码: ****" >> "$LOG_FILE"
    echo -e "\n"

    # 处理已安装的 MySQL 逻辑
    if [ "$USE_EXISTING_MYSQL" = "y" ] || [ "$USE_EXISTING_MYSQL" = "Y" ]; then
        handle_existing_mysql
    else
        handle_docker_mysql
    fi

    return 0
}

# 主数据库配置函数 - 根据用户选择调用不同的数据库配置函数
configure_database() {
    # 询问数据库选择
    log_message "INFO" "请选择数据库类型:"
    log_message "INFO" "1) SQLite (默认，无需凭证)"
    log_message "INFO" "2) PostgreSQL (需要数据库凭证)"
    log_message "INFO" "3) MySQL (需要数据库凭证)"
    read -p "请输入您的选择 (1/2/3): " DB_CHOICE
    log_message "INFO" "请选择数据库类型: $DB_CHOICE"

    # 时区选择已在main函数中完成

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
            echo -e "${COLORS[RED]}无效的选择!${COLORS[NC]}"
            return 1
            ;;
    esac
}

# 处理已安装的 PostgreSQL 辅助函数
handle_existing_postgresql() {

    # 检查数据库是否存在，如果不存在则创建
    log_message "INFO" "正在检查并创建数据库..."
    log_message "INFO" "当前正在执行 PostgreSQL 权限配置..."

    # 权限配置提示
    printf "${COLORS[YELLOW]}注意: 正在为用户 '$DB_USER' 配置数据库 '$DB_NAME' 的权限...${COLORS[NC]}\n"
    printf "${COLORS[YELLOW]}- 将创建数据库(如果不存在)\n${COLORS[NC]}"
    printf "${COLORS[YELLOW]}- 将创建用户(如果不存在)\n${COLORS[NC]}"
    printf "${COLORS[YELLOW]}- 将授予用户对数据库的所有权限\n${COLORS[NC]}"

    # 确保所有命令都使用execute函数包裹，支持dry-run模式
    execute "sudo -u postgres psql -c \"CREATE DATABASE IF NOT EXISTS $DB_NAME;\""
    execute "sudo -u postgres psql -c \"CREATE USER IF NOT EXISTS $DB_USER WITH PASSWORD '$DB_PASSWORD';\""
    execute "sudo -u postgres psql -c \"GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;\""
    execute "sudo -u postgres psql -c \"GRANT CREATE ON SCHEMA public TO $DB_USER;\""
    execute "sudo -u postgres psql -c \"FLUSH PRIVILEGES;\""

    # 创建 .env 文件
    create_env_file "existing_postgresql"

    # 准备 docker-compose.yml 内容，直接使用全局时区变量
    DOCKER_COMPOSE_CONTENT=$(generate_docker_compose_content "postgres_existing")
}

# 处理 Docker PostgreSQL 辅助函数
handle_docker_postgresql() {

    if [ "$DB_HOST" = "localhost" ] || [ "$DB_HOST" = "127.0.0.1" ] || [ -z "$DB_HOST" ]; then
        # Local Docker PostgreSQL
        echo -e "${COLORS[YELLOW]}注意: 本地PostgreSQL安装已替换为Docker方式，将自动创建PostgreSQL容器...${COLORS[NC]}"

        # Create .env file for Docker
        create_env_file "docker_postgresql"

        # Create init-data.sh script
        create_init_data_script

        # Create docker-compose.yml with PostgreSQL service
        DOCKER_COMPOSE_CONTENT=$(generate_docker_compose_content "postgres_docker")
    else
        # External PostgreSQL
        # Create .env file
        create_env_file "existing_postgresql"

        # Create docker-compose.yml content
        DOCKER_COMPOSE_CONTENT=$(generate_docker_compose_content "postgres_existing")
    fi
}

# 处理已安装的 MySQL 辅助函数
handle_existing_mysql() {

    # 创建 .env 文件
    create_env_file "existing_mysql"

    # 准备 docker-compose.yml 内容，直接使用全局时区变量
    DOCKER_COMPOSE_CONTENT=$(generate_docker_compose_content "mysql_existing")
}

# 处理 Docker MySQL 辅助函数
handle_docker_mysql() {

    if [ "$DB_HOST" = "localhost" ] || [ "$DB_HOST" = "127.0.0.1" ] || [ -z "$DB_HOST" ]; then
        # Local Docker MySQL
        echo -e "${COLORS[YELLOW]}注意: 将自动创建MySQL容器...${COLORS[NC]}"

        # Create .env file for Docker
        create_env_file "docker_mysql"

        # Create docker-compose.yml with MySQL service
        DOCKER_COMPOSE_CONTENT=$(generate_docker_compose_content "mysql_docker")
    else
        # External MySQL
        # Create .env file
        create_env_file "existing_mysql"

        # Create docker-compose.yml content
        DOCKER_COMPOSE_CONTENT=$(generate_docker_compose_content "mysql_existing")
    fi
}

# ========================== 配置生成模块 ==========================
# 创建集中的 docker-compose.yml 生成函数
generate_docker_compose_content() {
    local db_type="$1"

    case "$db_type" in
        "sqlite")
            cat <<EOF
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
            ;;

        "postgres_existing")
            cat <<EOF
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
            ;;

        "postgres_docker")
            cat <<EOF
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
            ;;

        "mysql_existing")
            cat <<EOF
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
            ;;

        "mysql_docker")
            cat <<EOF
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
            ;;

        *)
            echo -e "${COLORS[RED]}无效的数据库类型!${COLORS[NC]}"
            return 1
            ;;
    esac

    return 0  # 确保函数有返回值
}

# 创建 .env 文件辅助函数
create_env_file() {
    mode="$1"

    log_message "INFO" "正在创建 .env 文件..."
    ENV_CONTENT=""

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
        echo -e "$ENV_CONTENT"
    else
        echo -e "$ENV_CONTENT" > .env
        log_message "INFO" ".env 文件创建完成"
    fi

    return 0
}

# 创建 init-data.sh 脚本辅助函数
create_init_data_script() {
    log_message "INFO" "正在创建PostgreSQL初始化脚本 init-data.sh..."

    INIT_SCRIPT_CONTENT='#!/bin/bash
set -e;


if [ -n "${POSTGRES_NON_ROOT_USER:-}" ] && [ -n "${POSTGRES_NON_ROOT_PASSWORD:-}" ]; then
	psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
		CREATE USER ${POSTGRES_NON_ROOT_USER} WITH PASSWORD '\''${POSTGRES_NON_ROOT_PASSWORD}'\'';
		GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_DB} TO ${POSTGRES_NON_ROOT_USER};
		GRANT CREATE ON SCHEMA public TO ${POSTGRES_NON_ROOT_USER};
	EOSQL
else
	echo "SETUP INFO: No Environment variables given!"
fi'

    if [ "$DRY_RUN" = true ]; then
        log_message "INFO" "[DRY-RUN] 将要创建 init-data.sh 文件，内容如下:"
        echo -e "$INIT_SCRIPT_CONTENT"
    else
        echo -e "$INIT_SCRIPT_CONTENT" > init-data.sh
        chmod +x init-data.sh  # Ensure script is executable
        log_message "INFO" "PostgreSQL初始化脚本 init-data.sh 创建完成"
    fi
}

# 创建 docker-compose.yml 文件函数
create_docker_compose_file() {
    log_message "INFO" "正在创建 docker-compose.yml 文件..."

    if [ "$DRY_RUN" = true ]; then
        log_message "INFO" "[DRY-RUN] 将要创建 docker-compose.yml 文件，内容如下:"
        echo -e -e "$DOCKER_COMPOSE_CONTENT"
    else
        echo -e -e "$DOCKER_COMPOSE_CONTENT" > docker-compose.yml
        log_message "INFO" "docker-compose.yml 文件创建完成"
    fi
}

# 创建 n8n_data 目录函数
create_n8n_data_directory() {
    log_message "INFO" "正在创建 n8n_data 目录..."
    execute "mkdir -p ./n8n_data"
}

# ========================== 工具模块 ==========================
# 启动服务函数
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

# 安装完成提示函数
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

    # 询问安装方式
    log_message "INFO" "请选择安装方式:"
    log_message "INFO" "1) npm (推荐用于开发环境)"
    log_message "INFO" "2) Docker (推荐用于生产环境)"
    read -p "请输入您的选择 (1/2): " INSTALL_METHOD
    log_message "INFO" "请选择安装方式: $INSTALL_METHOD"

    case $INSTALL_METHOD in
        1)
            # 选择时区
            select_timezone

            install_npm || handle_error $? $LINENO "install_npm"
            print_install_completion || handle_error $? $LINENO "print_install_completion"
            ;;
        2)
            # 选择时区
            select_timezone

            install_docker || handle_error $? $LINENO "install_docker"
            configure_database || handle_error $? $LINENO "configure_database"

            # 创建 docker-compose.yml 文件
            create_docker_compose_file || handle_error $? $LINENO "create_docker_compose_file"

            # 创建 n8n_data 目录
            create_n8n_data_directory || handle_error $? $LINENO "create_n8n_data_directory"

            # 启动服务
            start_services || handle_error $? $LINENO "start_services"

            # 打印安装完成信息
            print_install_completion || handle_error $? $LINENO "print_install_completion"
            ;;
        *)
            echo -e "${COLORS[RED]}无效的选择!${COLORS[NC]}"
            handle_error 1 $LINENO "Invalid installation method choice"
            ;;
    esac

    return 0
}

# 调用主函数
main "$@"
