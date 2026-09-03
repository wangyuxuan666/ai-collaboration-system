package com.skeleton.modules.demo.controller;

import com.skeleton.common.Result;
import com.skeleton.modules.demo.domain.DemoItemBo;
import com.skeleton.modules.demo.domain.DemoItemVo;
import com.skeleton.modules.demo.service.DemoItemService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.baomidou.mybatisplus.extension.plugins.pagination.Page;

/**
 * 示例业务 Controller：展示分层的写法样板。
 * 新增业务模块时复制本模块结构（controller/service/mapper/domain）改业务名即可。
 */
@RestController
@RequestMapping("/api/v1/demo")
public class DemoItemController {

    private final DemoItemService demoItemService;

    public DemoItemController(DemoItemService demoItemService) {
        this.demoItemService = demoItemService;
    }

    /** 分页查询 */
    @GetMapping
    public Result<Page<DemoItemVo>> page(@RequestParam(defaultValue = "1") int pageNum,
                                         @RequestParam(defaultValue = "10") int pageSize,
                                         @RequestParam(required = false) String name) {
        return Result.ok(demoItemService.pageQuery(pageNum, pageSize, name));
    }

    /** 详情 */
    @GetMapping("/{id}")
    public Result<DemoItemVo> detail(@PathVariable Long id) {
        return Result.ok(demoItemService.getDetail(id));
    }

    /** 新增 */
    @PostMapping
    public Result<Void> create(@Valid @RequestBody DemoItemBo bo) {
        demoItemService.create(bo);
        return Result.ok();
    }

    /** 修改 */
    @PutMapping
    public Result<Void> update(@Valid @RequestBody DemoItemBo bo) {
        demoItemService.update(bo);
        return Result.ok();
    }

    /** 删除 */
    @DeleteMapping("/{id}")
    public Result<Void> remove(@PathVariable Long id) {
        demoItemService.remove(id);
        return Result.ok();
    }
}
