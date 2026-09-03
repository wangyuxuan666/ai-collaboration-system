/**
 * 可视化工作台 · 公共能力（core.js）
 * ------------------------------------------------------------------
 * 职责（技术方案第 7 节 + 16.2 清单）：
 *   1. 路径推导：体系根 = 入口页所在目录（入口页 可视化工作台.html 位于体系根）
 *      资产（css/js/lib/data.js/data-static.js）位于 体系根\工具\可视化工作台\
 *      支持 file:// 与 http:// 两种打开方式
 *   2. 相对路径跳转：统一编码拼接 URL（file:// 拼接 file URL；http:// 拼接站内路径），
 *      一律 <a> 用户手势（禁脚本 window.open file://）
 *   3. 复制降级链：navigator.clipboard → execCommand('copy') → 全选手动复制
 *   4. 视图注册 / 菜单切换 / 状态保留 / 全局页脚
 *   5. 背景粒子（轻量 canvas，零依赖；reduce/无 canvas 时静态光斑兜底）
 * 依赖：无（原生 ES2020，普通 <script> 加载，非模块）
 */
(function () {
  "use strict";

  /* ================= 工具函数 ================= */

  function escHtml(s) {
    return String(s == null ? "" : s)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
  }

  function reduceMotion() {
    return typeof matchMedia === "function" &&
      matchMedia("(prefers-reduced-motion: reduce)").matches;
  }

  /** 轻量 DOM 构建：h('div', {class:'x', onclick:fn}, [children...]) */
  function h(tag, attrs, children) {
    var el = document.createElement(tag);
    if (attrs) {
      Object.keys(attrs).forEach(function (k) {
        var v = attrs[k];
        if (v == null) return;
        if (k === "class") el.className = v;
        else if (k === "html") el.innerHTML = v;
        else if (k.indexOf("on") === 0 && typeof v === "function") el.addEventListener(k.slice(2), v);
        else if (k === "dataset") Object.assign(el.dataset, v);
        else el.setAttribute(k, v);
      });
    }
    (children || []).forEach(function (c) {
      if (c == null) return;
      el.appendChild(typeof c === "string" ? document.createTextNode(c) : c);
    });
    return el;
  }

  /* ================= 路径推导（技术方案 7.1） ================= */

  var _rootCache = null;

  /** 工作台目录相对体系根的路径（与 meta.workbenchRelPath 一致，正斜杠） */
  var WORKBENCH_REL = "工具/可视化工作台";

  /**
   * 推导体系根路径（技术方案 7.1）。
   * 入口页（可视化工作台.html）位于体系根目录，故体系根 = 入口页所在目录。
   *   file:// 下 location.pathname 形如 "/F:/AI协作体系/可视化工作台.html"（URL 编码）
   *           解码 → 去掉末尾文件名段 → 其余即体系根（含盘符）
   *   http:// 下形如 "/可视化工作台.html" 或 "/子路径/可视化工作台.html"；目录段即体系根（无盘符）
   * 返回 { ok, rootPath, workbenchDir, drive, scheme }
   *   rootPath    体系根（file:// 含盘符，如 "F:\AI协作体系"；http:// 为目录段）
   *   workbenchDir 工作台目录 = 体系根\工具\可视化工作台
   */
  function detectRoot() {
    if (_rootCache) return _rootCache;
    var result = { ok: false, rootPath: "", workbenchDir: "", drive: "", scheme: "file" };
    try {
      result.scheme = location.protocol === "file:" ? "file" : "http";
      var raw = decodeURIComponent(location.pathname);
      var segs = raw.replace(/^\/+/, "").split("/").filter(function (s) { return s.length > 0; });
      var rootSegs = segs.slice(0, -1);   // 去掉末尾文件名段（可视化工作台.html）→ 体系根目录段
      var drive = (rootSegs[0] || "").replace(/:$/, "");
      result.drive = /^[A-Za-z]$/.test(drive) ? drive : "";
      result.rootPath = rootSegs.join("\\");
      result.workbenchDir = (result.rootPath ? result.rootPath + "\\" : "") +
        WORKBENCH_REL.replace(/\//g, "\\");
      result.ok = result.scheme === "file"
        ? (/^[A-Za-z]$/.test(result.drive) && rootSegs.length >= 2)   // 盘符 + 体系根
        : (segs.length >= 1);                                         // http:// 有页面即可
    } catch (e) { /* 解码失败等异常 → ok:false */ }
    _rootCache = result;
    return result;
  }

  /** 路径段编码：盘符段不编码（保留 "F:"），其余段 encodeURIComponent */
  function encodePath(p) {
    return String(p || "").split(/[\\/]/).map(function (seg, i) {
      if (i === 0 && /^[A-Za-z]:?$/.test(seg)) return seg;
      return seg ? encodeURIComponent(seg) : seg;
    }).join("/");
  }

  /** relPath（相对体系根，正斜杠）→ 链接字符串（供 <a href> 使用；file:// 与 http:// 均可用） */
  function fileUrl(relPath) {
    var root = detectRoot();
    if (!root.ok) return "";
    if (root.scheme === "file") {
      return "file:///" + encodePath(root.rootPath) + "/" + encodePath(relPath);
    }
    // http://：站内绝对路径（从服务根 / 起始），目录段已含在 rootPath 中
    var joined = root.rootPath ? root.rootPath + "/" + relPath : relPath;
    return "/" + encodePath(joined);
  }

  /** 防呆校验：数据 meta.workbenchRelPath 是否与工作台目录约定（工具/可视化工作台）相符 */
  function workbenchMatches(meta) {
    var root = detectRoot();
    if (!root.ok || !meta || !meta.workbenchRelPath) return false;
    var expect = String(meta.workbenchRelPath).replace(/\\/g, "/").replace(/^\/+|\/+$/g, "");
    return expect.toLowerCase() === WORKBENCH_REL.toLowerCase();
  }

  /* ================= 复制降级链（UX 3.7） ================= */

  /** 返回 Promise<{ok, method}>；method: clipboard | execCommand | none */
  function copyText(text) {
    // 链 1：navigator.clipboard（file:// 下可能失败）
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text).then(function () {
        return { ok: true, method: "clipboard" };
      }).catch(function () {
        return copyByExecCommand(text);
      });
    }
    return Promise.resolve(copyByExecCommand(text));
  }

  function copyByExecCommand(text) {
    // 链 2：隐藏 textarea + execCommand('copy')
    var ta = document.createElement("textarea");
    ta.value = text;
    ta.setAttribute("readonly", "");
    ta.style.position = "fixed";
    ta.style.top = "-9999px";
    ta.style.opacity = "0";
    document.body.appendChild(ta);
    ta.select();
    ta.setSelectionRange(0, ta.value.length);
    var ok = false;
    try { ok = document.execCommand("copy"); } catch (e) { ok = false; }
    document.body.removeChild(ta);
    return { ok: ok, method: "execCommand" };
  }

  /** 全选某元素内文本（链 3 兜底，供用户手动复制） */
  function selectAllText(el) {
    if (!el) return;
    var range = document.createRange();
    range.selectNodeContents(el);
    var sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(range);
  }

  /**
   * 绑定复制按钮（含成功/失败反馈与降级 UI）
   * btn: 按钮元素；getText: () => string；fallbackSel: 失败时全选的文本元素
   */
  function bindCopyButton(btn, getText, fallbackSel) {
    if (!btn) return;
    var original = btn.textContent;
    btn.addEventListener("click", function () {
      btn.disabled = true;
      copyText(getText()).then(function (r) {
        btn.disabled = false;
        if (r.ok) {
          btn.classList.remove("is-failed");
          btn.classList.add("is-copied");
          btn.textContent = "已复制";
          setTimeout(function () {
            btn.classList.remove("is-copied");
            btn.textContent = original;
          }, 2000);
        } else {
          btn.classList.remove("is-copied");
          btn.classList.add("is-failed");
          btn.textContent = "复制失败，请手动复制";
          if (fallbackSel) {
            selectAllText(fallbackSel);
            var hint = document.getElementById("copy-fallback-hint");
            if (hint) hint.hidden = false;
          }
        }
      });
    });
  }

  /* ================= 视图注册 / 切换 ================= */

  var views = {};          // name -> { section, init, activate, deactivate }
  var scrollMemory = {};   // name -> scrollTop
  var current = null;
  var scrollEl = null;

  function register(name, view) {
    views[name] = view;
  }

  function switchView(name) {
    if (!document.getElementById("view-" + name)) return; // 无对应 section 则不切换
    if (current === name) return;

    if (current && views[current] && views[current].deactivate) {
      views[current].deactivate();
    }
    if (scrollEl) scrollMemory[current] = scrollEl.scrollTop;

    // 显隐按 DOM section 处理（未注册视图也能显示占位卡）
    document.querySelectorAll(".view").forEach(function (sec) {
      sec.classList.remove("active");
    });

    current = name;
    var section = document.getElementById("view-" + name);
    if (section) section.classList.add("active");
    if (scrollEl) scrollEl.scrollTop = scrollMemory[name] || 0;
    var v = views[name];
    if (v && v.activate) v.activate();

    // 菜单高亮 + aria-current
    var menuItems = document.querySelectorAll(".menu__item");
    menuItems.forEach(function (mi) {
      var on = mi.getAttribute("data-view") === name;
      mi.classList.toggle("is-active", on);
      if (on) mi.setAttribute("aria-current", "page"); else mi.removeAttribute("aria-current");
    });
  }

  /* ================= 背景粒子（6.7，<30 行，零依赖） ================= */

  function initParticles(canvas) {
    if (!canvas || reduceMotion()) return; // reduce 时保留静态光斑
    var ctx = canvas.getContext && canvas.getContext("2d");
    if (!ctx) return;
    var dots = [], W = 0, H = 0, running = true;
    var COLORS = ["34,211,238", "167,139,250"];

    function resize() {
      var rect = canvas.parentElement.getBoundingClientRect();
      W = canvas.width = Math.max(1, Math.floor(rect.width));
      H = canvas.height = Math.max(1, Math.floor(rect.height));
    }
    function spawn(n) {
      for (var i = 0; i < n; i++) {
        dots.push({
          x: Math.random() * W, y: Math.random() * H,
          r: 0.6 + Math.random() * 1.6,
          vy: -(0.08 + Math.random() * 0.35),
          vx: (Math.random() - 0.5) * 0.12,
          a: 0.12 + Math.random() * 0.35,
          tw: Math.random() * Math.PI * 2,
          c: COLORS[Math.floor(Math.random() * COLORS.length)]
        });
      }
    }
    function tick() {
      if (!running) return;
      ctx.clearRect(0, 0, W, H);
      for (var i = 0; i < dots.length; i++) {
        var d = dots[i];
        d.x += d.vx; d.y += d.vy; d.tw += 0.02;
        if (d.y < -4) { d.y = H + 4; d.x = Math.random() * W; }
        if (d.x < -4) d.x = W + 4;
        if (d.x > W + 4) d.x = -4;
        var alpha = d.a * (0.6 + 0.4 * Math.sin(d.tw));
        ctx.beginPath();
        ctx.arc(d.x, d.y, d.r, 0, Math.PI * 2);
        ctx.fillStyle = "rgba(" + d.c + "," + alpha.toFixed(3) + ")";
        ctx.fill();
      }
      requestAnimationFrame(tick);
    }
    resize();
    spawn(64);
    tick();
    window.addEventListener("resize", function () { resize(); spawn(8); });
  }

  /* ================= 启动 ================= */

  function boot() {
    scrollEl = document.getElementById("content-scroll");

    // 1) 菜单装配
    var menu = document.getElementById("menu");
    if (menu) {
      menu.addEventListener("click", function (e) {
        var item = e.target.closest(".menu__item");
        if (item) switchView(item.getAttribute("data-view"));
      });
    }

    // 2) 数据就绪检查（5.1 错误态：data.js 缺失/损坏 → 错误卡，骨架可用）
    var data = window.VWB_DATA;
    if (!data || typeof data !== "object") {
      var host = document.getElementById("content-scroll");
      if (host) {
        host.innerHTML = "";
        host.appendChild(
          h("div", { class: "state-card is-error", role: "alert" }, [
            h("h3", null, ["数据文件缺失或损坏"]),
            h("p", null, ["请确认 data.js 完整，或双击「人工维护\\可视化工作台更新数据.bat」重新生成后刷新页面。"]),
            h("p", { class: "detail-path" }, ["当前检测：window.VWB_DATA 不存在"])
          ])
        );
      }
      renderFooter(null);
      return;
    }

    // 3) 页脚更新时间
    renderFooter(data.meta);

    // 4) 视图初始化（每个视图只构建一次 DOM，切换只做显隐）
    Object.keys(views).forEach(function (name) {
      var v = views[name];
      var section = document.getElementById("view-" + name);
      if (!section) return;
      v.section = section;
      if (v.init) v.init(section, data);
    });

    // 4.5) 未注册视图 → 占位卡（基准页阶段：其余视图待风格确认后铺开）
    document.querySelectorAll(".view").forEach(function (sec) {
      var name = sec.id.replace(/^view-/, "");
      if (views[name]) return;
      var titles = { flow: "使用流程树", quickstart: "快速使用" };
      sec.appendChild(h("div", { class: "state-card" }, [
        h("h3", null, [titles[name] || name]),
        h("p", null, ["本视图待总览基准页风格确认后开发。"])
      ]));
    });

    // 5) 默认视图：总览
    switchView("overview");

    // 6) 粒子背景
    initParticles(document.getElementById("bg-particles"));
  }

  function renderFooter(meta) {
    var el = document.getElementById("footer-updated");
    if (!el) return;
    var t = (meta && meta.updatedAt) || "未知";
    el.textContent = "数据最后更新时间：" + t;
  }

  /* ================= 导出 ================= */

  window.VWB = {
    core: {
      escHtml: escHtml,
      reduceMotion: reduceMotion,
      h: h,
      detectRoot: detectRoot,
      root: detectRoot,
      fileUrl: fileUrl,
      encodePath: encodePath,
      workbenchMatches: workbenchMatches,
      copyText: copyText,
      bindCopyButton: bindCopyButton,
      selectAllText: selectAllText
    },
    register: register,
    switchView: switchView,
    boot: boot,
    views: views            // 视图注册表（调试/验证用）
  };
})();
