import { miniappLogin } from '../../apis/auth'
import { setNavigationBarHeight } from '../../utils/index'

// 登录页：wx.login 拿 code → 后端换 token → 存 storage → 回首页
Component({
  lifetimes: {
    attached() {
      setNavigationBarHeight()
    },
  },
  methods: {
    handleLogin() {
      wx.login({
        success: (res) => {
          if (!res.code) {
            wx.showToast({ title: '获取 code 失败', icon: 'none' })
            return
          }
          miniappLogin(res.code).then((data: any) => {
            wx.setStorageSync('token', data.data?.token ?? '')
            wx.showToast({ title: '登录成功', icon: 'success' })
            setTimeout(() => wx.reLaunch({ url: '/pages/index/index' }), 500)
          })
        },
        fail: () => wx.showToast({ title: '登录失败', icon: 'none' }),
      })
    },
  },
})
