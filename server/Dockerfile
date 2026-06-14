FROM node:22

ENV TZ=Asia/Shanghai
WORKDIR /app

RUN corepack enable pnpm

# 1. 切回淘宝源，国内下载肯定更快
RUN pnpm config set registry https://registry.npmmirror.com/

# 2. 配置代理
RUN pnpm config set http-proxy http://172.17.0.1:7890 && \
    pnpm config set https-proxy http://172.17.0.1:7890

# 3. 🌟 终极防爆墙：限制并发数为 2，关闭严格 SSL！
# 宁可安装慢一点，也绝不能让几百个请求把 Windows 代理瞬间冲垮！
RUN pnpm config set network-concurrency 2 && \
    pnpm config set strict-ssl false

ENV HTTP_PROXY=http://172.17.0.1:7890
ENV HTTPS_PROXY=http://172.17.0.1:7890

COPY package.json pnpm-lock.yaml* ./

# 继续保持啰嗦模式，看它慢条斯理但稳如泰山地安装
RUN pnpm install --reporter=ndjson --loglevel debug

COPY . .
RUN pnpm run build
RUN pnpm prune --prod

# 拔掉网线，清理战场
RUN pnpm config delete http-proxy && pnpm config delete https-proxy
ENV HTTP_PROXY=""
ENV HTTPS_PROXY=""

EXPOSE 3200

CMD ["sh", "-c", "pnpm run db:schema && node dist/src/main.js"]
