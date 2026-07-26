---
name: markdown-i18n
description: "Translate English Markdown docs (README, docs, tutorials) into Japanese as a sibling `<name>.ja.md` file next to the English `<name>.md`, preserving structure, code, links, badges, and frontmatter. Use when the user wants to internationalize, i18n, localize, or translate Markdown documentation, generate a Japanese README/doc, or keep `.md` and `.ja.md` in sync."
argument-hint: "Path to the English .md file to translate (e.g., README.md or docs/index.md)"
---

# Markdown Internationalization (i18n)

Create a Japanese translation of an English Markdown document as a sibling file, keeping the two versions structurally identical.

## When to Use

- Internationalize / i18n / localize / translate a README, docs page, or tutorial into Japanese.
- Generate a `*.ja.md` counterpart for an English `*.md` file.
- Refresh a Japanese translation after the English source changed.

Default target language is **Japanese (`ja`)**. The same procedure generalizes to other languages by swapping the language code (see [Naming convention](#naming-convention)).

## Naming Convention

Insert the language code immediately before the final `.md` extension, and write the file in the **same directory** as the source.

| English source                         | Japanese output                           |
| -------------------------------------- | ----------------------------------------- |
| `README.md`                            | `README.ja.md`                            |
| `docs/index.md`                        | `docs/index.ja.md`                        |
| `docs/tutorials/01_getting-started.md` | `docs/tutorials/01_getting-started.ja.md` |

Rules:

- Only translate English sources. **Skip** files that already carry a language code (e.g. `*.ja.md`, `*.zh.md`).
- Never change the base name, directory, or casing — only insert `.ja`.
- If the output file already exists, treat this as an update: re-translate from the current source and overwrite. Call out any manual `.ja.md`-only edits before replacing them.

## Procedure

1. **Locate the source.** Confirm the English `.md` path. If the user names a directory or glob, list candidate `.md` files (excluding existing `*.<lang>.md`) and confirm scope.
2. **Derive the output path** using the naming convention above.
3. **Read the entire source file** — never translate from a summary or a partial read.
4. **Translate the prose to natural Japanese**, applying the [Preservation rules](#preservation-rules) and [Translation guidelines](#translation-guidelines). Keep everything that is not human-readable prose byte-for-byte.
5. **Write the `*.ja.md` file** with the translated content.
6. **Verify** against the [Verification checklist](#verification-checklist) with a careful side-by-side review of the source and translation. Fix any drift before finishing.

## Preservation Rules

Translate only human-readable prose. Keep everything below **unchanged**:

| Element                                                                     | Rule                                                                                                                                   |
| --------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Fenced code blocks                                                          | Verbatim — language info string, code, and comments. Do **not** translate.                                                             |
| Inline code `` `code` ``                                                    | Verbatim — commands, file paths, identifiers, flags.                                                                                   |
| Links & images                                                              | Keep the target/URL. Translate only the visible link text / alt text (see [Internal link repointing](#internal-link-repointing)).      |
| Badges / shields (e.g. `![test](https://img.shields.io/...)`)               | Verbatim.                                                                                                                              |
| GitHub alerts `> [!NOTE]` `[!TIP]` `[!IMPORTANT]` `[!WARNING]` `[!CAUTION]` | Keep the `[!KEYWORD]` marker in English/uppercase; translate the blockquote body.                                                      |
| HTML tags                                                                   | Keep tags/attributes; translate only visible text (e.g. `<summary>`, `<details>` content).                                             |
| YAML frontmatter                                                            | Keep keys and machine-facing values (`layout`, `permalink`, `slug`, IDs). Translate human-facing values (`title`, `description`) only. |
| Heading hierarchy                                                           | Same number of headings, same levels, same order.                                                                                      |
| Product / command / brand names                                             | Keep in English (`GitHub`, `Makefile`, `make ci-test`, `gh aw`).                                                                       |

## Translation Guidelines

- **Style:** natural, technical Japanese in polite form (です・ます調), consistent across the whole document.
- **Terminology:** keep established English technical terms; on first mention you may gloss as `日本語（English）` when it aids clarity. Reuse the same translation for a term throughout.
- **Punctuation:** use full-width `。、` for Japanese prose; keep half-width punctuation inside code, paths, and URLs.
- **Fidelity:** convey exactly the same information — do not add, drop, or reorder content. One source paragraph maps to one Japanese paragraph.
- **Diagrams (` ```mermaid `):** by default keep verbatim so the diagram renders identically. Only translate node labels when explicitly requested.

### Internal link repointing

For links that point to **another Markdown file in the same repository**:

- If that file has (or will have) a `.ja.md` counterpart, repoint the link to the `.ja.md` version.
- Otherwise keep the original target.

For **same-document anchor links** (e.g. `#prerequisites`): translating a heading changes its generated anchor, so update the anchor to match the translated heading. GitHub slugifies Japanese headings by lowercasing and replacing spaces, so `## 前提条件` is reached via `#前提条件`.

External URLs are always kept as-is.

## Verification

Open the source and the `*.ja.md` output side by side and confirm each item below. Structural parity is the most common source of drift — count the headings and compare each fenced code block directly.

A quick way to compare structure without extra tooling:

````bash
# Headings should match exactly; code-fence counts should be equal.
grep -nE '^#{1,6} ' <source.md>
diff <(grep -cE '^```' <source.md>) <(grep -cE '^```' <output.ja.md>)
````

### Verification checklist

- [ ] Output path follows `<name>.ja.md` in the same directory.
- [ ] Same number and levels of headings, in the same order.
- [ ] All fenced code blocks are byte-identical (except intentionally localized mermaid labels).
- [ ] Inline code, commands, file paths, and flags are unchanged.
- [ ] Links resolve: external URLs unchanged; internal links repointed to `.ja.md` where applicable; anchors updated to translated headings.
- [ ] Badges, images, and HTML tags preserved.
- [ ] No untranslated English prose remains (excluding technical terms / proper nouns).
- [ ] Frontmatter keys and machine-facing values unchanged.
