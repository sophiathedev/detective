defmodule Detective.Cases.ResponseMatrix do
  @moduledoc """
  Normalizes the original case response graph used by interrogations.

  Response identifiers are server-owned. Clients may select an identifier, but
  never submit response text or whether the response is truthful.
  """

  def validate(case_definition) when is_map(case_definition) do
    case_cards = case_definition["case_cards"] || []
    suspects = case_definition["suspects"] || []
    matrix = case_definition["response_matrix"] || %{}

    with :ok <- validate_case_cards(case_cards),
         :ok <- validate_matrix(matrix),
         :ok <- validate_matrix_references(matrix, suspects, case_cards) do
      :ok
    end
  end

  def validate(_case_definition), do: {:error, :invalid_response_matrix}

  def initial_topic_ids(case_definition) do
    case_definition
    |> topics()
    |> Enum.filter(& &1.initially_known)
    |> Enum.map(& &1.id)
  end

  def topics(case_definition) when is_map(case_definition) do
    case_definition
    |> Map.get("case_cards", [])
    |> Enum.with_index()
    |> Enum.map(fn {card, index} ->
      %{
        id: card["id"],
        code: card["code"] || topic_code(index),
        title: card["title"],
        type: card["type"],
        description: card["description"] || "",
        takeable: card["takeable"] == true,
        initially_known: card["initially_known"] == true
      }
    end)
  end

  def topics(_case_definition), do: []

  def known_topics(case_definition, knowledge) do
    known_ids = MapSet.new(knowledge)
    Enum.filter(topics(case_definition), &MapSet.member?(known_ids, &1.id))
  end

  def topic(case_definition, topic_id) do
    case Enum.find(topics(case_definition), &(&1.id == topic_id)) do
      nil -> {:error, :invalid_topic}
      topic -> {:ok, topic}
    end
  end

  def response_options(case_definition, suspect_id, topic_id) do
    with matrix when is_map(matrix) <- case_definition["response_matrix"],
         suspect_matrix when is_map(suspect_matrix) <- matrix[suspect_id],
         entry when is_map(entry) <- suspect_matrix[topic_id],
         {:ok, most_useful} <-
           normalize_response(entry["most_useful"], "response-0", "most_useful"),
         {:ok, misdirections} <- normalize_misdirections(entry["misdirections"] || []) do
      {:ok, [most_useful | misdirections]}
    else
      _invalid -> {:error, :response_not_found}
    end
  end

  def response_option(case_definition, suspect_id, topic_id, response_id) do
    with {:ok, options} <- response_options(case_definition, suspect_id, topic_id),
         %{} = option <- Enum.find(options, &(&1.id == response_id)) do
      {:ok, option}
    else
      _invalid -> {:error, :invalid_response}
    end
  end

  def most_useful(case_definition, suspect_id, topic_id) do
    with {:ok, options} <- response_options(case_definition, suspect_id, topic_id),
         %{} = option <- Enum.find(options, &(&1.type == "most_useful")) do
      {:ok, option}
    else
      _invalid -> {:error, :response_not_found}
    end
  end

  defp validate_case_cards(case_cards) when is_list(case_cards) do
    ids = Enum.map(case_cards, & &1["id"])
    codes = Enum.map(case_cards, & &1["code"]) |> Enum.reject(&is_nil/1)

    cond do
      not Enum.all?(case_cards, &valid_case_card?/1) -> {:error, :invalid_case_cards}
      Enum.uniq(ids) != ids -> {:error, :duplicate_case_card_id}
      Enum.uniq(codes) != codes -> {:error, :duplicate_case_card_code}
      true -> :ok
    end
  end

  defp validate_case_cards(_case_cards), do: {:error, :invalid_case_cards}

  defp valid_case_card?(card) do
    is_map(card) and is_binary(card["id"]) and card["id"] != "" and
      is_binary(card["title"]) and card["title"] != "" and is_binary(card["type"]) and
      is_boolean(card["initially_known"]) and
      (is_nil(card["takeable"]) or is_boolean(card["takeable"])) and
      (is_nil(card["code"]) or (is_binary(card["code"]) and card["code"] != ""))
  end

  defp validate_matrix(matrix) when is_map(matrix) do
    if Enum.all?(matrix, fn {_suspect_id, suspect_matrix} ->
         is_map(suspect_matrix) and
           Enum.all?(suspect_matrix, fn {_topic_id, entry} -> valid_entry?(entry) end)
       end) do
      :ok
    else
      {:error, :invalid_response_matrix}
    end
  end

  defp validate_matrix(_matrix), do: {:error, :invalid_response_matrix}

  defp valid_entry?(entry) when is_map(entry) do
    with {:ok, most_useful} <-
           normalize_response(entry["most_useful"], "response-0", "most_useful"),
         {:ok, misdirections} <- normalize_misdirections(entry["misdirections"] || []) do
      ids = Enum.map([most_useful | misdirections], & &1.id)
      Enum.uniq(ids) == ids
    else
      _invalid -> false
    end
  end

  defp valid_entry?(_entry), do: false

  defp validate_matrix_references(matrix, suspects, case_cards) do
    suspect_ids = suspects |> Enum.map(& &1["id"]) |> MapSet.new()
    topic_ids = case_cards |> Enum.map(& &1["id"]) |> MapSet.new()

    valid? =
      Enum.all?(matrix, fn {suspect_id, suspect_matrix} ->
        MapSet.member?(suspect_ids, suspect_id) and
          Enum.all?(suspect_matrix, fn {topic_id, entry} ->
            MapSet.member?(topic_ids, topic_id) and response_references_valid?(entry, topic_ids)
          end)
      end)

    if valid?, do: :ok, else: {:error, :invalid_response_reference}
  end

  defp normalize_misdirections(misdirections) when is_list(misdirections) do
    misdirections
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {response, index}, {:ok, acc} ->
      case normalize_response(response, "response-#{index}", "misdirection") do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_misdirections(_misdirections), do: {:error, :invalid_response}

  defp normalize_response(text, default_id, type) when is_binary(text) and text != "" do
    {:ok, %{id: default_id, text: text, type: type, case_card_ids: []}}
  end

  defp normalize_response(response, default_id, type) when is_map(response) do
    id = response["id"] || default_id
    text = response["text"]
    case_card_ids = response["reveal_case_card_ids"] || []

    if is_binary(id) and id != "" and is_binary(text) and text != "" and
         valid_id_list?(case_card_ids) do
      {:ok, %{id: id, text: text, type: type, case_card_ids: case_card_ids}}
    else
      {:error, :invalid_response}
    end
  end

  defp normalize_response(_response, _default_id, _type), do: {:error, :invalid_response}

  defp response_references_valid?(entry, topic_ids) do
    with {:ok, most_useful} <-
           normalize_response(entry["most_useful"], "response-0", "most_useful"),
         {:ok, misdirections} <- normalize_misdirections(entry["misdirections"] || []) do
      Enum.all?([most_useful | misdirections], fn response ->
        MapSet.subset?(MapSet.new(response.case_card_ids), topic_ids)
      end)
    else
      _invalid -> false
    end
  end

  defp valid_id_list?(ids) when is_list(ids) do
    Enum.all?(ids, &(is_binary(&1) and &1 != "")) and Enum.uniq(ids) == ids
  end

  defp valid_id_list?(_ids), do: false

  defp topic_code(index) do
    index
    |> rem(26)
    |> Kernel.+(?A)
    |> then(&<<&1>>)
  end
end
