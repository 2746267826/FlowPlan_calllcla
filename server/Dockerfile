FROM node:24.13.1-alpine

# 设置工作目录
WORKDIR /app

# 🌟 核心魔法：配置 npm 国内镜像源，彻底解决网络卡顿问题
RUN npm config set registry https://registry.npmmirror.com/

# 先只拷贝 package 文件，利用 Docker 缓存机制加速后续构建
COPY package*.json ./

# 安装依赖（这步现在会飞快）
RUN npm install

# 拷贝服务端的所有源代码到容器中
COPY . .

# 暴露你的 3200 端口
EXPOSE 3200

# 启动服务（假设你的 package.json 里配置了 "start": "node xxx"）
# 如果你是直接运行 js 文件，请改成 CMD ["node", "你的入口文件.js"]
CMD ["npm", "start"]