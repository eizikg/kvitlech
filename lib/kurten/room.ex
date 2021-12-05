defmodule Kurten.Room do
  alias Phoenix.PubSub
  alias Kurten.Round
  alias Kurten.Room

  use GenServer

  defstruct [:admin, :room_id, :round_id, balances: [],  players: []]


  def init(args) do
    Phoenix.PubSub.subscribe(Kurten.PubSub, "presence:#{args[:room_id]}")
    {:ok, %Room{players: [args[:admin]], room_id: args[:room_id], balances: []}}
  end

  def start_link(options) do
    GenServer.start_link(__MODULE__, Keyword.take(options, [:admin, :room_id]), options)
  end

  def handle_info(%{event: "presence_diff", payload: diff}, state) do
    %{joins: joins, leaves: leaves} = diff
    players = Enum.map(state.players, fn player ->
      cond do
        Map.has_key?(joins, player.id) -> Map.put(player, :presence, "online")
        Map.has_key?(leaves, player.id) -> Map.put(player, :presence, "offline")
        true -> player
      end
    end)
    state = Map.put(state, :players, players)
    broadcast(state)
    {:noreply, state}
  end

  def handle_info(:timeout, _) do
    Process.exit(self(), :normal)
  end

  def handle_cast({:switch_admin, player_id}, state) do
    players = Enum.map(state.players, fn player ->
      cond do
        player.id == player_id -> Map.put(player, :type, "admin")
        player.type == "admin" -> Map.put(player, :type, "player")
        true -> player
      end
    end)
    state = Map.put(state, :players, players)
    broadcast(state)
    {:noreply, state}
  end

  def handle_call({:join, player}, _from, state) do
    players = [player | state.players]
    state = Map.put(state, :players, players)
    broadcast(state)
    {:reply, state, state}
  end

  def handle_call(:room, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:leave, player_id}, _from, state) do
    players = Enum.filter(state.players, fn player -> player.id != player_id end)
    state = Map.put(state, :players, players)
    broadcast(state)
    {:reply, :ok, state}
  end

  def broadcast(state) do
    PubSub.broadcast(Kurten.PubSub, "room:#{state.room_id}", [players: state.players])
  end

  def handle_cast(:create_round, state) do
    round_id = UUID.generate()
    via_tuple = {:via, Registry, {Kurten.RoundRegistry, round_id}}
    active_players = Enum.filter(state.players, fn player -> player.presence == "online" end)
    {:ok, _pid} = GenServer.start_link(Round, [players: active_players, round_id: round_id, room_id: state.room_id], name: via_tuple)
    PubSub.broadcast(Kurten.PubSub, "room:#{state.room_id}", :round_started)
    {:noreply, Map.put(state, :round_id, round_id)}
  end

  def handle_cast({:round_complete, balances}, state) do
    {:noreply, Map.merge(state, %{balances: balances ++ state.balances, round_id: nil})}
  end

#  client

  def create_room(admin) do
    room_id = UUID.generate()
    {:ok, _pid} = DynamicSupervisor.start_child(Kurten.RoomSupervisor, {__MODULE__, [name: via_tuple(room_id), room_id: room_id, admin: admin]})
    {:ok, room_id}
  end

  def via_tuple(name) do
    {:via, Registry, {Kurten.RoomRegistry, name}}
  end

  def join_room(player, room_id) do
    GenServer.call(via_tuple(room_id), {:join, player})
  end

  def start_round(room_id) do
    GenServer.cast(via_tuple(room_id), :create_round)
  end

  def get_info_for_player(room_id, player_id) do
    with {:ok, room} <- get_info(room_id),
         {:ok, player} <- find_player(room.players, player_id) do
      {:ok, room, player}
    end
  end

  def get_info(room_id) do
    try do
      room = GenServer.call({:via, Registry, {Kurten.RoomRegistry, room_id}}, :room)
      {:ok, Map.put(room, :admin, get_admin(room))}
    catch
      :exit, _ -> {:error, :not_found}
    end
  end

  def switch_admin(room_id, player_id) do
    GenServer.cast({:via, Registry, {Kurten.RoomRegistry, room_id}}, {:switch_admin, player_id})
  end

  def leave(room_id, player_id) do
    GenServer.call({:via, Registry, {Kurten.RoomRegistry, room_id}}, {:leave, player_id})
  end

  defp get_admin(room) do
    Enum.find(room.players, &(&1.type == "admin"))
  end

  defp find_player(players, player_id) do
    Enum.find(players, &(&1.id == player_id))
    |> case do
      nil -> {:error, :player_not_found}
      player -> {:ok, player}
    end
  end

end
