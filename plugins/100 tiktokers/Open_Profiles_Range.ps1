param(
[int]$From=1,
[int]$To=10,
[int]$MaxParallel=5,
[int]$DelayMs=500,
[string]$ProfilePrefix,
[string]$ProfilesRoot,
[string]$OperaExe
)
function Read-Config($path){ Get-Content -Raw -Path $path | ConvertFrom-Json }
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfg = Read-Config (Join-Path $ScriptDir "opera_profiles.config.json")
if($PSBoundParameters.ContainsKey('ProfilePrefix')){$cfg.ProfilePrefix=$ProfilePrefix}
if($PSBoundParameters.ContainsKey('ProfilesRoot')){$cfg.ProfilesRoot=$ProfilesRoot}
if($PSBoundParameters.ContainsKey('OperaExe')){$cfg.OperaExe=$OperaExe}
$jobs=@()
for($i=$From;$i -le $To;$i++){
  $name="{0}{1:D3}" -f $cfg.ProfilePrefix,$i
  $dir=Join-Path $cfg.ProfilesRoot $name
  $args='--user-data-dir="' + $dir + '"'
  Write-Host ("Launching {0} -> {1}" -f $name,$dir)
  $jobs+=Start-Process -FilePath $cfg.OperaExe -ArgumentList $args -PassThru
  while($jobs.Count -ge $MaxParallel){
    Start-Sleep -Milliseconds $DelayMs
    $jobs=$jobs | Where-Object { $_.HasExited -eq $false }
  }
  Start-Sleep -Milliseconds $DelayMs
}
Write-Host ("Launched {0} profiles." -f ($To-$From+1))
