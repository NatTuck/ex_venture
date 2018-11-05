use Mix.Config

config :ex_venture, version: "Docker"

config :ex_venture, Data.Repo,
  adapter: Ecto.Adapters.Postgres,
  database: "ex_venture",
  hostname: "postgres",
  username: "ex_venture",
  password: "ex_venture",
  pool_size: 10

config :ex_venture, Web.Endpoint,
  http: [port: 4000],
  url: [host: {:system, "HOST"}, port: 443, scheme: "https"],
  server: true,
  cache_static_manifest: "priv/static/cache_manifest.json"

config :ex_venture, :networking,
  host: {:system, "HOST"},
  port: 5555,
  ssl_port: {:system, "SSL_PORT"},
  server: true,
  socket_module: Networking.Protocol

config :ex_venture, :game,
  npc: Game.NPC,
  zone: Game.Zone,
  room: Game.Room,
  environment: Game.Environment,
  shop: Game.Shop,
  zone: Game.Zone,
  continue_wait: 500

config :logger,
  backends: [:console],
  level: :info

config :ex_venture, ExVenture.Mailer,
  adapter: Bamboo.SMTPAdapter,
  server: {:system, "SMTP_SERVER"},
  port: {:system, "SMTP_PORT"},
  username: {:system, "SMTP_USERNAME"},
  password: {:system, "SMTP_PASSWORD"}

config :ex_venture, :mailer, from: {:system, "EXVENTURE_MAILER_FROM"}
