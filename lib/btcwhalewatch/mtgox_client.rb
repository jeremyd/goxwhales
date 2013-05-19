require 'celluloid/websocket/client'
require 'json'
require 'logger'
require 'time'

class Whale
  attr_accessor :now, :price, :volume, :kind
  def initialize(price, volume, kind, now=nil)
    @price = price
    @volume = volume
    @kind = kind
    @now = now
  end
end

class FakeWall
  attr_accessor :seen, :count, :whale
  def initialize(whale)
    @whale = whale
    @seen = Time.now
    @count = 1
  end
end

class MtGoxClient
  include Celluloid
  include Celluloid::Logger

  def fakewall_sighted(whale)
    find_it = nil
    @fake_walls.each_with_index do |d,i|
      if d.whale.volume == whale.volume && d.whale.price == whale.price && d.whale.kind == whale.kind
        find_it = i
        break
      end
    end
    if find_it == nil
      a = FakeWall.new(whale)
      @fake_walls << a
      return a
    else
      @fake_walls[find_it].seen = Time.now
      @fake_walls[find_it].count += 1
      return @fake_walls[find_it]
    end
  end

  def initialize
    @nodelist ||= []
    if ENV["WHALE_IS"]
      @whale_is = ENV["WHALE_IS"].to_i
    else
      @whale_is = 49
    end
    @whales = []
    @dumptrack = []
    @temp_whales = []
    @fake_walls = []
    @players = 0

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
        @whales << Whale.new(ask["price"], ask["amount"], "ask")
      end
    end

    @full_depth["data"]["bids"].each do |bid|
      if bid["amount"].to_f > @whale_is 
        @whales << Whale.new(bid["price"], bid["amount"], "bid")
      end
    end

    add_message("discovered #{@whales.size} whales lurking in the full_depth")
    info("discovered #{@whales.size} whales lurking in the full_depth")

# Connect to websocket prior to loading the fulldepth ..
    @client = Celluloid::WebSocket::Client.new("ws://websocket.mtgox.com/mtgox?Channel=trades,ticker,depth&Currency=USD", current_actor, :headers => { "Origin" => "ws://websocket.mtgox.com:80" })

  end

  # polling for haproxy connected users
  def stats_enable(polling_interval)
    after(60) { get_stats }
    every(polling_interval) do
      get_stats
    end
  end

  def get_stats
    current_conns = `echo -e "show info" |socat stdio unix-connect:/var/run/haproxy.sock |grep CurrConns|cut -f2 -d:`.chomp
    @players = current_conns.to_i if current_conns
    info("current connected users from haproxy stats: #{current_conns}")
  end

  def on_open
    debug("websocket connection opened")
  end

  def calc_whales_above
    @high_whales = []
    @high_whales_weight = 0.0
    @whales.each do |whale|
      if whale.price.to_f > @ticker_buy.to_f
        @high_whales << whale
        @high_whales_weight += (whale.price.to_f * whale.volume.to_f)
      end
    end
    @high_whales.size
  end

  def calc_whales_below
    @low_whales = []
    @low_whales_weight = 0.0
    @whales.each do |whale|
      if whale.price.to_f < @ticker_buy.to_f
        @low_whales << whale
        @low_whales_weight += (whale.price.to_f * whale.volume.to_f)
      end
    end
    @low_whales.size
  end

  # if the whale is within 5$ of the ticker, he's ready to blow
  def calc_ready_whales_below
    @ready_low_whales = []
    @ready_low_whales_weight = 0.0
    @low_whales.each do |whale|
      if whale.price.to_f > (@ticker_buy.to_f - 10)
        @ready_low_whales << whale
        @ready_low_whales_weight += (whale.price.to_f * whale.volume.to_f)
      end
    end
    @ready_low_whales.size
  end

  # if the whale is within 5$ of the ticker, he's ready to blow
  def calc_ready_whales_above
    @ready_high_whales = []
    @ready_high_whales_weight = 0.0
    @high_whales.each do |whale|
      if whale.price.to_f < (@ticker_buy.to_f + 10)
        @ready_high_whales << whale
        @ready_high_whales_weight += (whale.price.to_f * whale.volume.to_f)
      end
    end
    @ready_high_whales.size
  end

  def expire_fakes
    # expire walls that the price has consumed
    @fake_walls.reject! do |fake|
      fake.whale.kind == "ask" && fake.whale.price.to_f <= @ticker_buy.to_f
    end
    @fake_walls.reject! do |fake|
      fake.whale.kind == "bid" && fake.whale.price.to_f >= @ticker_sell.to_f
    end
    @fake_walls.reject! do |fake|
