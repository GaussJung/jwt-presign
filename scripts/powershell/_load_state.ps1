# .state\resources.env 의 KEY=VALUE 줄들을 전역 변수로 로드 (각 스크립트에서 . .\scripts\powershell\_load_state.ps1)
Get-Content .state\resources.env | ForEach-Object {
  if ($_ -match '^\s*([^=]+)=(.*)$') { Set-Variable -Name $matches[1].Trim() -Value $matches[2].Trim() -Scope Global }
}
