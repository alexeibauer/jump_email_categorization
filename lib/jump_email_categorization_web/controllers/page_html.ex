defmodule JumpEmailCategorizationWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use JumpEmailCategorizationWeb, :html

  alias JumpEmailCategorizationWeb.EmailComponents

  embed_templates "page_html/*"
end
