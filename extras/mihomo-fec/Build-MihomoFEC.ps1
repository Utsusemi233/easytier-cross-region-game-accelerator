param([string]$WorkDir=(Join-Path $PSScriptRoot '_build'),[string]$Go='go')
$ErrorActionPreference='Stop'
$taskRoot=[IO.Path]::GetFullPath($WorkDir)
if(-not (Test-Path -LiteralPath $taskRoot)){[void](New-Item -ItemType Directory -Path $taskRoot)}
$taskSource=Join-Path $taskRoot 'mihomo-source'
if(-not (Test-Path -LiteralPath $taskSource)){
 & git clone --filter=blob:none --single-branch --branch v1.19.32 https://github.com/MetaCubeX/mihomo.git $taskSource
 if($LASTEXITCODE -ne 0){throw 'Upstream clone failed'}
}
$taskCommit=(& git -C $taskSource rev-parse HEAD).Trim()
if($taskCommit -ne '88dcbf7f1614a67c3b36b848ee3592dfa92ada36'){throw 'Unexpected upstream revision; do not patch this checkout'}
$taskPatch=Join-Path $PSScriptRoot 'mihomo-v1.19.32.patch'
& git -C $taskSource apply --check $taskPatch
if($LASTEXITCODE -eq 0){
 & git -C $taskSource apply $taskPatch
 if($LASTEXITCODE -ne 0){throw 'Patch application failed'}
}else{
 & git -C $taskSource apply --reverse --check $taskPatch
 if($LASTEXITCODE -ne 0){throw 'Patch does not match; preserve checkout for review'}
}
$taskOverlay=Join-Path $PSScriptRoot 'overlay'
Get-ChildItem -LiteralPath $taskOverlay -File -Recurse | ForEach-Object {
 $taskRelative=$_.FullName.Substring($taskOverlay.Length+1)
 $taskTarget=Join-Path $taskSource $taskRelative
 if(Test-Path -LiteralPath $taskTarget){
  if((Get-FileHash -LiteralPath $taskTarget).Hash -ne (Get-FileHash -LiteralPath $_.FullName).Hash){throw ('Preserve existing modified file: '+$taskTarget)}
 }else{
  [void](New-Item -ItemType Directory -Path (Split-Path $taskTarget) -Force)
  Copy-Item -LiteralPath $_.FullName -Destination $taskTarget
 }
}
$env:CGO_ENABLED='0';$env:GOAMD64='v1'
Push-Location $taskSource
try{
 & $Go test ./component/udpspeeder ./component/easytier ./dns ./adapter/outbound
 if($LASTEXITCODE -ne 0){throw 'Targeted tests failed'}
 & $Go build -tags with_gvisor -trimpath -ldflags '-X github.com/metacubex/mihomo/constant.Version=v1.19.32-fec.3 -s -w' -o (Join-Path $taskRoot 'mihomo-fec.exe') .
 if($LASTEXITCODE -ne 0){throw 'Build failed'}
}finally{Pop-Location}
Get-FileHash -LiteralPath (Join-Path $taskRoot 'mihomo-fec.exe') -Algorithm SHA256
