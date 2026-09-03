/**
 * 可视化工作台 · 使用流程树视图（flow.js · 多线并排版）
 * ------------------------------------------------------------------
 * 依据《UX方案与设计契约》3.4 / 4.2 / 8.2 与《技术方案》4.1 flow.scenes：
 *   顶部 5 场景卡；左 = 深度流程区（局部滚动），右 = "怎么用"固定面板
 *   渲染模型（用户确认：分支并排多线向下）：
 *     无分支的链 = 一条线向下；判断点（decision）= 分叉成多条并排的线一起向下，
 *     每条线走自己的环节（如"是否被指定了角色？"→ 是线 / 否线），各自可展开收起、非线性
 *   环节独立成框 + 资源标注（▸读·文件=青 / ⚙用·工具=紫）；环节点击 → 右侧详情抽屉
 *   数据流字段：action 可用 next:[]（显式下一步）或 end:true（线终点）；decision 用 branches
 */
(function () {
  "use strict";
  var C = window.VWB.core;
  var state = { activeScene: null, laneOpen: {} }; // laneOpen: sceneId -> decisionId|branchIdx -> bool(默认开)
  var sectionEl = null, drawerEl = null, maskEl = null;

  function esc(s) { return C.escHtml(s); }

  /* ---------- 资源徽标 ---------- */
  function resBadges(res) {
    return (res || []).map(function (r) {
      var isTool = r.kind === "tool";
      return C.h("span", { class: "res-badge" + (isTool ? " is-tool" : " is-file") },
        [(isTool ? "⚙ 用 · " : "▸ 读 · ") + esc(r.label)]);
    });
  }

  /* ---------- 抽屉 ---------- */
  function openDrawer(step) {
    if (!step) return;
    drawerEl.innerHTML = "";
    drawerEl.appendChild(C.h("div", { class: "drawer-head" }, [
      C.h("h3", { class: "drawer-title" }, [esc(step.text || "")]),
      C.h("button", { class: "detail-close", "aria-label": "关闭", onclick: closeDrawer }, ["×"])
    ]));
    drawerEl.appendChild(C.h("p", { class: "drawer-desc" }, [esc(step.detail || "（说明待补充）")]));
    if (step.relPath) {
      drawerEl.appendChild(C.h("div", { class: "drawer-section" }, [
        C.h("span", { class: "drawer-label" }, ["对应文件（相对体系根）"]),
        C.h("div", { class: "detail-path" }, [esc(step.relPath)])
      ]));
      drawerEl.appendChild(C.h("div", { class: "drawer-actions" }, [
        C.h("a", { class: "btn btn--primary", href: C.fileUrl(step.relPath), target: "_blank", rel: "noopener" }, ["打开文件"]),
        C.h("button", { class: "btn", onclick: function () {
          var self = this;
          C.copyText(step.relPath).then(function (r) {
            if (r.ok) self.textContent = "已复制";
            else { self.textContent = "复制失败"; var p = drawerEl.querySelector(".detail-path"); if (p) C.selectAllText(p); }
            setTimeout(function () { self.textContent = "复制路径"; }, 1800);
          });
        } }, ["复制路径"])
      ]));
    }
    drawerEl.classList.add("show");
    maskEl.classList.add("show");
  }
  function closeDrawer() {
    drawerEl.classList.remove("show");
    maskEl.classList.remove("show");
  }

  /* ---------- 环节卡（独立成框） ---------- */
  function actionCard(step, index) {
    return C.h("div", {
      class: "flow-node is-action",
      role: "button",
      tabindex: "0",
      "aria-label": "查看环节详情",
      onclick: function () { openDrawer(step); },
      onkeydown: function (e) { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); openDrawer(step); } }
    }, [
      C.h("span", { class: "flow-node__no" }, [String(index + 1)]),
      C.h("div", { class: "flow-node__body" }, [
        C.h("p", { class: "flow-node__text" }, [esc(step.text || "")]),
        step.detail ? C.h("p", { class: "flow-node__detail" }, [esc(step.detail)]) : null,
        (step.res && step.res.length) ? C.h("div", { class: "flow-node__res" }, resBadges(step.res)) : null
      ]),
      C.h("span", { class: "flow-node__open", "aria-hidden": "true" }, ["↗"])
    ]);
  }

  /* ---------- 流程图展开（多线并排） ---------- */
  var ctx = null; // { steps, byId, branchTargets, rendered, sceneId }

  function nextOf(step, idx) {
    if (step.branches && step.branches.length) return null;
    if (step.next && step.next.length) return step.next;
    if (step.end) return null;
    var nxt = ctx.steps[idx + 1];
    if (!nxt) return null;
    if (ctx.branchTargets.indexOf(nxt.id) !== -1) return null; // 下一项被其他分支独占
    return [nxt.id];
  }

  /** 渲染一条链（从 startIdx 起沿默认/显式 next 向下；遇 decision 分叉并排；遇已渲染步骤显示汇合引用） */
  function renderChain(host, startIdx) {
    var idx = startIdx;
    while (idx >= 0 && idx < ctx.steps.length) {
      var step = ctx.steps[idx];
      if (ctx.rendered[step.id]) {
        // 汇合（非线性）：引用卡，不重复渲染
        host.appendChild(C.h("div", { class: "flow-merge" }, [
          "↳ 汇入 步骤 " + (idx + 1) + "：" + esc(step.text || "")
        ]));
        return;
      }
      ctx.rendered[step.id] = true;

      if (step.branches && step.branches.length) {
        // 判断点：分叉源卡 + 并排多条线
        host.appendChild(C.h("div", { class: "flow-node is-decision" }, [
          C.h("span", { class: "flow-node__no" }, [String(idx + 1)]),
          C.h("div", { class: "flow-node__body" }, [
            C.h("div", { class: "decision-pill" }, [esc(step.text || "")])
          ])
        ]));
        var group = C.h("div", { class: "flow-lane-group" });
        (step.branches || []).forEach(function (b, bi) {
          var laneKey = step.id + "|" + bi;
          var open = state.laneOpen[ctx.sceneId] ? state.laneOpen[ctx.sceneId][laneKey] !== false : true;
          var lane = C.h("div", { class: "flow-lane" + (open ? " is-open" : " is-closed") });
          var head = C.h("button", {
            class: "lane-head",
            "aria-expanded": open ? "true" : "false",
            onclick: function () {
              state.laneOpen[ctx.sceneId] = state.laneOpen[ctx.sceneId] || {};
              state.laneOpen[ctx.sceneId][laneKey] = !open;
              renderScene(ctx.sceneId);
            }
          }, [
            C.h("b", { class: b.label === "是" ? "yes" : (b.label === "否" ? "no" : "mid") }, [esc(b.label)]),
            C.h("span", { class: "lane-targets" }, ["→ " + (b.next || []).map(function (id) {
              return "步骤 " + (ctx.steps.indexOf(ctx.byId[id]) + 1);
            }).join(" / ")])
          ]);
          lane.appendChild(head);
          var body = C.h("div", { class: "flow-lane__body" });
          if (open) {
            (b.next || []).forEach(function (tid, ti) {
              var tIdx = ctx.steps.indexOf(ctx.byId[tid]);
              if (tIdx < 0) return;
              if (ti > 0) body.appendChild(C.h("div", { class: "flow-arrow", "aria-hidden": "true" }, ["↓"]));
              renderChain(body, tIdx);
            });
          }
          lane.appendChild(body);
          group.appendChild(lane);
        });
        host.appendChild(group);
        return; // 分叉后主线终止
      }

      // action 环节卡 + 箭头
      host.appendChild(actionCard(step, idx));
      var nxt = nextOf(step, idx);
      if (!nxt || !nxt.length) return;
      host.appendChild(C.h("div", { class: "flow-arrow", "aria-hidden": "true" }, ["↓"]));
      idx = ctx.steps.indexOf(ctx.byId[nxt[0]]);
      if (idx < 0) return;
    }
  }

  /* ---------- 渲染场景 ---------- */
  function renderScene(sceneId) {
    var scenes = (window.VWB_DATA && window.VWB_DATA.flow && window.VWB_DATA.flow.scenes) || [];
    var scene = scenes.find(function (s) { return s.id === sceneId; });
    if (!scene) return;
    state.activeScene = sceneId;
    var host = sectionEl.querySelector(".flow-left__canvas");
    if (!host) return;

    var steps = scene.steps || [];
    var byId = {};
    steps.forEach(function (s) { byId[s.id] = s; });
    var branchTargets = [];
    steps.forEach(function (s) {
      (s.branches || []).forEach(function (b) { (b.next || []).forEach(function (id) { branchTargets.push(id); }); });
    });
    ctx = { steps: steps, byId: byId, branchTargets: branchTargets, rendered: {}, sceneId: sceneId };

    host.innerHTML = "";
    renderChain(host, 0);

    // 场景引导语 + 场景卡高亮
    var guide = sectionEl.querySelector(".flow-guide");
    if (guide) guide.textContent = scene.desc || "";
    sectionEl.querySelectorAll(".scene-card").forEach(function (c) {
      var on = c.getAttribute("data-scene") === sceneId;
      c.classList.toggle("is-active", on);
      c.setAttribute("aria-selected", on ? "true" : "false");
    });
  }

  /* ---------- 右面板 ---------- */
  function renderRightPanel() {
    var modules = [
      ["协作入口", "【占位】每次会话先读它，按序读完必读文件。"],
      ["角色", "【占位】被指定角色时，按入口启动对应角色。"],
      ["工具", "【占位】按需调用已登记的 MCP 与 skills。"],
      ["知识库", "【占位】专业判断时先扫索引，命中再读正文。"],
      ["自成长", "【占位】任务前先读画像、检索经验。"],
      ["代码开发", "【占位】代码任务按框架与流程执行。"],
      ["人工维护", "【占位】按维护说明更新记忆库等。"]
    ];
    return C.h("div", { class: "howto-panel panel" }, [
      C.h("div", { class: "howto-title" }, ["各模块一句话怎么用"]),
      C.h("ul", { class: "howto-list" }, modules.map(function (m) {
        return C.h("li", { class: "howto-item" }, [
          C.h("span", { class: "howto-name" }, [esc(m[0])]),
          C.h("span", { class: "howto-desc" }, [esc(m[1])])
        ]);
      })),
      C.h("div", { class: "howto-legend" }, [
        C.h("span", { class: "res-badge is-file" }, ["▸ 读 · 文件/入口"]),
        C.h("span", { class: "res-badge is-tool" }, ["⚙ 用 · 工具/MCP"])
      ])
    ]);
  }

  /* ---------- 视图 ---------- */
  function init(section, data) {
    sectionEl = section;
    var scenes = (data && data.flow && data.flow.scenes) || [];
    section.innerHTML = "";

    section.appendChild(C.h("div", { class: "page-head" }, [
      C.h("h1", { class: "view-title sheen" }, ["使用流程树"]),
      C.h("p", { class: "view-sub" }, ["按场景顺流程走，就知道怎么用（引导文案占位，产出者待定）。"])
    ]));

    var tabs = C.h("div", { class: "scene-tabs", role: "tablist", "aria-label": "使用场景" });
    scenes.forEach(function (sc) {
      tabs.appendChild(C.h("button", {
        class: "scene-card", role: "tab", "data-scene": sc.id, "aria-selected": "false",
        onclick: function () { renderScene(sc.id); }
      }, [esc(sc.title)]));
    });
    section.appendChild(tabs);
    section.appendChild(C.h("div", { class: "flow-guide" }, [""]));

    var body = C.h("div", { class: "flow-body" });
    body.appendChild(C.h("div", { class: "flow-left" }, [C.h("div", { class: "flow-left__canvas" })]));
    body.appendChild(renderRightPanel());
    section.appendChild(body);

    maskEl = C.h("div", { class: "drawer-mask", onclick: closeDrawer });
    drawerEl = C.h("div", { id: "drawer", role: "dialog", "aria-label": "环节详情", "aria-hidden": "true" });
    document.body.appendChild(maskEl);
    document.body.appendChild(drawerEl);
    document.addEventListener("keydown", function (e) { if (e.key === "Escape") closeDrawer(); });

    if (scenes.length) renderScene(scenes[0].id);
  }

  function deactivate() { closeDrawer(); }

  VWB.register("flow", { init: init, deactivate: deactivate });
})();
