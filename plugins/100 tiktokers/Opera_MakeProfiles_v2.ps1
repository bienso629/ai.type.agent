param(
[int]$Count,
[string]$ProfilePrefix,
[int]$StartIndex,
[string]$ProfilesRoot,
[string]$BaseTemplateDir,
[string]$OperaExe,
[string]$LauncherDir,
[switch]$ForceRecreate
)
function Read-Config($path){ if(-not(Test-Path -LiteralPath $path)){ throw "Config not found: $path"}; Get-Content -Raw -Path $path | ConvertFrom-Json }
function Ensure-Dir($path){ if(-not(Test-Path -LiteralPath $path)){ New-Item -ItemType Directory -Path $path | Out-Null } }
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $ScriptDir "opera_profiles.config.json"
$cfg = Read-Config $ConfigPath
if($PSBoundParameters.ContainsKey('Count')){$cfg.Count=$Count}
if($PSBoundParameters.ContainsKey('ProfilePrefix')){$cfg.ProfilePrefix=$ProfilePrefix}
if($PSBoundParameters.ContainsKey('StartIndex')){$cfg.StartIndex=$StartIndex}
if($PSBoundParameters.ContainsKey('ProfilesRoot')){$cfg.ProfilesRoot=$ProfilesRoot}
if($PSBoundParameters.ContainsKey('BaseTemplateDir')){$cfg.BaseTemplateDir=$BaseTemplateDir}
if($PSBoundParameters.ContainsKey('OperaExe')){$cfg.OperaExe=$OperaExe}
if($PSBoundParameters.ContainsKey('LauncherDir')){$cfg.LauncherDir=$LauncherDir}
if(-not(Test-Path -LiteralPath $cfg.OperaExe)){ Write-Error "Opera not found: $($cfg.OperaExe)"; exit 1 }
if(-not(Test-Path -LiteralPath $cfg.BaseTemplateDir)){ Write-Error "Base template not found: $($cfg.BaseTemplateDir)"; exit 1 }
Ensure-Dir $cfg.ProfilesRoot
Ensure-Dir $cfg.LauncherDir
function Copy-ProfileTemplate($src,$dst){
  Ensure-Dir $dst
  $excludeDirs=@("Cache","GPUCache","Code Cache","GrShaderCache","ShaderCache","Service Worker\CacheStorage")
  $xd=@(); foreach($d in $excludeDirs){ $xd+="/XD","$src\$d" }
  $args=@("$src","$dst","/MIR","/COPY:DAT","/R:1","/W:1")+$xd
  $rob=Start-Process -FilePath "robocopy.exe" -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
  if($rob.ExitCode -ge 8){ throw "Robocopy failed with code $($rob.ExitCode)" }
}
$endIndex=[int]$cfg.StartIndex+[int]$cfg.Count-1
for($i=[int]$cfg.StartIndex;$i -le $endIndex;$i++){
  $name="{0}{1:D3}" -f $cfg.ProfilePrefix,$i
  $dst=Join-Path $cfg.ProfilesRoot $name
  if((Test-Path -LiteralPath $dst) -and $ForceRecreate){
    Write-Host "Removing existing profile $dst"
    Remove-Item -LiteralPath $dst -Recurse -Force -ErrorAction SilentlyContinue
  }
  if(-not(Test-Path -LiteralPath $dst)){
    Write-Host "Creating $name at $dst"
    Copy-ProfileTemplate -src $cfg.BaseTemplateDir -dst $dst
  }else{
    Write-Host "Skipping copy; profile exists: $dst"
  }
  $batPath=Join-Path $cfg.LauncherDir ("Launch_{0}.bat" -f $name)
  $batContent='@echo off`r`nstart "" "' + $cfg.OperaExe + '" --user-data-dir="' + $dst + '"`r`n'
  Set-Content -Path $batPath -Value $batContent -Encoding ASCII
}
Write-Host "Done! Launchers written to: $($cfg.LauncherDir)"
