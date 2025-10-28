// shared/logger.ts
import log from "electron-log";

export type LogLevel = "error" | "warn" | "info" | "verbose" | "debug" | "silly";

export interface LoggerOptions {
  level?: LogLevel;
  consoleLevel?: LogLevel;
  logsDir?: string;
  appName?: string;
  capture?: boolean;
}

const isRenderer =
  typeof window !== "undefined" &&
  typeof (window as any).document !== "undefined";

export class Logger {
  private constructor(private readonly context?: string) {}

  private static _initialized = false;

  /** Ensure each process (main/renderer) is configured at least once. */
  private static ensureConfigured() {
    if (!Logger._initialized) {
      Logger.configure({});
    }
  }

  static configure(opts: LoggerOptions = {}) {
    const {
      level = "info",
      consoleLevel = "info",
      logsDir,
      appName = "app",
      capture = true,
    } = opts;

    // Always safe
    if (log.transports?.console) {
      log.transports.console.level = consoleLevel;
    }

    const fileTransport: any = (log.transports as any)?.file;

    if (isRenderer) {
      // Renderer: keep console only; disable file transport if present.
      if (fileTransport) fileTransport.level = false;

      if (capture) {
        const anyLog = log as any;
        if (anyLog.errorHandler && typeof anyLog.errorHandler.start === "function") {
          anyLog.errorHandler.start({
            showDialog: false,
            onError: (error: unknown) => log.error("[unhandled]", error),
          });
        } else if (typeof anyLog.catchErrors === "function") {
          anyLog.catchErrors({
            showDialog: false,
            onError: (error: unknown) => log.error("[unhandled]", error),
          });
        }
      }
    } else {
      // Main: enable and configure file transport if available.
      if (fileTransport) {
        fileTransport.level = level;
        if (logsDir) {
          const fileName = `${appName}.log`;
          if ("resolvePathFn" in fileTransport) {
            fileTransport.resolvePathFn = () => `${logsDir}/${fileName}`; // v5+
          } else if ("resolvePath" in fileTransport) {
            fileTransport.resolvePath = () => `${logsDir}/${fileName}`;   // v4 fallback
          }
        }
        fileTransport.maxSize = 5 * 1024 * 1024;
      }

      if (capture) {
        const anyLog = log as any;
        if (anyLog.errorHandler && typeof anyLog.errorHandler.start === "function") {
          anyLog.errorHandler.start({
            showDialog: false,
            onError: (error: unknown) => log.error("[unhandled]", error),
          });
        } else if (typeof anyLog.catchErrors === "function") {
          anyLog.catchErrors({
            showDialog: false,
            onError: (error: unknown) => log.error("[unhandled]", error),
          });
        }
      }
    }

    Logger._initialized = true;
  }

  static get(context?: string) {
    Logger.ensureConfigured();
    return new Logger(context);
  }

  scope(extra: string) {
    const ctx = this.context ? `${this.context}:${extra}` : extra;
    return new Logger(ctx);
  }

  private prefix(message: any) {
    return this.context ? `[${this.context}] ${message}` : message;
  }

  info(message: any, ...args: any[])   { log.info(this.prefix(message), ...args); }
  warn(message: any, ...args: any[])   { log.warn(this.prefix(message), ...args); }
  error(message: any, ...args: any[])  { log.error(this.prefix(message), ...args); }
  debug(message: any, ...args: any[])  { log.debug(this.prefix(message), ...args); }
  verbose(message: any, ...args: any[]){ log.verbose(this.prefix(message), ...args); }
  silly(message: any, ...args: any[])  { log.silly(this.prefix(message), ...args); }
}

export default Logger;
