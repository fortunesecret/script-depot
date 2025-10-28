// global.d.ts

export {};

declare global {
  interface Window {
    api: {
      call<TReq = unknown, TRes = unknown>(channel: string, payload?: TReq): Promise<TRes>;
    };
  }
}

/**
 * TS shim for vite-plugin-electron's simple reloader.
 * Some versions don’t ship subpath type declarations, so we declare a minimal shape.
 */
declare module 'vite-plugin-electron/simple-reloader' {
  export function simpleReloader(): any;
}
