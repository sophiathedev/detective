defmodule Detective.CasesFixtures do
  alias Detective.Cases

  def case_file_fixture(attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    attrs =
      Enum.into(attrs, %{
        slug: "case-#{unique}",
        title: "Case #{unique}",
        description: "An original investigation prepared for automated tests.",
        status: "published"
      })

    {:ok, case_file} = Cases.create_case(attrs)
    case_file
  end

  def case_version_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    {case_file, attrs} = Map.pop_lazy(attrs, :case_file, &case_file_fixture/0)

    attrs =
      Enum.into(attrs, %{
        version: 1,
        published_at: DateTime.utc_now(:second),
        content: %{
          "briefing" => "An original test mystery.",
          "max_days" => 3,
          "locations" => [
            %{
              "id" => "central-precinct",
              "name" => "Central Precinct",
              "type" => "police_station",
              "district_ids" => ["central"],
              "x" => 0.25,
              "y" => 0.35
            },
            %{
              "id" => "canal-gate",
              "name" => "Canal Gate",
              "type" => "standard",
              "district_ids" => ["central", "harbor"],
              "x" => 0.5,
              "y" => 0.5
            },
            %{
              "id" => "pier-club",
              "name" => "Pier Club",
              "type" => "mob_joint",
              "district_ids" => ["harbor"],
              "x" => 0.75,
              "y" => 0.7
            }
          ],
          "suspects" => [],
          "response_matrix" => %{},
          "solution" => %{}
        }
      })

    {:ok, version} = Cases.create_version(case_file, attrs)
    Detective.Repo.preload(version, :case_file)
  end
end
