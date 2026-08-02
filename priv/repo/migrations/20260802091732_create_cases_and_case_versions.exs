defmodule Detective.Repo.Migrations.CreateCasesAndCaseVersions do
  use Ecto.Migration

  def change do
    create table(:cases, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :title, :string, null: false
      add :description, :text, null: false
      add :status, :string, null: false, default: "draft"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:cases, [:slug])

    create constraint(:cases, :cases_status_check,
             check: "status IN ('draft', 'published', 'archived')"
           )

    create table(:case_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :case_id, references(:cases, type: :binary_id), null: false
      add :version, :integer, null: false
      add :content, :map, null: false
      add :published_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:case_versions, [:case_id, :version])
    create index(:case_versions, [:published_at])

    create constraint(:case_versions, :case_versions_positive_version, check: "version > 0")
  end
end
