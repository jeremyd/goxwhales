require 'reel'
require 'btcwhalewatch/mtgox_client'

class TimeServer
  include Celluloid
  include Celluloid::Notifications

  attr_accessor :ticker_display

  def initialize
    @message_list = []
    @alert_now = false
    @last_alerted = Time.now - 5000
    @server_startup = true
    @message_list = []
    @ticker_display = ""
  end

  def add_message(message)
    if message.include?("***")
      if @last_alerted + 1000 < Time.now
         @server_startup = false
         @last_alerted = Time.now
         @alert_now = true
      else
        return true
      end
    end
    #if @server_startup
    #  @last_alert_message = "Last Activity:  temporarily unavailable."
    #else
    #  @last_alert_message = "Last Activity:  #{((Time.now - @last_alerted) / 60).round.to_s}+ minutes ago."
    #end
    @message_list.pop if @message_list.length > 50
    #push the new message onto the list
    compose_message = "#{Time.now.to_s}: #{message}"
    @message_list.unshift(compose_message)
    #refresh_node_list
    true
  end

  def ticker(t)
    @ticker_display = t
  end

  def gen_json_world(options)
    nodelist = options['nodelist']
    dumptotal = options['dumptotal']
    gen = { "nodes" => [], "messages" => @message_list.select { |m| m.include?("***") }}
    gen["sightings"] = @message_list.select { |m| !m.include?("***") }
    gen["nodes"] = nodelist
    gen["alert"] = @alert_now.to_s
    gen["last_alert"] = dumptotal
    @alert_now = false
    gen["ticker"] = @ticker_display
    return gen.to_json
  end

  def refresh(options)
    publish 'time_change', gen_json_world(options)
  end
end

class TimeClient
  include Celluloid
  include Celluloid::Notifications
  include Celluloid::Logger

  def initialize(websocket)
    info "Streaming json_world_view changes to client"
    @socket = websocket
    subscribe('time_change', :notify_time_change)
  end

  def notify_time_change(topic, new_time)
    @socket << new_time
  rescue Reel::SocketError
    info "Time client disconnected"
    terminate
  end
end

class WebServer < Reel::Server
  include Celluloid::Logger

  def initialize(host, port)
    @host = host
    @port = port
    @wizards = []
    info "Reelweb http server starting on #{@host}:#{@port}"
    super(@host, @port, &method(:on_connection))
  end

  def on_connection(connection)
    while request = connection.request
      case request
      when Reel::Request
        info "request for #{request.url}"
        route_request connection, request
      when Reel::WebSocket
        info "Received a WebSocket connection"
        route_websocket request
      end
    end
  end

  def route_request(connection, request)
    if request.url == "/"
      return render_index(connection)
    end
    if request.url == "/btcww.js" || request.url == "/ami-agents.js"
      return render_ami_agents_js(connection)
    end
    if request.url =~ /\/(css\/.+)/ || request.url =~ /\/(js\/.+)/ || request.url =~ /\/(img\/.+)/ || request.url =~ /\/(audio\/.+)/
      return render_static_asset(connection, $1)
    end

    info "404 Not Found: #{request.path}"
    connection.respond :not_found, "Not found"
  end

  def render_static_asset(connection, static_path)
    static_file = File.join(Btcwhalewatch::config_dir, "..", "static_assets", static_path)
    puts "finding static file: #{static_file}"
    if File.exists?(static_file)
      connection.respond(:ok, File.read(static_file))
    else
      connection.respond(:not_found)
    end
  end

  def route_websocket(socket)
    if socket.url == "/timeinfo"
      TimeClient.new(socket)
    else
      info "Received invalid WebSocket request for: #{socket.url}"
      socket.close
    end
  end

  def render_ami_agents_js(connection)
    info "200 OK: /btcww.js"
    connection.respond(:ok, File.read(File.join(Btcwhalewatch::config_dir, "..", "js", "btcww.js")))
  end

  def render_index(connection)
    info "200 OK: /"
    connection.respond(:ok, File.read(File.join(Btcwhalewatch::config_dir, "..", "static_assets", "index.html")))
  end
end

config = Btcwhalewatch::config

host = "127.0.0.1"
port = "1234"
if config["reelweb_ip"]
  host = config["reelweb_ip"]
end
if config["reelweb_port"]
  port = config["reelweb_port"] 
end

WebServer.supervise_as(:reel, host, port)
TimeServer.supervise_as(:time_server)
MtGoxClient.supervise_as(:mtgox)

Celluloid::Actor[:mtgox].set_debug(5) if ENV['DEBUG_AUDIO']
Celluloid::Actor[:mtgox].stats_enable(600)
