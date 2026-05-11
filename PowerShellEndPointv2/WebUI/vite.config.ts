import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tsconfigPaths from 'vite-tsconfig-paths';
import svgr from 'vite-plugin-svgr';

export default defineConfig({
  plugins: [
    react(),
    tsconfigPaths(),
    svgr(),
  ],
  root: './',
  server: {
    port: 3000,
    proxy: {
      '/api': {
        target: 'http://localhost:5000',
        changeOrigin: true,
        secure: false,
      },
    },
  },
  build: {
    outDir: 'build',
    emptyOutDir: true,
    sourcemap: true,
    chunkSizeWarningLimit: 500,
    rollupOptions: {
      output: {
        manualChunks: {
          'react-vendor': ['react', 'react-dom', 'react-router-dom'],
          'mui-core': ['@mui/material', '@emotion/react', '@emotion/styled'],
          'mui-icons': ['@mui/icons-material'],
          'mui-x': ['@mui/x-charts', '@mui/x-data-grid', '@mui/x-date-pickers'],
          'tanstack': ['@tanstack/react-query', '@tanstack/react-table', '@tanstack/react-virtual'],
          'workflow': ['@xyflow/react', 'dagre', 'elkjs'],
          'tremor': ['@tremor/react'],
          'icons': ['lucide-react', '@tabler/icons-react'],
          'utils': ['date-fns', 'zod', 'zustand', 'framer-motion'],
          'pdf': ['jspdf', 'html2canvas'],
          'network': ['cidr-tools', 'ipaddr.js', 'is-ip', 'is-cidr', 'netmask', 'ip-regex'],
          'sentry': ['@sentry/react'],
        },
      },
    },
  },
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
    css: true,
  },
});
