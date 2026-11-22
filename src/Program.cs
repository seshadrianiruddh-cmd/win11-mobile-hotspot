using System;
using System.IO;
using System.Reflection;
using System.Diagnostics;
using System.Windows.Forms;

namespace HotspotLauncher
{
    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            try
            {
                string scriptPath = null;
                string currentDirScript = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "HotspotManager.ps1");

                // Prefer local script in the same directory if present
                if (File.Exists(currentDirScript))
                {
                    scriptPath = currentDirScript;
                }
                else
                {
                    // Fallback to embedded script resource
                    string tempDir = Path.Combine(Path.GetTempPath(), "HotspotManager");
                    Directory.CreateDirectory(tempDir);
                    scriptPath = Path.Combine(tempDir, "HotspotManager.ps1");

                    using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("HotspotManager.ps1"))
                    {
                        if (stream != null)
                        {
                            using (FileStream fileStream = new FileStream(scriptPath, FileMode.Create, FileAccess.Write))
                            {
                                stream.CopyTo(fileStream);
                            }
                        }
                    }
                }

                if (!File.Exists(scriptPath))
                {
                    MessageBox.Show(
                        "Unable to find or extract HotspotManager.ps1.",
                        "Hotspot Manager Error",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error
                    );
                    return;
                }

                string powershellPath = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.System),
                    @"WindowsPowerShell\v1.0\powershell.exe"
                );
                if (!File.Exists(powershellPath))
                {
                    powershellPath = "powershell.exe";
                }

                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = powershellPath;
                psi.Arguments = string.Format("-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"{0}\"", scriptPath);
                psi.CreateNoWindow = true;
                psi.UseShellExecute = false;
                psi.WindowStyle = ProcessWindowStyle.Hidden;

                using (Process proc = Process.Start(psi))
                {
                    proc.WaitForExit();
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    "An error occurred while launching Mobile Hotspot:\n\n" + ex.Message,
                    "Hotspot Manager Error",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error
                );
            }
        }
    }
}
