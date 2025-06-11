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
$statusPanel.Size = New-Object System.Drawing.Size(340,180)
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
$startButton.Location = New-Object System.Drawing.Point(20,210)
$startButton.Size = New-Object System.Drawing.Size(340,40)
$startButton.Text = 'Start All Services'
$form.Controls.Add($startButton)

$stopButton = New-Object System.Windows.Forms.Button
$stopButton.Location = New-Object System.Drawing.Point(20,260)
$stopButton.Size = New-Object System.Drawing.Size(340,40)
$stopButton.Text = 'Stop All Services'
$form.Controls.Add($stopButton)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Location = New-Object System.Drawing.Point(20,310)
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

# Erstellen des Einstellungs-Dialogs
function Add-PHPConfigGroup {
    param (
        [System.Windows.Forms.Panel]$parentPanel,
        [ref]$yPosRef,
        [ref]$configsRef
    )

    $newVersionGroup = New-Object System.Windows.Forms.GroupBox
    $newVersionGroup.Location = New-Object System.Drawing.Point(5,$yPosRef.Value)
    $newVersionGroup.Size = New-Object System.Drawing.Size(500,85)
    $newVersionGroup.Text = "New PHP Configuration"

    # Version
    $newVersionLabel = New-Object System.Windows.Forms.Label
    $newVersionLabel.Location = New-Object System.Drawing.Point(10,20)
    $newVersionLabel.Size = New-Object System.Drawing.Size(60,20)
    $newVersionLabel.Text = "Version:"

    $newVersionBox = New-Object System.Windows.Forms.TextBox
    $newVersionBox.Location = New-Object System.Drawing.Point(75,17)
    $newVersionBox.Size = New-Object System.Drawing.Size(50,20)

    # Path
    $newPathLabel = New-Object System.Windows.Forms.Label
    $newPathLabel.Location = New-Object System.Drawing.Point(10,45)
    $newPathLabel.Size = New-Object System.Drawing.Size(60,20)
    $newPathLabel.Text = "Path:"

    $newPathBox = New-Object System.Windows.Forms.TextBox
    $newPathBox.Location = New-Object System.Drawing.Point(75,42)
    $newPathBox.Size = New-Object System.Drawing.Size(320,20)
    $newPathBox.Name = "PathTextBox"
    $newPathBox.Text = "C:\"
    Set-Variable -Name 'pathTextBox' -Value $newPathBox -Scope Script

    # Browse Button
    $newBrowseButton = New-Object System.Windows.Forms.Button
    $newBrowseButton.Location = New-Object System.Drawing.Point(400,41)
    $newBrowseButton.Size = New-Object System.Drawing.Size(75,22)
    $newBrowseButton.Text = "Browse..."

    # Eventhandler für den Browse-Button
    $newBrowseButton.Add_Click({
        $fileDialog = New-Object System.Windows.Forms.OpenFileDialog
        $fileDialog.Filter = "PHP-CGI|php-cgi.exe|All files|*.*"
        if ($fileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:pathTextBox.Text = $fileDialog.FileName
        }
    })

    # IP
    $newIpLabel = New-Object System.Windows.Forms.Label
    $newIpLabel.Location = New-Object System.Drawing.Point(140,20)
    $newIpLabel.Size = New-Object System.Drawing.Size(30,20)
    $newIpLabel.Text = "IP:"

    $newIpBox = New-Object System.Windows.Forms.TextBox
    $newIpBox.Location = New-Object System.Drawing.Point(175,17)
    $newIpBox.Size = New-Object System.Drawing.Size(100,20)
    $newIpBox.Text = "127.0.0.1:9000"

    # Delete Button
    $newDeleteButton = New-Object System.Windows.Forms.Button
    $newDeleteButton.Location = New-Object System.Drawing.Point(400,16)
    $newDeleteButton.Size = New-Object System.Drawing.Size(75,22)
    $newDeleteButton.Text = "Delete"
    $newDeleteButton.ForeColor = [System.Drawing.Color]::Red

    $newDeleteButton.Add_Click({
        $newVersionGroup.Dispose()
        $configsRef.Value = $configsRef.Value | Where-Object { $_ -ne $newVersionGroup }
        $tempY = 10
        foreach ($group in $configsRef.Value) {
            $group.Location = New-Object System.Drawing.Point(5,$tempY)
            $tempY += 95
        }
        $yPosRef.Value = $tempY
    })

    $newVersionGroup.Controls.AddRange(@(
        $newVersionLabel, $newVersionBox, $newPathLabel, $newPathBox,
        $newBrowseButton, $newIpLabel, $newIpBox, $newDeleteButton
    ))
    $parentPanel.Controls.Add($newVersionGroup)
    $configsRef.Value += $newVersionGroup
    $yPosRef.Value += 95

    return $newVersionGroup
}

