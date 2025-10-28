import { ipcMain } from "electron-better-ipc";
import { Channels, IpcContract } from "../shared/ipcChannels";
import { SettingsService } from "./settingsService";
import { Logger } from "../shared/logger";

const log = Logger.get("ipc");
const settings = new SettingsService();

function answer<C extends keyof IpcContract>(
  channel: C,
  handler: (payload: IpcContract[C]['req']) => Promise<IpcContract[C]['res']> | IpcContract[C]['res']
) {
  ipcMain.answerRenderer(channel, handler as any);
}

export function registerIpc() {
  answer(Channels.Ping, async () => {
    log.info("ping");
    return { ok: true, ts: Date.now() };
  });

  answer(Channels.GetSettings, async () => {
    log.debug("get-settings");
    return settings.get();
  });

  answer(Channels.SaveSettings, async (incoming) => {
    log.info("save-settings", incoming);
    return settings.save(incoming ?? {});
  });
}
