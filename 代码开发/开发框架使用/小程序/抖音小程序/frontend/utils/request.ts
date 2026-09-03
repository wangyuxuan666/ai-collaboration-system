// request.ts - 请求封装（对齐纯净骨架后端契约）
// 约定：响应 { code, data, message }，code=0 成功；带 Authorization: Bearer <token>；HTTP 401 时清登录态跳登录页
import config from './config'
import { getToken, clearToken } from './auth'

interface RequestOptions {
  url: string
  method?: 'GET' | 'POST' | 'PUT' | 'DELETE'
  data?: Record<string, unknown>
  header?: Record<string, string>
}

interface ApiResponse<T = unknown> {
  code: number
  data?: T
  message?: string
}

/**
 * 统一请求封装
 * @returns Promise<data> resolve 业务数据；业务失败 reject {code, message}
 */
export function request<T = unknown>(options: RequestOptions): Promise<T> {
  return new Promise((resolve, reject) => {
    const token = getToken()
    tt.request({
      url: config.baseUrl + config.apiPrefix + options.url,
      method: options.method || 'GET',
      data: options.data || {},
      header: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...(options.header || {}),
      },
      success(res) {
        // HTTP 401：token 失效，清登录态跳登录页
        if (res.statusCode === 401) {
          clearToken()
          tt.reLaunch({ url: '/pages/login/index' })
          reject({ code: 401, message: '未授权' })
          return
        }
        const body = res.data as ApiResponse<T>
        // code=0 成功，返回业务数据
        if (body && body.code === 0) {
          resolve(body.data as T)
        } else {
          // 业务错误
          tt.showToast({ title: (body && body.message) || '请求失败', icon: 'none' })
          reject(body || { code: -1, message: '请求失败' })
        }
      },
      fail(err) {
        tt.showToast({ title: '网络错误', icon: 'none' })
        reject(err)
      },
    })
  })
}
