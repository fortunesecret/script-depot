// main/settingsService.ts
import Store from 'electron-store';
import { Settings, SettingsSchema } from '@shared/settingsSchema';

export class SettingsService {
  private store: Store<Settings>;

  constructor() {
    // Validate on load
    this.store = new Store<Settings>({
      name: 'settings',
      // electron-store v11 doesn't directly accept Zod; we validate manually.
      // Keep JSON schema minimal if you want electron-store-side validation too.
      migrations: {
        '1.0.0': (store) => {
          // Example migration: ensure theme default is applied
          const data = store.store as any;
          if (!data || !data.theme) {
            store.set('theme', 'dark');
          }
        },
      },
    });

    // Run Zod validation and coerce defaults if needed
    const parsed = SettingsSchema.safeParse(this.store.store || {});
    if (!parsed.success) {
      // Reset invalid store to defaults
      this.store.store = SettingsSchema.parse({});
    } else {
      // Ensure defaults applied to partial data
      this.store.store = { ...SettingsSchema.parse(parsed.data) };
    }
  }

  get(): Settings {
    return this.store.store;
  }

  save(patch: Partial<Settings>): Settings {
    const merged = { ...this.store.store, ...patch, lastOpenedAt: Date.now() };
    const parsed = SettingsSchema.parse(merged);
    this.store.store = parsed;
    return parsed;
  }
}
