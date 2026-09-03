package com.skeleton.modules.demo.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.skeleton.modules.demo.domain.DemoItem;

/**
 * 示例 Mapper：继承 BaseMapper 即获得单表 CRUD。
 * 复杂 SQL 写在 resources/mapper/demo/DemoItemMapper.xml 中。
 */
public interface DemoItemMapper extends BaseMapper<DemoItem> {
}
