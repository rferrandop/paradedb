# The default Postgres major version ParadeDB ships with. In CI, this gets updated to ship builds for all official PGDG versions.
ARG PG_VERSION_MAJOR=17

###############################################
# First Stage: Builder
###############################################

# Note: Debian Bookworm = Debian 12
FROM postgres:${PG_VERSION_MAJOR}-bookworm AS builder

ARG PG_VERSION_MAJOR
ARG RUST_VERSION=stable

# Declare buildtime environment variables
ENV PG_VERSION_MAJOR=${PG_VERSION_MAJOR} \
    RUST_VERSION=${RUST_VERSION}

SHELL ["/bin/bash", "-o", "pipefail", "-c", "-e"]

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
    ca-certificates \
    build-essential \
    gnupg \
    curl \
    git \
    make \
    gcc \
    clang \
    pkg-config \
    libopenblas-dev \
    postgresql-server-dev-all \
    && rm -rf /var/lib/apt/lists/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --default-toolchain "${RUST_VERSION}" -y

ENV PATH="/root/.cargo/bin:$PATH" \
    PGX_HOME=/usr/lib/postgresql/${PG_VERSION_MAJOR}

# Copy Cargo.toml because we need to extract the pgrx version
WORKDIR /tmp
COPY pg_search/Cargo.toml ./

# Install the pgrx version of pg_search and pg_analytics
RUN PGRX_VERSION=$(sed -n 's/^pgrx *= *"=*\([0-9.]*\)"/\1/p' Cargo.toml) && \
    echo "PGRX_VERSION=$PGRX_VERSION" && \
    cargo install --locked cargo-pgrx --version "${PGRX_VERSION}" && \
    cargo pgrx init "--pg${PG_VERSION_MAJOR}=/usr/lib/postgresql/${PG_VERSION_MAJOR}/bin/pg_config" && \
    rm -rf /tmp/Cargo.toml

######################
# pg_search
######################

FROM builder AS builder-pg_search

ARG POSTHOG_API_KEY
ARG POSTHOG_HOST
ARG COMMIT_SHA
ARG PARADEDB_TELEMETRY

# Declare compile-time environment variables
ENV POSTHOG_API_KEY=${POSTHOG_API_KEY} \
    POSTHOG_HOST=${POSTHOG_HOST} \
    COMMIT_SHA=${COMMIT_SHA} \
    PARADEDB_TELEMETRY=${PARADEDB_TELEMETRY}

COPY . /tmp/

# Build the extension
WORKDIR /tmp/pg_search
RUN cargo pgrx package --features icu --pg-config "/usr/lib/postgresql/${PG_VERSION_MAJOR}/bin/pg_config"

######################
# pg_analytics
######################

FROM builder AS builder-pg_analytics

ARG POSTHOG_API_KEY
ARG POSTHOG_HOST
ARG COMMIT_SHA
ARG PARADEDB_TELEMETRY

# Declare compile-time environment variables
ENV POSTHOG_API_KEY=${POSTHOG_API_KEY} \
    POSTHOG_HOST=${POSTHOG_HOST} \
    COMMIT_SHA=${COMMIT_SHA} \
    PARADEDB_TELEMETRY=${PARADEDB_TELEMETRY}

RUN git clone --branch v0.2.3 https://github.com/paradedb/pg_analytics.git /tmp/pg_analytics/

# Build the extension
WORKDIR /tmp/pg_analytics
RUN cargo pgrx package --pg-config "/usr/lib/postgresql/${PG_VERSION_MAJOR}/bin/pg_config"

######################
# pgvector
######################

FROM builder AS builder-pgvector

ARG PG_VERSION_MAJOR
ENV PG_CONFIG=/usr/lib/postgresql/${PG_VERSION_MAJOR}/bin/pg_config

# Build the extension
WORKDIR /tmp
RUN git clone --branch v0.8.0 https://github.com/pgvector/pgvector.git
WORKDIR /tmp/pgvector
RUN export PG_CFLAGS="-Wall -Wextra -Werror -Wno-unused-parameter -Wno-sign-compare" && \
    echo "trusted = true" >> vector.control && \
    make clean -j && \
    make USE_PGXS=1 OPTFLAGS="" -j

