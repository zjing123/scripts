#!/bin/bash

# n8n 更新脚本 - 用于将 n8n 升级到最新版本
# 支持 Docker 和 npm/pnpm 两种安装方式

# 定义日志文件路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/n8n_update.log"

# 将所有输出同时重定向到日志文件和控制台
# 控制台输出保留彩色，日志文件去掉ANSI颜色代码
# 使用更全面的正则表达式匹配所有ANSI escape序列
exec > >(tee -a >(sed -r 's/\x1B\[[0-9;]*[a-zA-Z]//g' > "$LOG_FILE")) 2>&1

set -e  # 如果命令执行失败则立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # 无颜色

# 欢迎信息
echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}                          n8n 更新脚本${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}                    支持: Ubuntu/Debian 系统${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo -e "\n"

# 询问更新方式
echo -e "${BLUE}请选择您的 n8n 安装方式:${NC}"
echo -e "1) ${RED}Docker Compose (推荐用于生产环境)${NC}"
echo -e "2) ${GREEN}npm/pnpm (推荐用于开发环境)${NC}"
read -p "请输入您的选择 (1/2): " UPDATE_METHOD
echo "请选择您的 n8n 安装方式: 请输入您的选择 (1/2): $UPDATE_METHOD" >> "$LOG_FILE"

case $UPDATE_METHOD in
    1)
        echo -e "\n${BLUE}=================================================================${NC}"
        echo -e "${BLUE}                       Docker 更新模式${NC}"
        echo -e "${BLUE}=================================================================${NC}"

        # 检查当前目录是否有 docker-compose.yml 文件
        if [ ! -f "docker-compose.yml" ]; then
            echo -e "${YELLOW}警告: 当前目录没有 docker-compose.yml 文件${NC}"
            read -p "请输入包含 docker-compose.yml 文件的目录路径: " COMPOSE_DIR
            echo "请输入包含 docker-compose.yml 文件的目录路径: $COMPOSE_DIR" >> "$LOG_FILE"
            if [ ! -d "$COMPOSE_DIR" ] || [ ! -f "$COMPOSE_DIR/docker-compose.yml" ]; then
                echo -e "${RED}错误: 目录或 docker-compose.yml 文件不存在${NC}"
                exit 1
            fi
            cd "$COMPOSE_DIR"
        fi

        # 检查 docker-compose.yml 中是否包含 n8n 服务
        if ! grep -q "n8nio/n8n" docker-compose.yml; then
            echo -e "${RED}错误: 当前 docker-compose.yml 文件中不包含 n8n 服务${NC}"
            exit 1
        fi

        # 更新 n8n Docker 镜像
        echo -e "${YELLOW}正在拉取最新的 n8n Docker 镜像...${NC}"
        docker pull docker.n8n.io/n8nio/n8n

        # 重启 n8n 服务
        echo -e "${YELLOW}正在重启 n8n 服务...${NC}"
        docker-compose up -d

        # 检查服务状态
        echo -e "${YELLOW}正在检查 n8n 服务状态...${NC}"
        sleep 5
        if docker-compose ps | grep -q "Up"; then
            echo -e "${GREEN}n8n 已成功更新并重启!${NC}"
        else
            echo -e "${RED}n8n 更新或重启失败!${NC}"
            echo -e "${YELLOW}请运行 'docker-compose logs -f' 查看详细日志${NC}"
            exit 1
        fi

        ;;

    2)
        echo -e "\n${BLUE}=================================================================${NC}"
        echo -e "${BLUE}                       npm/pnpm 更新模式${NC}"
        echo -e "${BLUE}=================================================================${NC}"

        # 检查是否已安装 n8n
        if ! command -v n8n &> /dev/null; then
            echo -e "${RED}错误: 未安装 n8n${NC}"
            exit 1
        fi

        # 检查是否使用 pnpm
        if command -v pnpm &> /dev/null; then
            echo -e "${YELLOW}正在使用 pnpm 更新 n8n...${NC}"
            pnpm install -g n8n@latest
        else
            echo -e "${YELLOW}正在使用 npm 更新 n8n...${NC}"
            npm install -g n8n@latest
        fi

        # 验证更新
        echo -e "${YELLOW}正在验证 n8n 更新...${NC}"
        n8n --version

        echo -e "${GREEN}n8n 已成功更新!${NC}"
        echo -e "${YELLOW}请重启 n8n 服务以使用新版本${NC}"

        ;;

    *)
        echo -e "${RED}无效的选择!${NC}"
        exit 1
        ;;
esac

echo -e "\n${BLUE}=================================================================${NC}"
echo -e "${GREEN}                    更新完成!${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo -e "${YELLOW}如需更多信息，请访问: https://docs.n8n.io/${NC}"
echo -e "${BLUE}=================================================================${NC}"
