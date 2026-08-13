# Home Point Native Row Boundary Design

## Outcome

AccessXI speaks exactly the visible Home Point menu row and never appends stale text retained in a reused native text buffer. The correction applies at the shared native query-row decoder, not through Home Point-specific phrase substitutions.

## Root cause

The game reuses each query-row text object. It rewrites the visible prefix and updates the object's visible-glyph length, but bytes from the previous label remain after that prefix. AccessXI currently scans a fixed `0x48`-byte range, splits controls into fragments, and concatenates every plausible fragment. That turns rows such as `Never mind.` into `Never mind Favorites.` and `Nowhere.` into `Nowhere Sles.`.

The native text object records the authoritative visible-glyph count at byte `text_ptr + 0x106`. Captured rows prove that count excludes the stale suffix. Control byte `0x0C` is a comma and `0x0E` is a period; neither is a universal terminator because valid rows such as `150-pt. Items.` contain an internal period.

## Decoder contract

- Decode exactly the validated native visible-glyph count and never scan beyond it. The count must be an integer from 1 through 63 inclusive; punctuation controls count as one visible glyph.
- Preserve supported inline controls, including `0x0C` as comma and `0x0E` as period.
- Reject malformed metadata, counts outside 1 through 63, unsupported control sequences, truncated reads, decoded glyph-count mismatches, and labels that fail the existing native-query cleanliness checks.
- Keep existing cursor, row-count, linked-list, and candidate-scoring validation. Only the text-object boundary changes.
- Remove no existing phrase normalization unless a focused regression proves it is obsolete; suffix-specific additions are forbidden.

The existing `generic_query_row_label_from_ptr` schema is the working reference. The bounded decoder may be shared with `native_query_phrase_from_ptr`, but Home Point, Survival Guide, and other query menus must retain their current context normalization after the bounded raw row has been recovered.

## Verification

Captured-byte Lua fixtures must first fail against the fixed-window decoder and then pass for:

- `Never mind.` followed by stale `FAVORITES.` with visible length 11;
- `Nowhere.` followed by stale `SLES.` with visible length 8;
- `On second thought, none.` with the `0x0C` composition control;
- `150-pt. Items.` with an internal `0x0E`, proving periods do not truncate valid text;
- missing, zero, oversized, or inconsistent length metadata, which must fail closed.

Existing Home Point, Survival Guide, generic query, Lua 5.1 syntax, and reader integration suites remain release gates.
