defmodule JumpEmailCategorization.Repo do
  use Ecto.Repo,
    otp_app: :jump_email_categorization,
    adapter: Ecto.Adapters.Postgres
end
