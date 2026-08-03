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
          "case_cards" => [
            %{
              "id" => "victim-file",
              "code" => "A",
              "type" => "victim",
              "title" => "Victim File",
              "description" => "The victim signed into the archive shortly before midnight.",
              "initially_known" => true
            },
            %{
              "id" => "sealed-ledger",
              "code" => "B",
              "type" => "evidence",
              "title" => "Sealed Ledger",
              "description" => "A ledger page removed from the archive binding.",
              "takeable" => true,
              "initially_known" => false
            }
          ],
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
          "suspects" => [
            %{
              "id" => "night-clerk",
              "name" => "Night Clerk",
              "occupation" => "records clerk",
              "location_id" => "central-precinct",
              "initially_known" => true
            }
          ],
          "response_matrix" => %{
            "night-clerk" => %{
              "victim-file" => %{
                "most_useful" => %{
                  "id" => "clerk-a-truth",
                  "text" => "The victim signed the register shortly before midnight."
                },
                "misdirections" => [
                  %{
                    "id" => "clerk-a-misdirection-1",
                    "text" => "The register was blank when I locked the archive."
                  },
                  %{
                    "id" => "clerk-a-misdirection-2",
                    "text" => "I never worked the midnight desk."
                  }
                ]
              }
            }
          },
          "search_results" => %{
            "locations" => %{
              "central-precinct" => %{
                "text" =>
                  "Behind the intake desk, a loose floorboard conceals the sealed ledger.",
                "archive" => true,
                "reveal_case_card_ids" => ["sealed-ledger"],
                "take_case_card_ids" => ["sealed-ledger"],
                "reveal_suspect_ids" => []
              }
            },
            "suspects" => %{
              "night-clerk" => %{
                "text" => "The clerk carries a duplicate archive key but no additional evidence.",
                "archive" => true,
                "reveal_case_card_ids" => [],
                "take_case_card_ids" => [],
                "reveal_suspect_ids" => []
              }
            },
            "all_other_locations" => %{
              "text" => "The search turns up nothing connected to the case.",
              "archive" => false,
              "reveal_case_card_ids" => [],
              "take_case_card_ids" => [],
              "reveal_suspect_ids" => []
            }
          },
          "accusation_options" => %{
            "weapons" => [
              %{
                "id" => "sealed-ledger",
                "label" => "Sealed Ledger",
                "case_card_id" => "sealed-ledger"
              },
              %{
                "id" => "victim-file",
                "label" => "Victim File",
                "case_card_id" => "victim-file"
              }
            ],
            "motives" => [
              %{"id" => "cover-up", "label" => "Cover up the altered register"},
              %{"id" => "robbery", "label" => "Robbery"}
            ]
          },
          "solution" => %{
            "suspect_id" => "night-clerk",
            "weapon_id" => "sealed-ledger",
            "motive_id" => "cover-up"
          },
          "epilogue" => "The clerk used the ledger to conceal the forged register."
        }
      })

    {:ok, version} = Cases.create_version(case_file, attrs)
    Detective.Repo.preload(version, :case_file)
  end
end
