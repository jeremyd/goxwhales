#!/usr/bin/env ruby

vendorlib = File.expand_path(File.join(File.dirname(File.realpath(__FILE__)), "..", "bundle", "bundler", "setup.rb"))
hardvendor = "/path/to/hardcoded/bundle/bundler/setup.rb"
config_dir = File.expand_path(File.join(File.dirname(File.realpath(__FILE__)), "..", "config")) 
STATIC_ASSETS = File.expand_path(File.join(File.dirname(File.realpath(__FILE__)), "..", "static_assets"))
puts "looking for standalone installed libs in bundle dir: #{vendorlib}"
if File.exists?(vendorlib)
  require vendorlib
elsif File.exists?(hardvendor)
  puts "luckily we have a hardcoded vendor directory for archlinux #{hardvendor}, requiring."
  require hardvendor
else
  puts "FATAL: you must run bundle install --standalone; or could not find the vendor directory #{vendorlib}"
  exit 1
end

require 'btcwhalewatch/whalebot'

require File.join(config_dir, 'whalebot.conf.rb')
include WhalebotConfig
options = get_config


MtGoxClient.supervise_as(:mtgox, options)
#Celluloid::Actor[:mtgox].set_debug(5)

sleep
