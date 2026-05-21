$text = Get-Content 'c:\Users\jyotu\Desktop\EndpointManagement\EMS\PowerShellEndPointv2\API\Start-EMSAPI.ps1' -Raw
$openCount = 0
$closeCount = 0
$text.ToCharArray() | ForEach-Object {
    if ($_ -eq '{') { $openCount++ }
    if ($_ -eq '}') { $closeCount++ }
}
Write-Host "Open: $openCount, Close: $closeCount"
if ($openCount -ne $closeCount) {
    Write-Host "MISMATCH FOUND!"
} else {
    Write-Host "Braces are balanced."
}
