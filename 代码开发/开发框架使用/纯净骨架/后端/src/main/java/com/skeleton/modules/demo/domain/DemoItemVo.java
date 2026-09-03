package com.skeleton.modules.demo.domain;

import lombok.Data;

/**
 * 出参对象（Vo）：返回给前端的数据结构。
 * 约定：只返回前端需要的字段，不直接返回实体。
 */
@Data
public class DemoItemVo {

    private Long id;

    private String name;

    private Integer status;

    private String createTime;
}
