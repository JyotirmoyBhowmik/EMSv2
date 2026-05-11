/**
 * EMS v5 — Typography System
 * Google Fonts: Inter (primary), JetBrains Mono (code).
 * Three density modes per spec §2.
 */

export const fontFamily = {
  primary: "'Inter', 'Segoe UI', -apple-system, BlinkMacSystemFont, sans-serif",
  mono: "'JetBrains Mono', 'Cascadia Code', 'Fira Code', monospace",
} as const;

/** Density scale — row height in px per spec §2 */
export const density = {
  compact:     { rowHeight: 24, fontSize: '0.75rem',  spacing: 4  },
  cozy:        { rowHeight: 32, fontSize: '0.8125rem', spacing: 6  },
  comfortable: { rowHeight: 40, fontSize: '0.875rem',  spacing: 8  },
} as const;

export type DensityMode = keyof typeof density;

/** Type scale */
export const typography = {
  h1: { fontSize: '1.75rem',  fontWeight: 800, lineHeight: 1.2, letterSpacing: '-0.025em' },
  h2: { fontSize: '1.375rem', fontWeight: 700, lineHeight: 1.3, letterSpacing: '-0.02em'  },
  h3: { fontSize: '1.125rem', fontWeight: 600, lineHeight: 1.4, letterSpacing: '-0.01em'  },
  h4: { fontSize: '1rem',     fontWeight: 600, lineHeight: 1.4, letterSpacing: '0'        },
  body1: { fontSize: '0.875rem', fontWeight: 400, lineHeight: 1.6 },
  body2: { fontSize: '0.8125rem', fontWeight: 400, lineHeight: 1.5 },
  caption: { fontSize: '0.75rem', fontWeight: 500, lineHeight: 1.4 },
  overline: { fontSize: '0.6875rem', fontWeight: 700, lineHeight: 1.4, letterSpacing: '0.08em', textTransform: 'uppercase' as const },
  kpi: { fontSize: '2rem', fontWeight: 800, lineHeight: 1.1, letterSpacing: '-0.02em' },
  kpiLabel: { fontSize: '0.75rem', fontWeight: 600, lineHeight: 1.3, letterSpacing: '0.02em' },
} as const;
