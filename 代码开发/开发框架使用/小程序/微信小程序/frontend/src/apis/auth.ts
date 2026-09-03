import { defaultRequest } from '../utils/index'

/**
 * 小程序登录：wx.login() 拿 code → 后端 miniapp-login 换 token
 * 对齐纯净骨架后端：POST /api/v1/auth/miniapp-login，入参 {code, platform}
 */
export async function miniappLogin(code: string) {
  return await defaultRequest({
    url: '/auth/miniapp-login',
    method: 'POST',
    data: { code, platform: 'wechat' },
  })
}

/** 获取当前用户信息（带 Bearer token） */
export async function getUserInfo() {
  return await defaultRequest({
    url: '/auth/info',
    method: 'GET',
  })
}
