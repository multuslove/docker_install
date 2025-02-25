#!/bin/bash
# 部署前请先执行: chmod +x deploy.sh && ./deflix.sh

# ----------------------
# 用户自定义配置区（必须修改！）
# ----------------------
REDIS_IMAGE="crpi-jg69vy9pa9c65dg4.cn-hangzhou.personal.cr.aliyuncs.com/alyuncangku/redis:alpine3.21"
MYSQL_IMAGE="crpi-jg69vy9pa9c65dg4.cn-hangzhou.personal.cr.aliyuncs.com/alyuncangku/mysql:8.1"
MYSQL_ROOT_PASSWORD="password"      # 手动设置root密码
MYSQL_USER_PASSWORD="password"      # 手动设置应用用户密码

# ----------------------
# 基础设施准备
# ----------------------
# 创建共享网络（若不存在）
docker network inspect app-network >/dev/null 2>&1 || docker network create app-network

# 创建持久化数据卷
docker volume create redis_data
docker volume create mysql_data

# ----------------------
# Redis容器部署
# ----------------------
docker run -d \
  --name redis-server \
  --network app-network \
  --memory 512m \
  --cpus 1 \
  --restart unless-stopped \
  --log-driver journald \
  --health-cmd "redis-cli ping" \
  --health-interval 30s \
  -p 6379:6379 \
  -v redis_data:/data \
  --security-opt no-new-privileges \
  ${REDIS_IMAGE} \
  redis-server --appendonly yes

# ----------------------
# MySQL容器部署
# ----------------------
docker run -d \
  --name mysql-server \
  --network app-network \
  --memory 1g \
  --cpus 1 \
  --restart unless-stopped \
  --log-driver journald \
  --health-cmd="mysqladmin ping -uroot -p${MYSQL_ROOT_PASSWORD}" \
  --health-interval 30s \
  -p 3306:3306 \
  -v mysql_data:/var/lib/mysql \
  -e MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD} \
  -e MYSQL_DATABASE=minecraft \
  -e MYSQL_USER= luckperms\
  -e MYSQL_PASSWORD=${MYSQL_USER_PASSWORD} \
  --security-opt no-new-privileges \
  --character-set-server=utf8mb4 \
  --collation-server=utf8mb4_unicode_ci \
  --bind-address=0.0.0.0 \
  ${MYSQL_IMAGE} \

# ----------------------
# 部署后验证
# ----------------------
echo "部署完成！验证服务状态："
echo "Redis状态：$(docker inspect --format '{{.State.Health.Status}}' redis-server)"
echo "MySQL状态：$(docker inspect --format '{{.State.Health.Status}}' mysql-server)"

# 输出连接信息
cat <<EOF

================ 连接信息 ================
MySQL公开访问地址:
  主机: $(curl -s icanhazip.com)  # 获取公网IP
  端口: 3306
  Root用户密码: ${MYSQL_ROOT_PASSWORD}

Redis公开访问地址:
  主机: $(curl -s icanhazip.com)
  端口: 6379

数据卷存储路径：
  Redis: $(docker volume inspect --format '{{.Mountpoint}}' redis_data)
  MySQL: $(docker volume inspect --format '{{.Mountpoint}}' mysql_data)
=========================================
EOF
