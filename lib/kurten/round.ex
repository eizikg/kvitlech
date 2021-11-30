defmodule Kurten.Round do

  alias Kurten.Turn
  alias Kurten.Deck
  alias Kurten.Room
  alias Phoenix.PubSub

  defstruct [:current_player, :round_id, :room_id, :deck, turns: []]

  # round should close itself if inactive for an hour
  @round_timeout 60 * 6000

  use GenServer

  def init(attrs) do
    deck = Deck.new()
    turns = Turn.initialize(attrs[:players])
    {:ok, %Kurten.Round{current_player: get_next_turn(turns).player.id, deck: deck, turns: turns, round_id: attrs[:round_id], room_id: attrs[:room_id]}}
  end

  def handle_cast({:join, player}, state) do
    turns = state.turns ++ Turn.initialize([player])
    PubSub.broadcast(Kurten.PubSub, "round:#{state.round_id}", [turns: turns])
    {:noreply, Map.put(state, :turns, turns)}
  end

  def handle_cast({:standby, turn}, state) when turn.player.type == "admin" do
    turn = Map.put(turn, :state, :standby)
    turns = merge_turn(state.turns, turn)
    state = Map.put(state, :turns, turns)
    Process.send_after(self(), :terminate_game, 5000)
    {:noreply, state}
  end

  def handle_cast({:standby, turn}, state) do
    turn = Map.put(turn, :state, :standby)
    turns = merge_turn(state.turns, turn)
    next_turn = get_next_turn(turns)
    state = Map.merge(state, %{turns: turns, current_player: next_turn.player.id})
    PubSub.broadcast(Kurten.PubSub, "round:#{state.round_id}", [turns: state.turns, current_player: state.current_player])
    {:noreply, state}
  end

  def handle_cast({:bet, turn, amount}, state) when turn.player.type == "admin" do
    [picked_card | rest] = state.deck
    turn = Map.merge(turn, %{cards: [picked_card | turn.cards], bet: amount, state: Turn.calc_state([picked_card | turn.cards])})
    turns = merge_turn(state.turns, turn)
    state = Map.merge(state, %{turns: turns, deck: rest})
    case turn.state do
      :pending -> PubSub.broadcast(Kurten.PubSub, "round:#{state.round_id}", [turns: turns, current_player: state.current_player])
                  {:noreply, state}
      _ -> Process.send_after(self(), :terminate_game, 5000)
           PubSub.broadcast(Kurten.PubSub, "round:#{state.round_id}", [turns: turns, current_player: state.current_player])
           {:noreply, state}
    end
  end

  def handle_cast({:bet, turn, amount}, state) do
    [picked_card | rest] = state.deck
    turn = Map.merge(turn, %{cards: [picked_card | turn.cards], bet: amount, state: Turn.calc_state([picked_card | turn.cards])})
    turns = merge_turn(state.turns, turn)
    next_turn = get_next_turn(turns)
    PubSub.broadcast(Kurten.PubSub, "round:#{state.round_id}", [turns: turns, current_player: next_turn.player.id])
    {:noreply, Map.merge(state, %{turns: turns, current_player: next_turn.player.id, deck: rest})}
  end

  def handle_call({:leave, player_id}, _from, state) do
    players = Enum.filter(state.players, &(&1 != player_id))
    {:reply, :ok, Map.put(state, :players, players)}
  end

  def handle_call(:round, _from, state) do
    {:reply, state, state}
  end

#  terminate game when admin stands or lost.
  def handle_info(:terminate_game, state) do
    balances = calculate_balances(state.turns)
    PubSub.broadcast(Kurten.PubSub, "round:#{state.round_id}", {:round_terminated, state})
    GenServer.cast(Room.via_tuple(state.room_id), {:round_complete, balances})
    Process.exit(self(), :normal)
  end

  defp calculate_balances(turns) do
    %{admin: admin_turn, players: player_turns} = Enum.reduce(turns, %{players: []}, fn turn, acc ->
      if turn.player.type == "admin" do
        Map.put(acc, :admin, turn)
      else
        Map.put(acc, :players, [turn | acc.players])
      end
    end)
    new_balances = Enum.map(player_turns, fn turn ->
      case turn.state do
        :lost -> %{amount: turn.bet, payee: admin_turn.player.id, payer: turn.player.id}
        :standby -> if player_won?(admin_turn, turn), do: %{amount: turn.bet, payer: admin_turn.player.id, payee: turn.player.id}, else: %{amount: turn.bet, payee: admin_turn.player.id, payer: turn.player.id}
        :won -> %{amount: turn.bet, payer: admin_turn.player.id, payee: turn.player.id}
      end
    end)
  end

  defp player_won?(admin_turn, player_turn) do
    player_total = get_winning_number(player_turn.cards)
    admin_total = get_winning_number(admin_turn.cards)
    player_total > admin_total
  end

  def get_winning_number(cards) do
    Turn.get_sums(cards) |> Enum.filter(&(&1 <= 21)) |> Enum.sort(&(&1 > &2)) |> Enum.at(0)
  end

  @spec get_next_turn(any()) :: nil | any()
  defp get_next_turn(turns) do
    pending_turns = Enum.filter(turns, &(&1.state == :pending))
    standing_turns = Enum.filter(turns, &(&1.state == :standby))
    if length(pending_turns) == 1 do
      #      only the admin remains
      hd(pending_turns)
    else
      Enum.find(pending_turns, fn turn -> turn.state == :pending and turn.player.type != "admin" end)
    end
  end

  defp merge_turn(turns, turn) do
    Enum.map(turns, fn t ->
      if t.player.id == turn.player.id do
        turn
      else
        t
      end
    end)
  end

#  callbacks
  def get_info(round_id) do
    try do
      round = GenServer.call(via_tuple(round_id), :round)
      {:ok, round}
      rescue
       _e -> {:error, :not_found}
    end
  end

  def place_bet(round_id, turn, amount) do
    GenServer.cast(via_tuple(round_id), {:bet, turn, amount})
  end

  def stand(round_id, turn) do
    GenServer.cast(via_tuple(round_id), {:standby, turn})
  end

  defp via_tuple(round_id) do
    {:via, Registry, {Kurten.RoundRegistry, round_id}}
  end

end
