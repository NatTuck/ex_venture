defmodule Data.Mail do
  @moduledoc """
  Mail schema
  """

  use Data.Schema

  alias Data.Character

  schema "mail" do
    field(:title, :string)
    field(:body, :string)
    field(:is_read, :boolean, default: false)

    belongs_to(:sender, Character)
    belongs_to(:receiver, Character)

    timestamps()
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [:title, :body, :is_read, :sender_id, :receiver_id])
    |> validate_required([:title, :is_read, :sender_id, :receiver_id])
    |> foreign_key_constraint(:sender_id)
    |> foreign_key_constraint(:receiver_id)
  end
end
