defmodule Detective.Games.Event do
  @moduledoc """
  An engine event before persistence assigns its database sequence.
  """

  @enforce_keys [:type, :public_payload]
  defstruct [:type, :public_payload, :delivery_id, :version, private_payloads: %{}]

  @type t :: %__MODULE__{
          type: atom(),
          public_payload: map(),
          delivery_id: Ecto.UUID.t() | nil,
          version: non_neg_integer() | nil,
          private_payloads: %{optional(Ecto.UUID.t()) => map()}
        }
end
