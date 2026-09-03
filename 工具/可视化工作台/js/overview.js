/**
 * 可视化工作台 · 总览视图（overview.js · 改版：左→右分层树）
 * ------------------------------------------------------------------
 * 依据《UX方案与设计契约》3.3 / 4.1 / 6.8 与《技术方案》8 节：
 *   ECharts tree：layout:'orthogonal' + orient:'LR'，固定视口 + 原生 roam 拖拽/缩放（scaleLimit 0.3~2.5，初始约 0.7 倍）
 *   3 主干垂直分区（单 series，正交布局各子树自动分带，互不交叉）
 *   线语义：lineType solid=必读（青实线）/ dashed=按需（紫虚线）+ trigger 触发条件（节点标签第二行 + 详情卡）
 *   渐进展开：点击节点 = 展开/收起（treeExpandAndCollapse）+ 右下详情卡；默认收起（画像/经验/分类/领域）
 *   角色节点展开 5 子项：简述（纯文字）+ 参考资料/流程/专业领域/资产目录（按真实文件，无文件不显示）
 *   无挂件（用户确认移除，信息后续在流程树场景体现）
 *   节点文字不斜体；prefers-reduced-motion 关动画
 */
(function () {
  "use strict";
  var C = window.VWB.core;
  var reduced = C.reduceMotion();

  /* ---------- 主题色（与 CSS 变量同源） ---------- */
  function cssVar(name, fallback) {
    try {
      var v = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
      return v || fallback;
    } catch (e) { return fallback; }
  }
  var COLORS = {
    cyan: cssVar("--accent-cyan", "#22d3ee"),
    violet: cssVar("--accent-violet", "#a78bfa"),
    text0: cssVar("--text-0", "#eaf2ff"),
    text1: cssVar("--text-1", "#9db2d8"),
    text2: cssVar("--text-2", "#5d7298")
  };

  /* ---------- 状态 ---------- */
  var chart = null, rootNode = null;
  var elViewport, elCanvas, elDetail, elMask, elHint;
  var INIT_SCALE = 0.7;       // 初始视角缩放（ECharts 原生 roam + scaleLimit 0.3~2.5）
  var rawById = {};           // id -> 原始节点
  var orderIds = [];          // 前序 id 列表（与 ECharts dataIndex 对齐）
  var initialized = false;

  /* ---------- 富文本转义（rich 标记用 '|' 与 '{}'） ---------- */
  function escRich(s) {
    return String(s == null ? "" : s).replace(/[{}|]/g, "");
  }

  /* ---------- 数据预处理 ----------
     深拷贝；按层级写内联样式；
     初始折叠：expandable 或深度 >= 4 且有子级的节点收起（渐进展开） */
  function normalizeTree(src) {
    var root = Array.isArray(src) ? (src[0] || null) : (src || null);
    if (!root) return null;
    root = JSON.parse(JSON.stringify(root));
    rawById = {};
    orderIds = [];

    var rootItem = {
      color: { type: "radial", x: 0.4, y: 0.4, r: 0.9,
        colorStops: [{ offset: 0, color: "#7ff3ff" }, { offset: 1, color: COLORS.cyan }] },
      borderColor: "#0a0e1a", borderWidth: 1, shadowBlur: 24, shadowColor: "rgba(34,211,238,0.6)"
    };
    var branchItem = {
      color: COLORS.cyan, borderColor: "#0a0e1a", borderWidth: 1.4,
      shadowBlur: 14, shadowColor: "rgba(34,211,238,0.5)"
    };
    var nodeItem = {
      color: "rgba(34,211,238,0.85)", borderColor: "rgba(34,211,238,0.4)", borderWidth: 1,
      shadowBlur: 8, shadowColor: "rgba(34,211,238,0.35)"
    };
    var roleItem = {
      color: "rgba(157,178,216,0.9)", borderColor: "rgba(34,211,238,0.35)", borderWidth: 1,
      shadowBlur: 6, shadowColor: "rgba(34,211,238,0.25)"
    };

    (function walk(n, depth, parent) {
      n.__depth = depth;
      n.__parentId = parent ? parent.id : null;   // 标量父引用（避免数据环，ECharts 深拷贝要求无环）
      rawById[n.id] = n;
      orderIds.push(n.id);

      if (depth === 0) {
        n.symbolSize = 34; n.itemStyle = rootItem;
        n.label = { fontSize: 14, color: COLORS.text0 };
      } else if (depth === 1) {
        n.symbolSize = 15; n.itemStyle = branchItem;
        n.label = { fontSize: 13, color: "#d8fbff" };
      } else if (n.type === "role") {
        n.symbolSize = 9; n.itemStyle = roleItem;
        n.label = { fontSize: 11.5, color: COLORS.text0 };
      } else {
        n.symbolSize = 10; n.itemStyle = nodeItem;
        n.label = { fontSize: 12, color: COLORS.text0 };
      }
      // 线语义（节点级 lineStyle 控制到父的连线）
      if (n.lineType === "dashed") {
        n.lineStyle = { type: "dashed", color: "rgba(167,139,250,0.75)", width: 1.4 };
      } else {
        n.lineStyle = { type: "solid", color: "rgba(34,211,238,0.32)", width: 1.4 };
      }
      // 渐进展开：expandable（画像/经验/分类/领域）、角色（点击角色才展开子项）、或深度 >= 4（角色子项的更深层）默认收起
      if (n.children && n.children.length && (n.expandable || depth >= 4 || n.type === "role")) {
        n.collapsed = true;
      }
      if (n.children) {
        n.children.forEach(function (c) { walk(c, depth + 1, n); });
      }
    })(root, 0, null);

    return root;
  }

  /* ---------- 详情卡 ---------- */
  function fillDetail(node) {
    var rel = node.relPath || "";
    var isDir = !(node.type === "file");
    var nameEl = elDetail.querySelector(".detail-name");
    var tagEl = elDetail.querySelector(".detail-tag");
    var pathEl = elDetail.querySelector(".detail-path");
    var descEl = elDetail.querySelector(".detail-desc");
    var trigEl = elDetail.querySelector(".detail-trigger");
    var actEl = elDetail.querySelector(".detail-actions");

    nameEl.textContent = node.name || "（未命名）";
    tagEl.textContent = isDir ? "目录" : "文件";
    tagEl.className = "tag detail-tag " + (isDir ? "tag--dir" : "tag--file");
    if (rel) { pathEl.textContent = rel; pathEl.hidden = false; } else { pathEl.hidden = true; }

    var desc = (node.desc || "").trim();
    if (desc) { descEl.textContent = desc; descEl.classList.remove("is-missing"); }
    else { descEl.textContent = "（待补充）"; descEl.classList.add("is-missing"); }

    if (node.trigger) { trigEl.textContent = "触发条件：" + node.trigger; trigEl.hidden = false; }
    else { trigEl.hidden = true; }

    actEl.innerHTML = "";
    if (rel) {
      if (!isDir) {
        actEl.appendChild(C.h("a", { class: "btn btn--primary", href: C.fileUrl(rel), target: "_blank", rel: "noopener" }, ["打开文件"]));
      } else {
        actEl.appendChild(C.h("span", { class: "footer-hint", style: "font-size:11px;align-self:center" },
          ["目录：复制路径后粘贴到文件资源管理器地址栏打开"]));
      }
      var copyBtn = C.h("button", { class: "btn", onclick: function () {
        var self = this;
        C.copyText(rel).then(function (r) {
          if (r.ok) self.textContent = "已复制";
          else { self.textContent = "复制失败"; C.selectAllText(pathEl); }
          setTimeout(function () { self.textContent = "复制路径"; }, 1800);
        });
      } }, ["复制路径"]);
      actEl.appendChild(copyBtn);
    }
  }

  function showDetail(node) {
    if (!node) return;
    fillDetail(node);
    elDetail.classList.add("show");
    elMask.classList.add("show");
    elDetail.setAttribute("aria-hidden", "false");
  }

  function hideDetail() {
    elDetail.classList.remove("show");
    elMask.classList.remove("show");
    elDetail.setAttribute("aria-hidden", "true");
  }

  /* ---------- 实时树查询 ---------- */
  function liveTree() {
    try {
      return chart.getModel().getSeriesByIndex(0).getData().tree;
    } catch (e) { return null; }
  }
  function liveNodeById(id) {
    var t = liveTree();
    if (!t) return null;
    var d = null;
    try { d = chart.getModel().getSeriesByIndex(0).getData(); } catch (e) { return null; }
    var out = null;
    t.eachNode("preorder", function (n) {
      if (out) return;
      var raw = d.getRawDataItem(n.dataIndex);
      if (raw && raw.id === id) out = n;
    });
    return out;
  }
  function nodeById(id) { return rawById[id] || null; }

  /* ---------- 节点点击（元素级监听，与 ECharts tree 原生机制一致） ---------- */
  function attachNodeClicks() {
    var data = chart.getModel().getSeriesByIndex(0).getData();
    data.each(function (idx) {
      var el = data.getItemGraphicEl(idx);
      if (!el) return;
      if (el.__vwbBound) return;
      el.__vwbBound = true;
      el.on("click", function () {
        // ECharts tree 的 dataIndex 含虚拟根（0），按原始 id 反查节点，避免序号偏移
        var raw = data.getRawDataItem(idx);
        var node = raw && raw.id ? nodeById(raw.id) : null;
        if (!node) return;
        // 渐进展开：有子级的节点点击展开/收起
        if (node.children && node.children.length) {
          chart.dispatchAction({ type: "treeExpandAndCollapse", seriesIndex: 0, dataIndex: idx });
        }
        showDetail(node);
      });
    });
  }

  /* ---------- 原生 roam（ECharts tree 内置：roam:true + scaleLimit + treeRoam action；浏览器内拖拽/缩放成熟可靠） ---------- */
  /** 初始视角：约 0.7 倍（treeRoam zoom 为增量 1→0.7），以视口中心为锚点 */
  function initialZoom() {
    if (!chart) return;
    try {
      chart.dispatchAction({
        type: "treeRoam", seriesIndex: 0,
        zoom: INIT_SCALE,
        originX: (elViewport.clientWidth || 600) / 2,
        originY: (elViewport.clientHeight || 400) / 2
      });
    } catch (e) { /* 容错：保持默认视角 */ }
  }

  /* ---------- 视图构建 ---------- */
  function buildChart() {
    if (initialized || !window.echarts) return;
    var ov = (window.VWB_DATA && window.VWB_DATA.overview) || {};
    rootNode = normalizeTree(ov.tree);
    if (!rootNode) {
      elCanvas.innerHTML = "";
      elCanvas.appendChild(C.h("div", { class: "state-card" }, [
        C.h("h3", null, ["暂无数据"]),
        C.h("p", null, ["尚未生成数据，请双击「人工维护\\可视化工作台更新数据.bat」后刷新。"])
      ]));
      initialized = true;
      return;
    }
    if (!elCanvas || elCanvas.offsetWidth === 0) return;

    var renderer = (window.VWB && window.VWB.renderer) || "canvas"; // renderer 可覆盖（测试/SSR 用）
    chart = window.echarts.init(elCanvas, null, { renderer: renderer });

    var option = {
      animation: reduced ? false : true,
      animationDuration: reduced ? 0 : 700,          // 首次进场动画（节点依次浮现）
      animationDurationUpdate: reduced ? 0 : 120,    // 展开/收起更新动画：120ms 轻量过渡（原 240ms）
      animationEasing: "ease-out",
      animationEasingUpdate: "ease-out",
      animationDelay: reduced ? undefined : function (idx) { return idx * 40; },      // 仅首次进场逐节点浮现
      animationDelayUpdate: reduced ? undefined : function () { return 0; },          // 展开/收起零延迟：新增子节点立即出现（避免逐节点 40ms 排队拖慢节奏）
      series: [{
        type: "tree",
        layout: "orthogonal",
        orient: "LR",
        roam: true,                     // ECharts 原生 roam：拖拽平移 + 滚轮缩放
        scaleLimit: { min: 0.3, max: 2.5 }, // 缩放限值（tree 系列生效项）
        expandAndCollapse: false,       // 展开/收起由节点点击处理（treeExpandAndCollapse + 详情卡）
        data: [rootNode],
        left: 24,
        right: 36,
        top: 12,
        bottom: 12,
        symbol: "circle",
        label: {
          position: "right",
          distance: 8,
          color: COLORS.text0,
          formatter: function (p) {
            var n = p && p.data;
            if (!n) return "";
            var parts = ["{name|" + escRich(n.name || "") + "}"];
            if (n.type === "role" && n.desc) parts.push("{desc|" + escRich(n.desc) + "}");
            if (n.trigger) parts.push("{trigger|" + escRich(n.trigger) + "}");
            // 折叠态提示（实时展开状态）
            if (n.children && n.children.length) {
              var isExpand = true;
              try {
                var ln = chart.getModel().getSeriesByIndex(0).getData().tree.getNodeByDataIndex(p.dataIndex);
                isExpand = !ln || ln.isExpand;
              } catch (e) { /* 保持默认 */ }
              if (!isExpand) parts.push("{hint|点击展开}");
            }
            return parts.join("\n");
          },
          rich: {
            name: { fontSize: 12, color: COLORS.text0, fontWeight: 500, lineHeight: 17,
              textShadowColor: "rgba(34,211,238,0.25)", textShadowBlur: 4 },
            desc: { fontSize: 10.5, color: COLORS.text1, lineHeight: 15 },
            trigger: { fontSize: 10, color: COLORS.violet, lineHeight: 14, textShadowColor: "rgba(167,139,250,0.3)", textShadowBlur: 3 },
            hint: { fontSize: 10, color: COLORS.text2, lineHeight: 14 }
          }
        },
        lineStyle: { color: "rgba(34,211,238,0.32)", width: 1.4 },
        emphasis: {
          scale: true,
          itemStyle: { shadowBlur: 24, shadowColor: "rgba(34,211,238,0.85)", borderColor: COLORS.cyan },
          label: { color: "#d8fbff", textShadowBlur: 8, textShadowColor: "rgba(34,211,238,0.6)" }
        }
      }]
    };
    chart.setOption(option);

    chart.on("rendered", function () {
      attachNodeClicks();
    });

    window.addEventListener("resize", function () {
      if (!chart) return;
      chart.resize();
    });

    // 首帧后应用初始视角（约 0.7 倍）
    setTimeout(function () { initialZoom(); }, reduced ? 0 : 60);
    initialized = true;
  }

  /* ---------- 视图生命周期 ---------- */
  function init(section, data) {
    var ov = (data && data.overview) || {};
    section.innerHTML = "";

    var head = C.h("div", { class: "ov-head" }, [
      C.h("h1", { class: "view-title sheen" }, ["总览"]),
      C.h("p", { class: "view-sub" }, ["AI 协作体系 · 左→右分层树（占位文案，产出者待定）"])
    ]);
    section.appendChild(head);

    elViewport = C.h("div", { class: "ov-viewport" });
    elCanvas = C.h("div", { class: "ov-canvas", role: "img", "aria-label": "AI 协作体系左→右分层树" });

    elHint = C.h("div", { class: "ov-hints" }, [
      C.h("span", null, ["点击节点看说明 / 展开收起"]),
      C.h("span", null, ["滚轮缩放 · 拖拽平移"])
    ]);
    var legend = C.h("div", { class: "ov-legend" }, [
      C.h("span", { class: "legend-item" }, [C.h("span", { class: "legend-line" }), "实线 = 必读"]),
      C.h("span", { class: "legend-item" }, [C.h("span", { class: "legend-line is-dashed" }), "虚线 = 按需 + 触发条件"])
    ]);

    elViewport.appendChild(elCanvas);
    elViewport.appendChild(elHint);
    elViewport.appendChild(legend);
    section.appendChild(elViewport);

    elMask = C.h("div", { class: "detail-mask", onclick: hideDetail });
    elDetail = C.h("div", {
      id: "detail-card", class: "card", role: "dialog", "aria-label": "节点详情", "aria-hidden": "true"
    }, [
      C.h("div", { class: "detail-head" }, [
        C.h("h3", { class: "detail-name" }, [""]),
        C.h("button", { class: "detail-close", "aria-label": "关闭", onclick: hideDetail }, ["×"])
      ]),
      C.h("span", { class: "tag detail-tag" }, [""]),
      C.h("div", { class: "detail-path", hidden: true }, [""]),
      C.h("p", { class: "detail-desc" }, [""]),
      C.h("p", { class: "detail-trigger", hidden: true }, [""]),
      C.h("div", { class: "detail-actions" }, [])
    ]);
    section.appendChild(elMask);
    section.appendChild(elDetail);

    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape") hideDetail();
    });
  }

  function activate() {
    if (!window.echarts) {
      elCanvas.innerHTML = "";
      elCanvas.appendChild(C.h("div", { class: "state-card is-error", role: "alert" }, [
        C.h("h3", null, ["树组件未就绪"]),
        C.h("p", null, ["未找到 lib/echarts.min.js，请确认该文件完整后刷新页面。"]),
        C.h("p", { class: "footer-hint" }, ["依赖：Apache ECharts（本地化，无 CDN）"])
      ]));
      return;
    }
    if (!initialized) {
      buildChart();
      if (chart) requestAnimationFrame(function () { chart.resize(); });
      return;
    }
    if (chart) {
      hideDetail();
      chart.resize();
    }
  }

  function deactivate() {
    hideDetail();
  }

  VWB.register("overview", {
    init: init,
    activate: activate,
    deactivate: deactivate,
    __test: {                       // 验证/调试探针（不影响正常使用）
      getChart: function () { return chart; },
      getZoom: function () {
        try { return chart.getModel().getSeriesByIndex(0).coordinateSystem.getZoom(); } catch (e) { return 1; }
      },
      getCenter: function () {
        try {
          var c = chart.getModel().getSeriesByIndex(0).coordinateSystem.getCenter();
          return c ? [Math.round(c[0]), Math.round(c[1])] : null;
        } catch (e) { return null; }
      },
      dispatchZoom: function (factor, x, y) {
        chart.dispatchAction({ type: "treeRoam", seriesIndex: 0, zoom: factor, originX: x || 0, originY: y || 0 });
      },
      dispatchPan: function (dx, dy) {
        chart.dispatchAction({ type: "treeRoam", seriesIndex: 0, dx: dx || 0, dy: dy || 0 });
      },
      initialZoom: initialZoom,
      showDetail: showDetail,
      hideDetail: hideDetail,
      getRoot: function () { return rootNode; }
    }
  });
})();
