# bibstd

![Logo](docs/icons/512x512/bibstd.png)

A small BibTeX parser and formatter built with Flex and Bison.

It reads BibTeX from standard input, validates key required fields for common entry types, normalizes selected fields, and prints canonicalized BibTeX to standard output.

## Requirements

- GNU Make
- Bash
- Flex
- Bison
- A C++17 compiler (for example, g++)

## Build

From the repository root:

```bash
make
```

This generates:

- `dist/bibtex_lexer.cpp`
- `dist/bibtex_parser.cpp`
- `dist/bibtex_parser.hpp`
- `dist/bibtex_compiler`

To clean generated files:

```bash
make clean
```

## Run

Use stdin redirection with a `.bib` file:

```bash
./dist/bibtex_compiler < test/sample.bib
```

## Test

Run the repository script:

```bash
./build_and_test.sh
```

The script rebuilds the project and runs the compiler on:

- `test/sample.bib`
- `test/A_Theory_of_Justice.bibtex`
- `test/big_file.bib`

## What The Tool Does

- Parses entries of the form `@type{key, field=value, ...}`.
- Reports parse errors with source location (`line:column`).
- Validates required fields for selected entry types.
- Canonicalizes output entry type to lowercase.
- Regenerates entry IDs from content when possible.
- Orders fields using a preferred field list, then alphabetically for unknown fields.
- Wraps long braced field values to 80 columns.

### Field Normalization

- `author` values are normalized to `First Last` form per author and emitted in braces.
- `journaltitle` is renamed to `journal`.
- `date={YYYY}` is normalized to `year={YYYY}`.
- `date={YYYY-MM}` is split into:
  - `year={YYYY}`
  - `month={M}` (non-zero-padded)
- Existing numeric `month` values are de-zero-padded (`01` -> `1`).

### Field Filtering

Some advertising/aggregator links are suppressed when found in `url` or `note`, including matches such as:

- `books.google.*`
- `jstor.org`
- `researchgate.net`
- `openresearchlibrary.org`
- `semanticscholar.org`

### Required Field Checks

The parser checks required fields for these types:

- `article`: `author`, `title`, `year`
- `book`: `title`, `year`, and one of `author` or `editor`
- `inproceedings`: `author`, `title`, `booktitle`, `year`
- `incollection`: `author`, `title`, `booktitle`, `publisher`, `year`
- `phdthesis` and `mastersthesis`: `author`, `title`, `school`, `year`
- `techreport`: `author`, `title`, `institution`, `year`
- `booklet`: `title`

If any required fields are missing, the program prints an error and exits with status 1.

## Output And Exit Codes

- Success: prints normalized BibTeX to stdout, exits 0.
- Validation failure: prints missing-field error to stderr, exits 1.
- Parse failure: prints parse error with location to stderr.

## Project Layout

- `src/bibtex_lexer.l`: Flex lexer
- `src/bibtex_parser.y`: Bison grammar, validation, normalization, and output
- `test/`: sample inputs
- `build_and_test.sh`: convenience build and test script
- `Makefile`: build rules

## License
This project is licensed under the GNU General Public License, version 3.
See `LICENSE` for the full text.