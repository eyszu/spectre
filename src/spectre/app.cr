module Spectre
  class App < Router
    # Largest request body `Request#body` will read, in bytes.
    property max_body : Int32 = 1_048_576

    @not_found : Handler?
    @error_handler : ErrorHandler?
    @table : RouteTable?
    @fallback : Array(Layer)?

    # Replaces the default "Cannot GET /path" 404 answer.
    def not_found(&block : Request, Response ->) : self
      @not_found = block
      self
    end

    # Replaces the default error answer. Runs for `HTTPError` and for any
    # exception raised by a handler or middleware.
    #
    # ```
    # app.error do |ex, req, res|
    #   status = ex.is_a?(Spectre::HTTPError) ? ex.status : 500
    #   res.status(status).json({error: ex.message})
    # end
    # ```
    def error(&block : Exception, Request, Response ->) : self
      @error_handler = block
      self
    end

    # Serves a directory, like `express.static`.
    def static(prefix : String, dir : String, max_age : Int32? = nil) : self
      use(prefix, Middleware.static(dir, prefix, max_age))
    end

    # Composes route chains and builds the lookup tables. `listen` and
    # `request` call this for you.
    def build! : self
      table = RouteTable.new
      @defs.each { |route| table.add(route.verb, route.pattern, route.chain) }

      fallback = [] of Layer
      @entries.each do |entry|
        if entry.prefix.empty?
          fallback << entry.layer
        else
          layer = entry.layer
          prefix = entry.prefix
          prefix_slash = prefix + "/"
          fallback << Spectre.layer do |req, res, nxt|
            if req.path == prefix || req.path.starts_with?(prefix_slash)
              layer.call(req, res, nxt)
            else
              nxt.call
            end
          end
        end
      end
      fallback << Spectre.layer { |req, res, _nxt| unmatched(req, res) }

      @table = table
      @fallback = fallback
      self
    end

    # The Spectre entry point. Pass it to `HTTP::Server` yourself, or use `listen`.
    def call(ctx : HTTP::Server::Context) : Nil
      req = Request.new(ctx.request, @max_body)
      res = Response.new(ctx.response)
      res.head_only = true if req.method == "HEAD"
      begin
        dispatch(req, res)
      rescue ex
        handle_error(ex, req, res)
      end
    end

    # Runs a request through the app in memory, without a socket. Handy in specs.
    def request(method : String, path : String, body : String? = nil,
                headers : HTTP::Headers? = nil) : HTTP::Client::Response
      build!
      io = IO::Memory.new
      req = HTTP::Request.new(method, path, headers, body)
      res = HTTP::Server::Response.new(io)
      call(HTTP::Server::Context.new(req, res))
      res.close
      io.rewind
      HTTP::Client::Response.from_io(io, ignore_body: method == "HEAD", decompress: false)
    end

    def listen(port : Int32 = 3000, host : String = "0.0.0.0", reuse_port : Bool = false) : Nil
      build!
      server = HTTP::Server.new { |ctx| call(ctx) }
      address = server.bind_tcp(host, port, reuse_port: reuse_port)
      Signal::INT.trap { server.close }
      Signal::TERM.trap { server.close }
      puts "Spectre #{VERSION} listening on http://#{address}"
      server.listen
    end

    private def table : RouteTable
      @table || begin
        build!
        @table.as(RouteTable)
      end
    end

    private def fallback : Array(Layer)
      @fallback || begin
        build!
        @fallback.as(Array(Layer))
      end
    end

    private def dispatch(req : Request, res : Response) : Nil
      path = req.path
      unless path.starts_with?('/')
        res.status(400).send("Bad Request")
        return
      end

      if verb = Verb.from_method(req.method)
        found = table.find(verb, path)
        found ||= table.find(Verb::GET, path) if verb.head?
        if found
          route, values = found
          req.params = Params.new(route.param_names, values)
          Next.new(route.chain, 0, req, res).call
          return
        end
      end

      Next.new(fallback, 0, req, res).call
    end

    # Runs when no route matched: automatic OPTIONS, 405 with Allow, or 404.
    private def unmatched(req : Request, res : Response) : Nil
      allowed = table.allowed(req.path)
      unless allowed.empty?
        res.header("Allow", allowed.join(", "))
        if req.method == "OPTIONS"
          res.send_status(204)
        else
          res.status(405).send("Method Not Allowed")
        end
        return
      end

      if handler = @not_found
        res.status(404)
        handler.call(req, res)
      else
        res.status(404).send("Cannot #{req.method} #{req.path}")
      end
    end

    private def handle_error(ex : Exception, req : Request, res : Response) : Nil
      return if ex.is_a?(IO::Error) # the client went away

      if handler = @error_handler
        begin
          handler.call(ex, req, res) unless res.sent?
          return
        rescue inner
          ex = inner
        end
      end

      status = ex.is_a?(HTTPError) ? ex.status : 500
      LOG.error(exception: ex) { "#{req.method} #{req.path}" } if status >= 500
      return if res.sent?
      res.status(status).send(ex.is_a?(HTTPError) ? ex.message.to_s : "Internal Server Error")
    rescue IO::Error
    end
  end
end
