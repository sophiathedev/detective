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
alias Detective.Cases.Validator
alias Detective.Repo

slug = "signal-at-midnight"

add_case_codes = fn case_cards ->
  case_cards
  |> Enum.with_index()
  |> Enum.map(fn {card, index} -> Map.put(card, "code", <<?A + index>>) end)
end

case_card_artwork_urls = %{
  "mara-venn" => "/images/cards/dcoa/faces/female-business.webp",
  "copper-tuning-key" => "/images/cards/dcoa/faces/truncheon.webp",
  "receiver-cable" => "/images/cards/dcoa/faces/bloody-ropes.webp"
}

add_case_card_artwork = fn case_cards ->
  Enum.map(case_cards, fn card ->
    case Map.get(case_card_artwork_urls, card["id"]) do
      nil -> Map.delete(card, "artwork_url")
      artwork_url -> Map.put(card, "artwork_url", artwork_url)
    end
  end)
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

add_response_case_card_effects = fn matrix ->
  update_in(matrix, ["iona-pike", "mara-venn", "most_useful"], fn
    response when is_binary(response) ->
      %{
        "text" => response,
        "reveal_case_card_ids" => ["receiver-cable"]
      }

    response when is_map(response) ->
      Map.put(response, "reveal_case_card_ids", ["receiver-cable"])
  end)
end

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
  |> add_case_card_artwork.()
  |> add_case_codes.()
end

