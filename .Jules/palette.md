
## 2026-05-27 - Login Form Accessibility Enhancements
**Learning:** Custom interactive elements (like auth provider selection cards in `Login.jsx`) were built using non-semantic `<div>` elements without keyboard accessibility, and standard form inputs lacked explicitly linked labels (missing `htmlFor` / `id`).
**Action:** Always convert interactive, selection-based `<div>` elements to `<button>` and ensure they include appropriate ARIA attributes (like `aria-pressed`). Additionally, always explicitly link `<label>` and `<input>` elements using `htmlFor` and `id` for screen reader compatibility.
