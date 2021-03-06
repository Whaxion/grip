module Grip
  module Controller
    class WebSocket < Base
      getter? closed = false

      def initialize
        @ws = HTTP::WebSocket::Protocol.new(IO::Memory.new)
        @buffer = Bytes.new(4096)
        @current_message = IO::Memory.new
      end

      def on_ping(context : HTTP::Server::Context, on_ping : String)
      end

      def on_pong(context : HTTP::Server::Context, on_pong : String)
      end

      def on_message(context : HTTP::Server::Context, on_message : String)
      end

      def on_binary(context : HTTP::Server::Context, on_binary : Bytes)
      end

      def on_close(context : HTTP::Server::Context, on_close : String)
      end

      protected def check_open
        raise IO::Error.new "Closed socket" if closed?
      end

      def send(message)
        check_open
        @ws.send(message)
      rescue exception
        if !closed?
          @closed = true
          @ws.close(exception.message)
        end
        exception
      end

      # It's possible to send a PING frame, which the client must respond to
      # with a PONG, or the server can send an unsolicited PONG frame
      # which the client should not respond to.
      #
      # See `#pong`.
      def ping(message = nil)
        check_open
        @ws.ping(message)
      rescue exception
        if !closed?
          @closed = true
          @ws.close(exception.message)
        end
        exception
      end

      # Server can send an unsolicited PONG frame which the client should not respond to.
      #
      # See `#ping`.
      def pong(message = nil)
        check_open
        @ws.pong(message)
      rescue exception
        if !closed?
          @closed = true
          @ws.close(exception.message)
        end
        exception
      end

      def stream(binary = true, frame_size = 1024)
        check_open
        @ws.stream(binary: binary, frame_size: frame_size) do |io|
          yield io
        end
      rescue exception
        if !closed?
          @closed = true
          @ws.close(exception.message)
        end
        exception
      end

      def close(message = nil)
        return if closed?
        @closed = true
        @ws.close(message)
      end

      def run(context)
        loop do
          begin
            info = @ws.receive(@buffer)
          rescue IO::EOFError
            on_close(context, "")
            break
          end

          case info.opcode
          when HTTP::WebSocket::Protocol::Opcode::PING
            @current_message.write @buffer[0, info.size]
            if info.final
              message = @current_message.to_s
              on_ping(context, message)
              pong(message) unless closed?
              @current_message.clear
            end
          when HTTP::WebSocket::Protocol::Opcode::PONG
            @current_message.write @buffer[0, info.size]
            if info.final
              on_pong(context, @current_message.to_s)
              @current_message.clear
            end
          when HTTP::WebSocket::Protocol::Opcode::TEXT
            @current_message.write @buffer[0, info.size]
            if info.final
              on_message(context, @current_message.to_s)
              @current_message.clear
            end
          when HTTP::WebSocket::Protocol::Opcode::BINARY
            @current_message.write @buffer[0, info.size]
            if info.final
              on_binary(context, @current_message.to_slice)
              @current_message.clear
            end
          when HTTP::WebSocket::Protocol::Opcode::CLOSE
            @current_message.write @buffer[0, info.size]
            if info.final
              message = @current_message.to_s
              on_close(context, message)
              close(message) unless closed?
              @current_message.clear
              break
            end
          end
        end
      end

      def call(context : HTTP::Server::Context)
        if websocket_upgrade_request? context.request
          response = context.response

          version = context.request.headers["Sec-WebSocket-Version"]?
          unless version == HTTP::WebSocket::Protocol::VERSION
            response.status = :upgrade_required
            response.headers["Sec-WebSocket-Version"] = HTTP::WebSocket::Protocol::VERSION
            return
          end

          key = context.request.headers["Sec-WebSocket-Key"]?

          unless key
            response.respond_with_status(:bad_request)
            return
          end

          accept_code = HTTP::WebSocket::Protocol.key_challenge(key)

          response.status = :switching_protocols
          response.headers["Upgrade"] = "websocket"
          response.headers["Connection"] = "Upgrade"
          response.headers["Sec-WebSocket-Accept"] = accept_code
          response.upgrade do |io|
            @ws = HTTP::WebSocket::Protocol.new(io)
            self.run(context)
            io.close
          end
        else
          call_next(context)
        end
      end

      private def websocket_upgrade_request?(request)
        return false unless upgrade = request.headers["Upgrade"]?
        return false unless upgrade.compare("websocket", case_insensitive: true) == 0

        request.headers.includes_word?("Connection", "Upgrade")
      end
    end
  end
end
