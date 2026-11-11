module Spectre
  # Ready-made middleware. Each method returns a `Layer`.
  module Middleware
    # Logs `METHOD /path status duration` through `Log` (source "spectre").
    def self.logger : Layer
      Spectre.layer do |req, res, nxt|
        started = Time.monotonic
        begin
          nxt.call
        rescue ex
          ms = (Time.monotonic - started).total_milliseconds.round(2)
          code = ex.is_a?(HTTPError) ? ex.status : 500
          LOG.info { "#{req.method} #{req.path} #{code} #{ms}ms" }
          raise ex
        end
        ms = (Time.monotonic - started).total_milliseconds.round(2)
        LOG.info { "#{req.method} #{req.path} #{res.status_code} #{ms}ms" }
      end
    end

    # Adds CORS headers and answers preflight requests.
    def self.cors(origin : String = "*",
                  methods : String = "GET, POST, PUT, PATCH, DELETE, OPTIONS",
                  headers : String = "Content-Type, Authorization",
                  max_age : Int32 = 600) : Layer
      Spectre.layer do |req, res, nxt|
        res.header("Access-Control-Allow-Origin", origin)
        res.header("Vary", "Origin") unless origin == "*"
        if req.method == "OPTIONS" && req.header("Access-Control-Request-Method")
          res.header("Access-Control-Allow-Methods", methods)
          res.header("Access-Control-Allow-Headers", headers)
          res.header("Access-Control-Max-Age", max_age.to_s)
          res.send_status(204)
        else
          nxt.call
        end
      end
    end
  end
end
