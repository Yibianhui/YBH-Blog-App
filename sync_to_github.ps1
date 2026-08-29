<# 一键同步到 GitHub：把当前改动提交并推送到 origin/main。
# 用法（在项目根目录执行）：
#   pwsh ./sync_to_github.ps1 [-Message "本次更新说明"]
#
# 首次使用前提：先配置远端（把下面地址换成你的仓库）：
#   git remote add origin git@github.com:<用户名>/<仓库名>.git
# 或 HTTPS：
#   git remote add origin https://github.com/<用户名>/<仓库名>.git
#>
param(
  [string]$Message = ""
)

$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot

# 1) 确保位于仓库根。
Set-Location $repo

# 2) 远端校验。
$remote = (git remote get-url origin 2>$null)
if (-not $remote) {
  Write-Host "错误：尚未配置 origin 远端。" -ForegroundColor Red
  Write-Host "请先执行（替换成你的仓库地址）：" -ForegroundColor Yellow
  Write-Host "  git remote add origin git@github.com:<用户名>/<仓库名>.git" -ForegroundColor Yellow
  Write-Host "然后重试本脚本。" -ForegroundColor Yellow
  exit 1
}

# 3) 拉取远端（rebase），避免非快进被拒。
Write-Host ">> 拉取远端最新（rebase）..." -ForegroundColor Cyan
git pull --rebase origin main 2>&1 | Out-Host

# 4) 若有未提交改动则提交。
$status = git status --porcelain
if ($status) {
  $files = ($status | Measure-Object).Count
  if (-not $Message) {
    $Message = "chore: 同步更新（$files 个文件改动）"
  }
  Write-Host ">> 暂存 $files 个改动并提交..." -ForegroundColor Cyan
  git add -A
  git commit -q -m $Message
  Write-Host "   提交完成：$Message" -ForegroundColor Green
} else {
  Write-Host ">> 没有本地改动需要提交。" -ForegroundColor Gray
}

# 5) 推送。
Write-Host ">> 推送到 origin/main ..." -ForegroundColor Cyan
git push origin main 2>&1 | Out-Host
Write-Host "完成。" -ForegroundColor Green
