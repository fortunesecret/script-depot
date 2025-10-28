/// <reference types="vite/client" />

export {};

declare global {
  interface Window {
    api: {
      /** Call a main-process handler. Payload is unknown; return type is generic. */
      call<TRes = unknown>(channel: string, payload?: unknown): Promise<TRes>;
    };
  }
}
