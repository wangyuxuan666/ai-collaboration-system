package com.skeleton.modules.demo.domain;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * 示例实体：演示 MyBatis-Plus 实体写法。
 * 约定：表名 snake_case，字段 camelCase，逻辑删除字段 deleted。
 */
@Data
@TableName("demo_item")
public class DemoItem {

    @TableId(type = IdType.AUTO)
    private Long id;

    /** 名称 */
    private String name;

    /** 状态：0 停用 1 启用 */
    private Integer status;

    /** 逻辑删除：0 未删 1 已删 */
    private Integer deleted;

    private LocalDateTime createTime;

    private LocalDateTime updateTime;
}
