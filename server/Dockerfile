FROM node:24.13.1

ENV TZ=Asia/Shanghai
ENV NODE_ENV=production

# 🌟 核心拦截：强行将常见底层二进制包的下载地址重定向到国内镜像
ENV PRISMA_ENGINES_MIRROR=https://npmmirror.com/mirrors/prisma/
ENV SHARP_DIST_BASE_URL=https://npmmirror.com/mirrors/sharp-libvips/
ENV SASS_BINARY_SITE=https://npmmirror.com/mirrors/node-sass/
ENV PUPPETEER_DOWNLOAD_HOST=https://npmmirror.com/mirrors/
ENV ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/

WORKDIR /app

RUN npm config set registry https://registry.npmmirror.com/

COPY package*.json ./

# 🌟 核心排错：开启 verbose (啰嗦模式)，强制打印每一次底层的网络请求
RUN npm install --verbose

COPY . .

EXPOSE 3200

# 绑定数据库表结构同步与服务启动
CMD ["sh", "-c", "npm run db:schema && npm start"]