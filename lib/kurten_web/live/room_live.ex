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
    PubSub.subscribe(Kurten.PubSub, "room:#{session["room_id"]}")
    Presence.track(self(), "presence:#{session["room_id"]}", session["player_id"], %{})
    {:ok, room, player} = Room.get_info_for_player(session["room_id"], session["player_id"])
    {:ok, assign(socket, [player: player, room: room])}
  end

  @impl true
  def handle_event("start_round", _params, socket) do
    Room.start_round(socket.assigns.room.room_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("join_round", _params, socket) do
    {:noreply, push_redirect(socket, to: "/round")}
  end

  @impl true
  def handle_info(:round_started, socket) do
    {:noreply, push_redirect(socket, to: "/round")}
  end

  @impl true
  def handle_info([players: players], socket) do
    {:noreply, assign(socket, :room, Map.put(socket.assigns.room, :players, players))}
  end

  @impl true
  def render(assigns) do
    ~H"""
  <div class="w-full h-full">
    <div class="flex flex-col p-4 h-full">
       <div class="text-center">
          Hello <%= @player.first_name %>
       </div>
        <div class="text-center mt-1 mb-2 text-xs text-gray-500">
              The bank can start the round.
       </div>

       <div class="flex flex-wrap w-full overflow-scroll">
         <%= for player <- @room.players  do %>
             <.avatar player={player} balances={@room.balances} current_player={@player} />
          <% end %>
       </div>
       <div x-data class="flex-col mt-auto justify-center w-full border-t-1 border-gray-500">
         <hr/>
         <div class="flex text-center justify-center text-lg text-gray-800 p-4">
          <span>Invite your friends to join the game.</span>
         </div>
         <div class="flex justify-center w-full mb-4">
           <div @click={"window.open('whatsapp://send?text=#{whatsapp_message(@player, @room.room_id)}')"} class="flex flex-col m-4 items-center text-center w-1/2">
             <div class="flex w-max justify-center border border-1 rounded-full p-4 hover:bg-gray-100">
                <a type="button">
                    <img class="h-10 w-auto" src="https://cdn2.iconfinder.com/data/icons/social-messaging-ui-color-shapes-2-free/128/social-whatsapp-circle-512.png"/>
                </a>
              </div>
              <span class="p-2 text-sm text-gray-600">Share on Whatsapp</span>
            </div>
            <div x-data class="flex flex-col m-4 items-center text-center w-1/2">
              <div @click={"copied = true; $clipboard('#{url(@room.room_id)}')"} class="flex w-max justify-center border border-1 rounded-full p-4 hover:bg-gray-100">
                <a id="copy_invite" type="button">
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-10 w-auto text-gray-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
                    </svg>
                </a>
              </div>
              <span class="p-2 text-sm text-gray-600">Copy Invite Link</span>
            </div>
          </div>
      </div>

       <%= if not is_nil(@room.round_id) do %>
       <button class="btn-blue" phx-click="join_round">Join round in progress</button>
       <%end%>
       <%= if @player.type == "admin" and length(@room.players) > 1 and is_nil(@room.round_id) do%>
          <button class="btn-blue" phx-click="start_round">Start Round</button>
        <% end %>
    </div>
  </div>
"""
  end

  def url(room_id) do
    "#{System.get_env("BASE_URL") || "http://localhost:4000"}/join/#{room_id}"
  end

  defp whatsapp_message(player, room_id) do
    "#{player.first_name} #{player.last_name} is inviting you to to join kvitlech game. #{url(room_id)}"
  end

  def avatar(assigns) do
    user_balances = Enum.filter(assigns.balances, fn balance -> balance.payee == assigns.player.id or balance.payer == assigns.player.id end)
    balance = Enum.reduce(user_balances, 0, fn balance, acc ->
      if balance.payee == assigns.player.id do
        acc + balance.amount
        else
        acc - balance.amount
      end
    end)
    ~H"""
      <div class="flex justify-center align-center w-1/3">
              <div class="flex flex-col justify-center items-center align-center m-1 w-auto p-2">
                <div class="relative">
                  <%= if assigns.player.type == "admin" do %>
                    <div class="h-16 w-16 rounded-full bg-gray-200 flex justify-center align-center items-center">
                      <svg xmlns="http://www.w3.org/2000/svg" class="h-10 w-10" viewBox="0 0 20 20" fill="currentColor">
                        <path class="text-gray-600" fill-rule="evenodd" d="M10.496 2.132a1 1 0 00-.992 0l-7 4A1 1 0 003 8v7a1 1 0 100 2h14a1 1 0 100-2V8a1 1 0 00.496-1.868l-7-4zM6 9a1 1 0 00-1 1v3a1 1 0 102 0v-3a1 1 0 00-1-1zm3 1a1 1 0 012 0v3a1 1 0 11-2 0v-3zm5-1a1 1 0 00-1 1v3a1 1 0 102 0v-3a1 1 0 00-1-1z" clip-rule="evenodd" />
                      </svg>
                    </div>
                    <span class={"absolute bottom-0 right-2 inline-block w-3 h-3 #{if assigns.player.presence == "online", do: "bg-green-600", else: "bg-gray-400"} border-2 border-white rounded-full"}></span>
                  <% else %>
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-20 w-20" viewBox="0 0 20 20" fill="currentColor">
                    <path class="text-gray-200" fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-6-3a2 2 0 11-4 0 2 2 0 014 0zm-2 4a5 5 0 00-4.546 2.916A5.986 5.986 0 0010 16a5.986 5.986 0 004.546-2.084A5 5 0 0010 11z" clip-rule="evenodd" />
                    </svg>
                  <span class={"absolute bottom-2 right-3 inline-block w-3 h-3 #{if assigns.player.presence == "online", do: "bg-green-600", else: "bg-gray-400"} border-2 border-white rounded-full"}></span>
                  <% end %>
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
