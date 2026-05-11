# EMS v5 — Dependency Manifest

Every dependency justified in one line per spec §1.1.

## Runtime Dependencies

| Package | Version | Why |
|---------|---------|-----|
| `@emotion/react` | ^11.14.0 | MUI v9 styling engine — required peer |
| `@emotion/styled` | ^11.14.1 | MUI v9 styled API — required peer |
| `@mui/material` | ^9.0.1 | Core component library — enterprise-grade, WCAG AA, theme system |
| `@mui/icons-material` | ^9.0.1 | Official MUI icon set for consistent icon language |
| `@mui/lab` | ^9.0.0-alpha.0 | Experimental MUI components (Timeline, TreeView enhancements) |
| `@mui/x-data-grid` | ^9.0.0 | Enterprise data grid — sorting, filtering, grouping, virtualization |
| `@mui/x-charts` | ^9.0.0 | Operations charts — spec §2 mandates this over recharts |
| `@mui/x-date-pickers` | ^9.0.0 | Date/time inputs for scheduling, report range selection |
| `@mui/x-tree-view` | ^9.0.0 | Hierarchical views for site/department tree |
| `@tanstack/react-query` | ^5.100.9 | Server state management — caching, refetching, stale detection |
| `@tanstack/react-query-devtools` | ^5.100.9 | Dev-only query inspector |
| `@tanstack/react-table` | ^8.21.0 | Headless table — spec §7.4 for 10k+ row endpoint grid |
| `@tanstack/react-virtual` | ^3.13.0 | Virtual scrolling for large lists — replaces `react-window` |
| `@hookform/resolvers` | ^3.10.0 | Bridges react-hook-form ↔ Zod validation |
| `react-hook-form` | ^7.54.0 | Performant form state — scan config, settings, filters |
| `zod` | ^3.24.0 | Schema validation — API payloads, form inputs, config |
| `zustand` | ^5.0.3 | Client state (theme, density, sidebar, user prefs) — minimal boilerplate |
| `ky` | ^1.7.5 | HTTP client — spec §1.1 mandates ky over axios (smaller, fetch-based) |
| `socket.io-client` | ^4.8.1 | Real-time scan progress, alerts, live console |
| `jwt-decode` | ^4.0.0 | Client-side JWT introspection for role/expiry display |
| `date-fns` | ^4.1.0 | Date formatting — spec §1.1 mandates over dayjs (tree-shakeable) |
| `framer-motion` | ^12.0.0 | Animations — spec §2 requires 150–200ms ease-out, reduced-motion aware |
| `lucide-react` | ^0.469.0 | Primary icon set — spec §1.1 mandates over react-icons |
| `@tabler/icons-react` | ^3.26.0 | Secondary icon set — broader coverage for niche icons |
| `react` | ^18.3.1 | UI framework — spec mandates React 18 |
| `react-dom` | ^18.3.1 | React DOM renderer |
| `react-router-dom` | ^7.15.0 | Client-side routing with lazy loading |
| `sonner` | ^1.7.1 | Toast notifications — spec §1.1 mandates over react-hot-toast/notistack |
| `cmdk` | ^1.0.4 | Command palette — spec §2 (⌘/Ctrl+K) |
| `vaul` | ^1.1.2 | Drawer component — spec §2 for mobile + confirmations |
| `react-resizable-panels` | ^2.1.7 | 3-pane resizable layout — spec §2 |
| `react-dropzone` | ^14.3.5 | File upload for CSV import, report templates |
| `@tremor/react` | ^3.18.7 | Executive dashboard charts — spec §4 mandates for exec view |
| `@xyflow/react` | ^12.10.2 | Workflow designer — scan pipeline visual builder |
| `dagre` | ^0.8.5 | Graph auto-layout for workflow designer |
| `elkjs` | ^0.9.3 | Alternative layout engine for complex workflows |
| `react-error-boundary` | ^6.1.1 | Graceful error handling with retry |
| `@sentry/react` | ^8.47.0 | Error tracking + performance monitoring |
| `jspdf` | ^2.5.2 | Client-side PDF generation for reports |
| `html2canvas` | ^1.4.1 | DOM-to-canvas for PDF chart rendering |
| `cidr-tools` | ^11.3.5 | CIDR parsing for subnet-based scan targets |
| `ipaddr.js` | ^2.2.0 | IP address validation and manipulation |
| `is-ip` | ^5.0.1 | IP address format detection |
| `is-cidr` | ^5.1.0 | CIDR notation validation |
| `netmask` | ^2.0.2 | Subnet mask calculations for topology classification |
| `ip-regex` | ^5.0.0 | IP address pattern matching in text |
| `react-i18next` | ^15.4.1 | i18n framework — spec §2 requires EN default + NP locale stub |
| `i18next` | ^24.2.2 | Core i18n engine |
| `i18next-browser-languagedetector` | ^8.0.4 | Auto-detect browser language preference |
| `@scalar/api-reference-react` | ^1.1.4 | OpenAPI docs UI — spec §18 |

## Dev Dependencies

| Package | Version | Why |
|---------|---------|-----|
| `typescript` | ^5.7.3 | Type safety — spec mandates TS |
| `@types/react` | ^18.3.18 | React type definitions |
| `@types/react-dom` | ^18.3.5 | ReactDOM type definitions |
| `@types/dagre` | ^0.7.52 | Dagre graph layout types |
| `@types/node` | ^22.10.0 | Node.js API types for build scripts |
| `@vitejs/plugin-react` | ^4.3.4 | Vite React integration (Fast Refresh, JSX) |
| `vite` | ^6.0.7 | Build tool — spec §1.2 mandates Vite 6 |
| `vite-tsconfig-paths` | ^5.1.4 | Resolves TS path aliases in Vite |
| `vite-plugin-svgr` | ^4.3.0 | SVG-as-React-component imports |
| `vitest` | ^3.0.4 | Test runner — spec §1.2 mandates over Jest |
| `@vitest/ui` | ^3.0.4 | Visual test UI |
| `eslint` | ^9.17.0 | Linting |
| `eslint-plugin-react-hooks` | ^5.1.0 | React hooks lint rules |
| `prettier` | ^3.4.2 | Code formatting |

## Removed (with replacement)

| Removed | Replaced By | Reason |
|---------|------------|--------|
| `axios` | `ky` | Spec §1.1 — smaller, fetch-based, no polyfill needed |
| `dayjs` | `date-fns` | Spec §1.1 — tree-shakeable, no mutable API |
| `react-hot-toast` | `sonner` | Spec §1.1 — better stacking, action support |
| `notistack` | `sonner` | Spec §1.1 — single toast lib |
| `recharts` | `@mui/x-charts` | Spec §1.1 — consistent with MUI ecosystem |
| `react-icons` | `lucide-react` + `@tabler/icons-react` | Spec §1.1 — tree-shakeable, consistent style |
| `react-window` | `@tanstack/react-virtual` | Spec §7.4 — more flexible, better integration with TanStack Table |
| `@sentry/tracing` | `@sentry/react` (built-in) | Sentry v8 includes tracing in core package |
