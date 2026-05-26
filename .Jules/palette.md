
## 2024-05-18 - Missing semantic inputs in interactive elements
**Learning:** Found a common accessibility pattern in this repository: many custom interactive elements, such as card-like buttons (e.g., authentication provider selections in `Login.jsx`), are built using `<div>` elements instead of semantic `<button>` elements. Additionally, form elements (`<label>` and `<input>`) frequently lack explicit `htmlFor` and `id` linking.
**Action:** When encountering interactive elements or forms, explicitly verify if they use proper HTML semantics (`<button>` instead of `<div>`, `fieldset`/`legend` for groupings, and `htmlFor`/`id` linking for labels).
