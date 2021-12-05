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
      {:ok, round} -> {:ok, assign(socket, compute_state(%{turns: round.turns, player: player, current_player: round.current_player, round_id: round.round_id}))}
      {:error, _} -> {:ok, push_redirect(socket, to: "/room")}
    end
  end

  def compute_state(%{turns: turns, player: player, current_player: current_player, round_id: round_id}, assigns \\ []) do
    viewing_player = current_player
    turn = Enum.find(turns, fn turn -> turn.player.id == viewing_player end)
    current_turn = Enum.find(turns, fn turn -> turn.player.id == current_player end)
    viewing_self = turn.player.id == player.id
    [turn: turn, turns: turns, added_bet: 0, selected_card_index: 0, viewing_self: viewing_self, round_id: round_id, current_turn: current_turn, player: player]
  end

  @impl true
  def handle_event("place_bet", _params, socket) do
    turn = socket.assigns.turn
    Round.place_bet(socket.assigns.round_id, turn, turn.bet + socket.assigns.added_bet)
    {:noreply, socket}
  end

  def handle_event("view_player", %{"player_id" => player_id}, socket) do
    turn = Enum.find(socket.assigns.turns, fn turn -> turn.player.id == player_id end)
    viewing_self = turn.player.id == socket.assigns.player.id
    {:noreply, assign(socket, turn: turn, viewing_self: viewing_self)}
  end

  @impl true
  def handle_event("stand", _params, socket) do
    Round.stand(socket.assigns.round_id, socket.assigns.turn)
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

  def handle_event("skip", _params, socket) do
    Round.skip(socket.assigns.round_id, socket.assigns.turn)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
      <.index turns={assigns.turns} turn={assigns.turn} player={assigns.player} added_bet={assigns.added_bet}, selected_card_index={assigns.selected_card_index} viewing_self={assigns.viewing_self} round_id={assigns.round_id} current_turn={assigns.current_turn}/>
    """
  end

  def get_current_turn(assigns) do
    Enum.find(assigns.round.turns, &(&1.player.id == assigns.round.current_player))
  end

  @impl true
  def handle_info(:round_terminated, socket) do
    {:noreply, push_redirect(socket, to: "/room")}
  end

  @impl true
  def handle_info([turns: turns, current_player: current_player], socket) do
    #    when the current_player changes put the new status before changing the current player
    previous_player = socket.assigns.current_turn.player.id
    if previous_player != current_player do
      Process.send_after(self(), [current_player: current_player], 3000)
      state = compute_state(%{turns: turns, player: socket.assigns.player, current_player: socket.assigns.current_turn.player.id, round_id: socket.assigns.round_id})
      {:noreply, assign(socket, state)}
    else
      state = compute_state(%{turns: turns, player: socket.assigns.player, current_player: current_player, round_id: socket.assigns.round_id})
      {:noreply, assign(socket, state)}
    end
  end

#  used after a win or lose
  @impl true
  def handle_info([current_player: current_player], socket) do
    state = assign(socket, compute_state(%{turns: socket.assigns.turns, player: socket.assigns.player, current_player: current_player, round_id: socket.assigns.round_id}))
    {:noreply, state}
  end

  def self_view?(player, turn) do
    player.id == turn.player.id
  end

  defp player_name(player, self) do
    if self do
      "You"
      else
      "#{player.first_name} #{player.last_name}"
    end
  end

  def index(assigns) do
    ~H"""
     <div x-data x-init={if assigns.current_turn.player.id == assigns.player.id and length(assigns.current_turn.cards) == 1 , do: "navigator.vibrate(200)"} class="p-3 flex flex-col h-full font-sans">
        <div class="text-center">
            <span class="text-blue-800 font-bold	"><%= player_name(assigns.turn.player, assigns.viewing_self) %></span>
        </div>
        <div class="flex-col justify-center relative align-center h-full w-full">
          <%= if (assigns.viewing_self) or (assigns.turn.state in [:lost, :won]) or (assigns.turn.player.type == "admin") do %>
              <.revealed_cards viewing_self={assigns.viewing_self} turn={assigns.turn} selected_card_index={assigns.selected_card_index}/>
           <% else %>
              <.hidden_cards turn={assigns.turn}/>
           <% end %>
          <div class="absolute top-1/2 text-center font-bold animate-pulse w-full font-bold text-6xl z-50">
              <%= if assigns.turn.state == :won do %>
                <span x-data x-init={if assigns.viewing_self, do: "confetti()"} class="text-green-700"><%= player_name(assigns.turn.player, assigns.viewing_self) %> won! 🎉</span>
              <% end %>
              <%= if assigns.turn.state == :lost do %>
                <span class="text-red-600 z-50"><%= player_name(assigns.turn.player, assigns.viewing_self) %> lost</span>
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
        <%= if assigns.viewing_self and assigns.turn.state == :pending and assigns.current_turn.player.id == assigns.player.id do%>
          <%= if assigns.player.type != "admin" do %>
            <.bet_amount bet={assigns.turn.bet} added_bet={assigns.added_bet}/>
          <% end %>
          <div class="flex justify-center align-center space-x-2">
            <%= if length(assigns.turn.cards) > 1 do %>
              <button phx-click="stand" class="border border-3 border-red-700 bg-white hover:bg-gray-200 text-red-700 font-bold py-2 px-4 rounded" > Stand </button>
            <% end %>
            <button disabled={(assigns.turn.bet + assigns.added_bet == 0 and assigns.turn.player.type != "admin") || assigns.turn.state != :pending} phx-click="place_bet" class="disabled:opacity-50 border border-1 text-nowrap border-green-700 text-white font-bold py-2 px-4 rounded" style="background-color: limegreen">Place bet
            </button>
          </div>
        <% end %>
        <div class="flex justify-center">
          <%= if assigns.current_turn.player.id == assigns.player.id do %>
            <span class="text-blue-800 font-bold	">You are playing</span>
            <% else %>
             <span class="text-blue-800 font-bold	"><%= player_name(assigns.current_turn.player, false) %> is playing</span>
          <% end %>
        </div>
        <%= if assigns.player.type == "admin" and assigns.turn.player.id != assigns.player.id and assigns.turn.state == :pending do %>
           <div class="flex justify-center">
              <button class="btn-blue" phx-click="skip">Skip <%= assigns.turn.player.first_name %></button>
           </div>
        <% end %>
        <div class="flex -space-x-1 overflow-hidden my-1 p-2 justify-center">
          <%= for turn <- assigns.turns do %>
            <.avatar turn={turn} viewing_turn={assigns.turn} current_turn={assigns.current_turn} self={turn.player.id == assigns.player.id}/>
          <% end %>
        </div>
      </div>
    """
  end

  def revealed_cards(assigns) do
    cards = Enum.with_index(assigns.turn.cards)
    ~H"""
      <%= if assigns.turn.player.type == "admin" and not assigns.viewing_self and assigns.turn.state == :pending do %>
         <div class="max-w-full">
            <.blank_card card={Enum.at(cards, 0)}/>
          </div>
          <.card_list cards={Enum.slice(cards, 1..length(cards))} selected_card_index={assigns.selected_card_index} />
      <% else %>
        <div class="max-w-full">
          <.card card={Enum.at(cards, assigns.selected_card_index)}/>
        </div>
        <.card_list cards={cards} selected_card_index={assigns.selected_card_index} />
      <% end %>
    """
  end

  def hidden_cards(assigns) do
    ~H"""
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
        <img class="filter drop-shadow-xl h-auto w-3/5" src={Routes.static_path(KurtenWeb.Endpoint, "/images/blank.png")} class="w-auto"/>
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

  def player_short_name(player, self) do
    if self do
      "You"
      else
      "#{String.at(player.first_name, 0) |> String.upcase}#{String.at(player.last_name, 0) |> String.upcase}"
    end
  end

  def avatar(assigns) do
