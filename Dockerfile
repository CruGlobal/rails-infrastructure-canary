FROM public.ecr.aws/docker/library/ruby:2.7-alpine

LABEL com.datadoghq.ad.logs='[{"source": "ruby"}]'

ARG SIDEKIQ_CREDS

# Upgrade alpine packages (useful for security fixes)
RUN apk upgrade --no-cache

# Install rails/app dependencies
RUN apk --no-cache add sqlite-libs tzdata nodejs yarn

WORKDIR /usr/src/app

COPY Gemfile Gemfile.lock ./

# Install bundler version which created the lock file
RUN gem install bundler -v $(awk '/^BUNDLED WITH/ { getline; print $1; exit }' Gemfile.lock)

# Setup bundler
# throw errors if Gemfile has been modified since Gemfile.lock
RUN bundle config --global frozen 1
RUN bundle config gems.contribsys.com $SIDEKIQ_CREDS

# Install build-dependencies, then install gems, subsequently removing build-dependencies
RUN apk --no-cache add --virtual build-deps build-base sqlite-dev \
    && bundle install --jobs 20 --retry 2 \
    && apk del build-deps

# Copy the application
COPY . .

# Compile assets
RUN RAILS_ENV=production bundle exec rake assets:precompile

# Run rails as non-root
RUN addgroup -g 1000 ruby \
    && adduser -u 1000 -G ruby -s /bin/sh -D ruby \
    && chown -R ruby:ruby /usr/src/app
USER ruby

# Define volumes used by ECS to share public html and extra nginx config with nginx container
VOLUME /usr/src/app/public
VOLUME /usr/src/app/nginx-conf

# Command to start rails
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
