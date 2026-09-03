import config from '../../config'

type AnyResType = string | IAnyObject | ArrayBuffer

// 只拓展了一个是否显示loading，可以按需添加
export type DefaultRequestOptions<T extends AnyResType = AnyResType> = WechatMiniprogram.RequestOption<T> & {
  loading?: boolean
}

// 后端默认返回格式（对齐纯净骨架后端：{ code, data, message }）
type ResponseRowData<T extends AnyResType = AnyResType> = {
  code: number
  message: string
  data?: T
}

// 对后端返回值的数据封装
export type DefaultResponseType<T extends AnyResType = AnyResType> = ResponseRowData<T> & {
  isSuccess: boolean
}

// 基本的请求方法实例
type BaseRequest = <T extends AnyResType = AnyResType, U extends DefaultResponseType<T> = DefaultResponseType<T>>(
  requestConfig: DefaultRequestOptions<U>,
) => Promise<U>

// 封装好http method的请求实例
type DefaultRequest = BaseRequest & {
  get: BaseRequest
  post: BaseRequest
  put: BaseRequest
  delete: BaseRequest
}

const baseRequest: BaseRequest = function <
  T extends AnyResType = AnyResType,
  U extends DefaultResponseType<T> = DefaultResponseType<T>,
>(requestOption: DefaultRequestOptions<U>) {
  return new Promise<U>((resolve) => {
    // 自动携带登录 token（Bearer 鉴权，对齐纯净骨架后端）
    const token = wx.getStorageSync('token')
    const header = {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    }
    if (requestOption.header) {
      requestOption.header = {
        ...requestOption.header,
        ...header,
      }
    } else {
      requestOption.header = header
    }
    // 是否显示loading，显示mask用于阻止用户多次点击
    if (requestOption.loading) {
      wx.showLoading &&
        wx.showLoading({
          title: '加载中...',
          mask: true,
        })
    }
    // 请求前拼接后端地址 + 接口前缀（对齐纯净骨架后端 /api/v1）
    requestOption.url = config.defaultApiServer[config.env] + config.apiPrefix + requestOption.url
    if (!requestOption.success) {
      // 通用的响应处理方法，可以在下面添加
      requestOption.success = (result: { data: IAnyObject; statusCode?: number }) => {
        // HTTP 401：token 失效，清登录态跳登录页，返回失败（不继续 resolve）
        if (result.statusCode === 401) {
          wx.removeStorageSync('token')
          wx.reLaunch({ url: '/pages/login/index' })
          resolve({
            isSuccess: false,
            code: 401,
            message: '未授权',
            data: undefined,
          } as U)
          return
        }
        resolve({
          isSuccess: Boolean(result.data && Number(result.data.code) === 0),
          code: result.data.code ?? -1,
          message: result.data.message ?? '',
          data: result.data.data,
        } as U)
      }
    } else {
      // 传递定制的handler进来，可以将特殊的响应数据处理成ResponseRowData，再在下方转成DefaultResponseType
      const optionSuccessHandler = requestOption.success
      requestOption.success = (result) => {
        optionSuccessHandler(result)
        resolve({
          isSuccess: Boolean(result.data && Number(result.data.code) === 0),
          code: result.data.code ?? -1,
          message: result.data.message ?? '',
          data: result.data.data ?? {},
        } as U)
      }
    }
    if (!requestOption.fail) {
      // 通用的失败处理方法，可以在下面添加
      requestOption.fail = (err: WechatMiniprogram.GeneralCallbackResult) => {
        resolve({
          isSuccess: false,
          code: -1,
          message: err.errMsg,
        } as U)
      }
    } else {
      // 传递定制的handler进来，可以在请求时在fail传递handler进来，特殊地对错误进行处理
      const optionFailHandler = requestOption.fail
      requestOption.fail = (err) => {
        optionFailHandler(err)
        resolve({
          isSuccess: false,
          code: -1,
          message: err.errMsg,
        } as U)
      }
    }
    wx.request({
      ...requestOption,
      complete() {
        wx.hideLoading && wx.hideLoading()
      },
    })
  })
}

const defaultRequest = baseRequest as unknown as DefaultRequest

// 仿照axios，添加get post put delete方法
;(['get', 'post', 'put', 'delete'] as const).forEach((method) => {
  defaultRequest[method] = (requestConfig) => {
    return baseRequest({
      ...requestConfig,
      method: method.toUpperCase() as 'GET' | 'POST' | 'PUT' | 'DELETE',
    })
  }
})

export { defaultRequest }
