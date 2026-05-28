## 2025-05-28 - Initial setup
**Learning:** Checking for UX improvement opportunities.
**Action:** Let's look for small UX/a11y improvements to make.
## 2025-05-28 - Login Accessibility Update
**Learning:** Found custom interactive elements (auth providers) built using `<div>` without roles or keyboard events, and form inputs missing `id`/`htmlFor` pairings. This impacts keyboard navigation and screen reader usability.
**Action:** Replaced `<div>`s with `<button type="button">` and added `aria-pressed`. Always ensure form inputs have proper `id` and `htmlFor` pairings for labels.
