#!/bin/bash
# 部署前请先执行: chmod +x deploy.sh && ./deploy.sh

# ----------------------
# 用户自定义配置区（必须修改！）
# ----------------------
MYSQL_IMAGE="crpi-jg69vy9pa9c65dg4.cn-hangzhou.personal.cr.aliyuncs.com/alyuncangku/mysql:8.1"
MYSQL_ROOT_PASSWORD="password"      # 手动设置root密码

# ----------------------
# 基础设施准备
# ----------------------
# 创建共享网络（若不存在）
docker network inspect app-network >/dev/null 2>&1 || docker network create app-network

# 创建持久化数据卷
docker volume create mysql_data

# ----------------------
# MySQL容器部署（修复版）
# ----------------------
docker run -d \
  --name mysql-server \
  --network app-network \
  -p 3306:3306 \
  -v mysql_data:/var/lib/mysql \
  -e MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD}" \
  ${MYSQL_IMAGE} \
  --character-set-server=utf8mb4 \
  --collation-server=utf8mb4_unicode_ci \
  --bind-address=0.0.0.0 \
  --default-authentication-plugin=mysql_native_password

# ----------------------
# 部署验证优化
# ----------------------
echo "=== 等待MySQL初始化（约30秒）==="
for i in {1..30}; do
  if docker exec mysql-server mysqladmin -uroot -p"${MYSQL_ROOT_PASSWORD}" ping &>/dev/null; then
    echo -e "\nMySQL已就绪"
    docker exec mysql-server mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "STATUS;"
    break
  fi
  printf "."
  sleep 1
done

# ----------------------
# 生成连接信息
# ----------------------
cat <<EOF

================ 连接信息 ================
MySQL访问地址:
  内网地址: mysql-server（容器间访问）
  公网IP: $(curl -s icanhazip.com || echo "无法获取公网IP")
  端口: 3306
  用户: root
  密码: ${MYSQL_ROOT_PASSWORD}

数据持久化位置:
  MySQL: $(docker volume inspect --format '{{.Mountpoint}}' mysql_data)
=========================================
EOF
