## 2026-05-31 - Login Form Accessibility
**Learning:** The auth provider cards in Login.jsx were <div> elements with onClick handlers, which breaks keyboard navigation (tabbing) and screen reader access. Additionally, form labels were missing 'htmlFor' attributes linked to input 'id's, preventing screen readers from reading label context.
**Action:** Convert interactive elements functioning as buttons into semantic <button type="button"> elements with appropriate aria-labels, and add 'htmlFor' matching the target input's 'id' to ensure correct linking.