# expire 50,000 seconds
      (Time.now - fake.seen) > 15000
    end
  end

  def calc_fake_walls_above_and_below
    @fakes_above = []
    @fakes_below = []
    expire_fakes
    @fake_walls.each do |fake|
      if fake.whale.kind == "ask" && fake.count >= 2 && (fake.whale.price.to_f < (@ticker_sell.to_f + 30))
        @fakes_above << fake
      elsif fake.whale.kind == "bid" && fake.count >= 2 && (fake.whale.price.to_f > (@ticker_buy.to_f - 30)) 
        @fakes_below << fake
      end
    end
    @fakes_above.sort! { |a,b| a.whale.price <=> b.whale.price }
    @fakes_below.sort! { |a,b| a.whale.price <=> b.whale.price }
  end

  def display_whales
    return false unless @ticker_buy && @ticker_sell
    above = calc_whales_above
    below = calc_whales_below
    ready_above = calc_ready_whales_above
    ready_below = calc_ready_whales_below
    calc_fake_walls_above_and_below

    @nodelist = []
    # display low whales with weight being their y axis (fatty)
    #@nodelist << {
    #    "id" => "#{@ready_low_whales.size} whales buying: #{@ready_low_whales_weight.round.to_s}$",
    #    "state" => "low",
    #    "x" => "100",
    #    "y" => "160",
    #    "xx" => "300",
    #    "yy" => (1 + (@ready_low_whales_weight / 10000)).round.to_s
    #}
