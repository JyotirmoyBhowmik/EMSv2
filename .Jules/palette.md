## 2024-06-04 - Converted interactive divs to buttons and linked form labels
**Learning:** Found an accessibility issue pattern specific to this app where custom interactive elements (like the auth provider selection cards in `Login.jsx`) were built using non-semantic `<div>` tags without keyboard support, and form labels were not properly linked to their inputs.
**Action:** Always verify that interactive components use semantic HTML (e.g., `<button>` instead of `<div>` with `onClick`) or include proper roles and keyboard event handlers. Ensure all `<label>` elements are linked to their corresponding `<input>` fields using `htmlFor` and `id` attributes.

## 2024-11-20 - Missing Label Attributes
**Learning:** Found a common pattern where form `<label>` elements lack `htmlFor` and their target inputs lack `id`. Screen readers need this linkage to properly associate a label with a form element.
**Action:** Always verify proper label association with target inputs by using matching `htmlFor` and `id` properties.
