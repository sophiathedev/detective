# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Detective.Repo.insert!(%Detective.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

Logger.configure(level: :info)

alias Detective.Cases
alias Detective.Cases.CaseFile
alias Detective.Cases.CaseVersion
alias Detective.Repo

slug = "signal-at-midnight"

add_case_codes = fn case_cards ->
  case_cards
  |> Enum.with_index()
  |> Enum.map(fn {card, index} -> Map.put(card, "code", <<?A + index>>) end)
end

second_misdirections = %{
  "iona-pike" => %{
    "mara-venn" => "Mara was calm when I left; whatever happened came long after my shift ended.",
    "copper-tuning-key" =>
      "I reported the key missing before dusk, so its disappearance cannot implicate me.",
    "signal-log" =>
      "Mara asked me to replace the entry because the receiver had logged a harmless test pulse."
  },
  "tomas-vale" => %{
    "mara-venn" =>
      "Mara called only for a weather reading and never mentioned an unregistered ship.",
    "copper-tuning-key" =>
      "That grease is sold at every chandlery; it cannot tie the tool to the harbor relay.",
    "signal-log" =>
      "My channel was closed before 00:17, so the missing transmission could not concern my route."
  },
  "celeste-rook" => %{
    "mara-venn" =>
      "Mara and I had not spoken in months; the sealed envelope arrived from an anonymous courier.",
    "copper-tuning-key" =>
      "The object missing from my photograph might be any instrument stored on the lower shelf.",
    "signal-log" =>
      "My copy is too blurred to distinguish a relay code from an ordinary maintenance notation."
  }
}

author_response_decks = fn matrix ->
  Map.new(matrix, fn {suspect_id, suspect_matrix} ->
    normalized_topics =
      Map.new(suspect_matrix, fn {topic_id, entry} ->
        [first_misdirection | _rest] = entry["misdirections"]
        second_misdirection = get_in(second_misdirections, [suspect_id, topic_id])
        misdirections = [first_misdirection, second_misdirection]

        {topic_id, Map.put(entry, "misdirections", misdirections)}
      end)

    {suspect_id, normalized_topics}
  end)
end

map_locations = [
  %{
    "id" => "central-precinct",
    "name" => "Central Precinct",
    "type" => "police_station",
    "district_ids" => ["civic"],
    "x" => 0.3,
    "y" => 0.42
  },
  %{
    "id" => "meridian-array",
    "name" => "Meridian Array",
    "type" => "standard",
    "district_ids" => ["observatory"],
    "x" => 0.42,
    "y" => 0.23
  },
  %{
    "id" => "northlight-boarding-house",
    "name" => "Northlight Boarding House",
    "type" => "standard",
    "district_ids" => ["observatory", "civic"],
    "x" => 0.39,
    "y" => 0.34
  },
  %{
    "id" => "city-archive",
    "name" => "City Archive",
    "type" => "standard",
    "district_ids" => ["civic"],
    "x" => 0.35,
    "y" => 0.5
  },
  %{
    "id" => "telegraph-exchange",
    "name" => "Telegraph Exchange",
    "type" => "standard",
    "district_ids" => ["civic", "harbor"],
    "x" => 0.55,
    "y" => 0.55
  },
  %{
    "id" => "harbor-precinct",
    "name" => "Harbor Precinct",
    "type" => "police_station",
    "district_ids" => ["harbor"],
    "x" => 0.68,
    "y" => 0.61
  },
  %{
    "id" => "breakwater-relay",
    "name" => "Breakwater Relay",
    "type" => "standard",
    "district_ids" => ["harbor"],
    "x" => 0.79,
    "y" => 0.71
  },
  %{
    "id" => "mariner-social-club",
    "name" => "Mariner Social Club",
    "type" => "mob_joint",
    "district_ids" => ["harbor"],
    "x" => 0.65,
    "y" => 0.72
  }
]

additional_case_cards = [
  %{
    "id" => "receiver-cable",
    "type" => "evidence",
    "title" => "Cut Receiver Cable",
    "description" =>
      "A weighted receiver cable cut from the array console and scrubbed with solvent.",
    "initially_known" => false
  },
  %{
    "id" => "harbor-flare",
    "type" => "evidence",
    "title" => "Harbor Signal Flare",
    "description" =>
      "A brass signal flare recovered near the breakwater with fresh impact damage.",
    "initially_known" => false
  }
]

upgrade_case_cards = fn case_cards ->
  existing_ids = MapSet.new(case_cards, & &1["id"])

  added_cards =
    Enum.reject(additional_case_cards, &MapSet.member?(existing_ids, &1["id"]))

  case_cards
  |> Kernel.++(added_cards)
  |> Enum.map(fn
    %{"id" => "copper-tuning-key"} = card -> Map.put(card, "takeable", true)
    card -> card
  end)
  |> add_case_codes.()
