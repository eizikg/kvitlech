defmodule KurtenWeb.RoundLive do
  use KurtenWeb, :live_view
  alias Kurten.Round
  alias Phoenix.PubSub
  alias Kurten.Room
  alias KurtenWeb.Presence

  @impl true
  def mount(_params, session, socket) do
    {:ok, room, player} = Room.get_info_for_player(session["room_id"], session["player_id"])
    PubSub.subscribe(Kurten.PubSub, "round:#{room.round_id}")
    Presence.track(self(), "presence:#{session["room_id"]}", session["player_id"], %{})
     case Round.get_info(room.round_id) do
      {:ok, round} -> {:ok, assign(socket, [round: round, player: player, view_mode: "current_player", selected_card_index: 0, added_bet: 0])}
      {:error, _} -> {:ok, push_redirect(socket, to: "/room")}
    end
  end

  @impl true
  def handle_event("place_bet", _params, socket) do
    turn = get_turn(socket.assigns)
    Round.place_bet(socket.assigns.round.round_id, turn, turn.bet + socket.assigns.added_bet)
    {:noreply, socket}
  end

  @impl true
  def handle_event("stand", _params, socket) do
    turn = get_turn(socket.assigns)
    Round.stand(socket.assigns.round.round_id, turn)
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_card", %{"index" => index}, socket) do
    {:noreply, assign(socket, :selected_card_index, String.to_integer(index))}
  end

  @impl true
  def handle_event("bet_amount", %{"amount" => amount}, socket) do
    {:noreply, assign(socket, added_bet: String.to_integer(amount))}
  end

  @impl true
  def render(assigns) do
    turn = get_turn(assigns)
    assigns = Map.merge(assigns, %{turn: turn})
    index(assigns)
  end

  defp get_turn(assigns) do
    if assigns.view_mode == "self" do
      Enum.find(assigns.round.turns, &(&1.player.id == assigns.player.id))
    else
      Enum.find(assigns.round.turns, &(&1.player.id == assigns.round.current_player))
    end
  end

  @impl true
  def handle_info(:round_terminated, socket) do
    {:noreply, push_redirect(socket, to: "/room")}
  end

  @impl true
  def handle_info([turns: turns, current_player: current_player], socket) do
    #    when the current_player changes put the new status before changing the current player
    previous_player = socket.assigns.round.current_player
    if previous_player != current_player do
      Process.send_after(self(), [current_player: current_player], 3000)
      {:noreply, assign(socket, round: Map.merge(socket.assigns.round, %{turns: turns}), added_bet: 0)}
    else
      {:noreply, assign(socket, round: Map.merge(socket.assigns.round, %{turns: turns, current_player: current_player}), added_bet: 0)}
    end
  end

#  used after a win or lose
  @impl true
  def handle_info([current_player: current_player], socket) do
    {:noreply, assign(socket, :round, Map.put(socket.assigns.round, :current_player, current_player))}
  end

  def index(assigns) do
    self_view? = assigns.player.id == assigns.turn.player.id
    player_name = if self_view?, do: "You", else: "#{assigns.turn.player.first_name} #{assigns.turn.player.last_name}"
    # viewing own
    ~H"""
     <div class="p-3 flex flex-col h-full font-sans">
        <div class="text-center">
          <%= if self_view? do %>
            <span class="text-blue-800 font-bold	">you</span> are playing
            <% else %>
             <span class="text-blue-800 font-bold	"><%= player_name %></span> is playing
          <% end %>
        </div>
        <div class="flex-col justify-center relative align-center h-full w-full">
          <%= if (self_view?) or (assigns.turn.state in [:lost, :won]) or (assigns.turn.player.type == "admin" and assigns.turn.state != :pending) do %>
              <.revealed_cards self_view?={self_view?} turn={assigns.turn} selected_card_index={assigns.selected_card_index}/>
           <% else %>
              <.hidden_cards turn={assigns.turn}/>
           <% end %>
          <div class="absolute top-1/2 text-center font-bold animate-pulse w-full font-bold text-6xl z-50">
              <%= if assigns.turn.state == :won do %>
                <span x-data x-init={if self_view?, do: "confetti()"} class="text-green-700"><%= player_name %> won! 🎉</span>
              <% end %>
              <%= if assigns.turn.state == :lost do %>
                <span class="text-red-600 z-50"><%= player_name %> lost</span>
              <% end %>
              <%= if assigns.turn.state == :standby do %>
                <span class="text-gray-600 z-50">Standing</span>
              <% end %>
          </div>
        <%= if assigns.turn.player.type != "admin" do %>
           <div class="flex justify-center text-gray-800 text-xl">
            <span class="text-blue-700">$<span class="font-bold text-blue-800"><%= assigns.turn.bet + assigns.added_bet %></span></span>
           </div>
        <% end %>
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
            </button>
          </div>
        <% end %>
        <div class="flex -space-x-1 overflow-hidden my-1 p-2 justify-center">
          <%= for turn <- assigns.round.turns do %>
            <.avatar turn={turn} player={assigns.player}/>
          <% end %>
        </div>
      </div>
    """
  end

  def revealed_cards(assigns) do
    cards = Enum.with_index(assigns.turn.cards)
    ~H"""
      <div class="max-w-full">
        <.card card={Enum.at(cards, assigns.selected_card_index)}/>
      </div>
      <.card_list cards={cards} selected_card_index={assigns.selected_card_index} />
    """
  end

  def hidden_cards(assigns) do
    ~H"""
    <%= if length(assigns.turn.cards) == 0 do %>
      <div class="flex justify-center items-center w-full h-full">
          <span class="text-center" >
              Waiting for player...
          </span>
      </div>
    <% end %>
    <div class="flex -space-x-72">
      <%= for card <- assigns.turn.cards do%>
      <.blank_card card={card}/>
      <% end %>
      </div>
    """
  end

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

  def blank_card(assigns) do
    ~H"""
    <div class="p-3 flex justify-center">
        <img class="filter drop-shadow-xl h-auto w-4/5" src={Routes.static_path(KurtenWeb.Endpoint, "/images/blank.png")} class="w-auto"/>
    </div>
    """
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

  def avatar(assigns) do
    self? = assigns.player.id == assigns.turn.player.id
    player_name = if self? do
      "You"
      else
        "#{String.at(assigns.turn.player.first_name, 0) |> String.upcase}#{String.at(assigns.turn.player.last_name, 0) |> String.upcase}"
    end
    ~H"""
      <div class="one">
       <button class={"inline-block h-12 w-12 rounded-full ring-2 ring-gray-300 border-2 border-blue-100 border items-center bg-gray-100 shadow-xl flex justify-center #{if self?, do: "z-10 ring-green-700"}"}><%= player_name %></button>
        <%= if assigns.turn.state == :lost do %>
          <span class="flex text-red-700 text-center justify-center"><%= "-#{assigns.turn.bet}" %><span>
        <% end %>
        <%= if assigns.turn.state == :pending do %>
          <span class="flex text-gray-400	text-center justify-center">--<span>
        <% end %>
        <%= if assigns.turn.state == :standby do %>
          <span class="flex text-gray-400	text-center justify-center p-1">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
          <span>
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
end
