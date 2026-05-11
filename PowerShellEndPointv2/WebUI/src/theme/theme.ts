/**
 * EMS v5 — MUI Theme Configuration
 * Integrates palette, typography, and density into MUI v9 theme.
 */

import { createTheme, type ThemeOptions } from '@mui/material/styles';
import { brand, palette, type PaletteMode } from './palette';
import { fontFamily, typography, density, type DensityMode } from './typography';

/**
 * Build MUI theme for a given mode and density.
 */
export function buildTheme(mode: PaletteMode = 'light', densityMode: DensityMode = 'cozy') {
  const colors = palette[mode];
  const dens = density[densityMode];
  const isDark = mode === 'dark' || mode === 'highContrast';

  const themeOptions: ThemeOptions = {
    palette: {
      mode: isDark ? 'dark' : 'light',
      primary:   { main: brand.primary },
      secondary: { main: brand.secondary },
      error:     { main: brand.error },
      warning:   { main: brand.warning },
      success:   { main: brand.success },
      info:      { main: brand.info },
      background: {
        default: colors.background.default,
        paper:   colors.background.paper,
      },
      text: {
        primary:   colors.text.primary,
        secondary: colors.text.secondary,
        disabled:  colors.text.disabled,
      },
      divider: colors.border.default,
    },
    typography: {
      fontFamily: fontFamily.primary,
      fontSize: parseFloat(dens.fontSize) * 16,
      h1: typography.h1,
      h2: typography.h2,
      h3: typography.h3,
      h4: typography.h4,
      body1: typography.body1,
      body2: typography.body2,
      caption: { ...typography.caption, color: colors.text.secondary },
      overline: typography.overline,
    },
    spacing: dens.spacing,
    shape: { borderRadius: 8 },
    components: {
      MuiCssBaseline: {
        styleOverrides: {
          body: {
            fontFamily: fontFamily.primary,
            backgroundColor: colors.background.default,
            color: colors.text.primary,
          },
          '*::-webkit-scrollbar': { width: 6, height: 6 },
          '*::-webkit-scrollbar-track': { background: 'transparent' },
          '*::-webkit-scrollbar-thumb': {
            background: colors.border.strong,
            borderRadius: 3,
          },
          'code, pre': { fontFamily: fontFamily.mono },
        },
      },
      MuiButton: {
        defaultProps: { disableElevation: true },
        styleOverrides: {
          root: {
            textTransform: 'none',
            fontWeight: 600,
            fontSize: dens.fontSize,
            borderRadius: 8,
            padding: `${dens.spacing}px ${dens.spacing * 2}px`,
          },
        },
      },
      MuiPaper: {
        defaultProps: { elevation: 0 },
        styleOverrides: {
          root: {
            border: `1px solid ${colors.border.default}`,
            backgroundImage: 'none',
          },
        },
      },
      MuiCard: {
        styleOverrides: {
          root: {
            border: `1px solid ${colors.border.default}`,
            borderRadius: 12,
            transition: 'box-shadow 0.18s ease, border-color 0.18s ease',
            '&:hover': {
              borderColor: colors.border.strong,
              boxShadow: isDark
                ? '0 4px 24px rgba(0,0,0,0.4)'
                : '0 4px 24px rgba(0,0,0,0.08)',
            },
          },
        },
      },
      MuiChip: {
        styleOverrides: {
          root: {
            fontWeight: 600,
            fontSize: '0.75rem',
            height: dens.rowHeight * 0.75,
          },
        },
      },
      MuiTableRow: {
        styleOverrides: {
          root: { height: dens.rowHeight },
        },
      },
      MuiTableCell: {
        styleOverrides: {
          root: {
            fontSize: dens.fontSize,
            padding: `${dens.spacing}px ${dens.spacing * 1.5}px`,
            borderColor: colors.border.default,
          },
        },
      },
      MuiTooltip: {
        defaultProps: { arrow: true },
        styleOverrides: {
          tooltip: {
            fontSize: '0.75rem',
            fontWeight: 500,
            borderRadius: 6,
          },
        },
      },
      MuiSkeleton: {
        defaultProps: { animation: 'wave' },
      },
    },
  };

  return createTheme(themeOptions);
}

/** Pre-built themes for quick access */
export const themes = {
  lightCompact:     buildTheme('light', 'compact'),
  lightCozy:        buildTheme('light', 'cozy'),
  lightComfortable: buildTheme('light', 'comfortable'),
  darkCompact:      buildTheme('dark', 'compact'),
  darkCozy:         buildTheme('dark', 'cozy'),
  darkComfortable:  buildTheme('dark', 'comfortable'),
} as const;

export { brand, palette, fontFamily, typography, density };
export type { PaletteMode, DensityMode };
