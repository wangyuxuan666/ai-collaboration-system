// auth.ts - 登录态管理
// 对齐纯净骨架后端契约：{ code, data, message }，code=0 成功；Bearer token 鉴权

const TOKEN_KEY = 'token'

export function getToken(): string {
  return tt.getStorageSync(TOKEN_KEY)
}

export function setToken(token: string): void {
  tt.setStorageSync(TOKEN_KEY, token)
}

export function clearToken(): void {
  tt.removeStorageSync(TOKEN_KEY)
}
