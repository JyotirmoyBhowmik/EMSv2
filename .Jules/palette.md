## 2024-06-04 - Converted interactive divs to buttons and linked form labels
**Learning:** Found an accessibility issue pattern specific to this app where custom interactive elements (like the auth provider selection cards in `Login.jsx`) were built using non-semantic `<div>` tags without keyboard support, and form labels were not properly linked to their inputs.
**Action:** Always verify that interactive components use semantic HTML (e.g., `<button>` instead of `<div>` with `onClick`) or include proper roles and keyboard event handlers. Ensure all `<label>` elements are linked to their corresponding `<input>` fields using `htmlFor` and `id` attributes.
## 2024-06-09 - Added htmlFor and id to labels and inputs
**Learning:** Found accessibility issue where `<label>` and `<input>` / `<textarea>` / `<select>` were not explicitly linked with `htmlFor` and `id` attributes in forms like in `ChangePasswordModal.jsx` and `ScanEndpoint.jsx`. This affects screen reader accessibility and reduces clickable area.
**Action:** Always ensure explicitly linking form `<label>` elements to their corresponding inputs with the `htmlFor` and `id` attributes.
