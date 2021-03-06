module Grip
  VERSION = {{ `shards version #{__DIR__}`.chomp.stringify }}

  # Stores all the configuration options for a Grip application.
  # It's a singleton and you can access it like.
  #
  # ```
  # Grip.config
  # ```
  class Config
    INSTANCE        = Config.new
    HANDLERS        = [] of HTTP::Handler
    CUSTOM_HANDLERS = [] of Tuple(Nil | Int32, HTTP::Handler)
    FILTER_HANDLERS = [] of HTTP::Handler
    ERROR_HANDLERS  = {} of Int32 => HTTP::Server::Context, Exception -> String

    {% if flag?(:without_openssl) %}
      @ssl : Bool?
    {% else %}
      @ssl : OpenSSL::SSL::Context::Server?
    {% end %}

    property host_binding, ssl, port, env, running
    property always_rescue, server : HTTP::Server?, extra_options

    def initialize
      @host_binding = "0.0.0.0"
      @port = 3000
      @env = ENV["GRIP_ENV"]? || "development"
      @error_handler = nil
      @always_rescue = true
      @router_included = false
      @default_handlers_setup = false
      @running = false
      @handler_position = 0
    end

    def env
      @env
    end

    def router=(router)
      @router = router
    end

    def handlers
      HANDLERS
    end

    def scheme
      ssl ? "https" : "http"
    end

    def clear
      @router_included = false
      @handler_position = 0
      @default_handlers_setup = false
      HANDLERS.clear
      CUSTOM_HANDLERS.clear
      FILTER_HANDLERS.clear
      ERROR_HANDLERS.clear
    end

    def custom_handlers
      CUSTOM_HANDLERS
    end

    def add_handler(handler : HTTP::Handler)
      CUSTOM_HANDLERS << {nil, handler}
    end

    def add_handler(handler : HTTP::Handler, position : Int32)
      CUSTOM_HANDLERS << {position, handler}
    end

    def add_filter_handler(handler : HTTP::Handler)
      FILTER_HANDLERS << handler
    end

    def error_handlers
      ERROR_HANDLERS
    end

    def add_error_handler(status_code : Int32, &handler : HTTP::Server::Context, Exception -> _)
      ERROR_HANDLERS[status_code] = ->(context : HTTP::Server::Context, error : Exception) { handler.call(context, error).to_s }
    end

    def extra_options(&@extra_options : OptionParser ->)
    end

    def setup
      unless @default_handlers_setup && @router_included
        setup_init_handler
        setup_error_handler
        setup_custom_handlers
        setup_filter_handlers

        @default_handlers_setup = true
        @router_included = true
        HANDLERS.insert(HANDLERS.size, Grip::Router::WebSocket::INSTANCE)
        HANDLERS.insert(HANDLERS.size, Grip::Router::Http::INSTANCE)
      end
    end

    private def setup_init_handler
      HANDLERS.insert(@handler_position, Grip::Core::Init::INSTANCE)
      @handler_position += 1
    end

    private def setup_error_handler
      if @always_rescue
        @error_handler ||= Grip::Core::Exception.new
        HANDLERS.insert(@handler_position, @error_handler.not_nil!)
        @handler_position += 1
      end
    end

    private def setup_custom_handlers
      CUSTOM_HANDLERS.each do |ch0, ch1|
        position = ch0
        HANDLERS.insert (position || @handler_position), ch1
        @handler_position += 1
      end
    end

    private def setup_filter_handlers
      FILTER_HANDLERS.each do |h|
        HANDLERS.insert(@handler_position, h)
      end
    end
  end

  def self.config
    yield Config::INSTANCE
  end

  def self.config
    Config::INSTANCE
  end
end
