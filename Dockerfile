FROM ruby:3.3-slim AS base

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    libpq-dev \
    git \
    curl \
    pkg-config \
    autoconf \
    automake \
    libtool \
    libyaml-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile ./

# Generate a fresh lockfile for this platform and install
RUN bundle lock && bundle install --jobs 4

COPY . .

EXPOSE 3000

CMD ["bin/rails", "server", "-b", "0.0.0.0"]
