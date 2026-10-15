# Task 1 report

Status: DONE

## Changes

- Added five cross-platform Telegram JSON fixtures under `tests/fixtures/telegram/` covering pairing, approval callback, question callback, foreign user/chat and action/error cases.
- Added the shared contract checklist to the design spec: canonical event names, update fields, pairing rules, callback grammar, action limits and state transitions, text and network limits, and 409/429/401 behavior.

## Validation

- `python3 -m json.tool tests/fixtures/telegram/get-updates-question.json`
- `python3 -m json.tool` for every Telegram fixture.
- `git diff --check`.
- Searched fixtures for real tokens, paths, and shell commands; none found.

## Commit

`1693ccd docs: define Telegram integration contract`

## Concerns

None.

## Review fix

- Replaced every fixture callback ref with a distinct 16-byte, unpadded base64url value (22 characters).
- Split action cases into canonical `event` (`approval`/`question`) and separate `operation` fields.
- Revalidated JSON, callback ref alphabet/length/decoded size, and whitespace.

## Scoped re-review fix

- Replaced all remaining malformed callback refs, including foreign, duplicate, and expired cases, with opaque 22-character base64url refs.
- Verified every fixture callback ref matches the allowed ASCII alphabet and decodes to exactly 16 bytes.
- Re-ran JSON parsing and `git diff --check`.
