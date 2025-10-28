import { Logger } from "@shared/logger";
import { ipcClient } from "@shared/ipcClient";

const log = Logger.get("renderer:main");

(async () => {
  const appDiv = document.getElementById("app")!;
  appDiv.textContent = "Hello from renderer.";

  const ping = await ipcClient.ping();
  log.info("Ping result", ping);
  appDiv.textContent = `Ping: ${ping.ok} at ${new Date(ping.ts).toLocaleString()}`;

  const saved = await ipcClient.saveSettings({ theme: "dark" });
  log.info("Saved settings", saved);
})();
