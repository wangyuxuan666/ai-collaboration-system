package com.skeleton.modules.auth.controller;

import com.skeleton.common.BusinessException;
import com.skeleton.common.JwtUtil;
import com.skeleton.common.Result;
import jakarta.validation.constraints.NotBlank;
import lombok.Data;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.HashMap;
import java.util.Map;

/**
 * 登录模块，接口对齐 V3 Admin Vite 前端约定（Web）与小程序约定：
 * - POST /api/v1/auth/login            Web 登录 {username, password, code?} → {token}
 * - GET  /api/v1/auth/captcha          验证码（骨架返回占位图，接真实验证码后替换）
 * - GET  /api/v1/auth/info             当前用户信息（带 Bearer token）
 * - POST /api/v1/auth/miniapp-login     小程序登录 {code, platform} → {token}
 * Web 骨架内置演示账号 admin/123456（内存校验）；小程序登录为骨架模拟，接真实平台后替换。
 */
@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {

    private final JwtUtil jwtUtil;

    public AuthController(JwtUtil jwtUtil) {
        this.jwtUtil = jwtUtil;
    }

    /** 登录：骨架内置账号 admin/123456 */
    @PostMapping("/login")
    public Result<Map<String, String>> login(@RequestBody LoginBo bo) {
        if (!"admin".equals(bo.getUsername()) || !"123456".equals(bo.getPassword())) {
            throw new BusinessException(1, "用户名或密码错误");
        }
        Map<String, String> data = new HashMap<>();
        data.put("token", jwtUtil.createToken(bo.getUsername()));
        return Result.ok(data);
    }

    /**
     * 小程序登录（Web 与小程序共用本后端）。
     * 骨架阶段为模拟登录：不真调微信/抖音服务器，直接用 code 生成 token（subject 存 "mp_" + platform + code 前 8 位）。
     * 接真实平台：用 code 调平台 code2session 接口换 openid，再查/建用户，发 token。
     * - 微信: GET https://api.weixin.qq.com/sns/jscode2session?appid=&secret=&js_code=&grant_type=authorization_code
     * - 抖音: POST https://developer.toutiao.com/api/apps/v2/jscode2session?appid=&secret=&code=
     */
    @PostMapping("/miniapp-login")
    public Result<Map<String, String>> miniappLogin(@RequestBody MiniappLoginBo bo) {
        if (!"wechat".equals(bo.getPlatform()) && !"douyin".equals(bo.getPlatform())) {
            throw new BusinessException(1, "platform 仅支持 wechat / douyin");
        }
        if (bo.getCode() == null || bo.getCode().isEmpty()) {
            throw new BusinessException(1, "code 不能为空");
        }
        // 骨架模拟：真实接入时此处调用平台 code2session 换 openid
        String openid = "mp_" + bo.getPlatform() + "_" + bo.getCode().substring(0, Math.min(8, bo.getCode().length()));
        Map<String, String> data = new HashMap<>();
        data.put("token", jwtUtil.createToken(openid));
        return Result.ok(data);
    }

    /** 验证码：骨架返回占位图 URL（data 为图片地址，前端 el-image 显示）。
     *  接真实验证码后：生成图片 + 存 code 到 Redis/会话，登录时校验。 */
    @GetMapping("/captcha")
    public Result<String> captcha() {
        // 1x1 透明占位图 data URL；生产替换为真实验证码图片
        String placeholder = "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7";
        return Result.ok(placeholder);
    }

    /** 当前用户信息（前端自动带 Authorization: Bearer <token> 头） */
    @GetMapping("/info")
    public Result<Map<String, Object>> info(@RequestHeader(value = "Authorization", required = false) String authorization) {
        if (authorization == null || !authorization.startsWith("Bearer ")) {
            throw new BusinessException(401, "未授权");
        }
        String token = authorization.substring("Bearer ".length());
        String username = jwtUtil.parseUsername(token);
        Map<String, Object> data = new HashMap<>();
        data.put("username", username);
        data.put("roles", new String[]{"admin"});
        return Result.ok(data);
    }

    /** 登录入参 */
    @Data
    public static class LoginBo {
        @NotBlank(message = "用户名不能为空")
        private String username;
        @NotBlank(message = "密码不能为空")
        private String password;
        /** 验证码（前端必发；骨架暂不校验，接真实验证码后校验） */
        private String code;
    }

    /** 小程序登录入参 */
    @Data
    public static class MiniappLoginBo {
        /** 平台：wechat / douyin */
        @NotBlank(message = "platform 不能为空")
        private String platform;
        /** 小程序端 wx.login()/tt.login() 获取的临时凭证 */
        @NotBlank(message = "code 不能为空")
        private String code;
    }
}
