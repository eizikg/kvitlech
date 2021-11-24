defmodule Kurten.Round do

  alias Kurten.Turn
  alias Kurten.Deck
  alias Phoenix.PubSub

  defstruct [:round_id, :deck, players: [], turns: []]

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
    {:ok, %Kurten.Round{deck: deck, players: attrs[:players], round_id: attrs[:round_id]}}
  end

  def handle_cast({:join, player}, state) do
    players = state.players ++ [player]
    PubSub.broadcast(Kurten.PubSub, "round:#{state.round_id}", [players: players])
    {:noreply, Map.put(state, :players, players)}
  end

  def handle_cast({:init_turn, player}, state) do
    turns = state.turns ++ %Turn{player: player}
    PubSub.broadcast(Kurten.PubSub, "round:#{state.round_id}", [turns: turns])
    {:noreply, Map.put(state, :turns, turns)}
  end

  def handle_call(:round, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:bet, player, amount}, _from, state) do
    turn = Enum.find(state.turns, fn turn -> turn.player  end)
    [card | rest] = state.cards
    new_cards = Map.put(turn, :cards, [card | turn.cards])
    turn = Map.merge(turn, %{cards: new_cards, state: Turn.calc_state(new_cards)})
    {:reply, Map.put(state, :turns, state.turns)}
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

  defp via_tuple(round_id) do
    {:via, Registry, {Kurten.RoundRegistry, round_id}}
  end

end
