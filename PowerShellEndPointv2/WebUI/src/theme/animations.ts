/**
 * EMS v5 — Framer Motion Presets
 * Spec §2: 150–200ms ease-out. Respects prefers-reduced-motion.
 */

import type { Transition, Variants } from 'framer-motion';

/** Default transition — spec: 150-200ms ease-out */
export const defaultTransition: Transition = {
  duration: 0.18,
  ease: [0.25, 0.1, 0.25, 1],
};

/** Fast transition for micro-interactions */
export const fastTransition: Transition = {
  duration: 0.12,
  ease: 'easeOut',
};

/** Spring for interactive elements */
export const springTransition: Transition = {
  type: 'spring',
  stiffness: 400,
  damping: 30,
};

/** Fade in/out */
export const fadeVariants: Variants = {
  initial: { opacity: 0 },
  animate: { opacity: 1, transition: defaultTransition },
  exit:    { opacity: 0, transition: fastTransition },
};

/** Slide up (for drawers, modals) */
export const slideUpVariants: Variants = {
  initial: { opacity: 0, y: 16 },
  animate: { opacity: 1, y: 0, transition: defaultTransition },
  exit:    { opacity: 0, y: 8, transition: fastTransition },
};

/** Scale (for cards, tooltips) */
export const scaleVariants: Variants = {
  initial: { opacity: 0, scale: 0.95 },
  animate: { opacity: 1, scale: 1, transition: defaultTransition },
  exit:    { opacity: 0, scale: 0.97, transition: fastTransition },
};

/** Stagger children */
export const staggerContainer: Variants = {
  animate: {
    transition: {
      staggerChildren: 0.04,
      delayChildren: 0.02,
    },
  },
};

/** List item for staggered lists */
export const listItemVariants: Variants = {
  initial: { opacity: 0, x: -8 },
  animate: { opacity: 1, x: 0, transition: defaultTransition },
};

/**
 * Check if user prefers reduced motion.
 * Returns true if reduced motion is preferred — skip animations.
 */
export function prefersReducedMotion(): boolean {
  if (typeof window === 'undefined') return false;
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
}
