defmodule Web.Feature do
  @moduledoc """
  Context for Features
  """

  import Ecto.Query

  alias Data.Feature
  alias Data.Repo
  alias Game.Features
  alias Web.Filter
  alias Web.Pagination

  @behaviour Filter

  @doc """
  Get all features
  """
  @spec all(Keyword.t()) :: [Feature.t()]
  def all(opts \\ []) do
    opts = Enum.into(opts, %{})

    Feature
    |> order_by([f], asc: f.key)
    |> Filter.filter(opts[:filter], __MODULE__)
    |> Pagination.paginate(opts)
  end

  @impl Filter
  def filter_on_attribute({"key", key}, query) do
    query |> where([f], ilike(f.key, ^"%#{key}%"))
  end

  @doc """
  Get a single feature
  """
  @spec get(integer()) :: Feature.t()
  def get(id) do
    Feature
    |> Repo.get(id)
  end

  @doc """
  Get a changeset for a new page
  """
  @spec new() :: Ecto.Changeset.t()
  def new(), do: %Feature{} |> Feature.changeset(%{})

  @doc """
  Get a changeset for an edit page
  """
  @spec edit(Feature.t()) :: Ecto.Changeset.t()
  def edit(feature), do: feature |> Feature.changeset(%{})

  @doc """
  Create an feature
  """
  @spec create(map()) :: {:ok, Feature.t()} | {:error, Ecto.Changeset.t()}
  def create(params) do
    changeset = %Feature{} |> Feature.changeset(cast_params(params))

    case changeset |> Repo.insert() do
      {:ok, feature} ->
        Features.insert(feature)
        {:ok, feature}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Update an feature
  """
  @spec update(integer(), map()) :: {:ok, Feature.t()} | {:error, Ecto.Changeset.t()}
  def update(id, params) do
    feature = id |> get()
    changeset = feature |> Feature.changeset(cast_params(params))

    case changeset |> Repo.update() do
      {:ok, feature} ->
        Features.reload(feature)
        {:ok, feature}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Delete a feature
  """
  @spec delete(integer()) :: {:ok, Feature.t()}
  def delete(id) do
    feature = id |> get()
    case feature |> Repo.delete() do
      {:ok, feature} ->
        Features.remove(feature)
        {:ok, feature}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Cast params into what `Data.Feature` expects
  """
  @spec cast_params(map) :: map
  def cast_params(params) do
    params
    |> parse_tags()
  end

  defp parse_tags(params = %{"tags" => tags}) do
    tags =
      tags
      |> String.split(",")
      |> Enum.map(&String.trim/1)

    params
    |> Map.put("tags", tags)
  end

  defp parse_tags(params), do: params
end
