// shared/config.ts
export type AppMode = 'development' | 'production' | 'test';

export interface AppConfig {
  mode: AppMode;
  appName: string;
  logging: {
    level: 'error' | 'warn' | 'info' | 'verbose' | 'debug' | 'silly';
    consoleLevel: 'error' | 'warn' | 'info' | 'verbose' | 'debug' | 'silly';
    captureUnhandled: boolean;
  };
  windows: {
    main: {
      width: number;
      height: number;
    };
  };
}

export const isRenderer = typeof window !== 'undefined' && !!(window as any).document;
export const isDev = !!(process.env.VITE_DEV_SERVER_URL || process.env.VITE_DEV);

export function loadConfig(): AppConfig {
  const mode = (process.env.NODE_ENV as AppMode) || (isDev ? 'development' : 'production');
  const appName = (isRenderer ? document.title : process.env.APP_NAME) || 'Enigma';

  return {
    mode,
    appName,
    logging: {
      level: (process.env.LOG_LEVEL as any) || 'info',
      consoleLevel: (process.env.LOG_CONSOLE_LEVEL as any) || (isDev ? 'debug' : 'info'),
      captureUnhandled: true,
    },
    windows: {
      main: {
        width: Number(process.env.MAIN_WIN_WIDTH || 1000),
        height: Number(process.env.MAIN_WIN_HEIGHT || 700),
      },
    },
  };
}
