defmodule KurtenWeb.RoundLive do
  use KurtenWeb, :live_view
  alias Kurten.Round
  alias Phoenix.PubSub
  alias Kurten.Room
  @moduledoc """
  round keeps track of the round and shows who is playing.
  when the person is playing, shows a different UI
"""

  @impl true
  def mount(_params, session, socket) do
    {:ok, room, player} = Room.get_info_for_player(session["room_id"], session["player_id"])
    PubSub.subscribe(Kurten.PubSub, "round:#{room.round_id}")
    {:ok, round} = Round.get_info(room.round_id)
    players = Enum.filter(room.players, fn player -> player.id in round.players end)
    {:ok, assign(socket, players: players, turns: round.turns, cards: round.deck)}
  end

  def render(assigns) do
    ~H"""
  <div class="flex -space-x-2 overflow-hidden">
    <%= for player <- @players do %>
      <img class="inline-block h-10 w-10 rounded-full ring-2 ring-white">
    <% end %>
  </div>
  <%= for card <- @cards do %>
            <.card card={card}/>
        <% end %>
"""
  end

  def card(assigns) do
    IO.inspect(assigns.card[:type])
    if assigns.card.attributes[:type] == "rosier" do
      ~H"""
      <img src={Routes.static_path(KurtenWeb.Endpoint, "/images/rosier_card.png")}/>
      """
    else
      ~H"""
  <div><%= assigns.card.name %></div>
"""
    end
  end

#  handle updates from round
  def handle_info(round, socket) do
    {:noreply, assign(socket, round)}
  end
end
