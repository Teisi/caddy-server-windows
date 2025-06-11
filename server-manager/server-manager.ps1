Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Konfiguration laden
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptPath "config.json"
$config = Get-Content -Path $configPath | ConvertFrom-Json

# Caddy-Pfade dynamisch ermitteln
$caddyExePath = $null

# 1. Versuche caddy.exe im System-PATH zu finden
$caddyExePath = Get-Command "caddy.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source

# 2. Falls nicht gefunden, suche im übergeordneten Verzeichnis des Skript-Ordners
if (-not $caddyExePath) {
    $parentPath = Split-Path -Parent $scriptPath
    $possibleCaddyPath = Join-Path $parentPath "caddy.exe"
    if (Test-Path $possibleCaddyPath) {
        $caddyExePath = $possibleCaddyPath
    }
}

# 3. Wenn immer noch nicht gefunden, zeige Fehlermeldung
if (-not $caddyExePath) {
    [System.Windows.Forms.MessageBox]::Show(
        "Caddy.exe wurde weder im PATH noch im übergeordneten Verzeichnis gefunden.`n`nBitte stellen Sie sicher, dass Caddy korrekt installiert ist oder sich im Verzeichnis über dem 'server-manager' Ordner befindet.",
        "Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error)
    exit
}

$caddyBasePath = Split-Path -Parent $caddyExePath
$caddyFilePath = Join-Path $caddyBasePath "Caddyfile"

# GUI erstellen
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Local Development Server Manager'
$form.Size = New-Object System.Drawing.Size(400,500)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

# Status Panel
$statusPanel = New-Object System.Windows.Forms.Panel
$statusPanel.Location = New-Object System.Drawing.Point(20,20)
$statusPanel.Size = New-Object System.Drawing.Size(340,120)
$statusPanel.BorderStyle = 'FixedSingle'

# Dynamisch PHP Status Labels erstellen
$yPos = 10
$statusLabels = @{}

foreach ($version in $config.php.PSObject.Properties) {
    $label = New-Object System.Windows.Forms.Label
    $label.Location = New-Object System.Drawing.Point(10,$yPos)
    $label.Size = New-Object System.Drawing.Size(200,20)
    $label.Text = "PHP $($version.Name): Checking..."
    $statusPanel.Controls.Add($label)
    $statusLabels[$version.Name] = $label
    $yPos += 30
}

# Caddy Status Label
$labelCaddy = New-Object System.Windows.Forms.Label
$labelCaddy.Location = New-Object System.Drawing.Point(10,$yPos)
$labelCaddy.Size = New-Object System.Drawing.Size(200,20)
$labelCaddy.Text = 'Caddy: Checking...'
$statusPanel.Controls.Add($labelCaddy)

$form.Controls.Add($statusPanel)

# Buttons
$startButton = New-Object System.Windows.Forms.Button
$startButton.Location = New-Object System.Drawing.Point(20,160)
$startButton.Size = New-Object System.Drawing.Size(340,40)
$startButton.Text = 'Start All Services'
$form.Controls.Add($startButton)

$stopButton = New-Object System.Windows.Forms.Button
$stopButton.Location = New-Object System.Drawing.Point(20,210)
$stopButton.Size = New-Object System.Drawing.Size(340,40)
$stopButton.Text = 'Stop All Services'
$form.Controls.Add($stopButton)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Location = New-Object System.Drawing.Point(20,260)
$refreshButton.Size = New-Object System.Drawing.Size(340,40)
$refreshButton.Text = 'Refresh Status'
$form.Controls.Add($refreshButton)

# Funktionen
function Get-ServiceStatus {
    param (
        [string]$version,
        [string]$taskName,
        [string]$processPath
    )

    # Prüfe ob der Prozess läuft
    $processInfo = Get-WmiObject Win32_Process -Filter "Name = 'php-cgi.exe'" |
                  Where-Object { $_.CommandLine -like "*${processPath}*" }

    if ($processInfo) {
        return @{
            Running = $true
            Message = "Running (PID: $($processInfo.ProcessId))"
            Color = [System.Drawing.Color]::Green
        }
    }

    # Wenn der Prozess nicht läuft, prüfe den Task-Status
    $taskExists = schtasks /query /tn $taskName 2>$null
    if ($LASTEXITCODE -eq 0) {
        return @{
            Running = $false
            Message = "Task exists but not running"
            Color = [System.Drawing.Color]::Orange
        }
    }

    return @{
        Running = $false
        Message = "Stopped"
        Color = [System.Drawing.Color]::Red
    }
}

function Start-PHPService {
    param (
        [string]$version,
        [string]$taskName,
        [string]$phpPath,
        [string]$phpIp
    )

    # Prüfe ob PHP existiert
    if (-not (Test-Path $phpPath)) {
        return "PHP ${version}: Datei nicht gefunden: ${phpPath}"
    }

    # Lösche existierenden Task
    schtasks /delete /tn $taskName /f 2>$null

    # Erstelle und starte Task
    $result = schtasks /create /tn $taskName /tr "`"${phpPath}`" -b ${phpIp}" /sc onstart /ru System /rl HIGHEST /f
    if ($LASTEXITCODE -ne 0) {
        return "PHP ${version}: Fehler beim Erstellen des Tasks: ${result}"
    }

    $result = schtasks /run /tn $taskName
    if ($LASTEXITCODE -ne 0) {
        return "PHP ${version}: Fehler beim Starten des Tasks: ${result}"
    }

    # Warte und prüfe
    Start-Sleep -Seconds 2
    $status = Get-ServiceStatus -version $version -taskName $taskName -processPath $phpPath
    if (-not $status.Running) {
        return "PHP ${version}: Dienst konnte nicht gestartet werden"
    }

    return $null
}

function Update-Status {
    # PHP Status überprüfen
    foreach ($version in $config.php.PSObject.Properties) {
        $taskName = "PHP$($version.Name -replace '\.','')_CGI"
        $phpPath = $version.Value.path

        $status = Get-ServiceStatus -version $version.Name -taskName $taskName -processPath $phpPath
        $label = $statusLabels[$version.Name]
        $label.Text = "PHP $($version.Name): $($status.Message)"
        $label.ForeColor = $status.Color
    }

    # Caddy Status
    $caddyProcess = Get-Process -Name "caddy" -ErrorAction SilentlyContinue
    if ($caddyProcess) {
        $labelCaddy.Text = "Caddy: Running (PID: $($caddyProcess.Id))"
        $labelCaddy.ForeColor = [System.Drawing.Color]::Green
    } else {
        $labelCaddy.Text = "Caddy: Stopped"
        $labelCaddy.ForeColor = [System.Drawing.Color]::Red
    }
}

function Start-AllServices {
    $startButton.Enabled = $false
    $errors = @()

    try {
        # PHP Services starten
        foreach ($version in $config.php.PSObject.Properties) {
            $taskName = "PHP$($version.Name -replace '\.','')_CGI"
            $phpPath = $version.Value.path
            $phpIp = $version.Value.ip

            $error = Start-PHPService -version $version.Name -taskName $taskName -phpPath $phpPath -phpIp $phpIp
            if ($error) {
                $errors += $error
            }
        }

        # Caddy starten
        $caddyProcess = Get-Process -Name "caddy" -ErrorAction SilentlyContinue
        if ($caddyProcess) {
            Stop-Process -Name "caddy" -Force
            Start-Sleep -Seconds 1
        }

        Start-Process $caddyExePath -ArgumentList "run --config $caddyFilePath" -WorkingDirectory $caddyBasePath -WindowStyle Hidden -Verb RunAs
        Start-Sleep -Seconds 2

        # Prüfe ob Caddy läuft
        $caddyProcess = Get-Process -Name "caddy" -ErrorAction SilentlyContinue
        if (-not $caddyProcess) {
            $errors += "Caddy konnte nicht gestartet werden"
        }

        # Zeige entsprechende Meldung
        if ($errors.Count -gt 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "Folgende Fehler sind aufgetreten:`n`n$($errors -join "`n")",
                "Fehler beim Starten der Dienste",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error)
        } else {
            [System.Windows.Forms.MessageBox]::Show(
                "Alle Dienste wurden erfolgreich gestartet!",
                "Erfolg",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information)
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Unerwarteter Fehler: $_",
            "Fehler",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
    }
    finally {
        $startButton.Enabled = $true
        Update-Status
    }
}

