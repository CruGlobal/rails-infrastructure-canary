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
RUN apk --no-cache add sqlite-libs tzdata jemalloc

ENV LD_PRELOAD="/usr/lib/libjemalloc.so.2"

# Copy dependency definitions and lock files
COPY Gemfile Gemfile.lock .ruby-version ./

# Install bundler version which created the lock file and configure it
ARG SIDEKIQ_CREDS
RUN gem install bundler -v $(awk '/^BUNDLED WITH/ { getline; print $1; exit }' Gemfile.lock) \
    && bundle config --global gems.contribsys.com $SIDEKIQ_CREDS

# Install build-dependencies, then install gems, subsequently removing build-dependencies
RUN apk --no-cache add --virtual build-deps build-base sqlite-dev yaml-dev \
    && bundle install --jobs 20 --retry 2 \
    && apk del build-deps

# Copy the application
COPY . .

# Environment required to build the application
ARG RAILS_ENV=production

# Compile assets and fix permissions
RUN RAILS_ENV=production bundle exec rake assets:precompile \
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
