package com.skeleton.common;

/**
 * 业务异常：全局异常处理器统一转成 Result 返回。
 * 业务代码抛 BusinessException，不需要在 Controller 里 try-catch。
 */
public class BusinessException extends RuntimeException {

    private final int code;

    public BusinessException(String message) {
        super(message);
        this.code = 1;
    }

    public BusinessException(int code, String message) {
        super(message);
        this.code = code;
    }

    public int getCode() {
        return code;
    }
}
