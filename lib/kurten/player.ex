defmodule Kurten.Player do
  use Ecto.Schema
  import Ecto.Changeset
  alias Kurten.Room

  @primary_key false

  embedded_schema do
    field :name, :string
    field :room_id, :string
    field :id, :string
    field :type, :string, default: "player"
  end

  def changeset(params) do
   %__MODULE__{}
   |> cast(params, [:name, :type])
   |> validate_required([:name])
   |> generate_uuid
  end

  def create(params, room_id) do
    player = changeset(params)
    |> apply_changes
    room = Room.join_room(player, room_id)
    {:ok, room, player}
  end

  def create(params) do
    params = Map.put(params, "type", "admin")
    player = changeset(params)
    |> apply_changes
    {:ok, room_id} = Room.create_room(player)
    {:ok, room_id, player}
  end

  def generate_uuid(changeset) do
    uuid = UUID.uuid1()
    put_change(changeset, :id, uuid)
  end

end
