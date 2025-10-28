// shared/settingsSchema.ts
import { z } from 'zod';

export const SettingsSchema = z.object({
  theme: z.enum(['light', 'dark']).default('dark'),
  lastOpenedAt: z.number().optional(),
});

export type Settings = z.infer<typeof SettingsSchema>;
