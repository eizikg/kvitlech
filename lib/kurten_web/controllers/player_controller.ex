defmodule KurtenWeb.PlayerController do
  use KurtenWeb, :controller
  alias Kurten.Player
  alias Kurten.Room


  def new(conn, %{"room_id" => room_id}) do
    changeset = Player.changeset(%{})
    case Room.get_info(room_id) do
      {:ok, room} -> render(conn, "new.html", [changeset: changeset, room: room])
      {:error, _} -> redirect_home(conn)
    end
  end

  def new(conn, _params) do
    changeset = Player.changeset(%{})
    render(conn, "new.html", [changeset: changeset, room: %{}])
  end

#  create new room
  def create(conn, %{"player" => params}) do
    {:ok, room_id, player} = Player.create(params)
    conn
    |> put_session(:player_id, player.id)
    |> put_session(:room_id, room_id)
    |> redirect(to: "/room")
  end

#  join existing room
  def join(conn, %{"player" => player} = params) do
    IO.inspect(player)
    {:ok, room, player} = Player.create(player, params["room_id"])
    conn
    |> put_session(:player_id, player.id)
    |> put_session(:room_id, room.room_id)
    |> redirect(to: "/room")
  end

  defp redirect_home(conn) do
    conn
    |> put_flash(:room, "The game does not exist.")
    |> redirect(to: Routes.home_path(conn, :index))
    |> halt
  end
end