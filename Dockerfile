FROM registry.gitlab.com/islandoftex/images/texlive:latest

#RUN apk add --no-cache bash coreutils findutils grep
COPY build-latex.sh /usr/local/bin/build-latex
RUN chmod +x /usr/local/bin/build-latex

WORKDIR /work

ENTRYPOINT ["build-latex"]
