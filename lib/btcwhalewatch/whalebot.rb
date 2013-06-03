require 'cinch'
require 'cinch/plugins/identify'
require 'btcwhalewatch/mtgox_client_only_action.rb'

# This module is broken out in order to do TDD without connecting to IRC.
# We can test these methods in isolation.
module WhalebotMethods
  def initialize(*args)
    super_result = super
    startup
    super_result
  end

  def startup
  end
  
  def whales(message)
    broadcast(Celluloid::Actor[:mtgox].dumptotal)
  end

  def help(message)
    broadcast("available commands: ;;whales - display sum of 15 minute activity")
  end

  def broadcast(message)
    bot.channels.each do |chan|
      chan.msg message
    end
  end
end

class Whalebot
  include Cinch::Plugin
  include WhalebotMethods

  #listen_to :connect, method: :refresh_watches

  #
  ## Routing of matches
  #
  match /^;;whales$/, :method => :whales, :use_prefix => false, :use_suffix => false
  match /^;;help$/, :method => :help, :use_prefix => false, :use_suffix => false
end
