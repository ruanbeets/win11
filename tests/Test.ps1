#Requires -Version 5.1
[CmdletBinding()]
param([switch]$RegistryIntegration)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
function Assert($Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {$_.Extension -in @('.ps1','.psm1')}) {
    $tokens=$null; $errors=$null
    [Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors) | Out-Null
    Assert (-not $errors.Count) "Syntax errors in $($file.FullName): $errors"
}
Import-Module (Join-Path $root 'scripts\Tune.psm1') -Force
$config=Get-Content -LiteralPath (Join-Path $root 'config.json') -Raw | ConvertFrom-Json
Assert-TuneConfig $config
$bad=Get-Content -LiteralPath (Join-Path $root 'config.json') -Raw | ConvertFrom-Json
$bad.removeApps += 'Microsoft.WindowsStore'
$rejected=$false
try { Assert-TuneConfig $bad } catch { $rejected=$true }
Assert $rejected 'Protected package was accepted.'
$settings=@(Get-TuneSettings User) + @(Get-TuneSettings Machine)
Assert ($settings.Count -eq 24) 'Unexpected settings count.'
Assert (-not ($settings.Path -match 'DeviceGuard|Defender|WindowsUpdate|Services|Memory Management')) 'Security or service tuning entered the plan.'
Assert (-not ($config.disableStartupValues -contains 'LGHUB')) 'Gaming peripheral startup must be preserved.'
Assert (-not ($config.removeApps -match 'Outlook|YourPhone|OneDrive|Office|Xbox|Store|VCLibs|WebView')) 'Keep-app preference violated.'
$stateRoot=Join-Path $env:LOCALAPPDATA 'Win11Tune'
$before=@(Get-ChildItem -LiteralPath $stateRoot -ErrorAction SilentlyContinue | ForEach-Object FullName)
Invoke-Tune -Scope User -Config $config -WhatIf
$after=@(Get-ChildItem -LiteralPath $stateRoot -ErrorAction SilentlyContinue | ForEach-Object FullName)
Assert (($before -join '|') -eq ($after -join '|')) 'Preview wrote rollback state.'
& (Join-Path $root 'install.ps1') -Scope User -WhatIf
if ($RegistryIntegration) {
    $testId=[guid]::NewGuid().ToString('N')
    $testKey='HKCU:\Software\Win11TuneTest-' + $testId
    $testFolder=Join-Path ([IO.Path]::GetTempPath()) ('Win11TuneTest-' + $testId)
    New-Item -ItemType Directory -Path $testFolder | Out-Null
    New-Item -Path $testKey | Out-Null
    try {
        New-ItemProperty -LiteralPath $testKey -Name Existing -Value '%USERPROFILE%\fixture' -PropertyType ExpandString | Out-Null
        New-ItemProperty -LiteralPath $testKey -Name Untouched -Value 42 -PropertyType DWord | Out-Null
        $module=Get-Module Tune
        $stateFile=Join-Path $testFolder 'state.json'
        & $module {
            param($Key,$File)
            $script:stateFile=$File
            $script:state=[pscustomobject]@{Version=1;Scope='User';UserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Computer=$env:COMPUTERNAME;Changes=@();RemovedApps=@();Failures=@()}
            Backup-TuneRegistry $Key Existing
            Backup-TuneRegistry $Key Absent
        } $testKey $stateFile
        Set-ItemProperty -LiteralPath $testKey -Name Existing -Value changed
        New-ItemProperty -LiteralPath $testKey -Name Absent -Value 1 -PropertyType DWord | Out-Null
        Restore-TuneState -Path $stateFile
        $key=Get-Item -LiteralPath $testKey
        Assert ($key.GetValue('Existing',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) -eq '%USERPROFILE%\fixture') 'Original raw value not restored.'
        Assert ($key.GetValueKind('Existing').ToString() -eq 'ExpandString') 'Registry type not restored.'
        Assert ($key.GetValue('Untouched') -eq 42) 'Unrelated registry value modified.'
        Assert (-not ($key.GetValueNames() -contains 'Absent')) 'Originally absent value not removed.'
        Restore-TuneState -Path $stateFile
        Assert ((Get-Item -LiteralPath $testKey).GetValue('Untouched') -eq 42) 'Repeated restore changed unrelated values.'
    } finally {
        # Exact freshly generated fixture paths only; no user data or recursive filesystem cleanup.
        Remove-Item -LiteralPath $testKey -Recurse -Force
        Remove-Item -LiteralPath (Join-Path $testFolder 'state.json') -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $testFolder -Force
    }
}
Write-Host 'PASS: syntax, config protection, preview; registry round-trip when requested.'
