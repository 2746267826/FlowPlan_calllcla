FROM node:22-alpine

ENV TZ=Asia/Shanghai

WORKDIR /app

# 1. 核心大洗牌：全局安装 pnpm，并配置淘宝源
RUN npm install -g pnpm && \
    pnpm config set registry https://registry.npmmirror.com/

# 2. 拷贝依赖文件（注意：如果有 pnpm-lock.yaml 也会被一起拷进去）
COPY package.json pnpm-lock.yaml* ./

# 3. 使用 pnpm 进行无情地高速安装（极大概率不会卡住）
RUN pnpm install

# 4. 拷贝源码并构建
COPY . .
RUN pnpm run build

# 5. 清理开发依赖，极致瘦身
RUN pnpm prune --prod

EXPOSE 3200

# 6. 启动
CMD ["sh", "-c", "pnpm run db:schema && node dist/main.js"]