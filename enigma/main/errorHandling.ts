// main/errorHandling.ts
import { app, dialog } from 'electron';
import { Logger } from '../shared/logger';

export function setupErrorHandling(showDialogs = false) {
  const log = Logger.get('errors');

  process.on('uncaughtException', (err) => {
    log.error('uncaughtException', err);
    if (showDialogs) {
      dialog.showErrorBox('Application Error', `${err?.message ?? err}`);
    }
  });

  process.on('unhandledRejection', (reason: any) => {
    log.error('unhandledRejection', reason);
  });

  app.on('render-process-gone', (_e, details) => {
    log.error('render-process-gone', details);
  });

  app.on('child-process-gone', (_e, details) => {
    log.error('child-process-gone', details);
  });
}
