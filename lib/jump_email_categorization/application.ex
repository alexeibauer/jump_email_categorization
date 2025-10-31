defmodule JumpEmailCategorization.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      JumpEmailCategorizationWeb.Telemetry,
      JumpEmailCategorization.Repo,
      {DNSCluster, query: Application.get_env(:jump_email_categorization, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: JumpEmailCategorization.PubSub},
      # Start a worker by calling: JumpEmailCategorization.Worker.start_link(arg)
      # {JumpEmailCategorization.Worker, arg},
      # Start to serve requests, typically the last entry
      JumpEmailCategorizationWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: JumpEmailCategorization.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    JumpEmailCategorizationWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
