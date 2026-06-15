## 2024-06-04 - Converted interactive divs to buttons and linked form labels
**Learning:** Found an accessibility issue pattern specific to this app where custom interactive elements (like the auth provider selection cards in `Login.jsx`) were built using non-semantic `<div>` tags without keyboard support, and form labels were not properly linked to their inputs.
**Action:** Always verify that interactive components use semantic HTML (e.g., `<button>` instead of `<div>` with `onClick`) or include proper roles and keyboard event handlers. Ensure all `<label>` elements are linked to their corresponding `<input>` fields using `htmlFor` and `id` attributes.

## 2024-08-01 - Missing explicit form label associations
**Learning:** Encountered a recurring accessibility pattern in `ScanEndpoint.jsx` where `<label>` elements were missing the `htmlFor` attribute linking them to their corresponding `<input>`, `<select>`, and `<textarea>` elements via `id`. This issue affects screen reader usability.
**Action:** Always ensure that form labels are explicitly associated with their input controls using the `htmlFor` and `id` attributes when building or modifying forms in this application.
## 2024-05-19 - Accessible Form Inputs
**Learning:** Found that custom form fields in `ComputerManagement.jsx` lacked standard `htmlFor` and `id` linking, and toggle buttons did not have ARIA properties communicating their expanded state.
**Action:** Always ensure toggle buttons use `aria-expanded` and `aria-controls` for accessibility, and standard form inputs and selects use `htmlFor` matching their respective `id` properties.