######################
# pg_cron
######################

FROM builder AS builder-pg_cron

ARG PG_VERSION_MAJOR
ENV PG_CONFIG=/usr/lib/postgresql/${PG_VERSION_MAJOR}/bin/pg_config

# Build the extension
WORKDIR /tmp
RUN git clone --branch v1.6.4 https://github.com/citusdata/pg_cron.git
WORKDIR /tmp/pg_cron
RUN echo "trusted = true" >> pg_cron.control && \
    make clean -j && \
    make USE_PGXS=1 -j

######################
# pg_ivm
######################

FROM builder AS builder-pg_ivm

ARG PG_VERSION_MAJOR
ENV PG_CONFIG=/usr/lib/postgresql/${PG_VERSION_MAJOR}/bin/pg_config

# Build the extension
WORKDIR /tmp
RUN git clone --branch v1.9 https://github.com/sraoss/pg_ivm.git
WORKDIR /tmp/pg_ivm
RUN echo "trusted = true" >> pg_ivm.control && \
    make clean -j && \
    make USE_PGXS=1 -j

###############################################
# Second Stage: PostgreSQL and Barman Cloud
###############################################

FROM postgres:${PG_VERSION_MAJOR}-bookworm AS paradedb

LABEL maintainer="ParadeDB - https://paradedb.com" \
    org.opencontainers.image.description="ParadeDB - Postgres for Search and Analytics" \
    org.opencontainers.image.source="https://github.com/paradedb/paradedb"

ARG PG_VERSION_MAJOR

# Declare runtime environment variables
ENV PG_VERSION_MAJOR=${PG_VERSION_MAJOR}

SHELL ["/bin/bash", "-o", "pipefail", "-c", "-e"]

