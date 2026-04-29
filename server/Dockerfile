FROM node:22

ENV TZ=Asia/Shanghai

# 🌟 终极大招：直接激活 Node 22 内置的 pnpm，无需下载！彻底绕开所有网络劫持！
RUN corepack enable pnpm

# 配置淘宝镜像源
RUN pnpm config set registry https://registry.npmmirror.com/

WORKDIR /app

COPY package.json pnpm-lock.yaml* ./

# 🌟 注入代理，专心用来下载 NestJS 那些需要梯子的底层 C++ 依赖
ENV HTTP_PROXY=http://172.17.0.1:7890
ENV HTTPS_PROXY=http://172.17.0.1:7890
ENV NO_PROXY=localhost,127.0.0.1,.npmmirror.com

# 极限啰嗦模式，飞速安装
RUN pnpm install --reporter=ndjson --loglevel debug

COPY . .
RUN pnpm run build

RUN pnpm prune --prod

# 拔掉网线
ENV HTTP_PROXY=""
ENV HTTPS_PROXY=""

EXPOSE 3200

CMD ["sh", "-c", "pnpm run db:schema && node dist/main.js"]