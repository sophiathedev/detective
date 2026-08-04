defmodule Detective.Games.ProjectionsTest do
  use ExUnit.Case, async: true

  alias Detective.Games.Projections
  alias Detective.Games.Projections.Public
  alias Detective.Games.State

  test "public and Detective projections never contain Chisel secrets" do
    state = state_fixture()

    public = Public.render(state)
    {:ok, detective} = Projections.for_user(state, detective_user_id())

    public_json = Jason.encode!(public)
    detective_json = Jason.encode!(detective)

    for forbidden <- [
          "solution",
          "response_matrix",
          "most_useful",
          "murderer",
          "user_id",
          "scratch"
        ] do
      refute public_json =~ forbidden
    end

    for forbidden <- ["solution", "response_matrix", "most_useful", "murderer", chisel_user_id()] do
      refute detective_json =~ forbidden
    end

    assert detective.private.scratch == 4
    assert detective.private.available_actions == ["place"]
    assert detective.private.placement_location_ids == ["51"]
  end

  test "only the Chisel projection contains the allow-listed secret casebook" do
    state = state_fixture()
    {:ok, chisel} = Projections.for_user(state, chisel_user_id())

    assert chisel.private.role == "chisel"
    assert chisel.private.casebook.solution == %{"suspect_id" => "murderer"}

    assert chisel.private.casebook.response_matrix["suspect"]["topic"]["most_useful"] ==
             "secret answer"

    refute Map.has_key?(chisel.private, :scratch)
    refute Map.has_key?(chisel.private, :actions_remaining)
  end

  test "pending response options and truth metadata remain role-private" do
    state =
      %{state_fixture() | phase: :waiting_for_chisel, pending_action: pending_interrogation()}

    public = Public.render(state)
    {:ok, detective} = Projections.for_user(state, detective_user_id())
    {:ok, chisel} = Projections.for_user(state, chisel_user_id())

    refute Jason.encode!(public) =~ "secret answer"
    refute Jason.encode!(public) =~ "response-0"
    refute Jason.encode!(detective) =~ "most_useful"

    assert Enum.map(chisel.private.pending_interrogation.response_options, & &1.type) == [
             "most_useful"
           ]

    selected =
      pending_interrogation()
      |> Map.put("selected_response_id", "response-0")
      |> Map.put("selected_response_text", "secret answer")
      |> Map.put("selected_response_type", "most_useful")

    selected_state = %{
      state
      | phase: :waiting_for_detective_decision,
        pending_action: selected
    }

    selected_public = Public.render(selected_state)
    {:ok, selected_detective} = Projections.for_user(selected_state, detective_user_id())

    refute Jason.encode!(selected_public) =~ "secret answer"
    refute Jason.encode!(selected_public) =~ "most_useful"
    assert selected_detective.private.pending_interrogation.response_text == "secret answer"
  end

  test "Search text, hidden card identity, and held evidence never enter public projection" do
    detective_id = "10000000-0000-0000-0000-000000000001"
    base = state_fixture()

    state = %{
      base
      | archived_searches: ["location:51"],
        taken_evidence: %{
          "hidden-card" => %{
            "player_id" => detective_id,
            "taken_day" => 1,
            "release_day" => 4
          }
        },
        players:
          Map.update!(base.players, detective_id, fn detective ->
            detective
            |> Map.put(:knowledge, ["topic", "hidden-card"])
            |> Map.put(:evidence, ["hidden-card"])
            |> Map.put(:search_notes, [
              %{
                "target_type" => "location",
                "target_id" => "51",
                "text" => "A fingerprint hides under the blotter.",
                "case_card_ids" => ["hidden-card"],
                "taken_case_card_ids" => ["hidden-card"],
                "day" => 1
              }
            ])
          end),
        case_definition:
          Map.update!(base.case_definition, "case_cards", fn cards ->
            [
              %{
                "id" => "hidden-card",
                "code" => "B",
                "title" => "Hidden Fingerprint",
                "type" => "evidence",
                "description" => "A private clue.",
                "takeable" => true,
                "initially_known" => false
              }
              | cards
            ]
          end)
    }

    public = Public.render(state)
    {:ok, detective} = Projections.for_user(state, detective_user_id())
    {:ok, chisel} = Projections.for_user(state, chisel_user_id())

    public_json = Jason.encode!(public)
    refute public_json =~ "hidden-card"
    refute public_json =~ "Hidden Fingerprint"
    refute public_json =~ "fingerprint hides"
    assert public.taken_evidence == [%{holder_player_id: detective_id, release_day: 4}]

    assert hd(detective.private.search_notes)["text"] ==
             "A fingerprint hides under the blotter."

    assert Enum.map(detective.private.evidence, & &1.id) == ["hidden-card"]
    assert Enum.map(chisel.private.casebook.case_cards, & &1["id"]) == ["hidden-card", "topic"]
  end

  test "paused public projection allow-lists pause metadata without private interrogation data" do
    detective_id = "10000000-0000-0000-0000-000000000001"

    paused = %{
      state_fixture()
      | status: :paused,
        phase: :paused,
        paused_from_phase: :waiting_for_chisel,
        pause_reason: :player_disconnected,
        paused_player_ids: [detective_id],
        pending_action:
          pending_interrogation()
          |> Map.put("selected_response_text", "secret answer")
          |> Map.put("response_matrix", %{"private" => true})
    }

    public = Public.render(paused)
    public_json = Jason.encode!(public)

    assert public.pause == %{
             reason: "player_disconnected",
             player_ids: [detective_id],
             previous_phase: "waiting_for_chisel"
           }

    for forbidden <- [
          "solution",
          "response_matrix",
          "pending_action",
          "selected_response_text",
          "secret answer"
        ] do
      refute public_json =~ forbidden
    end
  end

  test "active unplaced Detective receives only placement destination IDs" do
    state = movable_state_fixture()

    assert {:ok, projection} = Projections.for_user(state, detective_user_id())

    assert "place" in projection.private.available_actions
    refute "move" in projection.private.available_actions
    assert projection.private.placement_location_ids == ["51"]
    assert projection.private.valid_move_location_ids == []
  end

  test "active placed Detective with move action receives only move destination IDs" do
    state =
      movable_state_fixture()
      |> put_in(
        [Access.key!(:players), "10000000-0000-0000-0000-000000000001", :location_id],
        "51"
      )

    assert {:ok, projection} = Projections.for_user(state, detective_user_id())

    assert "move" in projection.private.available_actions
    refute "place" in projection.private.available_actions
    assert projection.private.placement_location_ids == []
    assert projection.private.valid_move_location_ids == ["48"]
  end

  test "Detective private projection suppresses map IDs when their actions are unavailable" do
    placed_state =
      movable_state_fixture()
      |> put_in(
        [Access.key!(:players), "10000000-0000-0000-0000-000000000001", :location_id],
        "51"
      )

    inactive = %{movable_state_fixture() | current_detective_id: nil}

    zero_actions =
      put_in(
        placed_state,
        [Access.key!(:players), "10000000-0000-0000-0000-000000000001", :actions_remaining],
        0
      )

    free_question =
      put_in(
        placed_state,
        [
          Access.key!(:players),
          "10000000-0000-0000-0000-000000000001",
          :free_question_suspect_id
        ],
        "suspect"
      )

    cases = [
      paused: %{movable_state_fixture() | status: :paused, phase: :paused},
      inactive: inactive,
      zero_actions: zero_actions,
      free_question: free_question
    ]

    for {state_name, state} <- cases do
      assert {:ok, projection} = Projections.for_user(state, detective_user_id())

      refute "place" in projection.private.available_actions,
             "#{state_name} unexpectedly allows place"

      refute "move" in projection.private.available_actions,
             "#{state_name} unexpectedly allows move"

      assert projection.private.placement_location_ids == [], "#{state_name} leaked placement IDs"
      assert projection.private.valid_move_location_ids == [], "#{state_name} leaked move IDs"
    end
  end

  test "Chisel and nonmembers never receive Detective map destination fields" do
    state = movable_state_fixture()

    assert {:ok, chisel} = Projections.for_user(state, chisel_user_id())
    refute Map.has_key?(chisel.private, :placement_location_ids)
    refute Map.has_key?(chisel.private, :valid_move_location_ids)
    assert {:error, :not_a_member} = Projections.for_user(state, "not-a-member")
  end

  defp state_fixture do
    detective_id = "10000000-0000-0000-0000-000000000001"
    chisel_id = "10000000-0000-0000-0000-000000000002"

    %State{
      game_id: Ecto.UUID.generate(),
      case_version_id: Ecto.UUID.generate(),
      days_remaining: 4,
      chisel_player_id: chisel_id,
      current_detective_id: detective_id,
      detective_order: [detective_id],
      players: %{
        detective_id => %{
          id: detective_id,
          user_id: detective_user_id(),
          display_name: "Detective",
          role: "detective",
          seat: 1,
          location_id: nil,
          actions_remaining: 4,
          scratch: 4,
          leverage_supply: 7,
          leverage_on_suspects: %{},
          knowledge: ["topic"],
          statements: [],
          search_notes: [],
          evidence: [],
          free_question_suspect_id: nil,
          solve_token_available: true,
          solve_attempt: nil,
          final_guess: nil,
          kickback_day: nil
        },
        chisel_id => %{
          id: chisel_id,
          user_id: chisel_user_id(),
          display_name: "Chisel",
          role: "chisel",
          leverage_by_detective: %{detective_id => 1}
        }
      },
      locations: %{
        "51" => %{
          id: "51",
          name: "L.A. Police Department Headquarters",
          type: "police_station",
          district_ids: ["central_la"],
          x: 0.623,
          y: 0.5527
        }
      },
      suspects: %{
        "suspect" => %{
          id: "suspect",
          name: "Suspect",
          occupation: "witness",
          location_id: "51"
        }
      },
      case_definition: %{
        "briefing" => "Private briefing",
        "solution" => %{"suspect_id" => "murderer"},
        "case_cards" => [
          %{
            "id" => "topic",
            "code" => "A",
            "title" => "Known Topic",
            "type" => "information",
            "description" => "Public topic.",
            "initially_known" => true
          }
        ],
        "response_matrix" => %{
          "suspect" => %{"topic" => %{"most_useful" => "secret answer"}}
        }
      }
    }
  end

  defp movable_state_fixture do
    state_fixture()
    |> Map.update!(:locations, fn locations ->
      Map.put(locations, "48", %{
        id: "48",
        name: "Los Angeles Public Library",
        type: "library",
        district_ids: ["central_la"],
        x: 0.612,
        y: 0.557
      })
    end)
  end

  defp pending_interrogation do
    %{
      "id" => Ecto.UUID.generate(),
      "type" => "interrogation",
      "detective_player_id" => "10000000-0000-0000-0000-000000000001",
      "detective_user_id" => detective_user_id(),
      "suspect_id" => "suspect",
      "topic_id" => "topic",
      "topic_code" => "A",
      "forced_truthful" => false,
      "selected_response_id" => nil,
      "selected_response_text" => nil,
      "selected_response_type" => nil
    }
  end

  defp detective_user_id, do: "20000000-0000-0000-0000-000000000001"
  defp chisel_user_id, do: "20000000-0000-0000-0000-000000000002"
end
