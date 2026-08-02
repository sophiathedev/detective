defmodule DetectiveWeb.Presence do
  use Phoenix.Presence,
    otp_app: :detective,
    pubsub_server: Detective.PubSub
end
