package com.skeleton.modules.demo.service;

import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.baomidou.mybatisplus.extension.service.IService;
import com.skeleton.modules.demo.domain.DemoItem;
import com.skeleton.modules.demo.domain.DemoItemBo;
import com.skeleton.modules.demo.domain.DemoItemVo;

/**
 * 示例服务接口：定义业务能力，实现放 impl。
 * 约定：入参用 Bo（接收），出参用 Vo（返回），不直接暴露实体给前端。
 */
public interface DemoItemService extends IService<DemoItem> {

    Page<DemoItemVo> pageQuery(int pageNum, int pageSize, String name);

    DemoItemVo getDetail(Long id);

    void create(DemoItemBo bo);

    void update(DemoItemBo bo);

    void remove(Long id);
}
