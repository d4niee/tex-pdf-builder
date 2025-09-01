FROM ubuntu:24.04 AS base

ARG DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8 TEXLIVE_INSTALL_NO_CONTEXT_CACHE=1 NOPERLDOC=1

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl perl fontconfig gpg unzip xz-utils make rsync \
      ghostscript python3 python3-pygments \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

FROM base AS texlive

ARG TL_MIRRORS="https://ftp.fau.de/ctan/systems/texlive/tlnet \
                https://mirror.kumi.systems/ctan/systems/texlive/tlnet \
                https://ctan.ijs.si/tex-archive/systems/texlive/tlnet"

ARG TL_PKGS_EXTRA="kpfonts xurl background epigraph cprotect scalerel glossaries-extra datatool tracklang pifont biblatex-apa"

RUN set -eux; \
  curl -fsSL -o /tmp/install-tl-unx.tar.gz https://mirror.ctan.org/systems/texlive/tlnet/install-tl-unx.tar.gz; \
  mkdir -p /opt/texlive-installer; \
  tar -xzf /tmp/install-tl-unx.tar.gz --strip-components=1 -C /opt/texlive-installer; \
  YEAR="$(date +%Y)"; \
  printf '%s\n' \
    "selected_scheme scheme-full" \
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
    "collection-latexrecommended 1" \
    "collection-latexextra 1" \
    "collection-fontsrecommended 1" \
    "collection-fontsextra 1" \
    "collection-pictures 1" \
    "collection-bibtexextra 1" \
    "collection-langenglish 1" \
    "collection-langgerman 1" \
    "collection-mathscience 1" \
    > /tmp/texlive.profile; \
  /opt/texlive-installer/install-tl -profile /tmp/texlive.profile; \
  ln -s /usr/local/texlive/${YEAR} /usr/local/texlive/current; \
  printf '%s\n' \
    '# add both common arches to PATH so image works on x86_64 and arm64' \
    'export PATH="/usr/local/texlive/current/bin/x86_64-linux:/usr/local/texlive/current/bin/aarch64-linux:$PATH"' \
    > /etc/profile.d/texlive.sh; \
  chmod +x /etc/profile.d/texlive.sh; \
  export PATH="/usr/local/texlive/current/bin/x86_64-linux:/usr/local/texlive/current/bin/aarch64-linux:$PATH"; \
  ok_repo=""; \
  for M in ${TL_MIRRORS}; do \
    echo "Trying TeX Live mirror: $M"; \
    tlmgr option repository "$M" || true; \
    if tlmgr --repository "$M" update --self --all; then ok_repo="$M"; break; fi; \
    echo "Mirror $M failed or outdated, trying next..."; \
  done; \
  test -n "$ok_repo" || (echo 'No valid CTAN mirror found.' >&2; exit 1); \
  failed=""; \
  for P in ${TL_PKGS_EXTRA}; do \
    if ! tlmgr --repository "$ok_repo" install "$P"; then \
      echo "WARN: failed to install $P"; failed="$failed $P"; \
    fi; \
  done; \
  # Caches
  (luaotfload-tool -u || true); \
  CONF="$(find /usr/local/texlive -name texlive-fontconfig.conf | head -1 || true)"; \
  if [ -n "$CONF" ]; then mkdir -p /etc/fonts/conf.d && cp "$CONF" /etc/fonts/conf.d/09-texlive-fonts.conf; fi; \
  fc-cache -fsv || true; \
  # Cleanup
  rm -rf /tmp/install-tl-unx.tar.gz /opt/texlive-installer /tmp/texlive.profile /usr/local/texlive/*/tlpkg/backups; \
  if [ -n "$failed" ]; then echo "The following TL packages failed:${failed}"; fi

FROM texlive AS builder

COPY build-latex.sh /usr/local/bin/build-latex
RUN chmod +x /usr/local/bin/build-latex

WORKDIR /work
ENV PATH="/usr/local/texlive/current/bin/x86_64-linux:/usr/local/texlive/current/bin/aarch64-linux:${PATH}"

ENTRYPOINT ["build-latex"]
