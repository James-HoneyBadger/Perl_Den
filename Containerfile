FROM debian:trixie-slim

LABEL org.opencontainers.image.title="PerlDen CLI"
LABEL org.opencontainers.image.description="PerlDen toolkit packaged for CLI usage"
LABEL org.opencontainers.image.source="https://github.com/James-HoneyBadger/Perl_Den"
LABEL org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive
ENV PERL5LIB=/opt/perlden/lib
WORKDIR /opt/perlden

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        perl \
        libyaml-libyaml-perl \
        libjson-pp-perl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY . /opt/perlden

ENTRYPOINT ["perl", "/opt/perlden/bin/perlden-cli"]
CMD ["help"]