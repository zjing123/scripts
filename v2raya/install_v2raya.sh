#!/bin/bash

# 安装v2raya的自动化脚本
# 结合官方文档和colin404.com的教程编写
# 适用于Debian/Ubuntu系统

set -e

# 输出颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误：${NC}请使用root用户运行此脚本"
    exit 1
fi

echo -e "${GREEN}开始安装v2raya...${NC}"

# 安装依赖
echo -e "${YELLOW}1. 安装必要的依赖...${NC}"
apt update
apt install -y wget curl gnupg2 apt-transport-https ca-certificates

# 导入GPG密钥
echo -e "${YELLOW}2. 导入v2raya的GPG密钥...${NC}"
wget -qO - https://apt.v2raya.org/key/public-key.asc | gpg --dearmor -o /usr/share/keyrings/v2raya-archive-keyring.gpg

# 添加v2raya软件源
echo -e "${YELLOW}3. 添加v2raya软件源...${NC}"
echo "deb [signed-by=/usr/share/keyrings/v2raya-archive-keyring.gpg arch=$(dpkg --print-architecture)] https://apt.v2raya.org/ v2raya main" | tee /etc/apt/sources.list.d/v2raya.list > /dev/null

# 更新软件源并安装v2raya和v2ray核心
echo -e "${YELLOW}4. 安装v2raya和v2ray核心...${NC}"
apt update
apt install -y v2raya v2ray

# 下载并安装geosite和geoip数据库（如果需要）
echo -e "${YELLOW}5. 安装GeoSite和GeoIP数据库...${NC}"
mkdir -p /usr/share/v2ray/
wget -qO- https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat > /usr/share/v2ray/geosite.dat
wget -qO- https://github.com/v2fly/geoip/releases/latest/download/geoip.dat > /usr/share/v2ray/geoip.dat

# 启动并启用v2raya服务
echo -e "${YELLOW}6. 启动并设置v2raya服务自启...${NC}"
systemctl start v2raya.service
systemctl enable v2raya.service

# 验证服务状态
echo -e "${YELLOW}7. 验证v2raya服务状态...${NC}"
sleep 2
if systemctl is-active --quiet v2raya.service; then
    echo -e "${GREEN}✓ v2raya服务已成功启动！${NC}"
    echo -e "${YELLOW}访问地址：${NC}http://$(curl -s icanhazip.com):2017"
    echo -e "${YELLOW}默认账号：${NC}admin"
    echo -e "${YELLOW}默认密码：${NC}password"
else
    echo -e "${RED}✗ v2raya服务启动失败！${NC}"
    echo -e "${RED}请运行 systemctl status v2raya.service 查看详细错误信息${NC}"
fi

echo -e "${GREEN}v2raya安装完成！${NC}"
