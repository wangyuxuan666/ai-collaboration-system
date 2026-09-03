package com.skeleton.modules.demo.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.skeleton.common.BusinessException;
import com.skeleton.modules.demo.domain.DemoItem;
import com.skeleton.modules.demo.domain.DemoItemBo;
import com.skeleton.modules.demo.domain.DemoItemVo;
import com.skeleton.modules.demo.mapper.DemoItemMapper;
import com.skeleton.modules.demo.service.DemoItemService;
import org.springframework.beans.BeanUtils;
import org.springframework.stereotype.Service;

/**
 * 示例服务实现：业务逻辑在这里写。
 * 约定：业务校验失败抛 BusinessException，由全局异常处理统一返回。
 */
@Service
public class DemoItemServiceImpl extends ServiceImpl<DemoItemMapper, DemoItem> implements DemoItemService {

    @Override
    public Page<DemoItemVo> pageQuery(int pageNum, int pageSize, String name) {
        Page<DemoItem> page = page(new Page<>(pageNum, pageSize),
                new LambdaQueryWrapper<DemoItem>()
                        .like(name != null && !name.isEmpty(), DemoItem::getName, name)
                        .orderByDesc(DemoItem::getId));
        Page<DemoItemVo> voPage = new Page<>(page.getCurrent(), page.getSize(), page.getTotal());
        voPage.setRecords(page.getRecords().stream().map(this::toVo).toList());
        return voPage;
    }

    @Override
    public DemoItemVo getDetail(Long id) {
        return toVo(getById(id));
    }

    @Override
    public void create(DemoItemBo bo) {
        DemoItem item = new DemoItem();
        BeanUtils.copyProperties(bo, item);
        item.setStatus(bo.getStatus() == null ? 1 : bo.getStatus());
        save(item);
    }

    @Override
    public void update(DemoItemBo bo) {
        if (bo.getId() == null) {
            throw new BusinessException("id 不能为空");
        }
        DemoItem item = new DemoItem();
        BeanUtils.copyProperties(bo, item);
        updateById(item);
    }

    @Override
    public void remove(Long id) {
        removeById(id); // 逻辑删除（配置了 logic-delete-field）
    }

    private DemoItemVo toVo(DemoItem item) {
        if (item == null) {
            return null;
        }
        DemoItemVo vo = new DemoItemVo();
        BeanUtils.copyProperties(item, vo);
        vo.setCreateTime(item.getCreateTime() == null ? null : item.getCreateTime().toString());
        return vo;
    }
}
