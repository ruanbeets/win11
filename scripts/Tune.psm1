#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-TuneAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-TuneConfig($Config) {
    $allowed = @('Clipchamp.Clipchamp','Microsoft.BingNews','Microsoft.BingWeather','Microsoft.GetHelp','Microsoft.Getstarted',
        'Microsoft.MicrosoftSolitaireCollection','Microsoft.WindowsFeedbackHub','Microsoft.People','Microsoft.Microsoft3DViewer',
        'Microsoft.MixedReality.Portal','Microsoft.SkypeApp','Microsoft.549981C3F5F10','Microsoft.WindowsMaps','Microsoft.ZuneMusic','Microsoft.ZuneVideo','Microsoft.Todos')
    foreach ($name in $Config.removeApps) {
        if ($name -notin $allowed) { throw "Package outside reviewed removal list: $name" }
    }
    foreach ($name in $Config.disableStartupShortcuts) {
        if ($name -notin @('Ollama.lnk','Send to OneNote.lnk')) { throw "Unreviewed startup shortcut: $name" }
    }
    foreach ($name in $Config.disableStartupValues) {
        if ($name -notin @('Docker Desktop','Steam','EADM','EpicGamesLauncher','GOG Galaxy','Battle.net','CanvaAutoLaunchAvailabilityCheckAgent')) {
            throw "Unreviewed startup entry: $name"
        }
    }
    if ($Config.powerPlan -notin @('Keep','HighPerformance')) { throw 'powerPlan must be Keep or HighPerformance.' }
    if ($Config.ssdRetrim -isnot [bool]) { throw 'ssdRetrim must be a JSON boolean.' }
}

function Get-TuneSettings([string]$Scope) {
    if ($Scope -eq 'User') {
        @(
            @('HKCU:\Software\Microsoft\GameBar','AutoGameModeEnabled',1,'DWord'),
            @('HKCU:\Software\Microsoft\GameBar','AllowAutoGameMode',1,'DWord'),
            @('HKCU:\System\GameConfigStore','GameDVR_Enabled',0,'DWord'),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR','AppCaptureEnabled',0,'DWord'),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR','HistoricalCaptureEnabled',0,'DWord'),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize','EnableTransparency',0,'DWord'),
            @('HKCU:\Control Panel\Desktop\WindowMetrics','MinAnimate','0','String'),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced','TaskbarAnimations',0,'DWord'),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced','TaskbarDa',0,'DWord'),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo','Enabled',0,'DWord'),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','SilentInstalledAppsEnabled',0,'DWord'),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','SubscribedContent-338388Enabled',0,'DWord'),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','SubscribedContent-338389Enabled',0,'DWord'),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','SubscribedContent-353694Enabled',0,'DWord'),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','SubscribedContent-353696Enabled',0,'DWord'),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement','ScoobeSystemSettingEnabled',0,'DWord')
        ) | ForEach-Object { [pscustomobject]@{Path=$_[0];Name=$_[1];Value=$_[2];Kind=$_[3]} }
    } else {
        @(
            @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR','AllowGameDVR',0,'DWord'),
            @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent','DisableWindowsConsumerFeatures',1,'DWord'),
            @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense','AllowStorageSenseGlobal',1,'DWord'),
            @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense','AllowStorageSenseTemporaryFilesCleanup',1,'DWord'),
            @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense','ConfigStorageSenseGlobalCadence',7,'DWord'),
            @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense','ConfigStorageSenseDownloadsCleanupThreshold',0,'DWord'),
            @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense','ConfigStorageSenseRecycleBinCleanupThreshold',0,'DWord'),
            @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense','ConfigStorageSenseCloudContentDehydrationThreshold',0,'DWord')
        ) | ForEach-Object { [pscustomobject]@{Path=$_[0];Name=$_[1];Value=$_[2];Kind=$_[3]} }
    }
}

