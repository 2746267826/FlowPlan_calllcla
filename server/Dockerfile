FROM node:22

ENV TZ=Asia/Shanghai

WORKDIR /app

# 1. 直接激活 Node 22 内置的 pnpm
RUN corepack enable pnpm

# 2. 🌟 强制给 pnpm 本身配置代理和淘宝源
# 这次绝对不加 NO_PROXY，让所有的网络请求乖乖走你的代理节点
RUN pnpm config set registry https://registry.npmmirror.com/ && \
    pnpm config set http-proxy http://172.17.0.1:7890 && \
    pnpm config set https-proxy http://172.17.0.1:7890

# 3. 环境变量也留着，以防其他 C++ 编译脚本需要
ENV HTTP_PROXY=http://172.17.0.1:7890
ENV HTTPS_PROXY=http://172.17.0.1:7890

COPY package.json pnpm-lock.yaml* ./

# 4. 啰嗦模式安装
RUN pnpm install --reporter=ndjson --loglevel debug

COPY . .
RUN pnpm run build

RUN pnpm prune --prod

# 5. 清理战场：打包完成后，把所有代理配置删得干干净净
RUN pnpm config delete http-proxy && pnpm config delete https-proxy
ENV HTTP_PROXY=""
ENV HTTPS_PROXY=""

EXPOSE 3200

CMD ["sh", "-c", "pnpm run db:schema && node dist/main.js"]