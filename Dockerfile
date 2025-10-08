# syntax=docker/dockerfile:1.7
###############################################################################
# TeX Live builder image (multi-arch friendly: works on amd64 and arm64)
# - Base: Debian bookworm-slim (multi-arch official image)
# - Installs TeX Live via rsync + install-tl (full scheme by default)
# - Generates optional caches (fontconfig, luaotfload, ConTeXt)
# - Provides a simple entrypoint script `build-latex`
#
# Notes:
# * This Dockerfile is intentionally verbose and heavily commented to ease
#   maintenance/debugging when mirrors, packages or TeX Live internals change.
# * Multi-arch SUPPORT is provided by:
#   - Using a multi-arch base image (Debian).
#   - Installing TeX Live from the official installer (which provides arch-
#     specific binaries for linux/amd64 (x86_64-linux) and linux/arm64 (aarch64-linux)).
#   - Setting PATH to include both potential bin directories for safety.
# * To actually PUBLISH a multi-arch image to your registry, you MUST build with
#   `docker buildx build --platform linux/amd64,linux/arm64 --push ...`
###############################################################################

############################
# Global build-time args
############################
ARG GENERATE_CACHES=yes             # Generate font caches & ConTeXt formats to speed up first runs
ARG DOCFILES=no                     # Include TeX doc files (larger image). "yes" or "no"
ARG SRCFILES=no                     # Include TeX source files (larger image). "yes" or "no"
ARG TL_SCHEME=full                  # TeX Live scheme (e.g., full / small / basic / medium)
# Fast German mirror via rsync; change if unavailable in your environment:
ARG TLMIRRORURL=rsync://rsync.dante.ctan.org/CTAN/systems/texlive/tlnet/

############################
# Base stage
############################
FROM debian:bookworm-slim AS base

# Enable non-interactive apt operations
ENV DEBIAN_FRONTEND=noninteractive

# Work in /tmp while preparing the toolchain
WORKDIR /tmp

