defmodule Omnigist.Repo do
  use Ecto.Repo,
    otp_app: :omnigist,
    adapter: Ecto.Adapters.SQLite3
end
