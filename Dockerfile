FROM 056154071827.dkr.ecr.us-east-1.amazonaws.com/base-image-ruby-version-arg:2.7-testing
MAINTAINER cru.org <wmd@cru.org>

ARG SIDEKIQ_CREDS
ARG RAILS_ENV=production
#ARG DD_API_KEY
#RUN DD_AGENT_MAJOR_VERSION=7 DD_INSTALL_ONLY=true DD_API_KEY=$DD_API_KEY bash -c "$(curl -L https://raw.githubusercontent.com/DataDog/datadog-agent/master/cmd/agent/install_script.sh)"

# Config for logging to datadog
#COPY docker/datadog-agent /etc/datadog-agent
#COPY docker/supervisord-datadog.conf /etc/supervisor/conf.d/supervisord-datadog.conf
#COPY docker/docker-entrypoint.sh /
COPY Gemfile Gemfile.lock ./

RUN bundle config gems.contribsys.com $SIDEKIQ_CREDS
RUN bundle install --jobs 20 --retry 5 --path vendor

COPY . ./

# I don't know why, but pum binstub creation only works correctly if done after the above COPY
RUN bundle binstub puma sidekiq rake --force

RUN bundle exec rails assets:precompile RAILS_ENV=production

## Run this last to make sure permissions are all correct
RUN mkdir -p \
    /home/app/webapp/tmp \
    /home/app/webapp/db \
    /home/app/webapp/log \
    /home/app/webapp/public/uploads \
  && chmod -R ugo+rw \
    /home/app/webapp/tmp \
    /home/app/webapp/db \
    /home/app/webapp/log \
    /home/app/webapp/public/uploads

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
