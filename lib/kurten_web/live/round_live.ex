defmodule KurtenWeb.RoundLive do
  use KurtenWeb, :live_view
  alias Kurten.Round
  alias Phoenix.PubSub
  alias Kurten.Room
  alias KurtenWeb.Presence
  @moduledoc """
  round keeps track of the round and shows who is playing.
  when the person is playing, shows a different UI

  states

  current_turn. automatically updated when new turn starts
  view_mode "self", "current_player". set by user but updated by system when turn changes
  selected_card_index. index of card being viewed. changes when user clicks on other own card.
          automatically updated to 0 when turn changes
          changes to new card when player bets.
          if a players turn has changed, the last card will slide in


"""

  @impl true
  def mount(_params, session, socket) do
    {:ok, room, player} = Room.get_info_for_player(session["room_id"], session["player_id"])
    PubSub.subscribe(Kurten.PubSub, "round:#{room.round_id}")
    Process.send_after(self(), {:after_join, session["room_id"]}, 500)
     case Round.get_info(room.round_id) do
      {:ok, round} -> {:ok, assign(socket, [round: round, player: player, view_mode: "current_player", selected_card_index: 0, added_bet: 0])}
      {:error, _} -> {:ok, push_redirect(socket, to: "/room")}
    end
  end

  def render(assigns) do
    current_turn = Enum.find(assigns.round.turns, &(&1.player.id == assigns.round.current_player))
    turn = if assigns.view_mode == "self" do
      Enum.find(assigns.round.turns, &(&1.player.id == assigns.player.id))
    else
      current_turn
    end
    assigns = Map.merge(assigns, %{turn: turn})
    index(assigns)
  end

  def handle_info({:after_join, room_id}, socket) do
    Presence.track(self(), "presence:#{room_id}", socket.assigns.player.id, %{})
    {:noreply, socket}
  end

  def index(assigns) do
    self_view? = assigns.player.id == assigns.turn.player.id
    # viewing own
    ~H"""
     <div class="p-3 flex flex-col h-full font-sans">
        <div class="text-center">
          <%= if self_view? do %>
            <span class="text-blue-800 font-bold	">you</span> are playing
            <% else %>
             <span class="text-blue-800 font-bold	"><%= assigns.turn.player.first_name%> <%= assigns.turn.player.last_name%></span> is playing
          <% end %>
        </div>
        <div class="flex-col justify-center relative align-center h-full w-full">
          <%= if self_view? or assigns.turn.state == :lost or (assigns.turn.player.type == "admin" and assigns.turn.state == :standing) do %>
              <.revealed_cards self_view?={self_view?} turn={assigns.turn} selected_card_index={assigns.selected_card_index}/>
           <% else %>
              <.hidden_cards turn={assigns.turn}/>
           <% end %>
          <div class="absolute top-1/2 text-center font-bold animate-pulse w-full font-bold text-6xl z-50">
              <%= if assigns.turn.state == :won do %>
                <span x-data x-init="confetti()" class="text-green-700">You won! 🎉</span>
              <% end %>
              <%= if assigns.turn.state == :lost do %>
                <span class="text-red-600 z-50">You lost 🙁</span>
              <% end %>
              <%= if assigns.turn.state == :standby do %>
                <span class="text-gray-600 z-50">Standing</span>
              <% end %>
          </div>
        </div>
        <%= if self_view? and assigns.turn.state == :pending do%>
          <%= if assigns.player.type != "admin" do %>
            <.bet_amount bet={assigns.turn.bet} added_bet={assigns.added_bet}/>
          <% end %>
          <div class="flex justify-center align-center space-x-2">
            <%= if length(assigns.turn.cards) > 0 do %>
              <button phx-click="stand" class="border border-3 border-red-700 bg-white hover:bg-gray-200 text-red-700 font-bold py-2 px-4 rounded" > Stand </button>
            <% end %>
            <button disabled={(assigns.turn.bet + assigns.added_bet == 0 and assigns.turn.player.type != "admin") || assigns.turn.state != :pending} phx-click="place_bet" class="disabled:opacity-50 border border-1 text-nowrap border-green-700 text-white font-bold py-2 px-4 rounded" style="background-color: limegreen">Place bet
              <%= if assigns.player.type != "admin" do %>
                <span class="text-black">$<%= assigns.turn.bet + assigns.added_bet %></span>
              <% end %>
            </button>
          </div>
        <% end %>
        <div class="flex -space-x-1 overflow-hidden my-1 p-2 justify-center">
          <%= for turn <- assigns.round.turns do %>
            <.avatar turn={turn}/>
          <% end %>
        </div>
      </div>
    """
  end


  # turn, self_view?, selected_card_index
  def revealed_cards(%{turn: turn, self_view?: self_view?, selected_card_index: selected_card_index} = assigns) do
    # if self view, show message if empty, otherwise show waiting for user
    cards = Enum.with_index(turn.cards)
    ~H"""
      <%= if card = Enum.at(cards, selected_card_index) do %>
      <div class="max-w-full">
        <.card card={card}/>
      </div>
      <% else %>
        <%= if self_view? do %>
          <div class="flex justify-center items-center w-full h-full">
            <span class="text-center" >
              <%= if turn.player.type == "admin" do %>
                Please take a card.
              <% else %>
                Please select an amount and place bet.
              <% end %>
            </span>
          </div>
        <% else %>
          <div class="flex justify-center items-center w-full h-full">
            <span class="text-center" >Waiting for user...</span>
          </div>
        <% end %>
      <% end %>
      <.card_list cards={cards} selected_card_index={selected_card_index} />
    """
  end

  def hidden_cards(%{turn: turn} = assigns) do
    # if self view, show message if empty, otherwise show waiting for user
    ~H"""
    <div class="flex -space-x-72">
      <%= for card <- turn.cards do%>
      <.blank_card card={card}/>
      <% end %>
      </div>
    """
  end

  # bet, added bet
  def bet_amount(assigns) do
    ~H"""
      <div class="flex justify-center mt-auto space-x-1 mb-2">
        <button class="rounded-md px-2  border border-2 border-gray-300 bg-gray-50" phx-click="bet_amount" phx-value-amount={0} >$<%= assigns.bet %></button>
        <button class="rounded-md px-2  border border-2 border-gray-300 bg-gray-50" phx-click="bet_amount" phx-value-amount={assigns.added_bet + 5} ><span class="text-gray-500">+</span> $5</button>
        <button class="rounded-md px-2  border border-2 border-gray-300 bg-gray-50" phx-click="bet_amount" phx-value-amount={assigns.added_bet + 3}><span class="text-gray-500">+</span> $3</button>
        <button class="rounded-md px-2  border border-2 border-gray-300 bg-gray-50" phx-click="bet_amount" phx-value-amount={assigns.added_bet + 2}><span class="text-gray-500">+</span> $2</button>
        <button class="rounded-md px-2  border border-2 border-gray-300 bg-gray-50" phx-click="bet_amount" phx-value-amount={assigns.added_bet + 1}><span class="text-gray-500">+</span> $1</button>
      </div>
    """
  end

  def other_view(assigns) do
    ~H"""
     <div class="p-3 flex flex-col h-full">
    <div class="text-center">
      <span class="text-blue-800 font-bold	"><%= assigns.current_turn.player.first_name%> <%= assigns.current_turn.player.last_name%></span> is playing
    </div>
    <div class="flex relative overflow-hidden my-1 p-2 max-w-full">
      <div class="flex -space-x-72">
      <%= for card <- assigns.current_turn.cards do%>
      <.blank_card card={card}/>
      <% end %>
      </div>
      <div class="absolute top-1/2 text-center font-bold animate-pulse w-full font-bold text-6xl z-50">
          <%= if assigns.current_turn.state == :won do %>
            <span x-data class="text-green-700">Won</span>
          <% end %>
          <%= if assigns.current_turn.state == :lost do %>
            <span class="text-red-600 z-50">Lost</span>
          <% end %>
          <%= if assigns.current_turn.state == :standby do %>
            <span class="text-gray-600 z-50">Standing</span>
          <% end %>
       </div>
    </div>
    <div class="text-center">$<%= assigns.current_turn.bet %></div>
    <div class="flex -space-x-1 overflow-hidden my-1 p-2 justify-center mt-auto">
      <%= for turn <- assigns.turns do %>
      <.avatar turn={turn}/>
      <% end %>
    </div>
    </div>
    """
  end

  def blank_card(assigns) do
    ~H"""
    <div class="p-3 flex justify-center">
        <img class="filter drop-shadow-xl h-auto w-4/5" src={Routes.static_path(KurtenWeb.Endpoint, "/images/blank.png")} class="w-auto"/>
    </div>
    """
  end

  def handle_event("bet_amount", %{"amount" => amount}, socket) do
    {:noreply, assign(socket, added_bet: String.to_integer(amount))}
  end

  def card_list(assigns) do
    ~H"""
    <div class="flex justify-center space-1 items-center ">
     <%= for {card, index} <- assigns.cards do %>
        <img class={"h-12 filter drop-shadow-xl shadow-red-200 #{if assigns.selected_card_index == index, do: "border border-1 rounded border-blue-500"}"} src={Routes.static_path(KurtenWeb.Endpoint, "/images/#{card.name}.png")} phx-click="select_card" phx-value-index={index} class="w-auto"/>
      <% end %>
    </div>
    """
  end

  def handle_event("select_card", %{"index" => index}, socket) do
    {:noreply, assign(socket, :selected_card_index, String.to_integer(index))}
  end

  def avatar(assigns) do
    ~H"""
      <div >
     <div class="inline-block h-10 w-10 rounded-full ring-2 ring-black items-center bg-white flex justify-center"><%= "#{String.at(assigns.turn.player.first_name, 0) |> String.upcase}#{String.at(assigns.turn.player.last_name, 0) |> String.upcase}" %></div>
      <%= if assigns.turn.state == :lost do %>
        <span class="flex text-red-700 text-center justify-center"><%= "-#{assigns.turn.bet}" %><span>
      <% end %>
      <%= if assigns.turn.state == :pending do %>
        <span class="flex text-gray-400	text-center justify-center">--<span>
      <% end %>
      <%= if assigns.turn.state == :won do %>
        <span class="flex text-green-700 text-center justify-center"><%= "#{assigns.turn.bet}" %><span>
      <% end %>
    </div>
    """
  end

  def card(assigns) do
    {card, _} = assigns.card
      ~H"""
      <div class="p-3 flex justify-center">
          <img class="filter drop-shadow-xl h-auto w-4/5" src={Routes.static_path(KurtenWeb.Endpoint, "/images/#{card.name}.png")} class="w-auto"/>
      </div>
      """
  end

  def handle_event("place_bet", params, socket) do
    player_turn = player_turn(socket.assigns.round.turns, socket.assigns.player)
    Round.place_bet(socket.assigns.round.round_id, player_turn, player_turn.bet + socket.assigns.added_bet)
    {:noreply, socket}
  end

  def handle_event("stand", _params, socket) do
    player_turn = player_turn(socket.assigns.round.turns, socket.assigns.player)
    Round.stand(socket.assigns.round.round_id, player_turn)
    {:noreply, socket}
  end

  defp player_turn(turns, player) do
    Enum.find(turns, &(&1.player.id == player.id))
  end

  def handle_info({:round_terminated, state}, socket) do
    {:noreply, push_redirect(socket, to: "/room")}
  end

  #  handle updates from round
  def handle_info([turns: turns, current_player: current_player], socket) do
    #    when the current_player changes put the new status before changing the current player
    previous_player = socket.assigns.round.current_player
    if previous_player != current_player do
      Process.send_after(self(), [current_player: current_player], 5000)
      {:noreply, assign(socket, round: Map.merge(socket.assigns.round, %{turns: turns}), added_bet: 0)}
    else
      {:noreply, assign(socket, round: Map.merge(socket.assigns.round, %{turns: turns, current_player: current_player}), added_bet: 0)}
    end
  end

#  used after a win or lose
  def handle_info([current_player: current_player], socket) do
    {:noreply, assign(socket, :round, Map.put(socket.assigns.round, :current_player, current_player))}
  end
end
