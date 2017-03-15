FROM ruby:2.3-alpine

# Default Environment
ENV BUNDLE_PATH /usr/shared/bundle
ENV APP_HOME /usr/src/app
#ENV RAILS_ENV production

# Application Home
RUN mkdir -p $APP_HOME

WORKDIR $APP_HOME

# Requirement
RUN apk add --no-cache \
    tzdata \
    build-base \
    libev \
    pkgconfig \
    bash \
    git

# Setup Gems
ADD Gemfile $APP_HOME/Gemfile
ADD Gemfile.lock $APP_HOME/Gemfile.lock

# Install Dependency
RUN cd $APP_HOME && \
    gem install puma && \
    bundle install --path $BUNDLE_PATH

# Add Application Source Code
ADD . $APP_HOME

# Volumes
VOLUME $APP_HOME
VOLUME $BUNDLE_PATH

EXPOSE 3000

#ENTRYPOINT ["bin/entrypoint"]
CMD ["bundle", "exec", "rackup", "-o", "0.0.0.0", "-p", "3000", "-s", "puma"]

