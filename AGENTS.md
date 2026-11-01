# Folio development guidance

For changes to rendered HTML, CSS, or preview sizing, follow the rendering-change checklist in [docs/VALIDATION.md](docs/VALIDATION.md#rendering-change-checklist). HTML string assertions alone do not validate readability. Preserve a representative, anonymized fixture for each layout regression and check its actual layout in WebKit before releasing.

Keep rendering lessons and validation results in `docs/VALIDATION.md`, rather than only in chat history. Both the app and Finder Quick Look consume the shared renderer; validate and install both when shipping rendering fixes.
