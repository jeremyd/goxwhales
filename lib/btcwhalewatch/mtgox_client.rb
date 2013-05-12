require 'celluloid/websocket/client'
require 'json'
require 'logger'
require 'time'

class MtGoxClient
  include Celluloid
  include Celluloid::Logger

  def initialize
    @nodelist ||= []
    if ENV["WHALE_IS"]
      @whale_is = ENV["WHALE_IS"].to_i
    else
      @whale_is = 49
    end
    @whales = []
    @dumptrack = []

    Celluloid.logger = ::Logger.new("whale.log")

# FULL DEPTH MORE THAN 5x per hour will get you banned!
# To load fulldepth delete the depth.json cache file.

    @full_depth = nil
    unless File.exists?("depth.json")
      info "curling depth.json"
      info `curl -L 'http://data.mtgox.com/api/2/BTCUSD/money/depth/full' -o depth.json`
    else
      info "using cached depth.json"
    end
    @full_depth = JSON::parse(::IO.read("depth.json"))

    @full_depth["data"]["asks"].each do |ask|

      if ask["amount"].to_f > @whale_is 
        @whales << [ ask["price"], ask["amount"], "ask" ]
      end
    end

    @full_depth["data"]["bids"].each do |bid|
      if bid["amount"].to_f > @whale_is 
        @whales << [ bid["price"], bid["amount"], "bid" ]
      end
    end

    add_message("discovered #{@whales.size} whales lurking in the full_depth")
    info("discovered #{@whales.size} whales lurking in the full_depth")

# Connect to websocket prior to loading the fulldepth ..
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
    return false unless @ticker_buy && @ticker_sell
    above = calc_whales_above
    below = calc_whales_below
    ready_above = calc_ready_whales_above
    ready_below = calc_ready_whales_below

    @nodelist = []
    # display low whales with weight being their y axis (fatty)
    @nodelist << {
        "id" => "#{@ready_low_whales.size} whales buying: #{@ready_low_whales_weight.round.to_s}$",
        "state" => "low",
        "x" => "100",
        "y" => "160",
        "xx" => "300",
        "yy" => (1 + (@ready_low_whales_weight / 10000)).round.to_s
    }

    # display high whales with weight being their y axis (fatty)
    @nodelist << {
        "id" => "#{@ready_high_whales.size} whales selling: #{@ready_high_whales_weight.round.to_s}$",
        "state" => "high",
        "x" => "520",
        "y" => "160",
        "xx" => "300",
        "yy" => (1 + (@ready_high_whales_weight / 10000)).round.to_s
    }
  end

  def refresh()
    Celluloid::Actor[:time_server].refresh('nodelist' => @nodelist, 'dumptotal' => dumptotal)
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
        display_whales
        Celluloid::Actor[:time_server].ticker("ticker buy: #{@ticker_buy} #{@ticker_currency}, ticker sell: #{@ticker_sell} #{@ticker_currency}, players: #{@whales.size}")
        refresh
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
        refresh
      end
      if volume < (0 - @whale_is)
        info("POSSIBLE WHALE DISAPPEARED: #{volume}BTC @ #{price}$, #{kind}")
        add_message("POSSIBLE WHALE DISAPPEARED: #{volume}BTC @ #{price}$, #{kind}")
        @whales.reject! do |whale|
          if whale[0] == price && whale[1] == volume.abs
            info("removing whale: #{whale[0]} == #{price} && #{whale[1]} == #{volume.abs}")
            true
          else
            false
          end
        end
        display_whales
        refresh
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

        dumptrackadd(amount, price, kind)

        add_message("*** AT MARKET! PRICE DAMAGED!") if market
        info("*** AT MARKET! PRICE DAMAGED!") if market

        saydumptotal = dumptotal

        add_message(saydumptotal)
        info(saydumptotal)

        refresh
      end
    end
  end

  def dumptrackadd(amount, price, kind, dumptime=Time.now)
    # expire > 15minute dumps
    @dumptrack.reject! { |r| (r[3] + 900) < Time.now }
    @dumptrack << [amount, price, kind, dumptime]
  end

# returns total dump human readable!
  def dumptotal
    # expire > 15minute dumps
    @dumptrack.reject! { |r| (r[3] + 900) < Time.now }
    total = 0
    @dumptrack.each do |t|
      if t[2] == "bid"
        total += t[0].to_i
      elsif t[2] == "ask"
        total -= t[0].to_i
      else
        debug("failed to match #{t[2]} trade type for total.")
      end
    end
    if total > 0
      return "Last 15 minutes: ***PUMP (bought) #{total.abs} BTC"
    elsif total < 0
      return "Last 15 minutes: ***DUMP (sold) #{total.abs} BTC"
    else
      return "Last 15 minutes: nothing happening.."
    end
  end

  def set_debug(resolution)
    #every(resolution) do
    #  display_whales
    #end

    if ENV['DEBUG_AUDIO']
      every(ENV['DEBUG_AUDIO'].to_i) do
        add_message("*** test PING simulate whale sell 123!")
        dumptrackadd("123.0", "123.0", "ask")
        add_message("*** test PING simulate whale buy 50!")
        dumptrackadd("50.0", "124.0", "bid")
        refresh
      end
    end
  end

  def on_close(code, reason)
    debug("websocket connection closed: #{code.inspect}, #{reason.inspect}")
  end
end
