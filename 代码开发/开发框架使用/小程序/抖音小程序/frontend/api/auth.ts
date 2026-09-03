// api/auth.ts - 登录相关接口（对齐纯净骨架后端）
import { request } from '../utils/request'

/**
 * 小程序登录：tt.login() 拿 code → 后端换 token
 * @param code tt.login 获取的临时凭证
 */
export function miniappLogin(code: string): Promise<{ token: string }> {
  return request<{ token: string }>({
    url: '/auth/miniapp-login',
    method: 'POST',
    data: { code, platform: 'douyin' },
  })
}

/** 获取当前用户信息 */
export function getUserInfo(): Promise<{ username: string; roles: string[] }> {
  return request<{ username: string; roles: string[] }>({
    url: '/auth/info',
    method: 'GET',
  })
}
