defmodule KurtenWeb.PLayerLive do
  use KurtenWeb, :live_view

  @moduledoc """
    page for registering, and creating or joining an existing room
  """

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, query: "", results: %{})}
  end

  def render(assigns) do
  end
end