function Stop-AllServices {
    $stopButton.Enabled = $false
    try {
        # PHP Services stoppen
        foreach ($version in $config.php.PSObject.Properties) {
            $taskName = "PHP$($version.Name -replace '\.','')_CGI"
            schtasks /end /tn $taskName 2>$null
            schtasks /delete /tn $taskName /f 2>$null

            # Finde und beende alle zugehörigen PHP-Prozesse
            $phpPath = $version.Value.path
            $processes = Get-WmiObject Win32_Process -Filter "Name = 'php-cgi.exe'" |
                        Where-Object { $_.CommandLine -like "*$phpPath*" }
            foreach ($process in $processes) {
                $process.Terminate()
            }
        }

        # Caddy stoppen
        Stop-Process -Name "caddy" -Force -ErrorAction SilentlyContinue

        [System.Windows.Forms.MessageBox]::Show(
            "Alle Dienste wurden gestoppt!",
            "Erfolg",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information)
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Fehler beim Stoppen der Dienste: $_",
            "Fehler",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
    }
    finally {
        $stopButton.Enabled = $true
        Update-Status
    }
}

# Event Handler
$startButton.Add_Click({ Start-AllServices })
$stopButton.Add_Click({ Stop-AllServices })
$refreshButton.Add_Click({ Update-Status })

# Initial Status Update
Update-Status

# Show Form
$form.ShowDialog()
