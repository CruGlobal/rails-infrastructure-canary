# RUBY_VERSION set by build.sh based on .ruby-version file
ARG RUBY_VERSION
FROM public.ecr.aws/docker/library/ruby:${RUBY_VERSION}-alpine

# DataDog logs source
LABEL com.datadoghq.ad.logs='[{"source": "ruby"}]'

# Create web application user to run as non-root
RUN addgroup -g 1000 webapp \
    && adduser -u 1000 -G webapp -s /bin/sh -D webapp \
    && mkdir -p /home/webapp/app
WORKDIR /home/webapp/app

# Upgrade alpine packages (useful for security fixes)
RUN apk upgrade --no-cache

# Install rails/app dependencies
RUN apk --no-cache add sqlite-libs tzdata vips jemalloc

ENV LD_PRELOAD="/usr/lib/libjemalloc.so.2"

# Copy dependency definitions and lock files
COPY Gemfile Gemfile.lock .ruby-version ./

# Install bundler version which created the lock file
RUN gem install bundler -v $(awk '/^BUNDLED WITH/ { getline; print $1; exit }' Gemfile.lock)

# Install build-dependencies, then install gems, subsequently removing build-dependencies
# The Sidekiq Pro login comes in as the sidekiq_creds BuildKit secret (see build.sh), and
# bundler reads it from BUNDLE_GEMS__CONTRIBSYS__COM during this RUN only, so it is not
# saved in the image history. Bundler names its index cache folder under /root/.bundle after
# the source URL, username included, so that folder is removed in the same RUN.
RUN --mount=type=secret,id=sidekiq_creds,env=BUNDLE_GEMS__CONTRIBSYS__COM \
    apk --no-cache add --virtual build-deps build-base sqlite-dev yaml-dev \
    && bundle install --jobs 20 --retry 2 \
    && rm -rf /root/.bundle \
    && apk del build-deps

# Copy the application
COPY . .

# Environment required to build the application
ARG RAILS_ENV=production

# Compile assets and fix permissions
# Precompile bootsnap code in the same RUN as the chown; in an earlier layer
# the chown would store a second copy of the cache.
RUN bundle exec bootsnap precompile --gemfile app/ lib/ \
    && RAILS_ENV=production bundle exec rake assets:precompile \
    && chown -R webapp:webapp /home/webapp/

# Define volumes used by ECS to share public html and extra nginx config with nginx container
VOLUME /home/webapp/app/public
VOLUME /home/webapp/app/nginx-conf

# Run container process as non-root user
USER webapp

# Thruster fronts Puma (HTTP caching/compression + static file serving) on its
# default port 80, proxying to Puma on 3000 — the fl-pos-admin fleet pattern.
# While the nginx sidecar still exists it proxies straight to Puma:3000
# (Thruster sits idle); after the cru-terraform nginx removal the ALB points
# at this container on 80.
EXPOSE 80

# Thruster request logs (default on) would interleave a Go slog JSON stream into the
# same stdout as the app's structured Ougai/lograge logs (Datadog pipeline is keyed on
# that format) and re-log the silenced health checks; request logging is lograge's job.
ENV LOG_REQUESTS="false"

# Start server via Thruster by default, this can be overwritten at runtime
CMD ["./bin/thrust", "./bin/rails", "server"]
