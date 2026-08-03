defmodule Detective.Games.CommandTest do
  use ExUnit.Case, async: true

  alias Detective.Games.Command

  test "builds only allow-listed command types" do
    command_id = Ecto.UUID.generate()

    assert {:ok, %Command{type: :move, command_id: ^command_id}} =
             Command.build(command_id, "move", 3, %{"location_id" => "archive"})

    for type <-
          ~w(search_location search_suspect skip_free_question interrogate allow_question block_question accept_question_block bribe_goon choose_snitch decline_snitch resolve_snitches select_response accept_response challenge_response accuse submit_final_guess resume_game) do
      assert {:ok, %Command{}} = Command.build(command_id, type, 3, %{})
    end

    assert {:error, :invalid_command} =
             Command.build(command_id, "invent_atom", 3, %{})

    assert {:error, :invalid_command} =
             Command.build("bad-id", "move", 3, %{})

    assert {:error, :invalid_command} =
             Command.build(command_id, "move", -1, %{})
  end
end
