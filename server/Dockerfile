FROM node:22

ENV TZ=Asia/Shanghai
WORKDIR /app

RUN corepack enable pnpm

# 🌟 终极破局：坚决不用国内源！强制使用国外官方源 + 代理，绕过路由黑洞！
RUN pnpm config set registry https://registry.npmjs.org/ && \
    pnpm config set http-proxy http://172.17.0.1:7890 && \
    pnpm config set https-proxy http://172.17.0.1:7890

# 保证其他底层依赖也走代理
ENV HTTP_PROXY=http://172.17.0.1:7890
ENV HTTPS_PROXY=http://172.17.0.1:7890

COPY package.json pnpm-lock.yaml* ./

# 继续保持啰嗦模式，看它起飞
RUN pnpm install --reporter=ndjson --loglevel debug

COPY . .
RUN pnpm run build
RUN pnpm prune --prod

# 拔掉网线，清理环境变量
RUN pnpm config delete http-proxy && pnpm config delete https-proxy
ENV HTTP_PROXY=""
ENV HTTPS_PROXY=""

EXPOSE 3200

CMD ["sh", "-c", "pnpm run db:schema && node dist/main.js"]