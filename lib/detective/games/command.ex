defmodule Detective.Games.Command do
  @moduledoc """
  A versioned command submitted by an authenticated game member.
  """

  @enforce_keys [:command_id, :type, :expected_version, :payload]
  defstruct [:command_id, :type, :expected_version, :payload]

  @type command_type :: :place | :move | :analyze | :kickback | :end_turn

  @type t :: %__MODULE__{
          command_id: Ecto.UUID.t(),
          type: command_type(),
          expected_version: non_neg_integer(),
          payload: map()
        }

  def build(command_id, type, expected_version, payload)
      when is_binary(command_id) and is_binary(type) and is_integer(expected_version) and
             expected_version >= 0 and is_map(payload) do
    with {:ok, command_id} <- Ecto.UUID.cast(command_id),
         {:ok, command_type} <- command_type(type) do
      {:ok,
       %__MODULE__{
         command_id: command_id,
         type: command_type,
         expected_version: expected_version,
         payload: payload
       }}
    else
      :error -> {:error, :invalid_command}
    end
  end

  def build(_command_id, _type, _expected_version, _payload),
    do: {:error, :invalid_command}

  defp command_type("place"), do: {:ok, :place}
  defp command_type("move"), do: {:ok, :move}
  defp command_type("analyze"), do: {:ok, :analyze}
  defp command_type("kickback"), do: {:ok, :kickback}
  defp command_type("end_turn"), do: {:ok, :end_turn}
  defp command_type(_type), do: :error
end
