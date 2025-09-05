namespace CaddyManager
{
    partial class CaddyManagerForm
    {
        /// <summary>
        ///  Required designer variable.
        /// </summary>
        private System.ComponentModel.IContainer components = null;

        /// <summary>
        ///  Clean up any resources being used.
        /// </summary>
        /// <param name="disposing">true if managed resources should be disposed; otherwise, false.</param>
        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
            {
                components.Dispose();
            }
            base.Dispose(disposing);
        }

        #region Windows Form Designer generated code

        /// <summary>
        ///  Required method for Designer support - do not modify
        ///  the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(CaddyManagerForm));

            this.components = new System.ComponentModel.Container();
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(800, 450);

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
            btnEditCaddyfile = new Button { Text = "Edit Caddyfile", Location = new Point(15, 100), Size = new Size(120, 30) };

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

            Icon = (Icon)resources.GetObject("$this.Icon");
        }

        #endregion
    }
}
