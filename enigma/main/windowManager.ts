// main/windowManager.ts
import { BrowserWindow, app } from 'electron';
import { join } from 'node:path';
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { Logger } from '../shared/logger';

type Bounds = { x?: number; y?: number; width: number; height: number; isMaximized?: boolean };
type CreateOpts = Electron.BrowserWindowConstructorOptions & { id: string };

const log = Logger.get('window');

export class WindowManager {
  private windows = new Map<string, BrowserWindow>();
  private stateDir = join(app.getPath('userData'), 'window-state');

  constructor() {
    if (!existsSync(this.stateDir)) mkdirSync(this.stateDir, { recursive: true });
  }

  private statePath(id: string) {
    return join(this.stateDir, `${id}.json`);
  }

  loadBounds(id: string, fallback: Bounds): Bounds {
    try {
      const p = this.statePath(id);
      if (existsSync(p)) {
        const raw = JSON.parse(readFileSync(p, 'utf-8')) as Bounds;
        return { ...fallback, ...raw };
      }
    } catch (err) {
      log.warn(`Failed to load bounds for ${id}`, err);
    }
    return fallback;
  }

  saveBounds(id: string, win: BrowserWindow) {
    const b = win.getBounds();
    const state: Bounds = { ...b, isMaximized: win.isMaximized() };
    try {
      writeFileSync(this.statePath(id), JSON.stringify(state, null, 2));
    } catch (err) {
      log.warn(`Failed to save bounds for ${id}`, err);
    }
  }

  create(opts: CreateOpts, load: (win: BrowserWindow) => Promise<void>): BrowserWindow {
    const id = opts.id;
    const fallback: Bounds = {
      width: opts.width ?? 1000,
      height: opts.height ?? 700,
    };
    const initial = this.loadBounds(id, fallback);

    const win = new BrowserWindow({
      ...opts,
      x: initial.x,
      y: initial.y,
      width: initial.width,
      height: initial.height,
      show: false,
    });

    if (initial.isMaximized) win.maximize();

    win.on('close', () => this.saveBounds(id, win));
    win.on('closed', () => this.windows.delete(id));

    this.windows.set(id, win);

    // Load URL/file and show when ready
    void (async () => {
      try {
        await load(win);
      } catch (e) {
        log.error(`Failed to load window ${id}`, e);
      } finally {
        // Avoid ready-to-show deadlocks
        if (!win.isDestroyed()) {
          if (win.isVisible()) return;
          if (win.isMinimized()) win.restore();
          win.show();
        }
      }
    })();

    return win;
  }

  get(id: string) {
    return this.windows.get(id) ?? null;
  }

  focus(id: string) {
    this.get(id)?.focus();
  }
}