end

search_results = %{
  "locations" => %{
    "meridian-array" => %{
      "text" =>
        "A torn calibration sleeve leads to the copper tuning key beneath the receiver dais.",
      "archive" => true,
      "reveal_case_card_ids" => ["copper-tuning-key"],
      "take_case_card_ids" => ["copper-tuning-key"],
      "reveal_suspect_ids" => []
    },
    "telegraph-exchange" => %{
      "text" =>
        "A routing clerk identifies a cut receiver cable hidden among condemned switchboard parts.",
      "archive" => true,
      "reveal_case_card_ids" => ["receiver-cable"],
      "take_case_card_ids" => [],
      "reveal_suspect_ids" => []
    },
    "mariner-social-club" => %{
      "text" =>
        "The coatroom ledger links an abandoned harbor flare to a private table used after midnight.",
      "archive" => true,
      "reveal_case_card_ids" => ["harbor-flare"],
      "take_case_card_ids" => [],
      "reveal_suspect_ids" => []
    }
  },
  "suspects" => %{
    "iona-pike" => %{
      "text" => "Iona's tool roll is missing one heavy calibration key and one sleeve.",
      "archive" => true,
      "reveal_case_card_ids" => [],
      "take_case_card_ids" => [],
      "reveal_suspect_ids" => []
    },
    "tomas-vale" => %{
      "text" => "Tomas carries harbor permits, grease pencils, and no concealed case evidence.",
      "archive" => true,
      "reveal_case_card_ids" => [],
      "take_case_card_ids" => [],
      "reveal_suspect_ids" => []
    },
    "celeste-rook" => %{
      "text" =>
        "Celeste's press satchel contains labeled photographs already copied into the file.",
      "archive" => true,
      "reveal_case_card_ids" => [],
      "take_case_card_ids" => [],
      "reveal_suspect_ids" => []
    }
  },
  "all_other_locations" => %{
    "text" => "The search turns up no material connected to the midnight signal.",
    "archive" => false,
    "reveal_case_card_ids" => [],
    "take_case_card_ids" => [],
    "reveal_suspect_ids" => []
  }
}

accusation_options = %{
  "weapons" => [
    %{
      "id" => "copper-tuning-key",
      "label" => "Copper Tuning Key",
      "case_card_id" => "copper-tuning-key"
    },
    %{
      "id" => "receiver-cable",
      "label" => "Cut Receiver Cable",
      "case_card_id" => "receiver-cable"
    },
    %{
      "id" => "harbor-flare",
      "label" => "Harbor Signal Flare",
      "case_card_id" => "harbor-flare"
    }
  ],
  "motives" => [
    %{"id" => "relay-code-cover-up", "label" => "Conceal the sale of the harbor relay code"},
    %{"id" => "silence-a-witness", "label" => "Silence a witness to harbor smuggling"},
    %{"id" => "steal-the-recording", "label" => "Steal the original midnight recording"}
  ]
}

solution = %{
  "suspect_id" => "iona-pike",
  "weapon_id" => "copper-tuning-key",
  "motive_id" => "relay-code-cover-up"
}

