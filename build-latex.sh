#!/usr/bin/env bash

# View on Github: https://github.com/d4niee/tex-pdf-builder
# View on Dockerhub: https://hub.docker.com/repository/docker/dani251/tex-pdf-builder

set -euo pipefail # if used in a pipeline

# helping script
usage() {
  cat <<EOF
Usage: build-latex [-s main.tex] [-o output.pdf] [-w /workdir] [--latex-opts "..."]
  -s, --source       root .tex file (default: main.tex)
  -o, --output       output file(default: output.pdf)
  -w, --workdir      Working directory inside the container (default: /work)
      --latex-opts   Additional options for pdflatex (z.B. "-interaction=nonstopmode")
Examples:
  docker run --rm -v "\$PWD/latex:/work" IMAGE
  docker run --rm -v "\$PWD/latex:/work" IMAGE -s thesis.tex -o Thesis.pdf
EOF
}

# default params
SOURCE="main.tex"
OUTPUT="output.pdf"
WORKDIR="/work"
LATEX_OPTS="-interaction=nonstopmode -halt-on-error -file-line-error"

# Args parsing
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--source) SOURCE="$2"; shift 2;;
    -o|--output) OUTPUT="$2"; shift 2;;
    -w|--workdir) WORKDIR="$2"; shift 2;;
    --latex-opts) LATEX_OPTS="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

cd "$WORKDIR"

if [[ ! -f "$SOURCE" ]]; then
  echo "[404] ERROR: source not found: $WORKDIR/$SOURCE" >&2
  exit 2
fi

BASENAME="${SOURCE%.tex}"
LOGFILE="${BASENAME}.log"

echo "==> Building $SOURCE -> $OUTPUT"
echo "==> Workdir: $WORKDIR"
echo "==> pdflatex opts: $LATEX_OPTS"
echo

pdflatex $LATEX_OPTS "$SOURCE"

if [[ -f "${BASENAME}.bcf" ]]; then
  biber "$BASENAME"
fi

pdflatex $LATEX_OPTS "$SOURCE"
pdflatex $LATEX_OPTS "$SOURCE"

if [[ -f "${BASENAME}.pdf" ]]; then
  cp "${BASENAME}.pdf" "$OUTPUT"
  echo "==> Fertig: $WORKDIR/$OUTPUT"
else
  echo "[404] ERROR: PDF not found (${BASENAME}.pdf). Please check for more informations: $LOGFILE" >&2
  exit 3
fi

echo
echo "==> Finished!. Last log: ${LOGFILE}:"
tail -n 20 "$LOGFILE" || true
