# 放弃 Alpine，直接使用官方全量 Debian 镜像（不带后缀就是全量版）
FROM node:24.13.1

# 环境变量：标准版镜像自带时区数据，直接设置即可生效
ENV TZ=Asia/Shanghai
ENV NODE_ENV=production

WORKDIR /app

# 1. 核心加速：配置国内镜像源
RUN npm config set registry https://registry.npmmirror.com/

# 2. 核心优化：只拷贝依赖描述文件
# 这样做能利用 Docker 的“层缓存”。只要你没改 package.json，下次部署这一步是 0 秒完成。
COPY package*.json ./

# 3. 增加参数防止日志刷屏导致缓冲区假死，并关闭安全审计以提速
RUN npm install --no-audit --progress=false

# 4. 拷贝源代码
COPY . .

EXPOSE 3200

# 启动
CMD ["npm", "start"]