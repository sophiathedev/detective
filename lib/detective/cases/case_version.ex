defmodule Detective.Cases.CaseVersion do
  use Ecto.Schema
  import Ecto.Changeset

  alias Detective.Cases.CaseFile

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "case_versions" do
    field :version, :integer
    field :content, :map, redact: true
    field :published_at, :utc_datetime

    belongs_to :case_file, CaseFile, foreign_key: :case_id

    timestamps(type: :utc_datetime)
  end

  def changeset(case_version, attrs) do
    case_version
    |> cast(attrs, [:version, :content, :published_at])
    |> validate_required([:case_id, :version, :content])
    |> validate_number(:version, greater_than: 0)
    |> foreign_key_constraint(:case_id)
    |> unique_constraint([:case_id, :version])
  end
end
