/**
 * EMS v5 — User Preferences Store
 * Persists theme, density, sidebar state, and saved views per user.
 */

import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import type { DensityMode, ThemeMode, TimeRange } from '@/types';

interface UserPreferences {
  // Display
  themeMode: ThemeMode;
  densityMode: DensityMode;
  sidebarCollapsed: boolean;

  // Dashboard
  defaultTimeRange: TimeRange;

  // Locale
  locale: string;
  dateFormat: string;

  // Actions
  setThemeMode: (mode: ThemeMode) => void;
  setDensityMode: (mode: DensityMode) => void;
  toggleSidebar: () => void;
  setDefaultTimeRange: (range: TimeRange) => void;
  setLocale: (locale: string) => void;
}

export const usePreferencesStore = create<UserPreferences>()(
  persist(
    (set) => ({
      themeMode: 'system',
      densityMode: 'cozy',
      sidebarCollapsed: false,
      defaultTimeRange: '30d',
      locale: 'en',
      dateFormat: 'yyyy-MM-dd',

      setThemeMode: (themeMode) => set({ themeMode }),
      setDensityMode: (densityMode) => set({ densityMode }),
      toggleSidebar: () => set((s) => ({ sidebarCollapsed: !s.sidebarCollapsed })),
      setDefaultTimeRange: (defaultTimeRange) => set({ defaultTimeRange }),
      setLocale: (locale) => set({ locale }),
    }),
    {
      name: 'ems-preferences',
      version: 1,
    }
  )
);
