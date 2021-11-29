defmodule KurtenWeb.RoomLive do
  use KurtenWeb, :live_view
  alias Kurten.Room
  alias Phoenix.PubSub
  alias KurtenWeb.Presence

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
    Presence.track(self(), "presence:#{session["room_id"]}", session["player_id"], %{})

    {:ok, room, player} = Room.get_info_for_player(session["room_id"], session["player_id"])
#     room = %{room_id: "hello", players: [%{name: "Breindy", type: "player"}, %{name: "Eizik", type: "player"}, %{name: "Chaim", type: "player"}, %{name: "Eizik", type: "player"}, %{name: "Eizik", type: "player"}]}
#     player = %{name: "Breindy", type: "admin"}
     IO.inspect(room, label: "room")
    {:ok, assign(socket, [player: player, room: room])}
  end

  def handle_event("start_round", params, socket) do
    Room.start_round(socket.assigns.room.room_id)
    {:noreply, socket}
  end

  def handle_info(:round_started, socket) do
    {:noreply, push_redirect(socket, to: "/round")}
  end

  def handle_event("join_round", _params, socket) do
    {:noreply, push_redirect(socket, to: "/round")}
  end

  def handle_info([players: players], socket) do
    {:noreply, assign(socket, :room, Map.put(socket.assigns.room, :players, players))}
  end

  def render(assigns) do
    ~H"""
  <div class="w-full h-full">
    <div class="flex flex-col p-4 h-full">
       <div class="text-center">
          Hello <%= @player.first_name %>
       </div>

       <div class="flex flex-wrap w-full">
         <%= for player <- @room.players  do %>
             <.avatar player={player} balances={@room.balances} current_player={@player} />
          <% end %>
       </div>
        <% invite_url = "#{Routes.url(KurtenWeb.Endpoint)}/join/#{@room.room_id}" %>
       <div x-data="{copied: false}" class="flex justify-center mt-auto mb-6">
            <input disabled value={"#{Routes.url(KurtenWeb.Endpoint)}/join/#{@room.room_id}"} class="bg-gray-100 text-gray-600 flex-1 py-2 px-4 rounded-l-lg border-l-1 border-t-1 border-b-1 overflow-clip	"/>
            <button class="bg-gray-300 text-gray-800 font-bold py-2 px-4 w-min-content rounded-r-lg inline-flex" id="copy_invite" type="button" @click={"copied = true; $clipboard('#{invite_url}')"}>
                <span x-show="!copied">Copy</span>
                <span x-show="copied">Copied!</span>
                <svg x-show="copied" xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-green-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                </svg>
            </button>
       </div>
       <%= if not is_nil(@room.round_id) do %>
       <button class="btn-blue" phx-click="join_round">Join round in progress</button>
       <%end%>
       <%= if @player.type == "admin" and length(@room.players) > 1 do%>
          <button class="btn-blue" phx-click="start_round">Start Round</button>
        <% end %>
    </div>
  </div>
"""
  end

  def avatar(assigns) do
    user_balances = Enum.filter(assigns.balances, fn balance -> balance.payee == assigns.player.id or balance.payer == assigns.player.id end)
    balance = Enum.reduce(user_balances, 0, fn balance, acc ->
      if balance.payee == assigns.player.id do
        acc - balance.amount
        else
        acc + balance.amount
      end
    end)
    ~H"""
      <div class="flex justify-center align-center w-1/3">
              <div class="flex flex-col justify-center items-center align-center m-1 w-auto p-2">
                <div class="relative">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-20 w-20" viewBox="0 0 20 20" fill="currentColor">
                    <path class="text-gray-200" fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-6-3a2 2 0 11-4 0 2 2 0 014 0zm-2 4a5 5 0 00-4.546 2.916A5.986 5.986 0 0010 16a5.986 5.986 0 004.546-2.084A5 5 0 0010 11z" clip-rule="evenodd" />
                    <span class={"absolute bottom-2 right-3 inline-block w-3 h-3 #{if assigns.player.presence == "online", do: "bg-green-600", else: "bg-gray-400"} border-2 border-white rounded-full"}></span>
                </svg>
                </div>
                <div class="text-center">
                <%= if assigns.player.id == assigns.current_player.id do %>
                 You
                  <% else %>
                <%= assigns.player.first_name %> <%= assigns.player.last_name %>
                <% end %>
                </div>
                <div class="text-center">
                <span class={"#{if balance >= 0, do: "text-green-500", else: "text-red-500"}"}>$<%= balance %></span>
                </div>
              </div>
            </div>
    """
  end
end
