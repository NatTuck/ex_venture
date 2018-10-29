defmodule Game.Room.Repo do
  @moduledoc """
  Repo helper for the Room modules
  """

  import Ecto.Query

  alias Data.Exit
  alias Data.Room
  alias Data.Repo

  @doc """
  Load all rooms
  """
  @spec all() :: [Room.t()]
  def all() do
    Room
    |> preload([:room_items, :shops, :zone])
    |> Repo.all()
  end

  @doc """
  Get a room
  """
  @spec get(integer) :: [Room.t()]
  def get(id) do
    case Room |> Repo.get(id) do
      nil ->
        nil

      room ->
        room
        |> Exit.load_exits()
        |> Repo.preload([:room_items, :shops, :zone])
    end
  end

  @doc """
  Load all rooms in a zone
  """
  @spec for_zone(integer()) :: [integer()]
  def for_zone(zone_id) do
    Room
    |> where([r], r.zone_id == ^zone_id)
    |> select([r], r.id)
    |> Repo.all()
  end

  def update(room, params) do
    room
    |> Room.changeset(params)
    |> Repo.update()
  end

  @doc """
  Read through cache for the global resources
  """
  def get_name(id) do
    case Room |> Repo.get(id) do
      nil ->
        {:error, :unknown}

      room ->
        {:ok, Map.take(room, [:id, :name])}
    end
  end
end
