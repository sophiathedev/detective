defmodule Detective.Cases do
  @moduledoc """
  Published, immutable case definitions available for room creation.
  """

  import Ecto.Query, warn: false

  alias Detective.Cases.{CaseFile, CaseVersion}
  alias Detective.Repo

  def list_published_versions do
    CaseVersion
    |> join(:inner, [version], case_file in assoc(version, :case_file))
    |> where([version, case_file], not is_nil(version.published_at))
    |> where([_version, case_file], case_file.status == "published")
    |> order_by([version, case_file], asc: case_file.title, desc: version.version)
    |> preload([_version, case_file], case_file: case_file)
    |> Repo.all()
  end

  def get_published_version(id) do
    CaseVersion
    |> join(:inner, [version], case_file in assoc(version, :case_file))
    |> where([version, case_file], version.id == ^id)
    |> where([version, case_file], not is_nil(version.published_at))
    |> where([_version, case_file], case_file.status == "published")
    |> preload([_version, case_file], case_file: case_file)
    |> Repo.one()
  end

  def create_case(attrs) do
    %CaseFile{}
    |> CaseFile.changeset(attrs)
    |> Repo.insert()
  end

  def create_version(%CaseFile{} = case_file, attrs) do
    %CaseVersion{case_file: case_file, case_id: case_file.id}
    |> CaseVersion.changeset(attrs)
    |> Repo.insert()
  end
end
