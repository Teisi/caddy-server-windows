# Globale Variable für die Watchdog-Status
$global:watchdogActive = @{}

function Start-PHPWatchdog {
    param (
        [string]$version,
        [string]$phpPath,
        [string]$phpIp,
        [string]$taskName
    )

    $global:watchdogActive[$version] = $true

    Start-Job -Name "Watchdog_$version" -ScriptBlock {
        param($version, $phpPath, $phpIp, $taskName, $watchdogActive)

        while ($watchdogActive[$version]) {
            # Prüfe ob der PHP-Prozess läuft
            $processInfo = Get-WmiObject Win32_Process -Filter "Name = 'php-cgi.exe'" |
                          Where-Object { $_.CommandLine -like "*$phpPath*" }

            if (-not $processInfo) {
                Write-Host "PHP $version ist nicht mehr aktiv. Starte neu..."

                # Lösche und erstelle den Task neu
                schtasks /delete /tn $taskName /f 2>$null
                $result = schtasks /create /tn $taskName /tr "`"$phpPath`" -b $phpIp" /sc onstart /ru System /rl HIGHEST /f
                if ($LASTEXITCODE -eq 0) {
                    schtasks /run /tn $taskName
                }
            }

            Start-Sleep -Seconds 4
        }
    } -ArgumentList $version, $phpPath, $phpIp, $taskName, $global:watchdogActive
}

function Stop-PHPWatchdog {
    param (
        [string]$version
    )

    $global:watchdogActive[$version] = $false
    $job = Get-Job -Name "Watchdog_$version" -ErrorAction SilentlyContinue
    if ($job) {
        Stop-Job -Job $job
        Remove-Job -Job $job
    }
}
