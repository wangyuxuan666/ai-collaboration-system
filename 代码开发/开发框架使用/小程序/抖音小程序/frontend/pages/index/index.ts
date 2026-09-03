// pages/index/index.ts - 首页：展示登录态与示例接口调用
import { getUserInfo } from '../../api/auth'
import { getToken } from '../../utils/auth'

Page({
  data: {
    loggedIn: false,
    username: '',
  },
  onShow() {
    this.checkLogin()
  },
  checkLogin() {
    const token = getToken()
    this.setData({ loggedIn: !!token })
    if (token) {
      getUserInfo()
        .then((data) => {
          this.setData({ username: data.username })
        })
        .catch(() => {})
    }
  },
  goLogin() {
    tt.navigateTo({ url: '/pages/login/index' })
  },
})
