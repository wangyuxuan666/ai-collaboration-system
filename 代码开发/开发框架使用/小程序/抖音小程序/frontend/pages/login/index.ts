// pages/login/index.ts - 登录页：tt.login 拿 code → 后端换 token → 存 storage → 回首页
import { miniappLogin } from '../../api/auth'
import { setToken } from '../../utils/auth'

Page({
  onLoad() {
    // 自动静默登录（骨架演示）；需要用户授权时在此加授权流程
    this.doLogin()
  },
  doLogin() {
    tt.login({
      success: (res) => {
        if (!res.code) {
          tt.showToast({ title: '获取 code 失败', icon: 'none' })
          return
        }
        miniappLogin(res.code)
          .then((data) => {
            setToken(data.token)
            tt.showToast({ title: '登录成功', icon: 'success' })
            setTimeout(() => tt.reLaunch({ url: '/pages/index/index' }), 500)
          })
          .catch(() => {})
      },
      fail: () => tt.showToast({ title: '登录失败', icon: 'none' }),
    })
  },
})
