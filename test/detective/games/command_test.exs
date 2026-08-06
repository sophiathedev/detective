defmodule Detective.Games.CommandTest do
  use ExUnit.Case, async: true

  alias Detective.Games.Command

  test "builds only allow-listed command types with canonical payloads" do
    command_id = Ecto.UUID.generate()

    payloads = %{
      "place" => %{"location_id" => "station"},
      "move" => %{"location_id" => "archive"},
      "analyze" => %{},
      "kickback" => %{},
      "search_location" => %{},
      "search_suspect" => %{"suspect_id" => "clerk"},
      "interact_special_actor" => %{"actor_id" => "informant", "option_id" => "tip"},
      "interrogate" => %{
        "suspect_id" => "clerk",
        "topic_id" => "ledger",
        "spend_leverage" => false
      },
      "skip_free_question" => %{},
      "allow_question" => %{},
      "block_question" => %{},
      "accept_question_block" => %{},
      "bribe_goon" => %{},
      "bribe_detective" => %{
        "detective_player_id" => Ecto.UUID.generate(),
        "case_card_id" => "ledger"
      },
      "bribe_officer" => %{"case_card_id" => "ledger"},
      "choose_snitch" => %{},
      "decline_snitch" => %{},
      "resolve_snitches" => %{"blocked_player_ids" => []},
      "select_response" => %{"response_id" => "ledger-lie"},
      "accept_response" => %{},
      "challenge_response" => %{},
      "accuse" => %{
        "suspect_id" => "clerk",
        "weapon_id" => "ledger",
        "motive_id" => "blackmail"
      },
      "submit_final_guess" => %{
        "suspect_id" => "clerk",
        "weapon_id" => "ledger",
        "motive_id" => "blackmail"
      },
      "resume_game" => %{},
      "end_turn" => %{}
    }

    for {type, payload} <- payloads do
      assert {:ok, %Command{command_id: ^command_id}} =
               Command.build(command_id, type, 3, payload)
    end

    assert {:error, :invalid_command} =
             Command.build(command_id, "invent_atom", 3, %{})

    assert {:error, :invalid_command} =
             Command.build("bad-id", "move", 3, %{})

    assert {:error, :invalid_command} =
             Command.build(command_id, "move", -1, %{})
  end

  test "rejects missing, extra, wrongly typed, or oversized payload fields" do
    command_id = Ecto.UUID.generate()

    invalid_commands = [
      {"move", %{}},
      {"move", %{"location_id" => "archive", "actions_remaining" => 99}},
      {"move", %{location_id: "archive"}},
      {"move", %{"location_id" => String.duplicate("a", 129)}},
      {"interrogate", %{"suspect_id" => "clerk", "topic_id" => "ledger", "spend_leverage" => 1}},
      {"resolve_snitches", %{"blocked_player_ids" => ["one", "one"]}},
      {"resolve_snitches", %{"blocked_player_ids" => ~w(one two three four five)}},
      {"accuse", %{"suspect_id" => "clerk", "weapon_id" => "ledger"}},
      {"end_turn", %{"player_id" => Ecto.UUID.generate()}}
    ]

    for {type, payload} <- invalid_commands do
      assert {:error, :invalid_command} = Command.build(command_id, type, 3, payload)
    end
  end
end
