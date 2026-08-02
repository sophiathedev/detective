defmodule Detective.Games.CommandTest do
  use ExUnit.Case, async: true

  alias Detective.Games.Command

  test "builds only allow-listed command types" do
    command_id = Ecto.UUID.generate()

    assert {:ok, %Command{type: :move, command_id: ^command_id}} =
             Command.build(command_id, "move", 3, %{"location_id" => "archive"})

    assert {:error, :invalid_command} =
             Command.build(command_id, "invent_atom", 3, %{})

    assert {:error, :invalid_command} =
             Command.build("bad-id", "move", 3, %{})

    assert {:error, :invalid_command} =
             Command.build(command_id, "move", -1, %{})
  end
end