#    turn={turn} viewing_turn={assigns.turn} current_turn={assigns.current_turn} self={turn.player.id == assigns.player.id}
    ~H"""
      <div>
       <button phx-click="view_player" phx-value-player_id={assigns.turn.player.id}  class={"inline-block h-12 w-12 rounded-full ring-2 ring-gray-300 border-2 border-blue-100 border items-center bg-gray-100 shadow-xl flex justify-center #{if assigns.current_turn.player.id == assigns.turn.player.id, do: "z-10 ring-green-700"}"}><%= player_short_name(assigns.turn.player, assigns.self) %></button>
        <div class="flex flex-col">
        <%= if assigns.turn.state == :lost do %>
          <span class="flex text-red-700 text-center justify-center"><%= "-#{assigns.turn.bet}" %></span>
        <% end %>
        <%= if assigns.turn.state == :pending do %>
          <span class="flex text-gray-400	text-center justify-center">--</span>
        <% end %>
        <%= if assigns.turn.state == :skipped do %>
            <span class="flex text-gray-400	text-center justify-center">ｘ</span>
          <% end %>
        <%= if assigns.turn.state == :standby do %>
            <div class="flex justify-center align-center text-center pt-2 h-full text-gray-400	text-center justify-center">
            <div class="h-6 flex justify-center align-center items-center text-center">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 11.5V14m0-2.5v-6a1.5 1.5 0 113 0m-3 6a1.5 1.5 0 00-3 0v2a7.5 7.5 0 0015 0v-5a1.5 1.5 0 00-3 0m-6-3V11m0-5.5v-1a1.5 1.5 0 013 0v1m0 0V11m0-5.5a1.5 1.5 0 013 0v3m0 0V11" />
              </svg>
            </div>
            <text class="flex pb-2 items-center text-center text-blue-800"><%= "#{assigns.turn.bet}" %></text>
          </div>
        <% end %>
        <%= if assigns.turn.state == :won do %>
          <span class="flex text-green-700 text-center justify-center"><%= "#{assigns.turn.bet}" %></span>
        <% end %>
        <%= if assigns.viewing_turn.player.id == assigns.turn.player.id do %>
            <div class="flex justify-center p-2">
            <div class="h-1 rounded bg-blue-700 w-6"></div>
            </div>
        <% end %>
        </div>
    </div>
    """
  end

  def card(assigns) do
    {card, _} = assigns.card
      ~H"""
      <div class="p-3 flex justify-center">
          <img class="filter drop-shadow-xl h-auto w-3/5" src={Routes.static_path(KurtenWeb.Endpoint, "/images/#{card.name}.png")} class="w-auto"/>
      </div>
      """
  end
end
