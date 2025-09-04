FROM debian:bookworm-slim AS base

ARG GENERATE_CACHES=yes
ARG DOCFILES=no
ARG SRCFILES=no
ARG TL_SCHEME=full
ARG TLMIRRORURL=rsync://rsync.dante.ctan.org/CTAN/systems/texlive/tlnet/

ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /tmp

# Basis-Tools
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl rsync gpg gpg-agent \
      fontconfig python3 python3-pygments \
      perl xz-utils unzip \
  && rm -rf /var/lib/apt/lists/*


FROM base AS texlive

# Dummy-Paket "texlive-local" mit equivs
RUN curl -fsSL https://tug.org/texlive/files/debian-equivs-2023-ex.txt -o texlive-local \
 && sed -i "s/2023/9999/" texlive-local \
 && apt-get update && apt-get install -qy --no-install-recommends equivs \
 && equivs-build texlive-local \
 && dpkg -i texlive-local_9999.99999999-1_all.deb || apt-get -qyf install \
 && rm -rf ./*texlive* \
 && apt-get remove -y --purge equivs \
 && apt-get autoremove -qy --purge \
 && rm -rf /var/lib/apt/lists/* && apt-get clean

# TeX Live via rsync spiegeln und per Profile installieren
RUN echo "Fetching installation from mirror ${TLMIRRORURL}" \
 && rsync -a --stats "${TLMIRRORURL}" texlive \
 && cd texlive \
 && echo "Building with documentation: ${DOCFILES}" \
 && echo "Building with sources: ${SRCFILES}" \
 && echo "Building with scheme: ${TL_SCHEME}" \
 && printf "selected_scheme scheme-%s\n" "${TL_SCHEME}" > install.profile \
 && if [ "${DOCFILES}" = "no" ]; then \
        echo "tlpdbopt_install_docfiles 0" >> install.profile \
        && echo "BUILD: Disabling documentation files"; \
    fi \
 && if [ "${SRCFILES}" = "no" ]; then \
        echo "tlpdbopt_install_srcfiles 0" >> install.profile \
        && echo "BUILD: Disabling source files"; \
    fi \
 && echo "tlpdbopt_autobackup 0" >> install.profile \
 && echo "tlpdbopt_sys_bin /usr/bin" >> install.profile \
 && ./install-tl -profile install.profile \
 && cd .. && rm -rf texlive

WORKDIR /workdir

RUN echo "Set PATH to ${PATH}" \
 && "$(/usr/bin/find /usr/local/texlive -name tlmgr | head -n1)" path add \
 && if [ "${TLMIRRORURL#*pretest}" != "${TLMIRRORURL}" ]; then \
        tlmgr option repository "${TLMIRRORURL}"; \
    fi \
 && (sed -i '/package.loaded\["data-ini"\]/a if os.selfpath then environment.ownbin=lfs.symlinktarget(os.selfpath..io.fileseparator..os.selfname);environment.ownpath=environment.ownbin:match("^.*"..io.fileseparator) else environment.ownpath=kpse.new("luatex"):var_value("SELFAUTOLOC");environment.ownbin=environment.ownpath..io.fileseparator..(arg[-2] or arg[-1] or arg[0] or "luatex"):match("[^"..io.fileseparator.."]*$") end' /usr/bin/mtxrun.lua || true) \
 # Optionale Cache-/ConTeXt-Generierung
 && if [ "${GENERATE_CACHES}" = "yes" ]; then \
        echo "Generating caches and ConTeXt files" \
        && (luaotfload-tool -u || true) \
        && (cp "$(/usr/bin/find /usr/local/texlive -name texlive-fontconfig.conf | head -n1)" /etc/fonts/conf.d/09-texlive-fonts.conf || true) \
        && fc-cache -fsv \
        && if [ -f "/usr/bin/context" ]; then \
              mtxrun --generate \
              && texlua /usr/bin/mtxrun.lua --luatex --generate \
              && context --make \
              && context --luatex --make; \
           fi; \
    else \
        echo "Not generating caches or ConTeXt files"; \
    fi

RUN echo "== Sanity check (non-fatal) =="; \
  warn(){ printf 'WARNING: %s\n' "$*"; }; \
  if [ "${TL_SCHEME:-}" = "full" ]; then \
    for cmd in latex biber xindy arara context asy; do \
      if command -v "$cmd" >/dev/null 2>&1; then \
        "$cmd" --version >/dev/null 2>&1 || warn "$cmd --version failed"; \
      else \
        warn "command '$cmd' not found in PATH"; \
      fi; \
      printf '\n'; \
    done; \
    # extra: context luatex
    if command -v context >/dev/null 2>&1; then \
      context --luatex --version >/dev/null 2>&1 || warn "context --luatex --version failed"; \
    fi; \
    # optionale Checks
    if [ "${DOCFILES:-}" = "yes" ]; then \
      texdoc -l geometry >/dev/null 2>&1 || warn "texdoc geometry lookup failed"; \
    fi; \
    if [ "${SRCFILES:-}" = "yes" ]; then \
      kpsewhich amsmath.dtx >/dev/null 2>&1 || warn "kpsewhich amsmath.dtx not found"; \
    fi; \
  fi; \
  (python3 --version >/dev/null 2>&1 || warn "python3 not found"); printf '\n'; \
  (pygmentize -V   >/dev/null 2>&1 || warn "pygmentize not found"); printf '\n'; \
  true


FROM texlive AS builder

COPY build-latex.sh /usr/local/bin/build-latex
RUN chmod +x /usr/local/bin/build-latex

WORKDIR /work
ENV PATH="/usr/local/texlive/current/bin/x86_64-linux:/usr/local/texlive/current/bin/aarch64-linux:${PATH}"

# Custom Source und Output
#docker run --rm -v "latex:/work" dani251/tex-pdf-builder:latest -s thesis.tex -o Thesis.pdf
#docker run --rm -u "$(id -u):$(id -g)" -v "latex:/work" dani251/tex-pdf-builder:latest -s main.tex -o Lambrecht_Masterarbeit.pdf
ENTRYPOINT ["build-latex"]

LABEL org.opencontainers.image.authors="tex-pdf-builder" \
      org.opencontainers.image.url="https://github.com/d4niee/tex-pdf-builder" \
      org.opencontainers.image.source="https://github.com/d4niee/tex-pdf-builder/blob/main/Dockerfile"
