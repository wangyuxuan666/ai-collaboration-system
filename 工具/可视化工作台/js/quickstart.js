/**
 * 可视化工作台 · 快速使用视图（quickstart.js）
 * ------------------------------------------------------------------
 * 依据《UX方案与设计契约》3.5 / 4.3 / 8.4 与《技术方案》7.1 / 9 节：
 *   页面加载即检测体系根路径（core.detectRoot：可视化工作台.html 所在目录即体系根）
 *   通用启动话术（单条，<体系根> 占位符替换为实际路径）+ 一键复制
 *   复制三级降级链：navigator.clipboard → execCommand → 全选提示（core.copyText）
 *   3 步使用说明（结构定，措辞【占位】）
 *   位置异常（meta.workbenchRelPath 与约定不符）→ 警示条，不崩、路径可复制
 */
(function () {
  "use strict";
  var C = window.VWB.core;

  function init(section, data) {
    var qs = (data && data.quickstart) || {};
    var meta = (data && data.meta) || {};
    var root = C.detectRoot();

    section.innerHTML = "";
    section.appendChild(C.h("div", { class: "page-head" }, [
      C.h("h1", { class: "view-title sheen" }, ["快速使用"]),
      C.h("p", { class: "view-sub" }, ["自动检测体系路径，一键复制启动话术。"])
    ]));

    // 路径检测结果条（正常 / 位置异常警示）
    var isWarn = !root.ok || !C.workbenchMatches(meta);
    var bar = C.h("div", { class: "qs-pathbar" + (isWarn ? " is-warning" : "") }, [
      C.h("span", { class: "qs-pathbar__label" }, ["检测到的体系根路径"]),
      C.h("span", { class: "qs-pathbar__value" }, [root.ok ? root.rootPath : "（未能从当前地址推导路径）"])
    ]);
    if (isWarn) {
      bar.appendChild(C.h("span", { class: "qs-pathbar__msg" }, [
        "数据位置异常：请确认 data.js 的 meta.workbenchRelPath 为「工具/可视化工作台」（当前：" +
        ((meta && meta.workbenchRelPath) || "未知") + "）。路径已显示，可手动复制。"
      ]));
    }
    section.appendChild(bar);

    // 话术卡 + 一键复制
    var scriptText = (qs.script || "每次新窗口开始时，先读取 <体系根>\\协作入口\\README.md 并遵守其规则。")
      .replace(/<体系根>/g, root.ok ? root.rootPath : "<体系根>");

    var scriptEl = C.h("p", { class: "script-card__text", id: "qs-script-text" }, [scriptText]);
    var copyBtn = C.h("button", { class: "btn btn--primary", id: "qs-copy-btn" }, ["复制话术"]);
    var selectAllBtn = C.h("button", { class: "btn", hidden: true, onclick: function () { C.selectAllText(scriptEl); } }, ["全选话术"]);
    var fallbackHint = C.h("span", { id: "copy-fallback-hint", hidden: true, class: "footer-hint" },
      ["复制未成功：已为你选中话术文本，请按 Ctrl+C 手动复制。"]);

    var card = C.h("div", { class: "script-card sheen" }, [
      C.h("div", { class: "script-card__label" }, ["启动话术"]),
      scriptEl,
      C.h("div", { class: "script-card__actions" }, [copyBtn, selectAllBtn, fallbackHint])
    ]);
    section.appendChild(card);

    // 一键复制（点击一次即成功；失败按三级降级链）
    copyBtn.addEventListener("click", function () {
      copyBtn.disabled = true;
      C.copyText(scriptText).then(function (r) {
        copyBtn.disabled = false;
        if (r.ok) {
          copyBtn.textContent = "✓ 已复制";
          copyBtn.classList.add("is-copied");
          selectAllBtn.hidden = true;
          fallbackHint.hidden = true;
          setTimeout(function () {
            copyBtn.textContent = "复制话术";
            copyBtn.classList.remove("is-copied");
          }, 2000);
        } else {
          copyBtn.textContent = "复制失败";
          copyBtn.classList.add("is-failed");
          selectAllBtn.hidden = false;
          fallbackHint.hidden = false;
          C.selectAllText(scriptEl);
        }
      });
    });

    // 3 步使用说明（占位）
    var steps = (qs.steps && qs.steps.length) ? qs.steps : [
      "【占位】复制上面的启动话术",
      "【占位】打开你的 AI 工具",
      "【占位】粘贴到新窗口的指令入口"
    ];
    section.appendChild(C.h("h2", { class: "section-title", style: "margin-top:28px" }, ["怎么用"]));
    var stepsWrap = C.h("div", { class: "qs-steps" });
    steps.forEach(function (s, i) {
      stepsWrap.appendChild(C.h("div", { class: "qs-step" }, [
        C.h("span", { class: "qs-step__no" }, [String(i + 1)]),
        C.h("p", { class: "qs-step__text" }, [s])
      ]));
    });
    section.appendChild(stepsWrap);

    if (qs.note) {
      section.appendChild(C.h("p", { class: "footer-hint", style: "margin-top:16px" }, [qs.note]));
    }
  }

  VWB.register("quickstart", { init: init });
})();
