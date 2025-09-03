#!/usr/bin/env bash
# View on Github: https://github.com/d4niee/tex-pdf-builder
# View on Dockerhub: https://hub.docker.com/repository/docker/dani251/tex-pdf-builder

set -euo pipefail

usage() {
  cat <<EOF
Usage: build-latex [-s main.tex] [-o output.pdf] [-w /workdir] [--latex-opts "..."]
  -s, --source       root .tex file (default: main.tex)
  -o, --output       output file (default: output.pdf) — kann auch außerhalb von WORKDIR liegen
  -w, --workdir      Working directory (default: /work)
      --latex-opts   Additional options for pdflatex (default: "-interaction=nonstopmode -halt-on-error -file-line-error")
Examples:
  docker run --rm -v "\$PWD/latex:/work" IMAGE
  docker run --rm -v "\$PWD/latex:/work" IMAGE -s thesis.tex -o Thesis.pdf
EOF
}

# defaults
SOURCE="main.tex"
OUTPUT="output.pdf"
WORKDIR="/work"
LATEX_OPTS="-interaction=nonstopmode -halt-on-error -file-line-error"

# args
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

# Build passes
pdflatex $LATEX_OPTS "$SOURCE" || true

if [[ -f "${BASENAME}.bcf" ]]; then
  echo "==> Running biber"
  biber "$BASENAME" || true
fi

pdflatex $LATEX_OPTS "$SOURCE" || true
pdflatex $LATEX_OPTS "$SOURCE" || true

# Copy result
if [[ -f "${BASENAME}.pdf" ]]; then
  cp -f "${BASENAME}.pdf" "$OUTPUT"
  echo "==> Fertig: $OUTPUT"
else
  echo "[404] ERROR: PDF not found (${BASENAME}.pdf). Please check log: $LOGFILE" >&2
  exit 3
fi

# -------------------- CLEANUP --------------------
echo
echo "==> Cleaning up LaTeX temp files in $WORKDIR …"

shopt -s nullglob dotglob

CLEAN_GLOBS=(
  "*.aux" "*.log" "*.toc" "*.lof" "*.lot" "*.bbl" "*.blg" "*.out"
  "*.fls" "*.fdb_latexmk" "*.synctex.gz" "*.idx" "*.ind" "*.ilg"
  "*.nav" "*.snm" "*.vrb" "*.dvi" "*.ps" "*.bcf" "*.synctex(busy)"
  "*.run.xml" "*.bbl-SAVE-ERROR" "*.bcf-SAVE-ERROR"
)

removed=0
for g in "${CLEAN_GLOBS[@]}"; do
  for f in $g; do
    if [[ -f "$f" ]]; then
      rm -f -- "$f" && ((removed++)) || true
    fi
  done
done
echo "   -> removed ${removed} temp files"

OUTPUT_BASENAME="$(basename -- "$OUTPUT")"
pdf_removed=0
for f in *.pdf; do
  if [[ "$(basename -- "$f")" != "$OUTPUT_BASENAME" ]]; then
    rm -f -- "$f" && ((pdf_removed++)) || true
  fi
done
echo "   -> removed ${pdf_removed} other PDF(s) in $WORKDIR (kept: ${OUTPUT_BASENAME})"

echo
echo "==> Finished. Tail of ${LOGFILE}:"
tail -n 20 "$LOGFILE" || true