search_results = %{
  "locations" => %{
    "29" => %{
      "text" =>
        "A torn calibration sleeve leads to the copper tuning key beneath the receiver dais.",
      "archive" => true,
      "reveal_case_card_ids" => ["copper-tuning-key"],
      "take_case_card_ids" => ["copper-tuning-key"],
      "reveal_suspect_ids" => []
    },
    "82" => %{
      "text" =>
        "A routing clerk identifies a cut receiver cable hidden among condemned switchboard parts.",
      "archive" => true,
      "reveal_case_card_ids" => ["receiver-cable"],
      "take_case_card_ids" => [],
      "reveal_suspect_ids" => []
    },
    "96" => %{
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

suspects = [
  %{
    "id" => "iona-pike",
    "name" => "Iona Pike",
    "occupation" => "array engineer",
    "location_id" => "29",
    "initially_known" => true
  },
  %{
    "id" => "tomas-vale",
    "name" => "Tomas Vale",
    "occupation" => "harbor pilot",
    "location_id" => "99",
    "initially_known" => true
  },
  %{
    "id" => "celeste-rook",
    "name" => "Celeste Rook",
    "occupation" => "investigative journalist",
    "location_id" => "38",
    "initially_known" => true
  }
]

special_rules = [
  %{
    "id" => "closing-signal-window",
    "title" => "Closing Signal Window",
    "text" =>
      "The harbor transmission is fading. Start with 6 days for two Detectives, 5 for three, or 4 for four.",
    "visibility" => "public",
    "trigger" => "setup",
    "effect" => %{
      "type" => "starting_days",
      "days_by_detective_count" => %{"2" => 6, "3" => 5, "4" => 4}
    }
  },
  %{
    "id" => "harbor-tail-spotted",
    "title" => "A Shadow at the Breakwater",
    "text" =>
      "At the start of Day 2, the harbor pilot spots a lookout shadowing the breakwater relay.",
    "visibility" => "chisel",
    "trigger" => "day_started",
    "effect" => %{
      "type" => "day_reveal",
      "day" => 2,
      "special_actor_updates" => [
        %{
          "actor_id" => "harbor-tail",
          "visible" => true,
          "active" => true,
          "location_id" => "99"
        }
      ]
    }
  },
  %{
    "id" => "breakwater-flare",
    "title" => "Flare Beyond the Breakwater",
    "text" =>
      "At the start of Day 3, a harbor patrol recovers the signal flare and enters it into public evidence.",
    "visibility" => "chisel",
    "trigger" => "day_started",
    "effect" => %{
      "type" => "day_reveal",
      "day" => 3,
      "reveal_case_card_ids" => ["harbor-flare"],
      "reveal_suspect_ids" => []
    }
  }
]

special_actors = [
  %{
    "id" => "harbor-tail",
    "name" => "The Harbor Tail",
    "role" => "counter-surveillance lookout",
    "kind" => "counter_surveillance",
    "location_id" => "99",
    "initially_visible" => false,
    "initially_active" => false,
    "blocks" => ["search_location", "search_suspect", "interrogate"],
    "options" => [
      %{
        "id" => "buy-off-tail",
        "label" => "Buy off the lookout",
        "action_cost" => 1,
        "scratch_cost" => 2,
        "once" => true,
        "choice_group" => "harbor-tail-approach",
        "effects" => [
          %{"type" => "disable_actor"},
          %{"type" => "private_case_cards", "case_card_ids" => ["receiver-cable"]}
        ]
      },
      %{
        "id" => "shadow-the-tail",
        "label" => "Shadow the lookout to Topsy's",
        "action_cost" => 2,
        "scratch_cost" => 0,
        "once" => true,
        "choice_group" => "harbor-tail-approach",
        "effects" => [
          %{"type" => "move_actor", "location_id" => "96"},
          %{"type" => "public_case_cards", "case_card_ids" => ["harbor-flare"]}
        ]
      }
    ]
  }
]

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
          "board_id" => "dcoa_classic",
          "briefing" =>
            "At 00:17, Dr. Mara Venn sent a broken distress call from Meridian Array. By sunrise she was dead, the station log had been altered, and an unknown ship had vanished beyond the breakwater. Determine who killed her, what was used, and why the midnight signal had to be silenced.",
          "special_rules" => special_rules,
          "special_actors" => special_actors,
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
          "suspects" => suspects,
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
          |> Map.update!("case_cards", add_case_card_artwork)
          |> Map.update!("case_cards", add_case_codes)
          |> Map.update!("response_matrix", fn response_matrix ->
            response_matrix
            |> author_response_decks.()
            |> add_response_case_card_effects.()
          end)

        {:ok, version} =
          Cases.create_version(case_file, %{
            version: 1,
            content: content,
            published_at: DateTime.utc_now() |> DateTime.truncate(:second)
          })

        version

      case_file ->
        case Repo.get_by(CaseVersion, case_id: case_file.id, version: 13) do
          nil ->
            legacy_version =
              Repo.get_by(CaseVersion, case_id: case_file.id, version: 12) ||
                Repo.get_by(CaseVersion, case_id: case_file.id, version: 11) ||
                Repo.get_by(CaseVersion, case_id: case_file.id, version: 9) ||
                Repo.get_by(CaseVersion, case_id: case_file.id, version: 8) ||
                Repo.get_by(CaseVersion, case_id: case_file.id, version: 7) ||
                Repo.get_by(CaseVersion, case_id: case_file.id, version: 6) ||
                Repo.get_by(CaseVersion, case_id: case_file.id, version: 5) ||
                Repo.get_by(CaseVersion, case_id: case_file.id, version: 4) ||
                Repo.get_by(CaseVersion, case_id: case_file.id, version: 3) ||
                Repo.get_by(CaseVersion, case_id: case_file.id, version: 2) ||
                Repo.get_by!(CaseVersion, case_id: case_file.id, version: 1)

            upgraded_content =
              legacy_version.content
              |> Map.put("max_days", 6)
              |> Map.delete("locations")
              |> Map.put("board_id", "dcoa_classic")
              |> Map.put("suspects", suspects)
              |> Map.update!("case_cards", upgrade_case_cards)
              |> Map.update!("response_matrix", fn response_matrix ->
                response_matrix
                |> author_response_decks.()
                |> add_response_case_card_effects.()
              end)
              |> Map.put("search_results", search_results)
              |> Map.put("accusation_options", accusation_options)
              |> Map.put("solution", solution)
              |> Map.put("special_rules", special_rules)
              |> Map.put("special_actors", special_actors)

            {:ok, version} =
              Cases.create_version(case_file, %{
                version: 13,
                content: upgraded_content,
                published_at: DateTime.utc_now() |> DateTime.truncate(:second)
              })

            version

          version ->
            version
        end
    end
  end)

catalog_path = Path.expand("../cases/the-glass-alibi.json", __DIR__)
catalog = catalog_path |> File.read!() |> Jason.decode!()
case_attrs = Map.fetch!(catalog, "case")
version_number = Map.fetch!(catalog, "version")
content = Map.fetch!(catalog, "content")
:ok = Validator.validate(content)

case_file =
  case Repo.get_by(CaseFile, slug: case_attrs["slug"]) do
    nil ->
      {:ok, case_file} =
        Cases.create_case(%{
          slug: case_attrs["slug"],
          title: case_attrs["title"],
          description: case_attrs["description"],
          status: case_attrs["status"]
        })

      case_file

    case_file ->
      case_file
  end

case Repo.get_by(CaseVersion, case_id: case_file.id, version: version_number) do
  nil ->
    {:ok, _version} =
      Cases.create_version(case_file, %{
        version: version_number,
        content: content,
        published_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

  _version ->
    :ok
end
