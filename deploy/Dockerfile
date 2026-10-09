# alc-migrate だけの image (Cloud Run job で本番に流す。.github/workflows/migrate.yml)
FROM rust:1.92-bookworm AS build
WORKDIR /src
COPY . .
RUN cargo build --release --locked --features cli --bin alc-migrate

FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/target/release/alc-migrate /usr/local/bin/alc-migrate
ENTRYPOINT ["alc-migrate"]
