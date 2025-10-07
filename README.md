[![Docker Image CI](https://github.com/d4niee/tex-pdf-builder/actions/workflows/docker-image.yml/badge.svg)](https://github.com/d4niee/tex-pdf-builder/actions/workflows/docker-image.yml)

# tex-pdf-builder
<p align="center">
<img width="30%" height="30%" align="center" src="https://github.com/d4niee/tex-pdf-builder/blob/main/.github/image.png" alt="logo">
</p>
Image to build latex with thre recipe: pdflatex -> biber pdflatex * 2

latex to PDF image Dockerhub: https://hub.docker.com/r/dani251/tex-pdf-builder

**disclaimer**: this image is based on the following image: registry.gitlab.com/islandoftex/images/texlive:latest

## Usage of the Image
```
Usage: build-latex [-s main.tex] [-o output.pdf] [-w /workdir]
                   [--latex-opts "..."] [--latexmk-opts "..."]
                   [-r|--recipe pdflatex|latexmk-xelatex|latexmk-lualatex]
                   [-C|--final-clean] [--final-clean-dir DIR]

  -s, --source            root .tex file (default: main.tex)
  -o, --output            output file (default: output.pdf) — kann auch außerhalb von WORKDIR liegen
  -w, --workdir           working directory (default: /work)
      --latex-opts        opts für (pdf|xe|lua)latex (default: "-interaction=nonstopmode -halt-on-error -file-line-error")
      --latexmk-opts      zusätzliche latexmk-Optionen (default: "-synctex=1")
  -r, --recipe            pdflatex | latexmk-xelatex | latexmk-lualatex (default: pdflatex)
  -C, --final-clean       LaTeX-Tempfiles NACH PDF-Erstellung löschen (off)
      --final-clean-dir   Zielverzeichnis für Clean (default: --workdir)

Beispiele:
  docker run --rm -v "$PWD/latex:/work" IMAGE
  docker run --rm -v "$PWD/latex:/work" IMAGE -s thesis.tex -o Thesis.pdf
  docker run --rm -v "$PWD/latex:/work" IMAGE -r latexmk-xelatex
```

## building the image

```bash
# FULL (all packages and features)
docker build --build-arg TL_SCHEME=full -t tex-pdf-builder:full .
# SLIM (minimal installation)
docker build --build-arg TL_SCHEME=small -t tex-pdf-builder:slim .
```

## Tags

The Image is available with the following tags:
* ``full``: full installation of tex live with all packages. If you don't know what you exactly need this image is recommend
* ``slim``: minimal installation for texlive. If you encounter errors with this image you should probably choose the full version

## Examples
```
  docker run --rm -v "\$PWD/latex:/work" IMAGE
  docker run --rm -v "\$PWD/latex:/work" IMAGE -s thesis.tex -o Thesis.pdf
```

## Pipeline Templates
Here some examples how we can use the image to automatically build latex projekts via pipeline in Gitlab oder Github Actions. This can be used if you decide to
track your latex projekt with git.
### Gitlab

```yml
"🔨 Recipe: pdflatex -> biber -> pdflatex * 2":
  image:
    name: docker.io/dani251/tex-pdf-builder:latest
    pull_policy: always
    entrypoint: [""]
  stage: "🛠️ Build"
  script:
    - set -euo pipefail
    - cd "$LATEX_DIR"
    - build-latex -w "$PWD" -s "$TEX_SOURCE" -o "../$OUTPUT_PDF"
    - |
      if [ "${DO_PRINT}" = "true" ]; then
        cp "../$OUTPUT_PDF" "../Lambrecht_Masterarbeit_PrintVersion.pdf"
      fi
  after_script:
    - cat "$LATEX_DIR/${TEX_SOURCE%.tex}.log" || true
```

### Github Actions

```yml
name: Build LaTeX PDF
on:
  push:
    branches: [ "main" ]
  workflow_dispatch:
jobs:
  build:
    name: "🔨 Recipe: pdflatex → biber → pdflatex ×2"
    runs-on: ubuntu-latest
    container:
      image: docker.io/dani251/tex-pdf-builder:latest
      options: --entrypoint ""
    steps:
      - uses: actions/checkout@v4
      - name: Build PDF
        shell: bash
        run: |
          set -euo pipefail
          cd "$LATEX_DIR"
          build-latex -w "$PWD" -s "$TEX_SOURCE" -o "../$OUTPUT_PDF"
      - name: Show LaTeX log (always)
        if: always()
        shell: bash
        run: |
          cat "$LATEX_DIR/${TEX_SOURCE%.tex}.log" || true
      - name: Upload PDFs
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: latex-pdfs
          path: |
            ${{ env.OUTPUT_PDF }}
            Lambrecht_Masterarbeit_PrintVersion.pdf
          if-no-files-found: warn
          retention-days: 30

```

