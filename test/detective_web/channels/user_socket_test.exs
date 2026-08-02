defmodule DetectiveWeb.UserSocketTest do
  use Detective.DataCase, async: true

  @endpoint DetectiveWeb.Endpoint

  import Detective.AccountsFixtures
  import Phoenix.ChannelTest

  alias Detective.Accounts
  alias DetectiveWeb.{UserAuth, UserSocket}

  test "connects with a revocable account session token" do
    user = user_fixture()
    token = Accounts.generate_user_session_token(user)

    assert {:ok, socket} =
             connect(UserSocket, %{}, connect_info: %{session: %{"user_token" => token}})

    assert socket.assigns.user_id == user.id
    assert socket.id == UserAuth.session_topic(token)
  end

  test "rejects missing, invalid, and revoked session tokens" do
    user = user_fixture()
    token = Accounts.generate_user_session_token(user)

    assert :error = connect(UserSocket, %{}, connect_info: %{session: %{}})

    assert :error =
             connect(UserSocket, %{}, connect_info: %{session: %{"user_token" => "invalid"}})

    assert :ok = Accounts.delete_user_session_token(token)

    assert :error =
             connect(UserSocket, %{}, connect_info: %{session: %{"user_token" => token}})
  end
end
