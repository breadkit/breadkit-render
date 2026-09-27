FROM ruby:4.0-slim-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential ca-certificates git librsvg2-bin fonts-noto-cjk fontconfig \
    && rm -rf /var/lib/apt/lists/*

COPY breadkit/ /opt/breadkit/
COPY breadkit-render/ /opt/breadkit-render/
WORKDIR /opt/breadkit-render

RUN printf "source 'https://rubygems.org'\ngem 'breadkit', path: '/opt/breadkit'\ngem 'breadkit-render', path: '/opt/breadkit-render'\n" > Gemfile.container \
    && BUNDLE_GEMFILE=/opt/breadkit-render/Gemfile.container bundle install \
    && BUNDLE_GEMFILE=/opt/breadkit-render/Gemfile.container bundle exec ruby exe/bkrender --version \
    && fc-match 'Noto Sans CJK JP' \
    && printf 'board :mini\n' > /tmp/smoke.bk.rb \
    && BUNDLE_GEMFILE=/opt/breadkit-render/Gemfile.container bundle exec ruby exe/bkrender /tmp/smoke.bk.rb -o /tmp/smoke.png \
    && ruby -e 'abort "PNG smoke check failed" unless File.binread("/tmp/smoke.png").start_with?("\x89PNG".b)'

ENV BUNDLE_GEMFILE=/opt/breadkit-render/Gemfile.container
WORKDIR /work
ENTRYPOINT ["bundle", "exec", "ruby", "/opt/breadkit-render/exe/bkrender"]
