defmodule Detective.Cases.CaseFile do
  use Ecto.Schema
  import Ecto.Changeset

  alias Detective.Cases.CaseVersion

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "cases" do
    field :slug, :string
    field :title, :string
    field :description, :string
    field :status, :string, default: "draft"

    has_many :versions, CaseVersion, foreign_key: :case_id

    timestamps(type: :utc_datetime)
  end

  def changeset(case_file, attrs) do
    case_file
    |> cast(attrs, [:slug, :title, :description, :status])
    |> update_change(:slug, &String.downcase/1)
    |> validate_required([:slug, :title, :description, :status])
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
    |> validate_length(:title, min: 3, max: 120)
    |> validate_length(:description, min: 10, max: 1_000)
    |> validate_inclusion(:status, ~w(draft published archived))
    |> unique_constraint(:slug)
  end
end
