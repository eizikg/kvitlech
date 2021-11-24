defmodule Kurten.Room do
  alias Phoenix.PubSub
  alias Kurten.Round

  use GenServer

  @moduledoc """
  rooms have players
"""

  def init(args) do
    {:ok, %{players: [args[:admin]], room_id: args[:room_id]}}
  end

  def start_link(options) do
    GenServer.start_link(__MODULE__, Keyword.take(options, [:admin, :room_id]), options)
  end

  def handle_call({:join, player}, _from, state) do
    state = Map.put(state, :players, [player | state.players])
    PubSub.broadcast(Kurten.PubSub, "room:#{state.room_id}", {:player_joined, player})
    {:reply, state, state}
  end

  def handle_call(:room, _from, state) do
    {:reply, state, state}
  end

  def handle_cast(:create_round, state) do
    round_id = UUID.uuid1()
    via_tuple = {:via, Registry, {Kurten.RoundRegistry, round_id}}
    {:ok, _pid} = GenServer.start_link(Round, [players: Enum.map(state.players, &(&1.id)), round_id: round_id], name: via_tuple)
    PubSub.broadcast(Kurten.PubSub, "room:#{state.room_id}", :round_started)
    {:noreply, Map.put(state, :round_id, round_id)}
  end
#  client

  def create_room(admin) do
    room_id = UUID.uuid1()
    {:ok, _pid} = DynamicSupervisor.start_child(Kurten.RoomSupervisor, {__MODULE__, [name: via_tuple(room_id), room_id: room_id, admin: admin]})
    {:ok, room_id}
  end

  defp via_tuple(name) do
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
