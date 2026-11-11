module Spectre
  # A route handler: `do |req, res| ... end`.
  alias Handler = Proc(Request, Response, Nil)

  # Middleware: `do |req, res, nxt| ... nxt.call ... end`.
  # (`next` is a Crystal keyword, so the continuation is conventionally `nxt`.)
  alias Layer = Proc(Request, Response, Next, Nil)

  alias ErrorHandler = Proc(Exception, Request, Response, Nil)

  # Continuation passed to middleware. It is a struct, so calling the next
  # layer allocates nothing: the chain is built once, when routes are registered.
  struct Next
    def initialize(@chain : Array(Layer), @index : Int32, @req : Request, @res : Response)
    end

    def call : Nil
      i = @index
      if i < @chain.size
        @chain.unsafe_fetch(i).call(@req, @res, Next.new(@chain, i + 1, @req, @res))
      end
      nil
    end
  end

  # Turns a block into a `Layer` value you can store and pass around:
  #
  # ```
  # auth = Spectre.layer do |req, res, nxt|
  #   req.header("Authorization") ? nxt.call : res.status(401).send("Unauthorized")
  # end
  # app.get "/admin", auth { |req, res| ... }
  # ```
  def self.layer(&block : Request, Response, Next ->) : Layer
    block
  end
end
