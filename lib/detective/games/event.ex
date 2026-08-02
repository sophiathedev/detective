defmodule Detective.Games.Event do
  @moduledoc """
  An engine event before persistence assigns its database sequence.
  """

  @enforce_keys [:type, :public_payload]
  defstruct [:type, :public_payload, private_payloads: %{}]

  @type t :: %__MODULE__{
          type: atom(),
          public_payload: map(),
          private_payloads: %{optional(Ecto.UUID.t()) => map()}
        }
end
