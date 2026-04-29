FROM node:22

ENV TZ=Asia/Shanghai

# 🌟 重新注入代理：给构建容器插上原本缺失的网线！
ENV HTTP_PROXY=http://172.17.0.1:7890
ENV HTTPS_PROXY=http://172.17.0.1:7890

WORKDIR /app

# 安装 pnpm 并配置镜像源
RUN npm install -g pnpm && \
    pnpm config set registry https://registry.npmmirror.com/

COPY package.json pnpm-lock.yaml* ./

# 🌟 开启 pnpm 的极限啰嗦模式：死盯代理网络下的每一个下载动作
RUN pnpm install --reporter=ndjson --loglevel debug

COPY . .
RUN pnpm run build

RUN pnpm prune --prod

# 拔掉网线：防止代理泄露到你的生产运行环境中
ENV HTTP_PROXY=""
ENV HTTPS_PROXY=""

EXPOSE 3200

CMD ["sh", "-c", "pnpm run db:schema && node dist/main.js"]