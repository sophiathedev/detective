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
          | :interact_special_actor
          | :interrogate
          | :skip_free_question
          | :allow_question
          | :block_question
          | :accept_question_block
          | :bribe_goon
          | :bribe_detective
          | :bribe_officer
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

  @empty_payload_commands [
    :analyze,
    :kickback,
    :search_location,
    :skip_free_question,
    :allow_question,
    :block_question,
    :accept_question_block,
    :bribe_goon,
    :choose_snitch,
    :decline_snitch,
    :accept_response,
    :challenge_response,
    :resume_game,
    :end_turn
  ]

  @single_id_payloads %{
    place: "location_id",
    move: "location_id",
    search_suspect: "suspect_id",
    bribe_officer: "case_card_id",
    select_response: "response_id"
  }

  def build(command_id, type, expected_version, payload)
      when is_binary(command_id) and is_binary(type) and is_integer(expected_version) and
             expected_version >= 0 and is_map(payload) do
    with {:ok, command_id} <- Ecto.UUID.cast(command_id),
         {:ok, command_type} <- command_type(type),
         :ok <- validate_payload(command_type, payload) do
      {:ok,
       %__MODULE__{
         command_id: command_id,
         type: command_type,
         expected_version: expected_version,
         payload: payload
       }}
    else
      :error -> {:error, :invalid_command}
      {:error, _reason} -> {:error, :invalid_command}
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
  defp command_type("interact_special_actor"), do: {:ok, :interact_special_actor}
  defp command_type("interrogate"), do: {:ok, :interrogate}
  defp command_type("skip_free_question"), do: {:ok, :skip_free_question}
  defp command_type("allow_question"), do: {:ok, :allow_question}
  defp command_type("block_question"), do: {:ok, :block_question}
  defp command_type("accept_question_block"), do: {:ok, :accept_question_block}
  defp command_type("bribe_goon"), do: {:ok, :bribe_goon}
  defp command_type("bribe_detective"), do: {:ok, :bribe_detective}
  defp command_type("bribe_officer"), do: {:ok, :bribe_officer}
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

  defp validate_payload(type, payload) when type in @empty_payload_commands do
    if payload == %{}, do: :ok, else: {:error, :invalid_command}
  end

  defp validate_payload(type, payload) when is_map_key(@single_id_payloads, type) do
    key = Map.fetch!(@single_id_payloads, type)

    with :ok <- exact_keys(payload, [key]),
         :ok <- valid_id(Map.get(payload, key)) do
      :ok
    end
  end

  defp validate_payload(:bribe_detective, payload) do
    validate_id_payload(payload, ["detective_player_id", "case_card_id"])
  end

  defp validate_payload(:interact_special_actor, payload) do
    validate_id_payload(payload, ["actor_id", "option_id"])
  end

  defp validate_payload(:interrogate, payload) do
    with :ok <- allowed_keys(payload, ["suspect_id", "topic_id"], ["spend_leverage"]),
         :ok <- valid_id(Map.get(payload, "suspect_id")),
         :ok <- valid_id(Map.get(payload, "topic_id")),
         :ok <- optional_boolean(payload, "spend_leverage") do
      :ok
    end
  end

  defp validate_payload(:resolve_snitches, payload) do
    with :ok <- exact_keys(payload, ["blocked_player_ids"]),
         player_ids when is_list(player_ids) <- Map.get(payload, "blocked_player_ids"),
         true <- length(player_ids) <= 4,
         true <- Enum.uniq(player_ids) == player_ids,
         true <- Enum.all?(player_ids, &(valid_id(&1) == :ok)) do
      :ok
    else
      _invalid -> {:error, :invalid_command}
    end
  end

  defp validate_payload(type, payload) when type in [:accuse, :submit_final_guess] do
    validate_id_payload(payload, ["suspect_id", "weapon_id", "motive_id"])
  end

  defp validate_payload(_type, _payload), do: {:error, :invalid_command}

  defp validate_id_payload(payload, keys) do
    with :ok <- exact_keys(payload, keys),
         true <- Enum.all?(keys, &(valid_id(Map.get(payload, &1)) == :ok)) do
      :ok
    else
      _invalid -> {:error, :invalid_command}
    end
  end

  defp exact_keys(payload, keys) do
    if MapSet.new(Map.keys(payload)) == MapSet.new(keys) do
      :ok
    else
      {:error, :invalid_command}
    end
  end

  defp allowed_keys(payload, required, optional) do
    keys = Map.keys(payload)

    if Enum.all?(required, &Map.has_key?(payload, &1)) and
         Enum.all?(keys, &(&1 in required or &1 in optional)) do
      :ok
    else
      {:error, :invalid_command}
    end
  end

  defp valid_id(value) when is_binary(value) and byte_size(value) in 1..128, do: :ok
  defp valid_id(_value), do: {:error, :invalid_command}

  defp optional_boolean(payload, key) do
    case Map.fetch(payload, key) do
      :error -> :ok
      {:ok, value} when is_boolean(value) -> :ok
      {:ok, _value} -> {:error, :invalid_command}
    end
  end
end