function Show-Settings {
    $settingsForm = New-Object System.Windows.Forms.Form
    $settingsForm.Text = 'Settings'
    $settingsForm.Size = New-Object System.Drawing.Size(600,400)
    $settingsForm.StartPosition = 'CenterParent'
    $settingsForm.FormBorderStyle = 'FixedDialog'
    $settingsForm.MaximizeBox = $false
    $settingsForm.MinimizeBox = $false

    # PHP Konfigurationen
    $phpGroupBox = New-Object System.Windows.Forms.GroupBox
    $phpGroupBox.Location = New-Object System.Drawing.Point(10,10)
    $phpGroupBox.Size = New-Object System.Drawing.Size(560,280)
    $phpGroupBox.Text = "PHP Configurations"

    $phpPanel = New-Object System.Windows.Forms.Panel
    $phpPanel.Location = New-Object System.Drawing.Point(10,20)
    $phpPanel.Size = New-Object System.Drawing.Size(540,250)
    $phpPanel.AutoScroll = $true

    $yPos = 10
    $phpConfigs = @()

    # Bestehende PHP-Konfigurationen laden
    foreach ($version in $config.php.PSObject.Properties) {
        $versionGroup = New-Object System.Windows.Forms.GroupBox
        $versionGroup.Location = New-Object System.Drawing.Point(5,$yPos)
        $versionGroup.Size = New-Object System.Drawing.Size(500,85)
        $versionGroup.Text = "PHP $($version.Name)"

        # Version
        $versionLabel = New-Object System.Windows.Forms.Label
        $versionLabel.Location = New-Object System.Drawing.Point(10,20)
        $versionLabel.Size = New-Object System.Drawing.Size(60,20)
        $versionLabel.Text = "Version:"

        $versionBox = New-Object System.Windows.Forms.TextBox
        $versionBox.Location = New-Object System.Drawing.Point(75,17)
        $versionBox.Size = New-Object System.Drawing.Size(50,20)
        $versionBox.Text = $version.Name

        # Path
        $pathLabel = New-Object System.Windows.Forms.Label
        $pathLabel.Location = New-Object System.Drawing.Point(10,45)
        $pathLabel.Size = New-Object System.Drawing.Size(60,20)
        $pathLabel.Text = "Path:"

        $pathBox = New-Object System.Windows.Forms.TextBox
        $pathBox.Location = New-Object System.Drawing.Point(75,42)
        $pathBox.Size = New-Object System.Drawing.Size(320,20)
        $pathBox.Text = $version.Value.path

        # Browse Button
        $browseButton = New-Object System.Windows.Forms.Button
        $browseButton.Location = New-Object System.Drawing.Point(400,41)
        $browseButton.Size = New-Object System.Drawing.Size(75,22)
        $browseButton.Text = "Browse..."
        $browseButton.Add_Click({
            $fileDialog = New-Object System.Windows.Forms.OpenFileDialog
            $fileDialog.Filter = "PHP-CGI|php-cgi.exe|All files|*.*"
            $fileDialog.InitialDirectory = [System.IO.Path]::GetDirectoryName($pathBox.Text)
            if ($fileDialog.ShowDialog() -eq 'OK') {
                $pathBox.Text = $fileDialog.FileName
            }
        })

        # IP
        $ipLabel = New-Object System.Windows.Forms.Label
        $ipLabel.Location = New-Object System.Drawing.Point(140,20)
        $ipLabel.Size = New-Object System.Drawing.Size(30,20)
        $ipLabel.Text = "IP:"

        $ipBox = New-Object System.Windows.Forms.TextBox
        $ipBox.Location = New-Object System.Drawing.Point(175,17)
        $ipBox.Size = New-Object System.Drawing.Size(100,20)
        $ipBox.Text = $version.Value.ip

        # Delete Button
        $deleteButton = New-Object System.Windows.Forms.Button
        $deleteButton.Location = New-Object System.Drawing.Point(400,16)
        $deleteButton.Size = New-Object System.Drawing.Size(75,22)
        $deleteButton.Text = "Delete"
        $deleteButton.ForeColor = [System.Drawing.Color]::Red
        $deleteButton.Add_Click({
            $versionGroup.Dispose()
            $phpConfigs = $phpConfigs | Where-Object { $_ -ne $configGroup }
            $yPos = 10
            foreach ($group in $phpConfigs) {
                $group.Location = New-Object System.Drawing.Point(5,$yPos)
                $yPos += 95
            }
        })

        $versionGroup.Controls.AddRange(@($versionLabel, $versionBox, $pathLabel, $pathBox, $browseButton, $ipLabel, $ipBox, $deleteButton))
        $phpPanel.Controls.Add($versionGroup)
        $phpConfigs += $versionGroup
        $yPos += 95
    }

    # Add New PHP Button
    $addButton = New-Object System.Windows.Forms.Button
    $addButton.Location = New-Object System.Drawing.Point(10,290)
    $addButton.Size = New-Object System.Drawing.Size(120,30)
    $addButton.Text = "Add PHP Version"
    $addButton.Add_Click({
        Add-PHPConfigGroup -parentPanel $phpPanel -yPosRef ([ref]$yPos) -configsRef ([ref]$phpConfigs)
    })

    # Save Button
    $saveButton = New-Object System.Windows.Forms.Button
    $saveButton.Location = New-Object System.Drawing.Point(400,290)
    $saveButton.Size = New-Object System.Drawing.Size(120,30)
    $saveButton.Text = "Save"
    $saveButton.Add_Click({
        $newConfig = [PSCustomObject]@{
            php = [PSCustomObject]@{}
        }

        foreach ($group in $phpConfigs) {
            if (-not $group.Disposed) {
                $version = ($group.Controls | Where-Object { $_.Size.Width -eq 50 -and $_.GetType().Name -eq "TextBox" } | Select-Object -First 1).Text
                $path = ($group.Controls | Where-Object { $_.Size.Width -eq 320 -and $_.GetType().Name -eq "TextBox" } | Select-Object -First 1).Text
                $ip = ($group.Controls | Where-Object { $_.Size.Width -eq 100 -and $_.GetType().Name -eq "TextBox" } | Select-Object -First 1).Text

                if ($version -and $path -and $ip) {
                    $versionConfig = [PSCustomObject]@{
                        path = $path
                        ip = $ip
                    }
                    Add-Member -InputObject $newConfig.php -MemberType NoteProperty -Name $version -Value $versionConfig
                }
            }
        }

        # Debug-Ausgabe zur Überprüfung
        Write-Host "Saving configuration:"
        Write-Host ($newConfig | ConvertTo-Json -Depth 10)

        # Speichern der Konfiguration
        $newConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath -Encoding UTF8

        # Neu laden der Konfiguration
        $script:config = Get-Content -Path $configPath | ConvertFrom-Json

        [System.Windows.Forms.MessageBox]::Show(
            "Settings saved successfully! Please restart the application to apply changes.",
            "Success",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information)
        $settingsForm.Close()
    })

    $phpGroupBox.Controls.Add($phpPanel)
    $settingsForm.Controls.AddRange(@($phpGroupBox, $addButton, $saveButton))
    $settingsForm.ShowDialog()
}

# Füge einen Settings-Button zur Hauptform hinzu
$settingsButton = New-Object System.Windows.Forms.Button
$settingsButton.Location = New-Object System.Drawing.Point(20,360)
$settingsButton.Size = New-Object System.Drawing.Size(340,40)
$settingsButton.Text = 'Settings'
$settingsButton.BackColor = [System.Drawing.Color]::LightGray
$form.Controls.Add($settingsButton)

# Event Handler für Settings-Button
$settingsButton.Add_Click({ Show-Settings })

# Event Handler
$startButton.Add_Click({ Start-AllServices })
$stopButton.Add_Click({ Stop-AllServices })
$refreshButton.Add_Click({ Update-Status })

# Initial Status Update
Update-Status

# Show Form
$form.ShowDialog()
