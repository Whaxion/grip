module Grip
  module Pipe
    class Log < Base
      def call(context : HTTP::Server::Context)
        STDOUT << Time.utc << ' ' << context.response.status_code << ' ' << context.request.method << ' ' << context.request.resource << '\n'
        STDOUT.flush
        context
      end
    end
  end
end
