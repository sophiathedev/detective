defmodule Detective.Repo do
  use Ecto.Repo,
    otp_app: :detective,
    adapter: Ecto.Adapters.Postgres
end
