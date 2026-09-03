export default {
  env: 'dev', // dev | prod
  // 后端服务地址（纯净骨架后端；开发用本地，生产改 https 域名并配微信后台 request 合法域名）
  defaultApiServer: {
    dev: 'http://localhost:8080',
    prod: 'https://your-domain.com',
  },
  // 后端接口前缀（纯净骨架后端路径）
  apiPrefix: '/api/v1',
  // 缓存默认有效时间（单位：秒）
  storageExpire: {
    dev: 60 * 60 * 24 * 30,
    prod: 60 * 60 * 24 * 30,
  },
} as const
