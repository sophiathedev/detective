defmodule Detective.Games.Command do
  @moduledoc """
  A versioned command submitted by an authenticated game member.
  """

  @enforce_keys [:command_id, :type, :expected_version, :payload]
  defstruct [:command_id, :type, :expected_version, :payload]

  @type command_type ::
          :place
          | :move
          | :analyze
          | :kickback
          | :search_location
          | :search_suspect
          | :interrogate
          | :skip_free_question
          | :allow_question
          | :block_question
          | :accept_question_block
          | :bribe_goon
          | :choose_snitch
          | :decline_snitch
          | :resolve_snitches
          | :select_response
          | :accept_response
          | :challenge_response
          | :accuse
          | :submit_final_guess
          | :resume_game
          | :end_turn

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
  defp command_type("search_location"), do: {:ok, :search_location}
  defp command_type("search_suspect"), do: {:ok, :search_suspect}
  defp command_type("interrogate"), do: {:ok, :interrogate}
  defp command_type("skip_free_question"), do: {:ok, :skip_free_question}
  defp command_type("allow_question"), do: {:ok, :allow_question}
  defp command_type("block_question"), do: {:ok, :block_question}
  defp command_type("accept_question_block"), do: {:ok, :accept_question_block}
  defp command_type("bribe_goon"), do: {:ok, :bribe_goon}
  defp command_type("choose_snitch"), do: {:ok, :choose_snitch}
  defp command_type("decline_snitch"), do: {:ok, :decline_snitch}
  defp command_type("resolve_snitches"), do: {:ok, :resolve_snitches}
  defp command_type("select_response"), do: {:ok, :select_response}
  defp command_type("accept_response"), do: {:ok, :accept_response}
  defp command_type("challenge_response"), do: {:ok, :challenge_response}
  defp command_type("accuse"), do: {:ok, :accuse}
  defp command_type("submit_final_guess"), do: {:ok, :submit_final_guess}
  defp command_type("resume_game"), do: {:ok, :resume_game}
  defp command_type("end_turn"), do: {:ok, :end_turn}
  defp command_type(_type), do: :error
end
