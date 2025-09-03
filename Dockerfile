FROM debian:bookworm-slim AS base

ARG DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8 TEXLIVE_INSTALL_NO_CONTEXT_CACHE=1 NOPERLDOC=1

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl perl fontconfig gpg unzip xz-utils make rsync \
      ghostscript && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

FROM base AS texlive

ARG TL_SCHEME=small
ARG TL_MIRRORS="https://ftp.fau.de/ctan/systems/texlive/tlnet \
                https://mirror.kumi.systems/ctan/systems/texlive/tlnet \
                https://ctan.ijs.si/tex-archive/systems/texlive/tlnet"

# minimum required for running KOMA-Script + biblatex/biber + APA
ARG TL_PKGS_EXTRA="latexmk biblatex biber csquotes babel babel-german microtype \
                   lm kpfonts xurl background epigraph cprotect scalerel nextpage \
                   glossaries-extra datatool tracklang pifont pgf pgfplots xcolor colortbl \
                   pdfpages pdflscape booktabs tabularx multirow threeparttable enumitem \
                   biblatex-apa koma-script xstring bigfoot footmisc \
                   datetime2 datetime2-english datetime2-german babel-english lipsum \
                   collection-latexextra"

RUN set -eu; \
  curl -fsSL -o /tmp/install-tl-unx.tar.gz https://mirror.ctan.org/systems/texlive/tlnet/install-tl-unx.tar.gz; \
  mkdir -p /opt/texlive-installer; \
  tar -xzf /tmp/install-tl-unx.tar.gz --strip-components=1 -C /opt/texlive-installer; \
  YEAR="$(date +%Y)"; \
  printf '%s\n' \
    "selected_scheme scheme-${TL_SCHEME}" \
    "TEXDIR /usr/local/texlive/${YEAR}" \
    "TEXMFCONFIG ~/.texlive/${YEAR}/texmf-config" \
    "TEXMFVAR ~/.texlive/${YEAR}/texmf-var" \
    "TEXMFHOME ~/texmf" \
    "TEXMFLOCAL /usr/local/texlive/texmf-local" \
    "TEXMFSYSCONFIG /usr/local/texlive/${YEAR}/texmf-config" \
    "TEXMFSYSVAR /usr/local/texlive/${YEAR}/texmf-var" \
    "tlpdbopt_autobackup 0" \
    "tlpdbopt_install_docfiles 0" \
    "tlpdbopt_install_srcfiles 0" \
    > /tmp/texlive.profile; \
  /opt/texlive-installer/install-tl -profile /tmp/texlive.profile; \
  ln -s /usr/local/texlive/${YEAR} /usr/local/texlive/current; \
  echo 'export PATH="/usr/local/texlive/current/bin/x86_64-linux:/usr/local/texlive/current/bin/aarch64-linux:$PATH"' > /etc/profile.d/texlive.sh; \
  chmod +x /etc/profile.d/texlive.sh; \
  export PATH="/usr/local/texlive/current/bin/x86_64-linux:/usr/local/texlive/current/bin/aarch64-linux:$PATH"; \
  \
  TLMGR_OPTS="--verify-repo=none --persistent-downloads"; \
  ok_repo=""; \
  for M in ${TL_MIRRORS}; do \
    echo "Trying TeX Live repo: $M"; \
    tlmgr $TLMGR_OPTS option repository "$M" || true; \
    if tlmgr $TLMGR_OPTS --repository "$M" update --self; then \
      ok_repo="$M"; echo "Using repository: $ok_repo"; break; \
    fi; \
  done; \
  test -n "$ok_repo"; \
  tlmgr $TLMGR_OPTS --repository "$ok_repo" update --all || true; \
  \
  echo "Installing extra TL packages (non-fatal batch)…"; \
  tlmgr $TLMGR_OPTS --repository "$ok_repo" install ${TL_PKGS_EXTRA} || true; \
  \
critical_pkgs="latexmk biblatex biber csquotes microtype \
               babel babel-english babel-german \
               biblatex-apa koma-script xstring \
               datetime2 datetime2-english datetime2-german \
               lm kpfonts xurl background epigraph cprotect scalerel nextpage \
               glossaries-extra datatool tracklang pgf pgfplots xcolor colortbl \
               pdfpages pdflscape booktabs tabularx multirow threeparttable enumitem pifont"; \
  for P in $critical_pkgs; do \
    if ! tlmgr info --only-installed "$P" >/dev/null 2>&1; then \
      echo "Missing critical package '$P' → retry install…"; \
      tlmgr $TLMGR_OPTS --repository "$ok_repo" install --reinstall "$P" || true; \
      tlmgr info --only-installed "$P" >/dev/null 2>&1 || { echo "ERROR: package '$P' still missing"; exit 1; }; \
    fi; \
  done; \
  \
  echo "Refreshing filename database and font maps…"; \
  mktexlsr || true; \
  updmap-sys --syncwithtrees || true; \
  (luaotfload-tool -u || true); \
  CONF="$(find /usr/local/texlive -name texlive-fontconfig.conf | head -1 || true)"; \
  if [ -n "$CONF" ]; then mkdir -p /etc/fonts/conf.d && cp "$CONF" /etc/fonts/conf.d/09-texlive-fonts.conf; fi; \
  fc-cache -fsv || true; \
  rm -rf /tmp/install-tl-unx.tar.gz /opt/texlive-installer /tmp/texlive.profile /usr/local/texlive/*/tlpkg/backups

FROM texlive AS builder

COPY build-latex.sh /usr/local/bin/build-latex
RUN chmod +x /usr/local/bin/build-latex

WORKDIR /work
ENV PATH="/usr/local/texlive/current/bin/x86_64-linux:/usr/local/texlive/current/bin/aarch64-linux:${PATH}"

ENTRYPOINT ["build-latex"]
