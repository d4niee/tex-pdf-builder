#!/usr/bin/env bash
# View on Github: https://github.com/d4niee/tex-pdf-builder
# View on Dockerhub: https://hub.docker.com/repository/docker/dani251/tex-pdf-builder

set -euo pipefail

usage() {
  cat <<'EOF'
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
EOF
}

# defaults
SOURCE="main.tex"
OUTPUT="output.pdf"
WORKDIR="/work"
LATEX_OPTS="-interaction=nonstopmode -halt-on-error -file-line-error"
LATEXMK_OPTS="-synctex=1"
RECIPE="pdflatex"
FINAL_CLEAN=false
FINAL_CLEAN_DIR=""

# args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--source) SOURCE="$2"; shift 2;;
    -o|--output) OUTPUT="$2"; shift 2;;
    -w|--workdir) WORKDIR="$2"; shift 2;;
    --latex-opts) LATEX_OPTS="$2"; shift 2;;
    --latexmk-opts) LATEXMK_OPTS="$2"; shift 2;;
    -r|--recipe) RECIPE="$2"; shift 2;;
    -C|--final-clean) FINAL_CLEAN=true; shift;;
    --final-clean-dir) FINAL_CLEAN_DIR="$2"; shift 2;;
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
echo "==> Recipe : $RECIPE"
echo "==> LaTeX opts: $LATEX_OPTS"
echo

build_pdflatex() {
  pdflatex $LATEX_OPTS "$SOURCE"
  if [[ -f "${BASENAME}.bcf" ]]; then
    echo "==> Running biber"
    biber "$BASENAME"
  fi
  pdflatex $LATEX_OPTS "$SOURCE"
  pdflatex $LATEX_OPTS "$SOURCE"
}

build_latexmk_engine() {
  local engine_flag="$1"   # -xelatex | -lualatex
  # sauber starten, aber Fehler ignorieren falls nix da
  latexmk -C >/dev/null 2>&1 || true
  # erster Lauf
  latexmk $engine_flag -latexoption="$LATEX_OPTS" $LATEXMK_OPTS "$SOURCE"
  # robuster Biber-Fallback: falls LaTeX um Biber bittet, nachholen & erneut bauen
  if grep -q "Please (re)run Biber" "$LOGFILE" 2>/dev/null; then
    echo "==> latexmk requested biber — running biber + rebuild"
    biber "$BASENAME" || true
    latexmk $engine_flag -latexoption="$LATEX_OPTS" $LATEXMK_OPTS "$SOURCE"
  fi
  # final noch einmal bauen
  latexmk $engine_flag -latexoption="$LATEX_OPTS" $LATEXMK_OPTS "$SOURCE"
}

case "$RECIPE" in
  pdflatex)
    build_pdflatex
    ;;
  latexmk-xelatex|xelatex)
    build_latexmk_engine -xelatex
    ;;
  latexmk-lualatex|lualatex)
    build_latexmk_engine -lualatex
    ;;
  *)
    echo "[400] ERROR: unknown recipe '$RECIPE' (use: pdflatex | latexmk-xelatex | latexmk-lualatex)" >&2
    exit 4
    ;;
esac

# Copy result
if [[ -f "${BASENAME}.pdf" ]]; then
  cp -f "${BASENAME}.pdf" "$OUTPUT"
  echo "==> Fertig: $OUTPUT"
else
  echo "[404] ERROR: PDF not found (${BASENAME}.pdf). Please check log: $LOGFILE" >&2
  exit 3
fi

echo
echo "==> Finished. Tail of ${LOGFILE}:"
tail -n 40 "$LOGFILE" || true

# -------------------- OPTIONAL FINAL CLEAN (beliebiges Zielverzeichnis) --------------------
if [[ "$FINAL_CLEAN" == true ]]; then
  TARGET_DIR="${FINAL_CLEAN_DIR:-$WORKDIR}"
  echo
  echo "==> Final cleanup in ${TARGET_DIR} …"
  shopt -s nullglob dotglob
  FINAL_GLOBS=(
    "*.aux" "*.log" "*.toc" "*.lof" "*.lot" "*.bbl" "*.blg" "*.out"
    "*.fls" "*.fdb_latexmk" "*.synctex.gz" "*.idx" "*.ind" "*.ilg"
    "*.nav" "*.snm" "*.vrb" "*.dvi" "*.ps" "*.bcf" "*.synctex(busy)"
    "*.run.xml" "*.bbl-SAVE-ERROR" "*.bcf-SAVE-ERROR"
  )
  final_removed=0
  for g in "${FINAL_GLOBS[@]}"; do
    for f in "${TARGET_DIR}"/$g; do
      [[ -f "$f" ]] && rm -f -- "$f" && ((final_removed++)) || true
    done
  done
  echo "   -> removed ${final_removed} temp files in ${TARGET_DIR}"
fi
