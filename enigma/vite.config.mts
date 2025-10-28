// vite.config.mts
import { defineConfig } from 'vite';
import electron from 'vite-plugin-electron';
import renderer from 'vite-plugin-electron-renderer';
import { resolve } from 'node:path';
import { builtinModules } from 'node:module';

// Externalize ONLY Electron and Node built-ins (not userland deps).
// We DO NOT externalize 'electron-better-ipc' or 'electron-store' so preload can load them when sandbox is off.
const externalBase = [
  'electron',
  'electron-log',
  // deliberately NOT: 'electron-better-ipc', 'electron-store'
];
const nodeBuiltins = [
  ...builtinModules,
  ...builtinModules.map((m) => `node:${m}`),
];
const externals = [...externalBase, ...nodeBuiltins];

export default defineConfig(({ command }) => {
  const isDev = command === 'serve';
  const sharedAlias = { '@shared': resolve(__dirname, 'shared') };

  return {
    root: resolve(__dirname, 'renderer', 'main'),

    build: {
      outDir: resolve(__dirname, 'dist'),
      emptyOutDir: true,
    },

    server: {
      port: 5173,
      strictPort: true,
    },

    resolve: {
      alias: sharedAlias, // renderer alias
    },

    plugins: [
      electron([
        // MAIN
        {
          entry: resolve(__dirname, 'main', 'main.ts'),
          vite: {
            resolve: { alias: sharedAlias }, // alias in main build
            build: {
              outDir: resolve(__dirname, 'dist-electron'),
              emptyOutDir: true,
              lib: {
                entry: resolve(__dirname, 'main', 'main.ts'),
                formats: ['cjs'],
                fileName: () => 'main.cjs',
              },
              rollupOptions: {
                external: externals,
                output: { format: 'cjs' },
              },
            },
          },
          onstart({ startup }) {
            if (isDev) startup();
          },
        },

        // PRELOAD
        {
          entry: resolve(__dirname, 'main', 'preload.ts'),
          vite: {
            resolve: { alias: sharedAlias }, // alias in preload build
            build: {
              outDir: resolve(__dirname, 'dist-electron'),
              lib: {
                entry: resolve(__dirname, 'main', 'preload.ts'),
                formats: ['cjs'],
                fileName: () => 'preload.cjs',
              },
              rollupOptions: {
                external: externals,
                output: { format: 'cjs' },
              },
            },
          },
        },
      ]),
      renderer(),
    ],
  };
});
