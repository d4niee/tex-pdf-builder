# tex-pdf-builder
Image to build latex with thre recipe: pdflatex -> biber pdflatex * 2

latex to PDF image Dockerhub: https://hub.docker.com/r/dani251/tex-pdf-builder

Usage: 
```
build-latex [-s main.tex] [-o output.pdf] [-w /workdir] [--latex-opts "..."]
  -s, --source       Root .tex file (default: main.tex)
  -o, --output       output file (default: output.pdf)
  -w, --workdir      Working directory inside the container (default: /work)
      --latex-opts   Additional options for pdflatex (e.g., “-interaction=nonstopmode”)
```
Examples:
```
  docker run --rm -v "\$PWD/latex:/work" IMAGE
  docker run --rm -v "\$PWD/latex:/work" IMAGE -s thesis.tex -o Thesis.pdf
```
