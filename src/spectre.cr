require "http/server"
require "json"
require "uri"
require "mime"
require "log"

require "./spectre/version"
require "./spectre/errors"
require "./spectre/params"
require "./spectre/request"
require "./spectre/response"
require "./spectre/types"
require "./spectre/route_table"
require "./spectre/router"
require "./spectre/middleware"
require "./spectre/static"
require "./spectre/app"

# Spectre is an Express-style web microframework.
#
# ```
# require "spectre"
#
# app = Spectre.new
# app.get "/hello/:name" do |req, res|
#   res.json({greeting: "Hello, #{req.params["name"]}!"})
# end
# app.listen 3000
# ```
module Spectre
  LOG = ::Log.for("spectre")

  # Creates a new application, like `express()`.
  def self.new : App
    App.new
  end
end
