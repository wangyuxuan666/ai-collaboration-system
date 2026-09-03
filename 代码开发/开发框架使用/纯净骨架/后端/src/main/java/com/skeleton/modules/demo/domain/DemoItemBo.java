package com.skeleton.modules.demo.domain;

import jakarta.validation.constraints.NotBlank;
import lombok.Data;

/**
 * 入参对象（Bo）：接收前端参数并做校验。
 * 约定：新增/修改共用，id 为空表示新增。
 */
@Data
public class DemoItemBo {

    private Long id;

    @NotBlank(message = "名称不能为空")
    private String name;

    private Integer status;
}
