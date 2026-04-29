FROM node:22-alpine

ENV TZ=Asia/Shanghai

WORKDIR /app

# 安装 pnpm 并配置国内镜像
RUN npm install -g pnpm && \
    pnpm config set registry https://registry.npmmirror.com/

COPY package.json pnpm-lock.yaml* ./

# 🌟 核心排错：开启 pnpm 的极限调试模式
# --reporter=ndjson：让输出变成一行行的结构化日志，方便排查死锁
# --loglevel debug：打印所有底层操作细节
RUN pnpm install --reporter=ndjson --loglevel debug

COPY . .
RUN pnpm run build

RUN pnpm prune --prod

EXPOSE 3200

CMD ["sh", "-c", "pnpm run db:schema && node dist/main.js"]