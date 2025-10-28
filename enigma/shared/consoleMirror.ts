// shared/consoleMirror.ts
import { Logger } from "./logger";

/**
 * Intercepts console output and forwards it to the Logger.
 * Can be toggled dynamically.
 */
export class ConsoleMirror {
  private static original: Partial<Record<keyof Console, Function>> = {};
  private static enabled = false;

  static toggle(enable: boolean, context = "console"): void {
    if (enable === this.enabled) return; // no change
    const log = Logger.get(context);

    if (enable) {
      // Backup originals
      this.original.log = console.log;
      this.original.warn = console.warn;
      this.original.error = console.error;

      console.log = (...args: any[]) => {
        this.original.log?.apply(console, args);
        log.info("[console.log]", ...args);
      };
      console.warn = (...args: any[]) => {
        this.original.warn?.apply(console, args);
        log.warn("[console.warn]", ...args);
      };
      console.error = (...args: any[]) => {
        this.original.error?.apply(console, args);
        log.error("[console.error]", ...args);
      };

      log.info("Console mirroring enabled");
    } else {
      // Restore originals
      if (this.original.log) console.log = this.original.log as any;
      if (this.original.warn) console.warn = this.original.warn as any;
      if (this.original.error) console.error = this.original.error as any;
      log.info("Console mirroring disabled");
    }

    this.enabled = enable;
  }

  static isEnabled(): boolean {
    return this.enabled;
  }
}
