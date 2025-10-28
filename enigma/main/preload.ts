import { contextBridge } from "electron";
import { ipcRenderer } from "electron-better-ipc";

contextBridge.exposeInMainWorld("api", {
  call: <TRes = unknown>(channel: string, payload?: unknown) =>
    ipcRenderer.callMain<TRes>(channel, payload),
});