function Save-TuneState {
    $json = $script:state | ConvertTo-Json -Depth 12
    $temporary = $script:stateFile + '.tmp'
    [IO.File]::WriteAllText($temporary, $json, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $script:stateFile -Force
}

function Backup-TuneRegistry([string]$Path,[string]$Name) {
    $key = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    $exists = $null -ne $key -and $key.GetValueNames() -contains $Name
    $value = $null; $kind = 'DWord'
    if ($exists) {
        $kind = $key.GetValueKind($Name).ToString()
        $value = $key.GetValue($Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    }
    $script:state.Changes += [pscustomobject]@{Type='Registry';Path=$Path;Name=$Name;Exists=$exists;Kind=$kind;Value=$value}
    Save-TuneState
}

function Invoke-Tune {
    [CmdletBinding(SupportsShouldProcess)]
    param([ValidateSet('User','Machine')][string]$Scope, $Config)
    Assert-TuneConfig $Config
    $root = if ($Scope -eq 'User') { Join-Path $env:LOCALAPPDATA 'Win11Tune' } else { Join-Path $env:ProgramData 'Win11Tune' }
    if (-not $WhatIfPreference) {
        if ($Scope -eq 'Machine' -and -not (Test-TuneAdmin)) { throw 'Administrator privileges required.' }
        $run = Join-Path $root ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
        New-Item -ItemType Directory -Path $run -Force | Out-Null
        $script:stateFile = Join-Path $run 'state.json'
        $script:state = [pscustomobject]@{Version=1;Scope=$Scope;UserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Computer=$env:COMPUTERNAME;Changes=@();RemovedApps=@();Failures=@()}
        Save-TuneState
        Write-Host "Rollback state: $script:stateFile"
        Start-Transcript -Path (Join-Path $run 'install.log') | Out-Null
    }
    try {
        foreach ($setting in Get-TuneSettings $Scope) {
            $existingKey = Get-Item -LiteralPath $setting.Path -ErrorAction SilentlyContinue
            if ($existingKey -and $existingKey.GetValueNames() -contains $setting.Name) {
                $existingValue = $existingKey.GetValue($setting.Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                if ("$existingValue" -eq "$($setting.Value)" -and $existingKey.GetValueKind($setting.Name).ToString() -eq $setting.Kind) {
                    continue
                }
            }
            if ($PSCmdlet.ShouldProcess("$($setting.Path)\$($setting.Name)","Set $($setting.Value)")) {
                Backup-TuneRegistry $setting.Path $setting.Name
                if (-not (Test-Path -LiteralPath $setting.Path)) { New-Item -Path $setting.Path -Force | Out-Null }
                New-ItemProperty -LiteralPath $setting.Path -Name $setting.Name -Value $setting.Value -PropertyType $setting.Kind -Force | Out-Null
            }
        }
        if ($Scope -eq 'User') {
            $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
            foreach ($name in $Config.disableStartupValues) {
                $key = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
                if ($key -and $key.GetValueNames() -contains $name -and $PSCmdlet.ShouldProcess($name,'Disable login startup')) {
                    Backup-TuneRegistry $path $name
                    Remove-ItemProperty -LiteralPath $path -Name $name
                }
            }
            $startup = [Environment]::GetFolderPath('Startup')
            foreach ($name in $Config.disableStartupShortcuts) {
                $source = Join-Path $startup $name
                if ((Test-Path -LiteralPath $source) -and $PSCmdlet.ShouldProcess($source,'Move shortcut to rollback folder')) {
                    $destination = Join-Path $run $name
                    $script:state.Changes += [pscustomobject]@{Type='Shortcut';Source=$source;Backup=$destination}
                    Save-TuneState
                    Move-Item -LiteralPath $source -Destination $destination
                }
            }
            foreach ($name in $Config.removeApps) {
                foreach ($package in @(Get-AppxPackage -Name $name)) {
                    if ($package.IsFramework -or $package.NonRemovable) { continue }
                    if ($PSCmdlet.ShouldProcess($package.Name,'Uninstall optional app for current user (reinstall from Store to undo)')) {
                        $script:state.RemovedApps += [pscustomobject]@{Name=$package.Name;Package=$package.PackageFullName;Status='Attempting'}
                        Save-TuneState
                        try {
                            Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop
                            $script:state.RemovedApps[-1].Status='Removed'
                        } catch {
                            $script:state.RemovedApps[-1].Status='Failed'
                            $script:state.Failures += "Uninstall $name : $($_.Exception.Message)"
                            Write-Warning $script:state.Failures[-1]
                        }
                        Save-TuneState
                    }
                }
            }
        } else {
            if ($Config.powerPlan -eq 'HighPerformance') {
                $active = (& powercfg.exe /getactivescheme) -join ' '
                if ($LASTEXITCODE -ne 0) { throw 'Cannot read current power scheme.' }
                $guid = [regex]::Match($active,'[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}').Value
                if (-not $guid) { throw 'Cannot parse power scheme GUID.' }
                if ($PSCmdlet.ShouldProcess('AC power plan','Select High Performance (battery devices keep current plan)')) {
                    $battery = @(Get-CimInstance Win32_Battery)
                    if ($battery.Count -eq 0) {
                        $script:state.Changes += [pscustomobject]@{Type='Power';Guid=$guid}
                        Save-TuneState
                        & powercfg.exe /setactive SCHEME_MIN
                        if ($LASTEXITCODE -ne 0) { throw 'High Performance plan unavailable. Select the plan in Windows Settings.' }
                    }
                }
            }
            if ($Config.ssdRetrim) {
                $ssds = @(Get-PhysicalDisk | Where-Object {$_.MediaType -eq 'SSD' -and $_.HealthStatus -eq 'Healthy' -and $_.BusType -ne 'USB'})
                foreach ($disk in $ssds) {
                    foreach ($partition in @(Get-Partition -DiskNumber ([int]$disk.DeviceId) | Where-Object {$_.DriveLetter -match '^[A-Z]$'})) {
                        $volume = Get-Volume -DriveLetter $partition.DriveLetter
                        if ($volume.FileSystem -eq 'NTFS' -and $volume.HealthStatus -eq 'Healthy' -and $PSCmdlet.ShouldProcess($partition.DriveLetter,'ReTrim healthy internal SSD')) {
                            try { Optimize-Volume -DriveLetter $partition.DriveLetter -ReTrim -Verbose -ErrorAction Stop }
                            catch {
                                $script:state.Failures += "ReTrim $($partition.DriveLetter): $($_.Exception.Message)"
                                Save-TuneState
                                Write-Warning $script:state.Failures[-1]
                            }
                        }
                    }
                }
            }
        }
        if (-not $WhatIfPreference -and $script:state.Failures.Count) { throw 'Some operations failed. See install.log and state.json.' }
    } finally {
        if (-not $WhatIfPreference) { Stop-Transcript | Out-Null }
    }
}

function Restore-TuneState {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Path)
    $state = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($state.Version -ne 1 -or $state.Computer -ne $env:COMPUTERNAME) { throw 'State belongs to another computer or unsupported version.' }
    if ($state.Scope -eq 'User' -and $state.UserSid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) { throw 'Restore under the original user account.' }
    if ($state.Scope -eq 'Machine' -and -not (Test-TuneAdmin) -and -not $WhatIfPreference) { throw 'Run machine restore as administrator.' }
    $changes = @($state.Changes)
    [array]::Reverse($changes)
    foreach ($change in $changes) {
        if ($PSCmdlet.ShouldProcess($change.Type,'Restore saved configuration')) {
            switch ($change.Type) {
                Registry {
                    if ($change.Exists) {
                        if (-not (Test-Path -LiteralPath $change.Path)) { New-Item -Path $change.Path -Force | Out-Null }
                        $value = $change.Value
                        if ($change.Kind -eq 'Binary') { $value = [byte[]]$value }
                        New-ItemProperty -LiteralPath $change.Path -Name $change.Name -Value $value -PropertyType $change.Kind -Force | Out-Null
                    } else {
                        Remove-ItemProperty -LiteralPath $change.Path -Name $change.Name -ErrorAction SilentlyContinue
                    }
                }
                Shortcut {
                    if (Test-Path -LiteralPath $change.Backup) {
                        if (Test-Path -LiteralPath $change.Source) { Write-Warning "Skipping existing shortcut: $($change.Source)" }
                        else { Copy-Item -LiteralPath $change.Backup -Destination $change.Source }
                    }
                }
                Power {
                    & powercfg.exe /setactive $change.Guid
                    if ($LASTEXITCODE -ne 0) { throw 'Power plan restore failed.' }
                }
                default { throw "Unknown state record: $($change.Type)" }
            }
        }
    }
    $removed = @($state.RemovedApps | Where-Object Status -eq 'Removed')
    if ($removed.Count) { Write-Warning ('Reinstall these apps from Microsoft Store if wanted: ' + (($removed | ForEach-Object Name) -join ', ')) }
}

function Get-TuneAudit {
    $report = [ordered]@{Captured=(Get-Date).ToString('o');User=[Security.Principal.WindowsIdentity]::GetCurrent().Name;Admin=(Test-TuneAdmin)}
    $queries = [ordered]@{
        OS={Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber,LastBootUpTime,TotalVisibleMemorySize,FreePhysicalMemory}
        CPU={Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors}
        GPU={Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion}
        RAM={Get-CimInstance Win32_PhysicalMemory | Select-Object Capacity,Speed,ConfiguredClockSpeed}
        Disks={Get-PhysicalDisk | Select-Object DeviceId,FriendlyName,MediaType,BusType,HealthStatus,OperationalStatus,Size}
        Reliability={Get-PhysicalDisk | Get-StorageReliabilityCounter | Select-Object DeviceId,Temperature,Wear,ReadErrorsUncorrected,WriteErrorsUncorrected,PowerOnHours}
        Volumes={Get-Volume | Where-Object DriveLetter | Select-Object DriveLetter,FileSystem,HealthStatus,Size,SizeRemaining}
        Startup={Get-CimInstance Win32_StartupCommand | Select-Object Name,Command,Location}
        StartupRegistry={foreach ($path in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\Microsoft\Windows\CurrentVersion\Run')) {
            $key=Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
            if ($key) { foreach ($name in $key.GetValueNames()) { [pscustomobject]@{Path=$path;Name=$name;Command=$key.GetValue($name)} } }
        }}
        StartupShortcuts={Get-ChildItem -LiteralPath ([Environment]::GetFolderPath('Startup')) | Select-Object Name,FullName}
        Pagefile={Get-CimInstance Win32_PageFileUsage | Select-Object Name,AllocatedBaseSize,CurrentUsage,PeakUsage}
        Apps={Get-AppxPackage | Select-Object Name,PackageFullName}
        Processes={Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 20 Name,Id,WorkingSet64,CPU}
        StorageErrors={Get-WinEvent -FilterHashtable @{LogName='System';StartTime=(Get-Date).AddDays(-7);Level=2,3} -MaxEvents 1000 -ErrorAction SilentlyContinue | Where-Object {$_.ProviderName -match '^(disk|Ntfs|Microsoft-Windows-Ntfs|storahci|stornvme|storport|Microsoft-Windows-StorPort)$'} | Select-Object TimeCreated,Id,ProviderName,Message}
        DiskActivity={Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk | Select-Object Name,PercentDiskTime,AvgDiskQueueLength,DiskBytesPersec}
    }
    foreach ($entry in $queries.GetEnumerator()) {
        try { $report[$entry.Key] = @(& $entry.Value) }
        catch { $report[$entry.Key] = @{Unavailable=$_.Exception.Message} }
    }
    $report.PowerPlan = (& powercfg.exe /getactivescheme) -join ' '
    $report.Settings = @(foreach ($scope in @('User','Machine')) {
        foreach ($setting in Get-TuneSettings $scope) {
            $key=Get-Item -LiteralPath $setting.Path -ErrorAction SilentlyContinue
            $value=$null
            if ($key) { $value=$key.GetValue($setting.Name) }
            [pscustomobject]@{Scope=$scope;Path=$setting.Path;Name=$setting.Name;Expected=$setting.Value;Actual=$value;Matches=($null -ne $value -and "$value" -eq "$($setting.Value)")}
        }
    })
    [pscustomobject]$report
}

Export-ModuleMember -Function Test-TuneAdmin,Assert-TuneConfig,Get-TuneSettings,Invoke-Tune,Restore-TuneState,Get-TuneAudit
