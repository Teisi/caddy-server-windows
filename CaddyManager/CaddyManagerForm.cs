using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace CaddyManager 
{
    // Main Application Form
    public partial class CaddyManagerForm : Form
    {
        // --- UI CONTROLS ---
        private Button btnStartCaddy, btnStopCaddy, btnReloadCaddy, btnDownloadCaddy;
        private Label lblCaddyStatus, lblPhpHeader;
        private ListView lvPhpVersions;
        private Button btnAddPhp, btnEditCaddyfile;
        private TextBox txtLogs;
        private System.Windows.Forms.Timer statusTimer;

        // --- CONFIG & STATE ---
        private AppConfig config;
        private readonly string configPath = "config.json";
        private readonly string caddyPath = Path.Combine(Application.StartupPath, "webserver", "caddy.exe");
        private readonly string caddyfilePath = Path.Combine(Application.StartupPath, "webserver", "Caddyfile");

        private Process caddyProcess;
        private Dictionary<string, Process> phpProcesses = new Dictionary<string, Process>();

        public CaddyManagerForm()
        {
            InitializeComponent();
            
            // --- EVENT HANDLERS ---
            // Moved from InitializeComponent to prevent designer errors.
            btnStartCaddy.Click += async (s, e) => await StartCaddy();
            btnStopCaddy.Click += (s, e) => StopCaddy();
            btnReloadCaddy.Click += (s, e) => ReloadCaddy();
            btnDownloadCaddy.Click += async (s, e) => await DownloadCaddy();
            btnAddPhp.Click += (s, e) => AddPhpVersion();
            btnEditCaddyfile.Click += (s, e) => EditCaddyfile();

            // --- TIMER ---
            statusTimer = new System.Windows.Forms.Timer { Interval = 3000 };
            statusTimer.Tick += StatusTimer_Tick;

            this.Load += async (s, e) => await OnFormLoad();
            this.FormClosing += OnFormClosing;
        }

        /// <summary>
        /// Initializes all UI components on the form.
        /// </summary>
        private void InitializeComponentCustom()
        {
            // --- FORM SETUP ---
            this.Text = "Caddy & PHP Manager";
            this.Size = new Size(800, 600);
            this.MinimumSize = new Size(700, 500);
            this.Font = new Font("Segoe UI", 9F, FontStyle.Regular, GraphicsUnit.Point, ((byte)(0)));
            this.BackColor = Color.WhiteSmoke;

            // --- CADDY CONTROLS ---
            GroupBox gbCaddy = new GroupBox { Text = "Caddy Webserver", Location = new Point(15, 15), Size = new Size(750, 80) };
            lblCaddyStatus = new Label { Text = "Status: UNKNOWN", Location = new Point(15, 35), Size = new Size(200, 20), Font = new Font(this.Font, FontStyle.Bold) };
            btnStartCaddy = new Button { Text = "Start", Location = new Point(220, 30), Size = new Size(80, 30) };
            btnStopCaddy = new Button { Text = "Stop", Location = new Point(310, 30), Size = new Size(80, 30) };
            btnReloadCaddy = new Button { Text = "Reload Config", Location = new Point(400, 30), Size = new Size(110, 30) };
            btnDownloadCaddy = new Button { Text = "Download Caddy", Location = new Point(590, 30), Size = new Size(140, 30), BackColor = Color.LightSeaGreen, ForeColor = Color.White };
            btnEditCaddyfile = new Button { Text = "Edit Caddyfile", Location = new Point(15, 100), Size = new Size(120, 30)};

            // --- PHP CONTROLS ---
            lblPhpHeader = new Label { Text = "PHP Versions", Location = new Point(15, 140), Font = new Font(this.Font.FontFamily, 12, FontStyle.Bold), Size = new Size(200, 25) };
            lvPhpVersions = new ListView { Location = new Point(15, 170), Size = new Size(750, 150), View = View.Details, FullRowSelect = true, GridLines = true };
            lvPhpVersions.Columns.Add("Version", 120);
            lvPhpVersions.Columns.Add("Path", 250);
            lvPhpVersions.Columns.Add("Port", 80);
            lvPhpVersions.Columns.Add("Status", 100);
            lvPhpVersions.Columns.Add("Actions", 180);
            btnAddPhp = new Button { Text = "Add PHP Version", Location = new Point(645, 135), Size = new Size(120, 30) };

            // --- LOGS ---
            GroupBox gbLogs = new GroupBox { Text = "Logs", Location = new Point(15, 330), Size = new Size(750, 210) };
            txtLogs = new TextBox { Dock = DockStyle.Fill, Multiline = true, ScrollBars = ScrollBars.Vertical, ReadOnly = true, Font = new Font("Consolas", 8.25F) };
            gbLogs.Controls.Add(txtLogs);

            // --- ADDING CONTROLS TO FORM ---
            gbCaddy.Controls.Add(lblCaddyStatus);
            gbCaddy.Controls.Add(btnStartCaddy);
            gbCaddy.Controls.Add(btnStopCaddy);
            gbCaddy.Controls.Add(btnReloadCaddy);
            gbCaddy.Controls.Add(btnDownloadCaddy);
            this.Controls.Add(gbCaddy);
            this.Controls.Add(btnEditCaddyfile);
            this.Controls.Add(lblPhpHeader);
            this.Controls.Add(lvPhpVersions);
            this.Controls.Add(btnAddPhp);
            this.Controls.Add(gbLogs);

            // --- ANCHORING ---
            gbCaddy.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            lvPhpVersions.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            gbLogs.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
            btnAddPhp.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            btnDownloadCaddy.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        }

        #region --- Form Load & Close ---

        private async Task OnFormLoad()
        {
            Log("Application starting...");
            await LoadConfig();
            EnsureFileStructure();
            UpdateUIState();
            RefreshPhpListView();
            statusTimer.Start();
            Log("Ready.");
        }

        private void OnFormClosing(object sender, FormClosingEventArgs e)
        {
            Log("Shutting down...");
            StopCaddy();
            StopAllPhp();
            statusTimer.Stop();
        }

        #endregion

        #region --- Configuration Management ---

        private async Task LoadConfig()
        {
            if (!File.Exists(configPath))
            {
                config = new AppConfig();
                await SaveConfig();
                Log("No config file found, created a new one.");
            }
            else
            {
                var json = File.ReadAllText(configPath);
                config = JsonSerializer.Deserialize<AppConfig>(json) ?? new AppConfig();
                Log("Configuration loaded.");
            }
        }

        private async Task SaveConfig()
        {
            var options = new JsonSerializerOptions { WriteIndented = true };
            var json = JsonSerializer.Serialize(config, options);
            await File.WriteAllTextAsync(configPath, json);
        }
        
        private void EnsureFileStructure()
        {
            Directory.CreateDirectory(Path.Combine(Application.StartupPath, "webserver", "snippets"));
            Directory.CreateDirectory(Path.Combine(Application.StartupPath, "webserver", "sites"));
            
            if (!File.Exists(caddyfilePath))
            {
                string caddyfileContent = @"# Caddyfile managed by Caddy & PHP Manager
# Refer to the Caddy docs for more information:
# https://caddyserver.com/docs/caddyfile

{
    email example@server.tld
    local_certs
    # auto_https off
}

# Global settings and snippets
import snippets/*.conf

# Site configurations
import sites/*.conf
";
                File.WriteAllText(caddyfilePath, caddyfileContent);
                Log("Created default Caddyfile.");
            }
        }

        #endregion

        #region --- UI Management ---
        
        private void UpdateUIState()
        {
            bool caddyExists = File.Exists(caddyPath);
            btnDownloadCaddy.Visible = !caddyExists;
            btnStartCaddy.Enabled = caddyExists;
            btnStopCaddy.Enabled = caddyExists;
            btnReloadCaddy.Enabled = caddyExists;
            btnEditCaddyfile.Enabled = caddyExists;

            bool isCaddyRunning = caddyProcess != null && !caddyProcess.HasExited;
            lblCaddyStatus.Text = isCaddyRunning ? "Status: RUNNING" : "Status: STOPPED";
            lblCaddyStatus.ForeColor = isCaddyRunning ? Color.Green : Color.Red;
        }

        private void RefreshPhpListView()
        {
            lvPhpVersions.Items.Clear();
            foreach (var php in config.PhpVersions)
            {
                var lvi = new ListViewItem(php.Version);
                lvi.SubItems.Add(php.Path);
                lvi.SubItems.Add(php.Port.ToString());
                
                bool isRunning = phpProcesses.ContainsKey(php.Version) && !phpProcesses[php.Version].HasExited;
                lvi.SubItems.Add(isRunning ? "RUNNING" : "STOPPED");
                lvi.SubItems[3].ForeColor = isRunning ? Color.Green : Color.Red;
                
                // This is a trick to add buttons to a ListView
                // In a real app, a DataGridView or custom control is better.
                lvi.SubItems.Add(""); 
                lvi.Tag = php;
                lvPhpVersions.Items.Add(lvi);
            }
            AddButtonsToListView();
        }
        
        private void AddButtonsToListView()
        {
            // Remove old buttons first
            var oldButtons = lvPhpVersions.Controls.OfType<Button>().ToList();
            foreach(var btn in oldButtons) lvPhpVersions.Controls.Remove(btn);

            foreach (ListViewItem item in lvPhpVersions.Items)
            {
                var phpVersion = (PhpConfig)item.Tag;
                bool isRunning = phpProcesses.ContainsKey(phpVersion.Version) && !phpProcesses[phpVersion.Version].HasExited;

                var btnStartStop = new Button { 
                    Text = isRunning ? "Stop" : "Start", 
                    Tag = phpVersion,
                    Size = new Size(60, 20),
                    Location = new Point(item.SubItems[4].Bounds.Left, item.SubItems[4].Bounds.Top)
                };

                var btnSettings = new Button {
                    Text = "Settings",
                    Tag = phpVersion,
                    Size = new Size(70, 20),
                    Location = new Point(btnStartStop.Right + 5, item.SubItems[4].Bounds.Top)
                };

                var btnRemove = new Button {
                    Text = "X",
                    ForeColor = Color.Red,
                    Tag = phpVersion,
                    Size = new Size(25, 20),
                    Location = new Point(btnSettings.Right + 5, item.SubItems[4].Bounds.Top)
                };

                btnStartStop.Click += (s, e) => {
                    if(isRunning) StopPhp(phpVersion);
                    else StartPhp(phpVersion);
                };
                btnSettings.Click += EditPhpSettings;
                btnRemove.Click += async (s, e) => await RemovePhpVersion(phpVersion);

                lvPhpVersions.Controls.Add(btnStartStop);
                lvPhpVersions.Controls.Add(btnSettings);
                lvPhpVersions.Controls.Add(btnRemove);
            }
        }

        #endregion

        #region --- Core Logic (Caddy) ---
        
        private async Task StartCaddy()
        {
            if (caddyProcess != null && !caddyProcess.HasExited)
            {
                Log("Caddy is already running.");
                return;
            }

            await GenerateCaddyPhpUpstreams();
            
            ProcessStartInfo startInfo = new ProcessStartInfo(caddyPath)
            {
                WorkingDirectory = Path.GetDirectoryName(caddyPath),
                Arguments = "run",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            };

            caddyProcess = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
            caddyProcess.OutputDataReceived += (s, e) => { if (e.Data != null) Log($"[Caddy] {e.Data}"); };
            // caddyProcess.ErrorDataReceived += (s, e) => { if (e.Data != null) Log($"[Caddy ERROR] {e.Data}"); };

            caddyProcess.ErrorDataReceived += (s, e) =>
            {
                if (e.Data != null)
                {
                    try
                    {
                        // JSON parsen
                        using var doc = JsonDocument.Parse(e.Data);
                        var root = doc.RootElement;

                        string level = root.GetProperty("level").GetString() ?? "UNKNOWN";
                        string message = root.GetProperty("msg").GetString() ?? "";

                        // Level groß schreiben (optional)
                        level = level.ToUpperInvariant();

                        Log($"[Caddy {level}] {message}");
                    }
                    catch (JsonException)
                    {
                        // Falls e.Data kein JSON ist, einfach raw loggen
                        Log($"[Caddy ERROR] {e.Data}");
                    }
                }
            };
            
            caddyProcess.Start();
            caddyProcess.BeginOutputReadLine();
            caddyProcess.BeginErrorReadLine();
            
            Log("Caddy started.");
            UpdateUIState();
        }

        private void StopCaddy()
        {
            if (caddyProcess == null || caddyProcess.HasExited) return;

            try
            {
                // Graceful shutdown using Caddy's command
                Process.Start(new ProcessStartInfo(caddyPath, "stop") {
                    WorkingDirectory = Path.GetDirectoryName(caddyPath),
                    CreateNoWindow = true, UseShellExecute = false
                })?.WaitForExit();
                
                caddyProcess.WaitForExit(3000); // Wait a bit
            }
            catch(Exception ex)
            {
                Log($"Could not stop Caddy gracefully: {ex.Message}. Killing process.");
            }
            finally
            {
                if (caddyProcess != null && !caddyProcess.HasExited)
                {
                    caddyProcess.Kill();
                }
                caddyProcess = null;
                Log("Caddy stopped.");
                UpdateUIState();
            }
        }

        private void ReloadCaddy()
        {
            if (caddyProcess == null || caddyProcess.HasExited)
            {
                Log("Caddy is not running. Cannot reload.");
                return;
            }
            
            Process.Start(new ProcessStartInfo(caddyPath, "reload") {
                WorkingDirectory = Path.GetDirectoryName(caddyPath),
                CreateNoWindow = true, UseShellExecute = false
            });
            Log("Caddy reload command sent.");
        }
        
        private void EditCaddyfile()
        {
            try
            {
                string editor = config.EditorPath;

                if (string.IsNullOrWhiteSpace(editor) || !File.Exists(editor))
                {
                    Log("Kein gültiger Editor gefunden. Benutzer wird gefragt.");
                    AskUserToSelectEditor();

                    editor = config.EditorPath;

                    if (string.IsNullOrWhiteSpace(editor) || !File.Exists(editor))
                    {
                        MessageBox.Show("Kein gültiger Editor ausgewählt.", "Abbruch", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                        return;
                    }
                }

                Process.Start(new ProcessStartInfo
                {
                    FileName = editor,
                    Arguments = $"\"{caddyfilePath}\"",
                    UseShellExecute = false
                });
            }
            catch (Exception ex)
            {
                Log($"Fehler beim Öffnen des Caddyfile: {ex.Message}");
                MessageBox.Show($"Fehler beim Öffnen von '{caddyfilePath}'.\n\n{ex.Message}", "Fehler", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void AskUserToSelectEditor()
        {
            using (OpenFileDialog ofd = new OpenFileDialog())
            {
                ofd.Title = "Editor auswählen";
                ofd.Filter = "Programme (*.exe)|*.exe";
                ofd.InitialDirectory = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);

                if (ofd.ShowDialog() == DialogResult.OK)
                {
                    config.EditorPath = ofd.FileName;
                    SaveConfig(); // Deine bestehende Methode zum Speichern der config.json
                    Log($"Editor gespeichert: {config.EditorPath}");
                }
            }
        }

        private async Task GenerateCaddyPhpUpstreams()
        {
            var snippetPath = Path.Combine(Application.StartupPath, "webserver", "snippets", "php_upstreams.conf");
            string content = "# This file is auto-generated. Do not edit.\n\n";
            
            foreach(var php in config.PhpVersions)
            {
                // Generate a snippet like:
                // (php_fastcgi_83) {
                //     php_fastcgi 127.0.0.1:9083
                // }
                var versionIdentifier = php.Version.Replace(".", "");
                content += $"(php_fastcgi_{versionIdentifier}) {{\n\tphp_fastcgi 127.0.0.1:{php.Port}\n}}\n\n";
            }
            
            await File.WriteAllTextAsync(snippetPath, content);
            Log("Generated PHP upstreams for Caddy.");
        }

        private async Task DownloadCaddy()
        {
            Log("Starting Caddy download...");
            btnDownloadCaddy.Enabled = false;
            btnDownloadCaddy.Text = "Downloading...";

            // Offizielle Caddy-Download-API liefert direkt eine .exe-Datei
            string url = "https://caddyserver.com/api/download?os=windows&arch=amd64";
            string tempDownloadPath = Path.Combine(Path.GetTempPath(), "caddy_download.exe");
            string finalCaddyPath = caddyPath; // z. B. ...\webserver\caddy.exe

            try
            {
                using (var client = new HttpClient())
                {
                    var response = await client.GetAsync(url);
                    response.EnsureSuccessStatusCode();

                    using (var fs = new FileStream(tempDownloadPath, FileMode.Create, FileAccess.Write, FileShare.None))
                    {
                        await response.Content.CopyToAsync(fs);
                    }
                }

                // Wenn caddy.exe bereits existiert, vorher löschen
                if (File.Exists(finalCaddyPath))
                {
                    File.Delete(finalCaddyPath);
                }

                // Heruntergeladene Datei umbenennen
                File.Move(tempDownloadPath, finalCaddyPath);

                Log($"Caddy erfolgreich heruntergeladen nach: {finalCaddyPath}");
            }
            catch (Exception ex)
            {
                Log($"Fehler beim Download von Caddy: {ex.Message}");
                MessageBox.Show($"Fehler beim Herunterladen von Caddy:\n\n{ex.Message}", "Download-Fehler", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            finally
            {
                // Falls etwas schiefging und temp-Datei noch da ist, aufräumen
                if (File.Exists(tempDownloadPath))
                {
                    try { File.Delete(tempDownloadPath); } catch { /* ignorieren */ }
                }

                btnDownloadCaddy.Enabled = true;
                btnDownloadCaddy.Text = "Download Caddy";
                UpdateUIState();
            }
        }

        #endregion

        #region --- Core Logic (PHP) ---
        
        private void StartPhp(PhpConfig php)
        {
            if (phpProcesses.ContainsKey(php.Version) && !phpProcesses[php.Version].HasExited)
            {
                Log($"PHP {php.Version} is already running.");
                return;
            }

            string phpCgiPath = Path.Combine(php.Path, "php-cgi.exe");
            if (!File.Exists(phpCgiPath))
            {
                Log($"ERROR: php-cgi.exe not found for version {php.Version} at {php.Path}");
                return;
            }

            var startInfo = new ProcessStartInfo(phpCgiPath)
            {
                Arguments = $"-b 127.0.0.1:{php.Port}",
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardError = true,
                RedirectStandardOutput = true
            };

            var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
            process.OutputDataReceived += (s, e) => { if (e.Data != null) Log($"[PHP {php.Version}] {e.Data}"); };
            process.ErrorDataReceived += (s, e) => { if (e.Data != null) Log($"[PHP {php.Version} ERROR] {e.Data}"); };
            
            process.Start();
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            
            phpProcesses[php.Version] = process;
            Log($"Started PHP {php.Version} on port {php.Port}.");
            RefreshPhpListView();
        }
        
        private void StopPhp(PhpConfig php)
        {
            if (phpProcesses.TryGetValue(php.Version, out Process process) && !process.HasExited)
            {
                try
                {
                    process.Kill();
                    Log($"Stopped PHP {php.Version}.");
                }
                catch (Exception ex)
                {
                    Log($"Error stopping PHP {php.Version}: {ex.Message}");
                }
                finally
                {
                    phpProcesses.Remove(php.Version);
                }
            }
            RefreshPhpListView();
        }

        private void StopAllPhp()
        {
            foreach (var php in config.PhpVersions)
            {
                StopPhp(php);
            }
        }

        private async void AddPhpVersion()
        {
            using (var fbd = new FolderBrowserDialog())
            {
                fbd.Description = "Select the root directory of a PHP installation (e.g., C:\\php\\php-8.2)";
                if (fbd.ShowDialog() == DialogResult.OK && !string.IsNullOrWhiteSpace(fbd.SelectedPath))
                {
                    string path = fbd.SelectedPath;
                    string phpExePath = Path.Combine(path, "php.exe");
                    
                    if(!File.Exists(phpExePath))
                    {
                        MessageBox.Show($"php.exe not found in the selected directory:\n{path}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                        return;
                    }
                    
                    string version = GetPhpVersion(phpExePath);
                    if (string.IsNullOrEmpty(version))
                    {
                        MessageBox.Show("Could not determine PHP version.", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                        return;
                    }

                    if(config.PhpVersions.Any(p => p.Version == version))
                    {
                        MessageBox.Show($"PHP version {version} is already configured.", "Duplicate", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                        return;
                    }
                    
                    var newPhp = new PhpConfig
                    {
                        Version = version,
                        Path = path,
                        Port = CalculatePortFromVersion(version)
                    };
                    
                    config.PhpVersions.Add(newPhp);
                    await SaveConfig();
                    RefreshPhpListView();
                    Log($"Added PHP version {version}.");
                }
            }
        }
        
        private async Task RemovePhpVersion(PhpConfig php)
        {
            if(MessageBox.Show($"Are you sure you want to remove PHP {php.Version}?", "Confirm", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes)
            {
                StopPhp(php);
                config.PhpVersions.Remove(php);
                await SaveConfig();
                RefreshPhpListView();
                Log($"Removed PHP {php.Version}.");
            }
        }

        private void EditPhpSettings(object sender, EventArgs e)
        {
            var php = (PhpConfig)((Button)sender).Tag;
            string phpIniPath = Path.Combine(php.Path, "php.ini");

            // Wenn keine php.ini existiert → aus "php.ini-development" kopieren
            if (!File.Exists(phpIniPath))
            {
                string devIni = Path.Combine(php.Path, "php.ini-development");
                if (File.Exists(devIni))
                {
                    File.Copy(devIni, phpIniPath);
                    Log($"Created php.ini from php.ini-development for {php.Version}");
                }
                else
                {
                    MessageBox.Show(
                        $"Could not find php.ini or php.ini-development in:\n{php.Path}",
                        "File Not Found",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error);
                    return;
                }
            }

            try
            {
                string editor = config.EditorPath;

                if (string.IsNullOrWhiteSpace(editor) || !File.Exists(editor))
                {
                    Log("Kein gültiger Editor gefunden. Benutzer wird gefragt.");
                    AskUserToSelectEditor();

                    editor = config.EditorPath;

                    if (string.IsNullOrWhiteSpace(editor) || !File.Exists(editor))
                    {
                        MessageBox.Show("Kein gültiger Editor ausgewählt.", "Abbruch", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                        return;
                    }
                }

                Process.Start(new ProcessStartInfo
                {
                    FileName = editor,
                    Arguments = $"\"{phpIniPath}\"",
                    UseShellExecute = false
                });
            }
            catch (Exception ex)
            {
                Log($"Fehler beim Öffnen von php.ini: {ex.Message}");
                MessageBox.Show($"Fehler beim Öffnen der Datei:\n{phpIniPath}\n\n{ex.Message}", "Fehler", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private string GetPhpVersion(string phpExePath)
        {
            try
            {
                var startInfo = new ProcessStartInfo(phpExePath, "-v")
                {
                    RedirectStandardOutput = true, UseShellExecute = false, CreateNoWindow = true
                };
                var process = Process.Start(startInfo);
                string output = process.StandardOutput.ReadToEnd();
                process.WaitForExit();
                
                // Match "PHP 8.2.1 (cli) ..."
                var match = Regex.Match(output, @"^PHP\s+([0-9]+\.[0-9]+)\.");
                return match.Success ? match.Groups[1].Value : null;
            }
            catch(Exception ex)
            {
                Log($"Could not get PHP version: {ex.Message}");
                return null;
            }
        }
        
        private int CalculatePortFromVersion(string version)
        {
            var parts = version.Split('.');
            if (parts.Length >= 2)
            {
                return 9000 + int.Parse(parts[0]) * 10 + int.Parse(parts[1]);
            }
            // Fallback for versions like "8"
            return 9000 + int.Parse(parts[0]) * 10;
        }

        #endregion
        
        #region --- Watchdog & Status Timer ---
        
        private void StatusTimer_Tick(object sender, EventArgs e)
        {
            // Check Caddy
            if ((caddyProcess?.HasExited ?? true) && lblCaddyStatus.Text.Contains("RUNNING"))
            {
                Log("Caddy process has exited unexpectedly.");
                caddyProcess = null;
            }
            UpdateUIState();

            // Check PHP (Watchdog)
            bool phpStatusChanged = false;
            foreach (var php in config.PhpVersions.ToList())
            {
                if (phpProcesses.TryGetValue(php.Version, out Process process))
                {
                    if (process.HasExited)
                    {
                        Log($"WATCHDOG: PHP {php.Version} crashed! Restarting...");
                        phpProcesses.Remove(php.Version);
                        StartPhp(php); // Automatic restart
                        phpStatusChanged = true;
                    }
                }
            }
            
            if(phpStatusChanged || lvPhpVersions.Items.Count != config.PhpVersions.Count)
            {
                RefreshPhpListView();
            }
        }

        #endregion

        #region --- Utilities ---

        private void Log(string message)
        {
            if (txtLogs.InvokeRequired)
            {
                txtLogs.Invoke(new Action(() => Log(message)));
            }
            else
            {
                txtLogs.AppendText($"[{DateTime.Now:HH:mm:ss}] {message}{Environment.NewLine}");
            }
        }

        #endregion
    }
}



// --- DATA MODELS FOR CONFIGURATION (JSON) ---

public class AppConfig
{
    public List<PhpConfig> PhpVersions { get; set; } = new List<PhpConfig>();
    public string EditorPath { get; set; } = "notepad.exe"; // Default
}

public class PhpConfig
{
    public string Version { get; set; }
    public string Path { get; set; }
    public int Port { get; set; }
}

