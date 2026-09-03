package com.skeleton.common;

import lombok.Data;

/**
 * 统一响应结构，对齐 V3 Admin Vite 前端约定：
 * code = 0 表示成功；data 为业务数据；message 为提示信息。
 */
@Data
public class Result<T> {

    private int code;
    private T data;
    private String message;

    public static <T> Result<T> ok(T data) {
        Result<T> r = new Result<>();
        r.code = 0;
        r.data = data;
        r.message = "success";
        return r;
    }

    public static <T> Result<T> ok() {
        return ok(null);
    }

    public static <T> Result<T> fail(int code, String message) {
        Result<T> r = new Result<>();
        r.code = code;
        r.message = message;
        return r;
    }
}
