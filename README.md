# OCRmacPDF

Native macOS PDF OCR tool that converts scanned, image-based PDFs into searchable
documents using Apple's Live Text technology (Apple Vision Framework + PDFKit on
macOS 13.0+). It embeds an invisible OCR text layer without third-party
dependencies like Tesseract.

## Key Features

- No dependencies: no tesseract, ghostscript, or python required.
- Superior quality: better text recognition and layout detection than OCRmyPDF/Tesseract.
- Hardware accelerated: uses Apple Neural Engine (ANE) when available.
- Private: 100% on-device; no cloud APIs.

## Requirements

- macOS 13+
- Xcode Command Line Tools: `xcode-select --install`

## Installation & Build

```sh
git clone https://github.com/marat-turaev/OCRmacPDF
cd OCRmacPDF
make
```

## Usage

```sh
./ocrmacpdf [options] input.pdf [more.pdf ...]
```

Options:

- `-h`, `--help` Show help and exit
- `-v`, `--verbose` Print progress messages
- `-o`, `--overwrite` Overwrite input files in place
- `--dry-run` Print planned outputs without writing files
- `-p`, `--prefix STR` Prefix for output files (default: `OCR_`)
- `-j`, `--jobs N` Number of parallel jobs (default: `1`)

Examples:

```sh
./ocrmacpdf invoice.pdf
./ocrmacpdf --overwrite -j 4 **/*.pdf
```

Outputs are written next to inputs with an `OCR_` prefix unless `--overwrite` is set.

## Clean

```sh
make clean
```
