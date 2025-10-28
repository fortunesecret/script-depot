// shared/ipcChannels.ts

// 1) Channel names
export enum Channels {
  Ping = "ping",
  GetSettings = "get-settings",
  SaveSettings = "save-settings"
}

// 2) Request/Response contracts
export interface PingReq { }
export interface PingRes { ok: boolean; ts: number; }

export interface GetSettingsReq { }
export interface GetSettingsRes { theme: "light" | "dark"; lastOpenedAt?: number; }

export interface SaveSettingsReq { theme?: "light" | "dark"; }
export type SaveSettingsRes = GetSettingsRes;

// 3) Mapping table
export interface IpcContract {
  [Channels.Ping]: { req: PingReq; res: PingRes };
  [Channels.GetSettings]: { req: GetSettingsReq; res: GetSettingsRes };
  [Channels.SaveSettings]: { req: SaveSettingsReq; res: SaveSettingsRes };
}

// Utility types
export type IpcRequest<C extends keyof IpcContract> = IpcContract[C]['req'];
export type IpcResponse<C extends keyof IpcContract> = IpcContract[C]['res'];
