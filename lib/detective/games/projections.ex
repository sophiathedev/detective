defmodule Detective.Games.Projections do
  @moduledoc false

  alias Detective.Games.State
  alias Detective.Games.Projections.Chisel, as: ChiselProjection
  alias Detective.Games.Projections.Detective, as: DetectiveProjection
  alias Detective.Games.Projections.Public

  def for_user(%State{} = state, user_id) do
    private_projection =
      DetectiveProjection.render_private(state, user_id) ||
        ChiselProjection.render_private(state, user_id)

    if private_projection do
      {:ok, %{public: Public.render(state), private: private_projection}}
    else
      {:error, :not_a_member}
    end
  end

  def private_for_user(%State{} = state, user_id) do
    case for_user(state, user_id) do
      {:ok, projection} -> {:ok, projection.private}
      {:error, reason} -> {:error, reason}
    end
  end
end