# -----------------------------------------------------------------------------
# Install base tools:
# - ca-certificates, curl, rsync: fetching mirrors / data
# - gpg, gpg-agent: signature checks (if needed)
# - fontconfig: needed for font cache generation
# - python3 + pygments: pygmentize (often used in LaTeX listings)
# - perl, xz-utils, unzip: required by TeX Live installer/scripts
# -----------------------------------------------------------------------------
RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl rsync gpg gpg-agent \
      fontconfig python3 python3-pygments \
      perl xz-utils unzip \
    && rm -rf /var/lib/apt/lists/*

############################
# TeX Live stage (install TL)
############################
FROM base AS texlive

# -----------------------------------------------------------------------------
# Create a dummy "texlive-local" package using equivs
# Why: This convinces dpkg/apt that TeX Live is "present", which prevents
# accidental apt installations from pulling distro TeX packages that could
# conflict with our installer-based TL. The example file is versioned (2023);
# we bump it to a high value so it always "wins".
# If tug.org changes paths/names, update the URL below.
# -----------------------------------------------------------------------------
RUN curl -fsSL https://tug.org/texlive/files/debian-equivs-2023-ex.txt -o texlive-local \
 && sed -i "s/2023/9999/" texlive-local \
 && apt-get update && apt-get install -qy --no-install-recommends equivs \
 && equivs-build texlive-local \
 && dpkg -i texlive-local_9999.99999999-1_all.deb || apt-get -qyf install \
 && rm -rf ./*texlive* \
 && apt-get remove -y --purge equivs \
 && apt-get autoremove -qy --purge \
 && rm -rf /var/lib/apt/lists/* && apt-get clean

# -----------------------------------------------------------------------------
# Mirror TeX Live installer tree via rsync and run install-tl with a profile.
# Notes:
#  - TL_SCHEME controls the size/features. "full" is large but hassle-free.
#  - DOCFILES/SRCFILES can be disabled to reduce image size.
#  - The installer will auto-detect the CPU arch and place binaries under
#    /usr/local/texlive/<year>/bin/<arch>, e.g.:
#      - x86_64-linux  (for linux/amd64)
#      - aarch64-linux (for linux/arm64)
# -----------------------------------------------------------------------------
RUN echo "Fetching installation from mirror ${TLMIRRORURL}" \
 && rsync -a --stats "${TLMIRRORURL}" texlive \
 && cd texlive \
 && echo "Building with documentation: ${DOCFILES}" \
 && echo "Building with sources: ${SRCFILES}" \
 && echo "Building with scheme: ${TL_SCHEME}" \
 && printf "selected_scheme scheme-%s\n" "${TL_SCHEME}" > install.profile \
 && if [ "${DOCFILES}" = "no" ]; then \
        echo "tlpdbopt_install_docfiles 0" >> install.profile && \
        echo "BUILD: Disabling documentation files"; \
    fi \
 && if [ "${SRCFILES}" = "no" ]; then \
        echo "tlpdbopt_install_srcfiles 0" >> install.profile && \
        echo "BUILD: Disabling source files"; \
    fi \
 && echo "tlpdbopt_autobackup 0" >> install.profile \
 && echo "tlpdbopt_sys_bin /usr/bin" >> install.profile \
 && ./install-tl -profile install.profile \
 && cd .. && rm -rf texlive

# After installation, switch to a clean working directory
WORKDIR /workdir

# -----------------------------------------------------------------------------
# Post-install steps:
# - Ensure TL bin dir is on PATH via tlmgr "path add" (symlinks).
# - If using a pretest mirror, pin repository.
# - Patch mtxrun.lua (ConTeXt) selfpath handling for robustness (non-fatal).
# - Optionally generate caches (fontconfig, luaotfload) & ConTeXt formats.
#   These speed up first-time runs inside CI/containers.
# -----------------------------------------------------------------------------
RUN echo "Set PATH to ${PATH}" \
 && "$(/usr/bin/find /usr/local/texlive -name tlmgr | head -n1)" path add \
 && if [ "${TLMIRRORURL#*pretest}" != "${TLMIRRORURL}" ]; then \
        tlmgr option repository "${TLMIRRORURL}"; \
    fi \
 && (sed -i '/package.loaded\["data-ini"\]/a if os.selfpath then environment.ownbin=lfs.symlinktarget(os.selfpath..io.fileseparator..os.selfname);environment.ownpath=environment.ownbin:match("^.*"..io.fileseparator) else environment.ownpath=kpse.new("luatex"):var_value("SELFAUTOLOC");environment.ownbin=environment.ownpath..io.fileseparator..(arg[-2] or arg[-1] or arg[0] or "luatex"):match("[^"..io.fileseparator.."]*$") end' /usr/bin/mtxrun.lua || true) \
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

# -----------------------------------------------------------------------------
# Non-fatal sanity checks:
# - Try to run versions of commonly used tools to catch missing binaries early.
# - Note: Some tools (e.g., xindy) may not be available on all arches/years.
# -----------------------------------------------------------------------------
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
    if command -v context >/dev/null 2>&1; then \
      context --luatex --version >/dev/null 2>&1 || warn "context --luatex --version failed"; \
    fi; \
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

############################
# Final stage (builder)
############################
FROM texlive AS builder

# Copy your build script into PATH
COPY build-latex.sh /usr/local/bin/build-latex
RUN chmod +x /usr/local/bin/build-latex

WORKDIR /work

# -----------------------------------------------------------------------------
# PATH for TeX Live binaries:
# - We include both x86_64-linux (amd64) and aarch64-linux (arm64) in PATH.
#   Only one will exist at runtime, but this makes the image portable across
#   arches without extra logic. tlmgr "path add" above also created symlinks.
# -----------------------------------------------------------------------------
ENV PATH="/usr/local/texlive/current/bin/x86_64-linux:/usr/local/texlive/current/bin/aarch64-linux:${PATH}"

# Example (keep here as doc):
# docker run --rm -v "latex:/work" dani251/tex-pdf-builder:latest -s thesis.tex -o Thesis.pdf
# docker run --rm -u "$(id -u):$(id -g)" -v "latex:/work" dani251/tex-pdf-builder:latest -s main.tex -o Lambrecht_Masterarbeit.pdf

# Entrypoint: run the LaTeX build wrapper
ENTRYPOINT ["build-latex"]

# OCI labels for provenance
LABEL org.opencontainers.image.authors="tex-pdf-builder" \
      org.opencontainers.image.url="https://github.com/d4niee/tex-pdf-builder" \
      org.opencontainers.image.source="https://github.com/d4niee/tex-pdf-builder/blob/main/Dockerfile"
