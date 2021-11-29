# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

config :kurten,
  ecto_repos: [Kurten.Repo]

config :esbuild,
       version: "0.13.10",
       default: [
         args:
           ~w(js/app.js --bundle --target=es2016 --outdir=../priv/static/assets),
         cd: Path.expand("../assets", __DIR__),
         env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
       ]
# Configures the endpoint
config :kurten, KurtenWeb.Endpoint,
  url: [host: System.get_env("BASE_URL")],
  check_origin: false,
  secret_key_base: "QIMcQV+qRpo0iY66gL/XbBVqdS5G+F6h5a9PrivNOd8SrzsePPNdn7/Q0pp2Rll+",
  render_errors: [view: KurtenWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Kurten.PubSub,
  live_view: [signing_salt: "mzaN5keh"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
