// shared/ipcClient.ts
import { Channels, IpcContract, IpcRequest, IpcResponse } from './ipcChannels';

type CallFn = <C extends keyof IpcContract>(
  channel: C,
  payload?: IpcRequest<C>
) => Promise<IpcResponse<C>>;

function getBridge(): CallFn {
  const call = (window as any)?.api?.call as Function | undefined;
  if (!call) throw new Error('window.api.call is not available (preload not loaded?)');
  return call as CallFn;
}

export const ipcClient = {
  call: getBridge(),
  // Friendly wrappers (discoverable)
  ping: () => getBridge()(Channels.Ping, {}),
  getSettings: () => getBridge()(Channels.GetSettings, {}),
  saveSettings: (patch: IpcRequest<Channels.SaveSettings>) =>
    getBridge()(Channels.SaveSettings, patch),
};
