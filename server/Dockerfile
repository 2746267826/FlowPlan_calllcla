# 降级到极其稳定的 Node 22 长期支持版，避开原生模块编译坑
FROM node:22

ENV TZ=Asia/Shanghai
# 🌟 注意：这里先不设置 production，保证能装上 TypeScript 等开发依赖

# 配置国内镜像及二进制源
ENV PRISMA_ENGINES_MIRROR=https://npmmirror.com/mirrors/prisma/
ENV SHARP_DIST_BASE_URL=https://npmmirror.com/mirrors/sharp-libvips/
WORKDIR /app

# 1. 配置淘宝源
RUN npm config set registry https://registry.npmmirror.com/

# 2. 拷贝依赖描述文件并安装 (包含 devDependencies)
COPY package*.json ./
RUN npm install --no-audit --progress=false

# 3. 拷贝所有源代码
COPY . .

# 4. 🌟 NestJS 核心步骤：将 TypeScript 编译成 JavaScript (生成 dist 目录)
RUN npm run build

# 5. 设置为生产环境，并清理掉庞大的开发依赖，极致瘦身
ENV NODE_ENV=production
RUN npm prune --production

EXPOSE 3200

# 6. 运行数据库同步，并启动编译后的主文件
# (NestJS 生产环境应该运行 dist/main.js，而不是用 ts-node 跑源码)
CMD ["sh", "-c", "npm run db:schema && node dist/main.js"]