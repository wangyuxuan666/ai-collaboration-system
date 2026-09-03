@echo off
rem 可视化工作台 · 数据更新入口（人工维护）
rem 调用项目脚本：%~dp0..\工具\可视化工作台\可视化工作台更新数据.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\工具\可视化工作台\可视化工作台更新数据.ps1"
if errorlevel 1 (
  echo.
  echo   [错误] 更新未完成！请查看上方错误信息。
  echo   若上方为乱码或空白，请手动运行：
  echo     powershell -ExecutionPolicy Bypass -File "%~dp0..\工具\可视化工作台\可视化工作台更新数据.ps1"
)
echo.
pause
