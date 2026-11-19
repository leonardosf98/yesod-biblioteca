FROM ubuntu:24.04

RUN apt-get update \
 && apt-get install -y --no-install-recommends libpq5 libgmp10 libffi8 ca-certificates netbase \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --create-home --home-dir /app biblioteca

ENV LANG=C.UTF-8

WORKDIR /app
COPY dist/ /usr/local/bin/
COPY config/settings.yml config/settings.yml

USER biblioteca
EXPOSE 3000
CMD ["biblioteca"]
