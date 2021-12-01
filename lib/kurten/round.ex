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

  def handle_cast({:standby, turn}, state) do
    turn = Map.put(turn, :state, :standby)
    turns = merge_turn(state.turns, turn)
    state = Map.put(state, :turns, turns)
    case get_next_turn(turns) do
      {:ok, turn} -> state = Map.put(state, :current_player, turn.player.id)
                     broadcast(state)
                     {:noreply, state}
      :terminate -> broadcast(state)
                    Process.send_after(self(), :terminate_game, 5000)
                    {:noreply, state}
    end
  end

  def handle_cast({:bet, turn, amount}, state) do
    [picked_card | rest] = state.deck
    turn = Map.merge(
      turn,
      %{cards: [picked_card | turn.cards], bet: amount, state: Turn.calc_state([picked_card | turn.cards])}
    )
    turns = merge_turn(state.turns, turn)
    state = Map.merge(state, %{turns: turns, deck: rest})
    case get_next_turn(turns) do
      {:ok, turn} -> state = Map.put(state, :current_player, turn.player.id)
                     broadcast(state)
                     {:noreply, state}
      :terminate -> broadcast(state)
                    Process.send_after(self(), :terminate_game, 5000)
                    {:noreply, state}
    end
  end

  @spec get_next_turn([any()]) :: {:ok, any()} | :terminate
  def get_next_turn(turns) do
    # if there isn't a player anymore, return :terminate else next_turn
    pending_turns = Enum.filter(turns, &(&1.state == :pending and &1.player.type != "admin"))
    admin_turn = Enum.find(turns, &(&1.player.type == "admin"))
    standing_turns = Enum.filter(turns, &(&1.state == :standby))
    cond  do
      # only the admin remains
      is_nil(pending_turns) and length(standing_turns) > 0 and not admin_turn.state == :pending -> {:ok, admin_turn}
      # everybody played and nobody standing
      is_nil(pending_turns) -> :terminate
      # there are still other players
      true -> {:ok, hd(pending_turns)}
    end
  end

  def broadcast(state) do
    PubSub.broadcast(Kurten.PubSub, "round:#{state.round_id}", [turns: state.turns, current_player: state.current_player])
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
    player_total > (admin_total || 0)
  end

  def get_winning_number(cards) do
    Turn.get_sums(cards) |> Enum.filter(&(&1 <= 21)) |> Enum.sort(&(&1 > &2)) |> Enum.at(0)
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