{:ok, _result} =
  Repo.transaction(fn ->
    case Repo.get_by(CaseFile, slug: slug) do
      nil ->
        {:ok, case_file} =
          Cases.create_case(%{
            slug: slug,
            title: "Signal at Midnight",
            description:
              "A radio astronomer dies after intercepting a coded transmission over the harbor.",
            status: "published"
          })

        content = %{
          "locale" => "en",
          "max_days" => 6,
          "briefing" =>
            "At 00:17, Dr. Mara Venn sent a broken distress call from Meridian Array. By sunrise she was dead, the station log had been altered, and an unknown ship had vanished beyond the breakwater. Determine who killed her, what was used, and why the midnight signal had to be silenced.",
          "case_cards" => [
            %{
              "id" => "mara-venn",
              "type" => "victim",
              "title" => "Dr. Mara Venn",
              "description" =>
                "A radio astronomer who recorded an unauthorized transmission shortly before her death.",
              "initially_known" => true
            },
            %{
              "id" => "copper-tuning-key",
              "type" => "evidence",
              "title" => "Copper Tuning Key",
              "description" =>
                "A heavy calibration tool wiped clean except for a trace of marine grease.",
              "takeable" => true,
              "initially_known" => false
            },
            %{
              "id" => "signal-log",
              "type" => "information",
              "title" => "Altered Signal Log",
              "description" =>
                "A station ledger with the 00:17 transmission overwritten by a maintenance entry.",
              "initially_known" => true
            }
            | additional_case_cards
          ],
          "suspects" => [
            %{
              "id" => "iona-pike",
              "name" => "Iona Pike",
              "occupation" => "array engineer",
              "location_id" => "meridian-array",
              "initially_known" => true
            },
            %{
              "id" => "tomas-vale",
              "name" => "Tomas Vale",
              "occupation" => "harbor pilot",
              "location_id" => "breakwater-relay",
              "initially_known" => true
            },
            %{
              "id" => "celeste-rook",
              "name" => "Celeste Rook",
              "occupation" => "investigative journalist",
              "location_id" => "northlight-boarding-house",
              "initially_known" => true
            }
          ],
          "locations" => map_locations,
          "response_matrix" => %{
            "iona-pike" => %{
              "mara-venn" => %{
                "most_useful" =>
                  "Mara confronted me about a false maintenance entry, then locked the receiver room while she copied the signal.",
                "misdirections" => [
                  "Mara worked alone after dusk; I left before the midnight watch began."
                ]
              },
              "copper-tuning-key" => %{
                "most_useful" =>
                  "The key belonged at my calibration bench, but I carried it to the receiver room that night.",
                "misdirections" => [
                  "Every technician used that tool; it could have been anywhere in the station."
                ]
              },
              "signal-log" => %{
                "most_useful" =>
                  "I replaced the 00:17 entry because the signal exposed a relay code I had sold to smugglers.",
                "misdirections" => [
                  "The recorder often produced duplicate entries, so I removed one during routine cleanup."
                ]
              }
            },
            "tomas-vale" => %{
              "mara-venn" => %{
                "most_useful" =>
                  "Mara warned me that someone inside the array was guiding an unregistered ship through the fog.",
                "misdirections" => [
                  "I knew Mara only by voice and never discussed harbor traffic with her."
                ]
              },
              "copper-tuning-key" => %{
                "most_useful" =>
                  "Marine grease like that is used on relay housings, and Iona inspected ours two days ago.",
                "misdirections" => [
                  "The grease proves the tool came from my launch, though I never saw it aboard."
                ]
              },
              "signal-log" => %{
                "most_useful" =>
                  "The missing transmission matched the timing code used by the ship that crossed my channel without clearance.",
                "misdirections" => [
                  "Harbor static makes station logs unreliable after midnight."
                ]
              }
            },
            "celeste-rook" => %{
              "mara-venn" => %{
                "most_useful" =>
                  "Mara gave me a sealed copy of her findings and said Iona would lose everything if the relay scheme became public.",
                "misdirections" => [
                  "Mara contacted me about funding cuts, not a criminal investigation."
                ]
              },
              "copper-tuning-key" => %{
                "most_useful" =>
                  "I photographed the calibration bench at 23:40; the key was missing and Iona was still inside the array.",
                "misdirections" => [
                  "The tool appears in one photograph, but the timestamp on my camera was wrong."
                ]
              },
              "signal-log" => %{
                "most_useful" =>
                  "My copy preserves the original 00:17 entry and links the broadcast to the breakwater relay code.",
                "misdirections" => [
                  "I never saw the station ledger; Mara only described the transmission to me."
                ]
              }
            }
          },
          "search_results" => search_results,
          "accusation_options" => accusation_options,
          "solution" => solution,
          "epilogue" =>
            "Mara traced the midnight broadcast to a smuggling route enabled by Iona's stolen relay code. When Mara prepared to expose the scheme, Iona struck her with the tuning key and rewrote the signal log. The preserved recording and Celeste's photograph reveal the cover-up."
        }

        content =
          content
          |> Map.update!("case_cards", add_case_codes)
          |> Map.update!("response_matrix", author_response_decks)

        {:ok, version} =
          Cases.create_version(case_file, %{
            version: 1,
            content: content,
            published_at: DateTime.utc_now() |> DateTime.truncate(:second)
          })

        version

      case_file ->
        case Repo.get_by(CaseVersion, case_id: case_file.id, version: 5) do
          nil ->
            legacy_version =
              Repo.get_by(CaseVersion, case_id: case_file.id, version: 4) ||
                Repo.get_by(CaseVersion, case_id: case_file.id, version: 3) ||
                Repo.get_by(CaseVersion, case_id: case_file.id, version: 2) ||
                Repo.get_by!(CaseVersion, case_id: case_file.id, version: 1)

            upgraded_content =
              legacy_version.content
              |> Map.put("max_days", 6)
              |> Map.put("locations", map_locations)
              |> Map.update!("case_cards", upgrade_case_cards)
              |> Map.update!("response_matrix", author_response_decks)
              |> Map.put("search_results", search_results)
              |> Map.put("accusation_options", accusation_options)
              |> Map.put("solution", solution)

            {:ok, version} =
              Cases.create_version(case_file, %{
                version: 5,
                content: upgraded_content,
                published_at: DateTime.utc_now() |> DateTime.truncate(:second)
              })

            version

          version ->
            version
        end
    end
  end)
