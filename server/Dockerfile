FROM node:22

ENV TZ=Asia/Shanghai

# 注入代理：应付底层二进制文件的下载
ENV HTTP_PROXY=http://172.17.0.1:7890
ENV HTTPS_PROXY=http://172.17.0.1:7890

WORKDIR /app

# 🌟 关键修复：先给 npm 换淘宝源 -> 再秒下 pnpm -> 再给 pnpm 换淘宝源
RUN npm config set registry https://registry.npmmirror.com/ && \
    npm install -g pnpm && \
    pnpm config set registry https://registry.npmmirror.com/

COPY package.json pnpm-lock.yaml* ./

# pnpm 在啰嗦模式下高速安装
RUN pnpm install --reporter=ndjson --loglevel debug

COPY . .
RUN pnpm run build

RUN pnpm prune --prod

# 拔掉网线，保持生产环境纯净
ENV HTTP_PROXY=""
ENV HTTPS_PROXY=""

EXPOSE 3200

CMD ["sh", "-c", "pnpm run db:schema && node dist/main.js"]