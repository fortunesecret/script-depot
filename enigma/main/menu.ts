// main/menu.ts
import {
  app,
  Menu,
  MenuItem,
  MenuItemConstructorOptions,
  shell,
} from "electron";

import { createLogViewerWindow } from "./logViewer"; // case-correct
import { Logger } from "../shared/logger";
import { ConsoleMirror } from "../shared/consoleMirror";

const log = Logger.get("menu");

export function createAppMenu(): void {
  const isMac = process.platform === "darwin";

  const macAppMenu: MenuItemConstructorOptions[] = isMac
    ? [
        {
          label: app.name,
          submenu: [
            { role: "about" as const },
            { type: "separator" as const },
            { role: "services" as const },
            { type: "separator" as const },
            { role: "hide" as const },
            { role: "hideOthers" as const },
            { role: "unhide" as const },
            { type: "separator" as const },
            { role: "quit" as const },
          ],
        },
      ]
    : [];

  const template: MenuItemConstructorOptions[] = [
    ...macAppMenu,

    { label: "File", submenu: [{ role: "quit" as const }] },

    {
      label: "View",
      submenu: [
        { role: "reload" as const },
        { role: "forceReload" as const },
        { type: "separator" as const },
        {
          label: "Open Log Viewer",
          accelerator: "Ctrl+L",
          click: () => {
            log.info("Opening Log Viewer");
            createLogViewerWindow();
          },
        },
        {
          label: "Mirror Console Output",
          type: "checkbox",
          checked: false,
          accelerator: "Ctrl+Shift+L",
          click: (menuItem: MenuItem) => {
            const enabled = menuItem.checked;
            ConsoleMirror.toggle(enabled, "renderer-console");
          },
        },
        { type: "separator" as const },
        { role: "toggleDevTools" as const },
        { role: "resetZoom" as const },
        { role: "zoomIn" as const },
        { role: "zoomOut" as const },
        { type: "separator" as const },
        { role: "togglefullscreen" as const },
      ],
    },

    {
      label: "Help",
      submenu: [
        {
          label: "Open Logs Folder",
          click: async () => {
            const dir = app.getPath("logs");
            log.info("Opening logs folder:", dir);
            await shell.openPath(dir);
          },
        },
        {
          label: "Learn More",
          click: async () => {
            await shell.openExternal("https://www.electronjs.org");
          },
        },
      ],
    },
  ];

  const menu = Menu.buildFromTemplate(template);
  Menu.setApplicationMenu(menu);
}
