module Spectre
  def self.normalize_path(path : String) : String
    result = path.empty? ? "/" : (path.starts_with?('/') ? path : "/#{path}")
    while result.size > 1 && result.ends_with?('/')
      result = result.rchop('/')
    end
    result
  end

  def self.join_paths(prefix : String, path : String) : String
    prefix = normalize_path(prefix)
    prefix = "" if prefix == "/"
    path = normalize_path(path)
    path = "" if path == "/"
    full = prefix + path
    full.empty? ? "/" : full
  end

  record RouteDef, verb : Verb, pattern : String, chain : Array(Layer)

  # Records routes and middleware in the order they are written, like
  # Express's `Router`. Everything is composed into a flat chain per route
  # at registration time, so nothing is assembled while serving requests.
  #
  # As in Express, order matters: a middleware applies to the routes
  # registered after it.
  class Router
    record Entry, prefix : String, layer : Layer do
      def matches?(path : String) : Bool
        prefix.empty? || path == prefix || path.starts_with?(prefix + "/")
      end
    end

    getter defs = [] of RouteDef
    @entries = [] of Entry

    # Adds middleware for every route registered after this call.
    def use(layer : Layer) : self
      use("", layer)
    end

    def use(&block : Request, Response, Next ->) : self
      use("", block)
    end

    # Adds middleware for routes under `prefix`.
    def use(prefix : String, layer : Layer) : self
      prefix = Spectre.normalize_path(prefix)
      prefix = "" if prefix == "/"
      @entries << Entry.new(prefix, layer)
      self
    end

    def use(prefix : String, &block : Request, Response, Next ->) : self
      use(prefix, block)
    end

    # `app.use "/api", router` mounts a router, like Express.
    def use(prefix : String, router : Router) : self
      mount(prefix, router)
    end

    def mount(prefix : String, router : Router) : self
      router.defs.each do |route|
        pattern = Spectre.join_paths(prefix, route.pattern)
        @defs << RouteDef.new(route.verb, pattern, scoped(pattern) + route.chain)
      end
      self
    end

    # Defines routes under a common prefix.
    #
    # ```
    # app.group "/api/v1" do |api|
    #   api.use Spectre::Middleware.cors
    #   api.get("/users") { |req, res| ... }
    # end
    # ```
    def group(prefix : String, & : Router ->) : self
      router = Router.new
      yield router
      mount(prefix, router)
    end

    {% for name in %w(get post put patch delete head options) %}
      # Registers a `{{name.upcase.id}}` route. Extra `Layer` arguments run before the handler.
      def {{name.id}}(path : String, *layers, &handler : Request, Response ->) : self
        chain = [] of Layer
        layers.each { |layer| chain << layer }
        add(Verb::{{name.upcase.id}}, path, chain, handler)
      end
    {% end %}

    # Registers a route for every method.
    def all(path : String, *layers, &handler : Request, Response ->) : self
      Verb.each do |verb|
        chain = [] of Layer
        layers.each { |layer| chain << layer }
        add(verb, path, chain, handler)
      end
      self
    end

    protected def add(verb : Verb, path : String, route_layers : Array(Layer), handler : Handler) : self
      pattern = Spectre.normalize_path(path)
      chain = scoped(pattern)
      chain.concat(route_layers)
      chain << ->(req : Request, res : Response, nxt : Next) { handler.call(req, res); nil }
      @defs << RouteDef.new(verb, pattern, chain)
      self
    end

    protected def entries : Array(Entry)
      @entries
    end

    private def scoped(pattern : String) : Array(Layer)
      list = [] of Layer
      @entries.each { |entry| list << entry.layer if entry.matches?(pattern) }
      list
    end
  end
end
