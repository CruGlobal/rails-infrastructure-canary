FROM public.ecr.aws/docker/library/ruby:2.7

LABEL com.datadoghq.ad.logs='[{"source": "ruby"}]'

ARG SIDEKIQ_CREDS

# Add Yarn APT repository.
RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - \
  && echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list

# Install dependencies
RUN apt-get update -qq && apt-get install -y nodejs yarn && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /usr/src/app

COPY Gemfile Gemfile.lock ./

# Install bundler version which created the lock file
RUN gem install bundler -v $(awk '/^BUNDLED WITH/ { getline; print $1; exit }' Gemfile.lock)

# Setup bundler
# throw errors if Gemfile has been modified since Gemfile.lock
RUN bundle config --global frozen 1
RUN bundle config gems.contribsys.com $SIDEKIQ_CREDS

RUN bundle install --jobs 20 --retry 5

COPY . .

RUN bundle exec rake assets:precompile RAILS_ENV=production

VOLUME /usr/src/app/public
VOLUME /usr/src/app/nginx-conf

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
