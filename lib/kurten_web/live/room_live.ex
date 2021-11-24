defmodule KurtenWeb.RoomLive do
  use KurtenWeb, :live_view
  alias Kurten.Room
  alias Phoenix.PubSub

  @moduledoc """
    pages.
    index. lets you create and join a room
    room. lists room participants
    round. playing the round
  """

  @impl true
  def mount(_params, session, socket) do
#    subscribe to room updates
#    get room info for user
    PubSub.subscribe(Kurten.PubSub, "room:#{session["room_id"]}")
    {:ok, room, player} = Room.get_info_for_player(session["room_id"], session["player_id"])
    {:ok, assign(socket, [player: player, room: room])}
  end

  def handle_event("start_round", params, socket) do
    Room.start_round(socket.assigns.room.room_id)
    {:noreply, socket}
  end

  def handle_info(:round_started, socket) do
    {:noreply, push_redirect(socket, to: "/round")}
  end

  def handle_info({:player_joined, player}, socket) do
    {:noreply, assign(socket, players: [player, socket.assigns.players])}
  end

  def render(assigns) do
    ~H"""
  <h1>Hello <%= @player.name %> </h1>
  <div class="flex flex-wrap w-auto">
  <%= for player <- @room.players  do %>
    <div class="flex justify-center flex-col w-1/3">
      <svg xmlns="http://www.w3.org/2000/svg" class="h-8 w-8" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5.121 17.804A13.937 13.937 0 0112 16c2.5 0 4.847.655 6.879 1.804M15 10a3 3 0 11-6 0 3 3 0 016 0zm6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
      <%= player.name %>
    </div>
  <% end %>
     <div x-data>
      <button id="copy_invite" type="button" @click={"$clipboard('http://localhost:4000/join/#{@room.room_id}')"}>Copy Invite Link</button>
     </div>
    <%= if @player.type == "admin" do%>
      <button phx-click="start_round">Start Round</button>
    <% end %>
</div>
"""
  end
end
