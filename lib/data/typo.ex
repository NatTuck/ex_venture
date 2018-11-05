defmodule Data.Typo do
  @moduledoc """
  Typo schema
  """

  use Data.Schema

  alias Data.Character
  alias Data.Room

  schema "typos" do
    field(:title, :string)
    field(:body, :string)

    belongs_to(:reporter, Character)
    belongs_to(:room, Room)

    timestamps()
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [:title, :body, :reporter_id, :room_id])
    |> validate_required([:title, :reporter_id, :room_id])
    |> foreign_key_constraint(:reporter_id)
    |> foreign_key_constraint(:room_id)
  end
end
