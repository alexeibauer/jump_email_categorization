defmodule JumpEmailCategorizationWeb.PageController do
  use JumpEmailCategorizationWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
