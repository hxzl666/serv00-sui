@echo off
setlocal enabledelayedexpansion
set GITHUB_TOKEN=
for /f "delims=" %%i in ('gh auth token') do (
    set TOKEN=%%i
    git remote set-url origin https://hxzl666:!TOKEN!@github.com/hxzl666/serv00-sui.git
    git add .
    git commit -m "feat: 在 GitHub Actions 中加入 FreeBSD 自动构建与发布，并使一键脚本支持双模拉取"
    set GITHUB_TOKEN=
    git push origin main
)
