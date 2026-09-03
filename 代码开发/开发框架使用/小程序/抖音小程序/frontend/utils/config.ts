// config.ts - 全局配置
// 对接纯净骨架后端（默认 http://localhost:8080）；生产改为已备案的 https 域名并在抖音后台配置 request 合法域名

interface Config {
  baseUrl: string
  apiPrefix: string
}

const config: Config = {
  // 后端地址（开发用本地；真机/生产改 https 域名）
  baseUrl: 'http://localhost:8080',
  // 后端接口前缀（纯净骨架后端路径）
  apiPrefix: '/api/v1',
}

export default config
