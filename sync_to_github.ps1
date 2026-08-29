<# One-click sync to GitHub: commit local changes and push to origin/main.
# Usage (run at project root):
#   powershell -ExecutionPolicy Bypass -File ./sync_to_github.ps1 -Message "update notes"
#
# First-time setup: add the remote (replace with your repo):
#   git remote add origin git@github.com:<user>/<repo>.git
#   # or HTTPS:
#   git remote add origin https://github.com/<user>/<repo>.git
# Then store a GitHub PAT in Windows Credential Manager (git credential approve)
# so pushes are non-interactive.
#>
param(
  [string]$Message = ""
)

$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot

# 1) Ensure we are at the repo root.
Set-Location $repo

# 2) Verify remote exists.
$remote = (git remote get-url origin 2>$null)
if (-not $remote) {
  Write-Host "ERROR: origin remote is not configured." -ForegroundColor Red
  Write-Host "Run first (replace with your repo):" -ForegroundColor Yellow
  Write-Host "  git remote add origin git@github.com:<user>/<repo>.git" -ForegroundColor Yellow
  Write-Host "then rerun this script." -ForegroundColor Yellow
  exit 1
}

# 3) Commit any uncommitted local changes first.
$status = git status --porcelain
if ($status) {
  $files = ($status | Measure-Object).Count
  if (-not $Message) {
    $Message = "chore: sync update, $files files changed"
  }
  Write-Host ">> Staging $files change(s) and committing..." -ForegroundColor Cyan
  git add -A
  git commit -q -m $Message
  Write-Host "   Committed: $Message" -ForegroundColor Green
} else {
  Write-Host ">> No local changes to commit." -ForegroundColor Gray
}

# 4) Pull latest (rebase) onto remote so push is a fast-forward.
Write-Host ">> Pulling latest from origin/main (rebase)..." -ForegroundColor Cyan
git pull --rebase origin main 2>&1 | Out-Host

# 5) Push.
Write-Host ">> Pushing to origin/main ..." -ForegroundColor Cyan
git push origin main 2>&1 | Out-Host
Write-Host "Done." -ForegroundColor Green
