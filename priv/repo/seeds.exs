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

alias Detective.Cases
alias Detective.Cases.CaseFile
alias Detective.Repo

slug = "signal-at-midnight"

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
          "locations" => [
            %{
              "id" => "meridian-array",
              "name" => "Meridian Array",
              "x" => 0.24,
              "y" => 0.31
            },
            %{
              "id" => "breakwater-relay",
              "name" => "Breakwater Relay",
              "x" => 0.78,
              "y" => 0.68
            },
            %{
              "id" => "northlight-boarding-house",
              "name" => "Northlight Boarding House",
              "x" => 0.46,
              "y" => 0.82
            }
          ],
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
          "solution" => %{
            "suspect_id" => "iona-pike",
            "weapon_id" => "copper-tuning-key",
            "motive" => "conceal the sale of the harbor relay code"
          },
          "epilogue" =>
            "Mara traced the midnight broadcast to a smuggling route enabled by Iona's stolen relay code. When Mara prepared to expose the scheme, Iona struck her with the tuning key and rewrote the signal log. The preserved recording and Celeste's photograph reveal the cover-up."
        }

        {:ok, version} =
          Cases.create_version(case_file, %{
            version: 1,
            content: content,
            published_at: DateTime.utc_now() |> DateTime.truncate(:second)
          })

        version

      case_file ->
        case_file
    end
  end)
