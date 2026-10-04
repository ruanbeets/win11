#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('All','User','Machine')][string]$Scope = 'All',
    [switch]$Audit,
    [string]$AuditPath,
    [switch]$Restore,
    [string]$StatePath,
    [string]$ConfigPath,
    [switch]$NoElevation
)
$ErrorActionPreference = 'Stop'
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot 'config.json' }
Import-Module (Join-Path $PSScriptRoot 'scripts\Tune.psm1') -Force
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
Assert-TuneConfig $config
if ($Audit) {
    $json = Get-TuneAudit | ConvertTo-Json -Depth 8
    if ($AuditPath) { [IO.File]::WriteAllText($AuditPath,$json,[Text.UTF8Encoding]::new($false)) }
    else { $json }
    exit 0
}
if ($Restore) {
    if (-not $StatePath) { throw 'Supply -StatePath with the state.json file printed during installation.' }
    Restore-TuneState -Path $StatePath -WhatIf:$WhatIfPreference
    exit 0
}
if ($Scope -eq 'Machine' -and -not (Test-TuneAdmin) -and -not $WhatIfPreference) {
    throw 'Machine scope requires an elevated PowerShell window.'
}
if ($Scope -in @('All','User')) {
    Invoke-Tune -Scope User -Config $config -WhatIf:$WhatIfPreference
}
if ($Scope -eq 'Machine' -or ($Scope -eq 'All' -and (Test-TuneAdmin))) {
    Invoke-Tune -Scope Machine -Config $config -WhatIf:$WhatIfPreference
} elseif ($Scope -eq 'All') {
    if ($WhatIfPreference) {
        Invoke-Tune -Scope Machine -Config $config -WhatIf
    } elseif ($NoElevation) {
        Write-Warning 'User changes completed. Machine changes skipped; run install.cmd -Scope Machine as administrator.'
    } else {
        # Apply HKCU settings before elevation so alternative admin credentials cannot target the wrong user.
        $args = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -Scope Machine -ConfigPath "{1}"' -f $PSCommandPath, (Resolve-Path -LiteralPath $ConfigPath).Path
        $child = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $args -Verb RunAs -WindowStyle Hidden -Wait -PassThru
        if ($child.ExitCode -ne 0) { throw "Machine changes failed (exit $($child.ExitCode)). Inspect the machine log in ProgramData\Win11Tune." }
    }
}
Write-Host 'Completed. Sign out or restart when convenient; no restart was triggered.'
