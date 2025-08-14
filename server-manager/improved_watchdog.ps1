# Globale Variablen für die Watchdog-Status und Event-Handling
$global:watchdogActive = @{}
$global:processEventJobs = @{}

function Register-ProcessWatcher {
    param (
        [string]$version,
        [string]$phpPath,
        [string]$phpIp,
        [string]$taskName
    )

    # WMI Event Query für Prozessbeendigung
    $query = "SELECT * FROM __InstanceDeletionEvent WITHIN 1 WHERE TargetInstance ISA 'Win32_Process' AND TargetInstance.Name = 'php-cgi.exe'"

    # Erstelle einen permanent laufenden Job für die Prozessüberwachung
    $job = Register-WmiEvent -Query $query -SourceIdentifier "PHPWatcher_$version" -Action {
        param($sourceEventArgs)
        $process = $sourceEventArgs.SourceEventArgs.NewEvent.TargetInstance
        $version = $event.MessageData.version
        $phpPath = $event.MessageData.phpPath
        $phpIp = $event.MessageData.phpIp
        $taskName = $event.MessageData.taskName

        # Überprüfe ob es der überwachte PHP-Prozess ist
        if ($process.CommandLine -like "*$phpPath*") {
            Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - PHP $version wurde beendet. Starte neu..."

            # Sofortiger Neustart
            Start-Process $phpPath -ArgumentList "-b $phpIp" -WindowStyle Hidden

            # Aktualisiere den Task (optional, falls der Neustart fehlschlägt)
            schtasks /delete /tn $taskName /f 2>$null
            schtasks /create /tn $taskName /tr "`"$phpPath`" -b $phpIp" /sc onstart /ru System /rl HIGHEST /f | Out-Null
            schtasks /run /tn $taskName | Out-Null
        }
    } -MessageData @{
        version = $version
        phpPath = $phpPath
        phpIp = $phpIp
        taskName = $taskName
    }

    # Speichere den Job für späteres Cleanup
    $global:processEventJobs[$version] = $job
}

function Start-PHPWatchdog {
    param (
        [string]$version,
        [string]$phpPath,
        [string]$phpIp,
        [string]$taskName
    )

    $global:watchdogActive[$version] = $true

    # Registriere den Event-basierten Watcher
    Register-ProcessWatcher -version $version -phpPath $phpPath -phpIp $phpIp -taskName $taskName

    Write-Host "Watchdog für PHP $version wurde gestartet"
}

function Stop-PHPWatchdog {
    param (
        [string]$version
    )

    $global:watchdogActive[$version] = $false

    # Entferne den Event-Watcher
    if ($global:processEventJobs.ContainsKey($version)) {
        $sourceIdentifier = "PHPWatcher_$version"
        Unregister-Event -SourceIdentifier $sourceIdentifier -Force -ErrorAction SilentlyContinue
        $global:processEventJobs[$version] | Remove-Job -Force -ErrorAction SilentlyContinue
        $global:processEventJobs.Remove($version)
    }

    Write-Host "Watchdog für PHP $version wurde gestoppt"
}

# Funktion zum Aktualisieren des GUI-Status mit Watchdog-Informationen
function Update-Status {
    # Existierender Status-Update-Code...

    # PHP Status überprüfen
    foreach ($version in $config.php.PSObject.Properties) {
        $taskName = "PHP$($version.Name -replace '\.','')_CGI"
        $phpPath = $version.Value.path

        $status = Get-ServiceStatus -version $version.Name -taskName $taskName -processPath $phpPath
        $label = $statusLabels[$version.Name]

        # Füge Watchdog-Status zur Anzeige hinzu
        if ($global:watchdogActive[$version.Name]) {
            $status.Message += " (Watchdog: Active)"
        }

        $label.Text = "PHP $($version.Name): $($status.Message)"
        $label.ForeColor = $status.Color
    }

    # Restlicher Status-Update-Code...
}
