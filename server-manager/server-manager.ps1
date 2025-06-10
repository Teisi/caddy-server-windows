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

# Caddy Basis-Pfad und Caddyfile-Pfad ermitteln
$caddyBasePath = Split-Path -Parent $caddyExePath
$caddyFilePath = Join-Path $caddyBasePath "Caddyfile"

# Überprüfe ob Caddyfile existiert
if (-not (Test-Path $caddyFilePath)) {
    [System.Windows.Forms.MessageBox]::Show(
        "Caddyfile wurde nicht gefunden in: $caddyFilePath`n`nBitte stellen Sie sicher, dass sich die Caddyfile im gleichen Verzeichnis wie caddy.exe befindet.",
        "Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error)
    exit
}

# Erstelle das Hauptfenster
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
$startButton.BackColor = [System.Drawing.Color]::LightGreen
$form.Controls.Add($startButton)

$stopButton = New-Object System.Windows.Forms.Button
$stopButton.Location = New-Object System.Drawing.Point(20,210)
$stopButton.Size = New-Object System.Drawing.Size(340,40)
$stopButton.Text = 'Stop All Services'
$stopButton.BackColor = [System.Drawing.Color]::LightCoral
$form.Controls.Add($stopButton)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Location = New-Object System.Drawing.Point(20,260)
$refreshButton.Size = New-Object System.Drawing.Size(340,40)
$refreshButton.Text = 'Refresh Status'
$refreshButton.BackColor = [System.Drawing.Color]::LightBlue
$form.Controls.Add($refreshButton)

# URLs Panel
$urlsPanel = New-Object System.Windows.Forms.Panel
$urlsPanel.Location = New-Object System.Drawing.Point(20,320)
$urlsPanel.Size = New-Object System.Drawing.Size(340,120)
$urlsPanel.BorderStyle = 'FixedSingle'

$urlLabel = New-Object System.Windows.Forms.Label
$urlLabel.Location = New-Object System.Drawing.Point(10,10)
$urlLabel.Size = New-Object System.Drawing.Size(320,100)

# Dynamische URL-Liste basierend auf PHP-Versionen erstellen
$urls = ""
foreach ($version in $config.php.PSObject.Properties) {
    $urls += "http://php$($version.Name -replace '\.','').localhost`n"
    $urls += "https://php$($version.Name -replace '\.','').localhost`n"
}
$urlLabel.Text = "Available URLs:`n`n$urls"

$urlsPanel.Controls.Add($urlLabel)
$form.Controls.Add($urlsPanel)

# Funktionen
function Update-Status {
    # PHP Status überprüfen
    foreach ($version in $config.php.PSObject.Properties) {
        $taskName = "PHP$($version.Name -replace '\.','')_CGI"
        $status = schtasks /query /tn $taskName 2>$null
        $label = $statusLabels[$version.Name]
        $label.Text = "PHP $($version.Name): " + $(if ($LASTEXITCODE -eq 0) { "Running" } else { "Stopped" })
        $label.ForeColor = if ($LASTEXITCODE -eq 0) { [System.Drawing.Color]::Green } else { [System.Drawing.Color]::Red }
    }

    # Caddy Status
    $caddyProcess = Get-Process -Name "caddy" -ErrorAction SilentlyContinue
    $labelCaddy.Text = "Caddy: " + $(if ($caddyProcess) { "Running" } else { "Stopped" })
    $labelCaddy.ForeColor = if ($caddyProcess) { [System.Drawing.Color]::Green } else { [System.Drawing.Color]::Red }
}

function Start-AllServices {
    $startButton.Enabled = $false
    try {
        # PHP Services starten
        foreach ($version in $config.php.PSObject.Properties) {
            $taskName = "PHP$($version.Name -replace '\.','')_CGI"
            $phpPath = $version.Value.path
            $phpIp = $version.Value.ip

            schtasks /create /tn $taskName /tr "`"$phpPath`" -b $phpIp" /sc onstart /ru System /rl HIGHEST /f
            schtasks /run /tn $taskName
        }

        # Caddy starten
        Start-Process $caddyExePath -ArgumentList "run --config $caddyFilePath" -WorkingDirectory $caddyBasePath -WindowStyle Hidden -Verb RunAs

        [System.Windows.Forms.MessageBox]::Show("Services started successfully!", "Success")
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Error starting services: $_", "Error")
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
        }

        # Caddy stoppen
        Stop-Process -Name "caddy" -Force -ErrorAction SilentlyContinue

        [System.Windows.Forms.MessageBox]::Show("Services stopped successfully!", "Success")
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Error stopping services: $_", "Error")
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
