// app.ts - 抖音小程序入口
// 骨架约定：全局配置放这里；登录态 token 存 storage，见 utils/auth
App<IAppOption>({
  onLaunch() {
    // 启动时检查登录态；未登录跳登录页（或按业务在页面守卫处理）
    const token = tt.getStorageSync('token')
    if (!token) {
      // 骨架默认首页无需登录；需要登录的项目在此跳转 pages/login/index
    }
  },
  globalData: {
    // 全局业务数据
  },
})
