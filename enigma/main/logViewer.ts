import { BrowserWindow, app } from "electron";
import { join } from "node:path";
import { readFileSync, watchFile, existsSync } from "node:fs";
import { Logger } from "../shared/logger";

let logViewerWindow: BrowserWindow | null = null;
const log = Logger.get("log-viewer");

export function createLogViewerWindow(): void {
  if (logViewerWindow) {
    logViewerWindow.focus();
    return;
  }

  const logFilePath = join(app.getPath("logs"), `${app.getName()}.log`);
  log.info("Opening log viewer for", logFilePath);

  logViewerWindow = new BrowserWindow({
    width: 900,
    height: 600,
    title: "Log Viewer",
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });

  const html = generateViewerHTML(logFilePath);
  logViewerWindow.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(html)}`);

  logViewerWindow.on("closed", () => (logViewerWindow = null));
}

/**
 * Generates an inline HTML page that tails and displays the log file.
 */
function generateViewerHTML(logFilePath: string): string {
  const initialLogs = existsSync(logFilePath)
    ? readFileSync(logFilePath, "utf-8")
        .split("\n")
        .slice(-500)
        .join("\n")
    : "Log file not found.";

  // Watch for updates
  const watcherScript = `
    const fs = require('fs');
    const filePath = ${JSON.stringify(logFilePath)};
    const pre = document.getElementById('log');
    function refresh() {
      fs.readFile(filePath, 'utf-8', (err, data) => {
        if (err) return;
        pre.textContent = data.split('\\n').slice(-500).join('\\n');
        window.scrollTo(0, document.body.scrollHeight);
      });
    }
    fs.watchFile(filePath, { interval: 1000 }, refresh);
    refresh();
  `;

  return `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Log Viewer</title>
  <style>
    body { background: #111; color: #0f0; font-family: monospace; margin: 0; padding: 1em; }
    pre { white-space: pre-wrap; word-break: break-word; }
  </style>
</head>
<body>
  <pre id="log">${initialLogs}</pre>
  <script>${watcherScript}</script>
</body>
</html>
`;
}
