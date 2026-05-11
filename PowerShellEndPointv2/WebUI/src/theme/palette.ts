/**
 * EMS v5 — Color Palette
 * SNPL brand-aware, WCAG 2.2 AA compliant.
 * Three modes: light, dark, high-contrast.
 */

/** SNPL brand colors */
export const brand = {
  primary:    '#1E40AF', // Deep blue — trust, enterprise
  secondary:  '#7C3AED', // Purple — distinction
  accent:     '#0EA5E9', // Sky blue — clarity, data
  success:    '#16A34A', // Green — compliant
  warning:    '#D97706', // Amber — attention
  error:      '#DC2626', // Red — critical
  info:       '#2563EB', // Blue — informational
} as const;

/** Semantic tokens per mode */
export const palette = {
  light: {
    background: {
      default:   '#F8FAFC',
      paper:     '#FFFFFF',
      subtle:    '#F1F5F9',
      elevated:  '#FFFFFF',
    },
    text: {
      primary:   '#0F172A',
      secondary: '#475569',
      tertiary:  '#94A3B8',
      disabled:  '#CBD5E1',
      inverse:   '#FFFFFF',
    },
    border: {
      default:   '#E2E8F0',
      subtle:    '#F1F5F9',
      strong:    '#CBD5E1',
    },
    sidebar: {
      bg:        'linear-gradient(180deg, #1A1F3C 0%, #0F1729 100%)',
      text:      'rgba(255,255,255,0.85)',
      textMuted: 'rgba(255,255,255,0.45)',
      active:    'rgba(99,179,237,0.2)',
      activeBorder: '#63B3ED',
      hover:     'rgba(255,255,255,0.08)',
    },
    severity: {
      compliant:  { bg: '#DCFCE7', text: '#166534', border: '#BBF7D0' },
      warning:    { bg: '#FEF3C7', text: '#92400E', border: '#FDE68A' },
      critical:   { bg: '#FEE2E2', text: '#991B1B', border: '#FECACA' },
      info:       { bg: '#DBEAFE', text: '#1E40AF', border: '#BFDBFE' },
    },
  },
  dark: {
    background: {
      default:   '#0B1120',
      paper:     '#111827',
      subtle:    '#1E293B',
      elevated:  '#1E293B',
    },
    text: {
      primary:   '#F1F5F9',
      secondary: '#94A3B8',
      tertiary:  '#64748B',
      disabled:  '#475569',
      inverse:   '#0F172A',
    },
    border: {
      default:   '#1E293B',
      subtle:    '#1E293B',
      strong:    '#334155',
    },
    sidebar: {
      bg:        'linear-gradient(180deg, #0D1117 0%, #010409 100%)',
      text:      'rgba(255,255,255,0.9)',
      textMuted: 'rgba(255,255,255,0.4)',
      active:    'rgba(56,139,253,0.2)',
      activeBorder: '#388BFD',
      hover:     'rgba(255,255,255,0.06)',
    },
    severity: {
      compliant:  { bg: '#052E16', text: '#4ADE80', border: '#166534' },
      warning:    { bg: '#451A03', text: '#FBBF24', border: '#92400E' },
      critical:   { bg: '#450A0A', text: '#F87171', border: '#991B1B' },
      info:       { bg: '#172554', text: '#60A5FA', border: '#1E40AF' },
    },
  },
  highContrast: {
    background: {
      default:   '#000000',
      paper:     '#0A0A0A',
      subtle:    '#1A1A1A',
      elevated:  '#1A1A1A',
    },
    text: {
      primary:   '#FFFFFF',
      secondary: '#E5E5E5',
      tertiary:  '#A3A3A3',
      disabled:  '#737373',
      inverse:   '#000000',
    },
    border: {
      default:   '#404040',
      subtle:    '#262626',
      strong:    '#FFFFFF',
    },
    sidebar: {
      bg:        '#000000',
      text:      '#FFFFFF',
      textMuted: '#A3A3A3',
      active:    'rgba(255,255,255,0.15)',
      activeBorder: '#FFFFFF',
      hover:     'rgba(255,255,255,0.1)',
    },
    severity: {
      compliant:  { bg: '#000000', text: '#00FF00', border: '#00FF00' },
      warning:    { bg: '#000000', text: '#FFFF00', border: '#FFFF00' },
      critical:   { bg: '#000000', text: '#FF0000', border: '#FF0000' },
      info:       { bg: '#000000', text: '#00BFFF', border: '#00BFFF' },
    },
  },
} as const;

export type PaletteMode = keyof typeof palette;
