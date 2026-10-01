# Changelog

## [0.2.1] - 2026-10-02

- Keep decompression failures and malformed UTF-8 responses, including invalid decoded JSON strings, inside the sanitized error contract, preserving uncertain-write recovery without retries.
- Preserve callback identity when another webhook subscription has credentials matching this subscription's URL components; continue filtering secrets throughout free text.

## [0.2.0] - 2026-09-29

- Add explicit sale update/undo, order, invoice, payment, sale manual-journal, standalone journal, tax-rule and webhook operations while preserving existing read methods.
- Send JSON payloads without rounding amounts or FX rates; distinguish parent sale IDs, document task IDs, payment IDs and webhook IDs.
- Expose request method/path and `ambiguous?` on errors for uncertain write outcomes after transport failures, server errors or invalid success responses. Never retry automatically.
- Sanitize credentials in response bodies and headers, omit sensitive transport causes and response details from error messages, and make object inspection safe for logging.
- Document document-replacement semantics, recovery lookup contracts, webhook constraints and release verification. Live financial behavior remains the caller's responsibility to verify.

## [0.1.0] - 2026-08-12

- Add tenant-scoped authentication for the CIN7 Core API v2.
- Add read-only clients for account, customer, location, sale, credit note, and payment resources.
- Add transparent responses and typed HTTP, transport, and JSON parsing errors.
