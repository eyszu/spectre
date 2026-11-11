module Spectre
  # Raise (or use `Spectre.halt`) from anywhere in a handler to stop and
  # answer with the given status. The default error handler sends `message`
  # as plain text; install your own with `App#error`.
  class HTTPError < Exception
    getter status : Int32

    def initialize(@status : Int32, message : String? = nil)
      super(message || HTTP::Status.new(@status).description || "Error")
    end
  end

  def self.halt(status : Int32, message : String? = nil) : NoReturn
    raise HTTPError.new(status, message)
  end
end