# Copy third-party extensions from their builder stages
COPY --from=builder-pgvector /tmp/pgvector/*.so /usr/lib/postgresql/${PG_VERSION_MAJOR}/lib/
COPY --from=builder-pgvector /tmp/pgvector/*.control /usr/share/postgresql/${PG_VERSION_MAJOR}/extension/
COPY --from=builder-pgvector /tmp/pgvector/sql/*.sql /usr/share/postgresql/${PG_VERSION_MAJOR}/extension/
COPY --from=builder-pg_cron /tmp/pg_cron/*.so /usr/lib/postgresql/${PG_VERSION_MAJOR}/lib/
COPY --from=builder-pg_cron /tmp/pg_cron/*.control /usr/share/postgresql/${PG_VERSION_MAJOR}/extension/
COPY --from=builder-pg_cron /tmp/pg_cron/*.sql /usr/share/postgresql/${PG_VERSION_MAJOR}/extension/
COPY --from=builder-pg_ivm /tmp/pg_ivm/*.so /usr/lib/postgresql/${PG_VERSION_MAJOR}/lib/
COPY --from=builder-pg_ivm /tmp/pg_ivm/*.control /usr/share/postgresql/${PG_VERSION_MAJOR}/extension/
COPY --from=builder-pg_ivm /tmp/pg_ivm/*.sql /usr/share/postgresql/${PG_VERSION_MAJOR}/extension/

# Copy the ParadeDB extensions from their builder stages
COPY --from=builder-pg_search /tmp/target/release/pg_search-pg${PG_VERSION_MAJOR}/usr/lib/postgresql/${PG_VERSION_MAJOR}/lib/* /usr/lib/postgresql/${PG_VERSION_MAJOR}/lib/
COPY --from=builder-pg_search /tmp/target/release/pg_search-pg${PG_VERSION_MAJOR}/usr/share/postgresql/${PG_VERSION_MAJOR}/extension/* /usr/share/postgresql/${PG_VERSION_MAJOR}/extension/
COPY --from=builder-pg_analytics /tmp/pg_analytics/target/release/pg_analytics-pg${PG_VERSION_MAJOR}/usr/lib/postgresql/${PG_VERSION_MAJOR}/lib/* /usr/lib/postgresql/${PG_VERSION_MAJOR}/lib/
COPY --from=builder-pg_analytics /tmp/pg_analytics/target/release/pg_analytics-pg${PG_VERSION_MAJOR}/usr/share/postgresql/${PG_VERSION_MAJOR}/extension/* /usr/share/postgresql/${PG_VERSION_MAJOR}/extension/

# Switch to root for configuring runtime dependencies
USER root

# Required for pg_analytics and pg_cron
#
# If a user connects to ParadeDB with the superuser, the DuckDB folder will be created in the user's home directory. If
# the user connects with the postgres user, the DuckDB folder will be created in the /var/lib/postgresql directory. We
# chmod both directories to ensure that DuckDB can write to them no matter which user is used to connect to the database.
RUN mkdir .duckdb/ && chmod -R a+rwX .duckdb/ && \
    mkdir /var/lib/postgresql/.duckdb/ && \
    chmod -R a+rwX /var/lib/postgresql/.duckdb/

# Install Barman Cloud and its dependencies for Azure, Google, and AWS via `pip`, and clean up after the installation to
# minimize the size of the image. These are required for enabling Postgres backups in our CloudNativePG deployments.
RUN apt-get update && \
    apt-get install -y --no-install-recommends libpq5 python3-pip python3-dev python3-psycopg2 && \
    rm /usr/lib/python*/EXTERNALLY-MANAGED && \
    pip3 install --no-cache-dir 'barman[cloud,azure,snappy,google]<3.12' && \
    apt-get remove -y python3-dev python3-pip --purge && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/* && \
    find /usr/lib | grep -E "(/__pycache__$|\.pyc$|\.pyo$)" | xargs rm -rf && \
    find /usr/local | grep -E "(/__pycache__$|\.pyc$|\.pyo$)" | xargs rm -rf && \
    find /var/cache -type f -exec truncate --size 0 {} \; && \
    find /var/log -type f -exec truncate --size 0 {} \;

# Install Postgis and ca-certificates
# ca-certificates required for TLS connection to PostHog (which is used for telemetry) and PostGIS
ENV POSTGIS_VERSION_MAJOR=3
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    postgresql-$PG_VERSION_MAJOR-postgis-$POSTGIS_VERSION_MAJOR \
    postgresql-$PG_VERSION_MAJOR-postgis-$POSTGIS_VERSION_MAJOR-scripts \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* && \
    update-ca-certificates

# The postgresql.conf.sample file is used as a template for the postgresql.conf file, which
# does not exist until the first time the container is started. By adding our settings to the
# postgresql.conf.sample file, we ensure that our settings are applied onto the postgresql.conf file.
#
# The `postgres` database is the default database that exists in every Postgres installation. The pg_cron
# extension requires a database to store its metadata tables. By using `postgres`, we ensure that it has a
# stable, always-available database for its operations, no matter what other databases are created or deleted.
RUN sed -i "s/^#shared_preload_libraries = ''/shared_preload_libraries = 'pg_search,pg_analytics,pg_cron'/" /usr/share/postgresql/postgresql.conf.sample && \
    echo "cron.database_name = 'postgres'" >> /usr/share/postgresql/postgresql.conf.sample

# In order for a user to manually install third party Postgres extensions (e.g. PostGIS, pg_partman, etc.) that ParadeDB does not
# ship with by default, it is necessary to fetch the PostgreSQL APT repository key and add the repository to the list of sources.
# To minimize the burden on the user, we pre-fetch the key and the repository, but do not run `apt-get update` to avoid unnecessarily
# downloading the packages. The user can run `apt-get update` themselves to fetch the package lists and install the desired third party
# extension(s) if/when the time comes. This keeps the image as small as possible for each user's specific use case.
#
# We also uninstall `wget` after adding the PostgreSQL APT repository to the list of sources to minimize the surface area for potential security risks.
RUN apt-get update && \
    apt-get install -y --no-install-recommends wget && \
    echo "deb http://apt.postgresql.org/pub/repos/apt/ bookworm-pgdg main" | tee /etc/apt/sources.list.d/pgdg.list && \
    wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - && \
    apt-get purge -y wget && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

# Switch back to the postgres user, with the new uid
USER postgres

# Copy ParadeDB bootstrap script to install extensions and configure postgresql.conf
COPY ./docker/bootstrap.sh /docker-entrypoint-initdb.d/10_bootstrap_paradedb.sh