#
#    # display high whales with weight being their y axis (fatty)
#    @nodelist << {
#        "id" => "#{@ready_high_whales.size} whales selling: #{@ready_high_whales_weight.round.to_s}$",
#        "state" => "high",
#        "x" => "520",
#        "y" => "160",
#        "xx" => "300",
#        "yy" => (1 + (@ready_high_whales_weight / 10000)).round.to_s
#    }

    # display low whales with weight being their y axis (fatty)

    x = 100
    y = 160
    yy = 20
    @fakes_below.each do |fb|
      xx = fb.whale.volume.abs.to_f.round
      last_seen = (Time.now - fb.seen).round
      @nodelist << {
          "id" => " #{fb.whale.price} USD. Volume #{fb.whale.volume}.  Faked wall #{fb.count}x times.  Last fake: #{last_seen}s ago.",
          "state" => "low",
          "x" => x.to_s,
          "y" => y.to_s,
          "xx" => xx.to_s,
          "yy" => yy.to_s
      }
      y += (yy + 20)
    end

    @fakes_above.each do |fb|
      xx = fb.whale.volume.abs.to_f.round
      last_seen = (Time.now - fb.seen).round
      @nodelist << {
          "id" => " #{fb.whale.price} USD. Volume #{fb.whale.volume}.  Faked wall #{fb.count}x times.  Last fake: #{last_seen}s ago.",
          "state" => "high",
          "x" => x.to_s,
          "y" => y.to_s,
          "xx" => xx.to_s,
          "yy" => yy.to_s
      }
      y += (yy + 20)
    end

  end

  def refresh()
    Celluloid::Actor[:time_server].ticker("Ticker buy: #{@ticker_buy} #{@ticker_currency},  Ticker sell: #{@ticker_sell} #{@ticker_currency},  Players: #{@players}")
    Celluloid::Actor[:time_server].refresh('nodelist' => @nodelist, 'dumptotal' => dumptotal)
  end

  def add_message(message)
    Celluloid::Actor[:time_server].add_message(message)
  end

  def reflow_whales
    # sort first by timestamp, top is oldest, then by kind, buys on top of sells.
    @temp_whales.sort_by! { |a| [a.now, a.kind] }
    # grab the oldest whale off the top
    whaletransit = @temp_whales.shift
    return unless whaletransit
    @this_now = whaletransit.now
    if @last_now && @this_now <= @last_now 
      info("WARN: OUT OF ORDER DETECTED")
    end
    @last_now = @this_now
    if whaletransit.volume.to_f > 0
      @whales << whaletransit
      info "SIGHTED: #{whaletransit.inspect}"
      display_whales
      refresh
    elsif whaletransit.volume.to_f < 0
      #after(60) do
        rejected = false
        @whales.reject! do |r| 
          if( r.volume.to_f.abs == whaletransit.volume.to_f.abs &&
              r.price.to_f == whaletransit.price.to_f &&
              r.kind == whaletransit.kind && rejected == false )
            rejected = true
            true
          else
            false
          end
        end
        if rejected == false
          info("WARN: whale mia but nothing rejected for #{whaletransit.inspect}")
        else
          info("GONE: #{whaletransit.inspect}")
          showit = fakewall_sighted(whaletransit)
          info("POSSIBLE FAKE WALL (#{showit.count} seen) #{showit.whale.inspect}")
          display_whales
          refresh
        end
      #end
    end
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
        refresh
      end
    end
    if jdata["channel_name"] == "depth.BTCUSD"
      now = jdata['depth']['now'].to_i
      price = jdata["depth"]["price"].to_f
      volume = jdata["depth"]["volume"].to_f
      kind = jdata["depth"]["type_str"]
      currency = jdata["depth"]["currency"]
      if volume > @whale_is 
        @temp_whales << Whale.new(price, volume, kind, now)
      end
      if volume < (0 - @whale_is)
        @temp_whales << Whale.new(price, volume, kind, now)
      end
      after(30) { reflow_whales }
    end
    if jdata["channel_name"] == "trade.BTC"
      currency = jdata["price_currency"]
      market = true if jdata["properties"] == 'market'
      limit = true if jdata["properties"] == 'limit'
      amount = jdata["trade"]["amount"].to_f
      price = jdata["trade"]["price"].to_f
      kind = jdata["trade"]["trade_type"]
# NEED CURRENCY DETECT HERE? maybe not.
      if amount >= @whale_is
        add_message("WHALE DUMP DETECTED! #{amount} @ #{price}.  Price going down!") if kind == "ask"
        info("WHALE DUMP DETECTED! #{amount} @ #{price}.  Price going down!") if kind == "ask"

        add_message("WHALE PUMP DETECTED! #{amount} @ #{price}.  Price going UP!") if kind == "bid"
        info("WHALE PUMP DETECTED! #{amount} @ #{price}.  Price going UP!") if kind == "bid"

        dumptrackadd(amount, price, kind)

        add_message("AT MARKET! PRICE DAMAGED!") if market
        info("AT MARKET! PRICE DAMAGED!") if market

        saydumptotal = dumptotal

        #add_message(saydumptotal)
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
    # get 5 minute
    alert_msg = "Sum of whale action; In the last 15 minutes:"
    add_message("*** 15 minute whale action is over the 375 btc threshold! #{total} BTC (alert sleep timer set 1000s)") if total.abs >= 375
    if total > 0
      return alert_msg + " + #{total.abs} BTC (bought)"
    elsif total < 0
      return alert_msg + "- #{total.abs} BTC (sold)"
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

  def set_refresh(interval)
    every(interval) do
      refresh
    end
  end

end
