defmodule Kurten.Round do

  alias Kurten.Turn
  alias Kurten.Deck
  alias Kurten.Room
  alias Phoenix.PubSub

  defstruct [:current_player, :round_id, :room_id, :deck, turns: []]

  # round should close itself if inactive for an hour
  @round_timeout 60 * 6000

  use GenServer
  @moduledoc """
    rounds need to be initialized, then turns are created and then finalized and closed.


    initialization

    1. create a deck
    2. keep track of players


    playing
    pick first person from list and create a turn.
    once a bet happens, determine if won or not and move on to next player accordingly.


    runtime constraints


    it is a server that holds state.


  """

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
    {:noreply, Map.put(state, :turns, merge_turn(state.turns, turn))}
  end

  def handle_cast({:bet, turn, amount}, state) do
    [picked_card | rest] = state.deck
    turn = Map.merge(turn, %{cards: [picked_card | turn.cards], bet: amount, state: Turn.calc_state([picked_card | turn.cards])})
    turns = merge_turn(state.turns, turn)
    case get_next_turn(turns) do
      nil -> terminate_game(Map.put(state, :turns, turns))
      next_turn -> PubSub.broadcast(Kurten.PubSub, "round:#{state.round_id}", [turns: turns, current_player: next_turn.player.id])
              {:noreply, Map.merge(state, %{turns: turns, current_player: next_turn.player.id, deck: rest})}
    end
  end

  def handle_call({:leave, player_id}, _from, state) do
    players = Enum.filter(state.players, &(&1 != player_id))
    {:reply, :ok, Map.put(state, :players, players)}
  end

  def handle_call(:round, _from, state) do
    {:reply, state, state}
  end

  def terminate_game(state) do
    PubSub.broadcast(Kurten.PubSub, "round:#{state.round_id}", :round_terminated)
    GenServer.cast(Room.via_tuple(state.room_id), {:round_complete, state.turns})
    Process.exit(self(), :normal)
  end

  def continue_game(state) do
  end

  @spec get_next_turn(any()) :: nil | any()
  defp get_next_turn(turns) do
    pending_turns = Enum.filter(turns, &(&1.state == :pending))
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
