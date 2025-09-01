# tex-pdf-builder
Image to build latex with thre recipe: pdflatex -> biber pdflatex * 2

latex to PDF image Dockerhub: https://hub.docker.com/r/dani251/tex-pdf-builder

**disclaimer**: this image is based on the following image: registry.gitlab.com/islandoftex/images/texlive:latest

## Usage of the Image
```
build-latex [-s main.tex] [-o output.pdf] [-w /workdir] [--latex-opts "..."]
  -s, --source       Root .tex file (default: main.tex)
  -o, --output       output file (default: output.pdf)
  -w, --workdir      Working directory inside the container (default: /work)
      --latex-opts   Additional options for pdflatex (e.g., “-interaction=nonstopmode”)
```
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

