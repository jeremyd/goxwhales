require 'celluloid/websocket/client'
require 'json'
require 'logger'
require 'time'

class MtGoxClient
  include Celluloid
  include Celluloid::Logger

  def initialize
    @whale_is = 49
    @whales = []
    Celluloid.logger = ::Logger.new("whale.log")

# FULL DEPTH MORE THAN 5x per hour will get you banned!

#    depth_response = Celluloid::Http.get('http://data.mtgox.com/api/2/BTCUSD/money/depth/full')
#    full_depth = JSON::parse(depth_response.body)
#    add_message("got full depth")
#    #binding.pry
#
#    full_depth["data"]["asks"].each do |ask|
#      if ask["amount"].to_f > @whale_is 
#        @whales << [ ask["price"], ask["amount"], "ask" ]
#      end
#    end
#
#    full_depth["data"]["bids"].each do |bid|
#      if bid["amount"].to_f > @whale_is 
#        @whales << [ bid["price"], bid["amount"], "bid" ]
#      end
#    end
#
#    add_message("discovered #{@whales.size} whales lurking in the full_depth")

    @client = Celluloid::WebSocket::Client.new("ws://websocket.mtgox.com/mtgox?Channel=trades,ticker,depth", current_actor, :headers => { "Origin" => "ws://websocket.mtgox.com:80" })

  end

  def on_open
    debug("websocket connection opened")
  end

  def calc_whales_above
    @high_whales = []
    @high_whales_weight = 0.0
    @whales.each do |whale|
      if whale[0].to_f > @ticker_buy.to_f
        @high_whales << whale
        @high_whales_weight += (whale[0].to_f * whale[1].to_f)
      end
    end
    @high_whales.size
  end

  def calc_whales_below
    @low_whales = []
    @low_whales_weight = 0.0
    @whales.each do |whale|
      if whale[0].to_f < @ticker_buy.to_f
        @low_whales << whale
        @low_whales_weight += (whale[0].to_f * whale[1].to_f)
      end
    end
    @low_whales.size
  end

  # if the whale is within 5$ of the ticker, he's ready to blow
  def calc_ready_whales_below
    @ready_low_whales = []
    @ready_low_whales_weight = 0.0
    @low_whales.each do |whale|
      if whale[0].to_f > (@ticker_buy.to_f - 10)
        @ready_low_whales << whale
        @ready_low_whales_weight += (whale[0].to_f * whale[1].to_f)
      end
    end
    @ready_low_whales.size
  end

  # if the whale is within 5$ of the ticker, he's ready to blow
  def calc_ready_whales_above
    @ready_high_whales = []
    @ready_high_whales_weight = 0.0
    @high_whales.each do |whale|
      if whale[0].to_f < (@ticker_buy.to_f + 10)
        @ready_high_whales << whale
        @ready_high_whales_weight += (whale[0].to_f * whale[1].to_f)
      end
    end
    @ready_high_whales.size
  end

  def display_whales
    above = calc_whales_above
    below = calc_whales_below
    ready_above = calc_ready_whales_above
    ready_below = calc_ready_whales_below

    @nodelist ||= []

    # display low whales with weight being their y axis (fatty)
    @nodelist << {
        "id" => "#{@ready_low_whales.size} whales: #{@ready_low_whales_weight.round.to_s}$",
        "state" => "low",
        "x" => "120",
        "y" => "60",
        "xx" => "200",
        "yy" => (1 + (@ready_low_whales_weight / 10000)).round.to_s
    }

    # display high whales with weight being their y axis (fatty)
    @nodelist << {
        "id" => "#{@ready_high_whales.size} whales: #{@ready_high_whales_weight.round.to_s}$",
        "state" => "high",
        "x" => "520",
        "y" => "60",
        "xx" => "200",
        "yy" => (1 + (@ready_high_whales_weight / 10000)).round.to_s
    }
    refresh
  end

  def refresh()
    @nodelist ||= []
    Celluloid::Actor[:time_server].refresh('nodelist' => @nodelist)
  end


  def add_message(message)
    Celluloid::Actor[:time_server].add_message(message)
  end

  def on_message(data)
    jdata = JSON::parse(data)
    # Track the current ticker price for comparison
    if jdata["channel_name"] == "ticker.BTCUSD"
      @old_ticker_buy = @ticker_buy
      @old_ticker_sell = @ticker_sell
      @ticker_buy = jdata["ticker"]["buy"]["value"]
      @ticker_sell = jdata["ticker"]["sell"]["value"]
      @ticker_currency = "USD" #jdata["ticker"]["currency"]
      if (@old_ticker_buy != @ticker_buy) || (@old_ticker_sell != @ticker_sell)
        Celluloid::Actor[:time_server].ticker("ticker buy: #{@ticker_buy} #{@ticker_currency}, ticker sell: #{@ticker_sell} #{@ticker_currency}")
      end
    end
    if jdata["channel_name"] == "depth.BTCUSD"
      price = jdata["depth"]["price"].to_f
      volume = jdata["depth"]["volume"].to_f
      kind = jdata["depth"]["type_str"]
      if volume > @whale_is 
        info("POSSIBLE WHALE SIGHTED:  #{volume}BTC @ #{price}$, #{kind}")
        add_message("POSSIBLE WHALE SIGHTED:  #{volume}BTC @ #{price}$, #{kind}")
        @whales << [price, volume, kind]
        display_whales
        log_whales
      end
      if volume < (0 - @whale_is)
        info("POSSIBLE WHALE DISAPPEARED: #{volume}BTC @ #{price}$, #{kind}")
        add_message("POSSIBLE WHALE DISAPPEARED: #{volume}BTC @ #{price}$, #{kind}")
        @whales.reject! do |whale|
          whale[0] == price && whale[1] == volume.abs
        end
        display_whales
        log_whales
      end
    end
    if jdata["channel_name"] == "trade.BTC"
      currency = jdata["price_currency"]
      market = true if jdata["properties"] == 'market'
      limit = true if jdata["properties"] == 'limit'
      amount = jdata["trade"]["amount"].to_f
      price = jdata["trade"]["price"].to_f
      kind = jdata["trade"]["trade_type"]
      if amount >= @whale_is
        add_message("*** WHALE DUMP DETECTED! #{amount} @ #{price}.  Price going down!") if kind == "ask"
        info("*** WHALE DUMP DETECTED! #{amount} @ #{price}.  Price going down!") if kind == "ask"
        add_message("*** WHALE PUMP DETECTED! #{amount} @ #{price}.  Price going UP!") if kind == "bid"
        info("*** WHALE PUMP DETECTED! #{amount} @ #{price}.  Price going UP!") if kind == "bid"
        add_message("*** AT MARKET! PRICE DAMAGED!") if market
        info("*** AT MARKET! PRICE DAMAGED!") if market
      end
    end
      
    #debug("#{jdata.inspect}")
    #add_message("amount: #{jdata["trade"]["amount"]}, price: #{jdata["trade"]["price"]} #{jdata["trade"]["price_currency"]}")
    #if jdata["trade"]["amount"] > 50
    #  add_message("LARGE TRADE DETECTED!! REDALERT!")
    #end
  end

  def log_whales
    #add_message("READY ABOVE: #{@ready_high_whales.size} whales weighing #{@ready_high_whales_weight.round(2)}")
    #add_message("READY BELOW: #{@ready_low_whales.size} whales weighing #{@ready_low_whales_weight.round(2)}")
    #add_message("whale grand total: #{@whales.size}")
    #add_message("      total above: #{@high_whales.size} whales weighing #{@high_whales_weight.round(2)}")
    #add_message("      total below: #{@low_whales.size} whales weighing #{@low_whales_weight.round(2)}")
  end

  def set_refresh(resolution)
    every(resolution) do
      display_whales
    end

    every(10) do
      add_message("*** test PING")
    end
  end

  def on_close(code, reason)
    debug("websocket connection closed: #{code.inspect}, #{reason.inspect}")
  end
end
