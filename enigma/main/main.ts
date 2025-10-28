import { app, BrowserWindow } from "electron";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { registerIpc } from "./ipc";
import { Logger } from "../shared/logger";
import { loadConfig, isDev } from "../shared/config";
import { WindowManager } from "./windowManager";
import { setupErrorHandling } from "./errorHandling";
import { createAppMenu } from "./menu";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const config = loadConfig();

// ---- Logging setup
Logger.configure({
  logsDir: app.getPath("logs"),
  appName: app.getName() || config.appName,
  level: config.logging.level,
  consoleLevel: config.logging.consoleLevel,
  capture: config.logging.captureUnhandled,
});
const log = Logger.get("main");

const windows = new WindowManager();

async function loadMain(win: BrowserWindow) {
  try {
    const devUrl = process.env.VITE_DEV_SERVER_URL;
    if (isDev && devUrl) {
      log.info("Loading dev URL:", devUrl);
      await win.loadURL(devUrl);
    } else {
      const filePath = join(__dirname, "../dist/index.html");
      log.info("Loading file:", filePath);
      await win.loadFile(filePath);
    }
  } catch (err) {
    log.error("Failed to load main window", err);
  }
}

async function createMainWindow() {
  registerIpc();
  createAppMenu();

  const preloadPath = isDev
    ? join(__dirname, "../dist-electron/preload.cjs")
    : join(__dirname, "preload.cjs");

  windows.create(
    {
      id: "main",
      width: config.windows.main.width,
      height: config.windows.main.height,
      webPreferences: {
        contextIsolation: true,
        nodeIntegration: false,
        // IMPORTANT: no sandbox here (preload needs Node to run bundled code cleanly)
        // sandbox: true,  // <- removed
        preload: preloadPath,
      },
      show: false,
    },
    loadMain
  );
}

app.on("ready", async () => {
  setupErrorHandling(false);
  log.info("App ready", { version: app.getVersion(), dev: isDev });
  await createMainWindow();
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    log.info("All windows closed; quitting.");
    app.quit();
  }
});

app.on("activate", () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    log.info("Re-activating; creating main window.");
    void createMainWindow();
  } else {
    windows.focus("main");
  }
});

const gotTheLock = app.requestSingleInstanceLock();
if (!gotTheLock) {
  log.warn("Second instance detected; quitting.");
  app.quit();
} else {
  app.on("second-instance", () => {
    const w = BrowserWindow.getAllWindows()[0];
    if (w) {
      if (w.isMinimized()) w.restore();
      w.focus();
    }
  });
}
