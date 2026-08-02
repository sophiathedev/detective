defmodule Detective.GamesFixtures do
  import Detective.CasesFixtures

  alias Detective.Accounts.Scope
  alias Detective.Games

  def game_fixture(user, attrs \\ %{}, opts \\ []) do
    case_version = Map.get_lazy(attrs, :case_version, &case_version_fixture/0)

    create_attrs = %{
      title: Map.get(attrs, :title, "Night Shift"),
      case_version_id: case_version.id,
      max_detectives: Map.get(attrs, :max_detectives, 2),
      invite_hours: Map.get(attrs, :invite_hours, 24)
    }

    room_code =
      :crypto.strong_rand_bytes(5)
      |> Base.encode32(padding: false)
      |> binary_part(0, 6)

    token = "invite-#{System.unique_integer([:positive])}"

    default_opts = [
      room_code: room_code,
      invite_token: {token, :crypto.hash(:sha256, token)}
    ]

    {:ok, result} =
      Games.create_game(Scope.for_user(user), create_attrs, Keyword.merge(default_opts, opts))

    Map.put(result, :case_version, case_version)
  end
end
