defmodule Detective.Cases.SeedCatalogTest do
  use ExUnit.Case, async: true

  alias Detective.Cases.Validator
  alias Detective.Games.{Engine, Projections}
  alias Detective.Games.Projections.Public

  test "The Glass Alibi is a complete original A-L case definition" do
    catalog = catalog()
    content = catalog["content"]

    assert catalog["case"]["slug"] == "the-glass-alibi"
    assert catalog["case"]["status"] == "published"
    assert :ok = Validator.validate(content)
    assert Enum.map(content["case_cards"], & &1["code"]) == Enum.map(?A..?L, &<<&1>>)
    assert length(content["suspects"]) == 4
    assert length(content["special_rules"]) == 2
    assert length(content["special_actors"]) == 1
  end

  test "The Glass Alibi boots in the engine without leaking its solution" do
    content = catalog()["content"]
    game_id = Ecto.UUID.generate()

    players = [
      %{
        id: "chisel-player",
        user_id: "chisel-user",
        display_name: "The Chisel",
        role: "chisel",
        seat: nil
      },
      %{
        id: "detective-player-1",
        user_id: "detective-user-1",
        display_name: "Detective One",
        role: "detective",
        seat: 1
      },
      %{
        id: "detective-player-2",
        user_id: "detective-user-2",
        display_name: "Detective Two",
        role: "detective",
        seat: 2
      }
    ]

    assert {:ok, state} =
             Engine.new(
               %{id: game_id, case_version_id: Ecto.UUID.generate()},
               players,
               content
             )

    assert state.days_remaining == 7
    assert state.special_actors["studio-tail"].visible == false

    public = Public.render(state)
    assert Enum.map(public.case_card_slots, & &1.code) == Enum.map(?A..?L, &<<&1>>)
    assert Enum.map(public.case_cards, & &1.code) == ["A", "B", "E"]
    assert public.special_actors == []

    assert {:ok, detective} = Projections.for_user(state, "detective-user-1")
    assert {:ok, chisel} = Projections.for_user(state, "chisel-user")

    for projection <- [public, detective] do
      encoded = Jason.encode!(projection)
      refute encoded =~ "miles-cade"
      refute encoded =~ "response_matrix"
      refute encoded =~ "cyanide-vial"
    end

    assert chisel.private.casebook.solution == %{
             "suspect_id" => "miles-cade",
             "weapon_id" => "cyanide-vial",
             "motive_id" => "silence-blackmail"
           }
  end

  defp catalog do
    :detective
    |> :code.priv_dir()
    |> List.to_string()
    |> Path.join("cases/the-glass-alibi.json")
    |> File.read!()
    |> Jason.decode!()
  end
end
