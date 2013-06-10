#BTC Whale Watch

# What is it?

See the FAQ

# Quickstart

## Requirements

Ruby >= 1.9 or JRuby
Bundler >= 1.3.5

## Using standalone install (recommended)

    git clone http://github.com/jeremyd/goxwhales
    cd goxwhales

    # Ruby
    gem install bundler
    bundle install --standalone
    
    # Jruby
    jruby -S gem install bundler
    jruby -S bundle install --standalone

## Configure

    cp config/config.yml.example config/config.yml

## Running the server

    # Optional set the whale definition.
    export WHALE_IS=49

    # Run server in the foreground
    ruby bin/start_server
    jruby -S bin/start_server

## Open your browser

    firefox http://localhost:1234/

## Logs
    
    logs are in project_root/whales.log
