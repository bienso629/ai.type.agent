param(
[switch]$DeleteProfiles,
[switch]$DeleteLaunchers
)
function Read-Config($path){ Get-Content -Raw -Path $path | ConvertFrom-Json }
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfg = Read-Config (Join-Path $ScriptDir "opera_profiles.config.json")
if($DeleteProfiles){
  if(Test-Path -LiteralPath $cfg.ProfilesRoot){
    Write-Host ("Deleting profiles under: {0}" -f $cfg.ProfilesRoot)
    Get-ChildItem -LiteralPath $cfg.ProfilesRoot -Directory | ForEach-Object {
      if($_.Name -like ($cfg.ProfilePrefix + "*")){
        Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
      }
    }
  }
}
if($DeleteLaunchers){
  if(Test-Path -LiteralPath $cfg.LauncherDir){
    Write-Host ("Deleting launchers under: {0}" -f $cfg.LauncherDir)
    Get-ChildItem -LiteralPath $cfg.LauncherDir -Filter "Launch_*.bat" | Remove-Item -Force -ErrorAction SilentlyContinue
  }
}
Write-Host "Cleanup done."
