defmodule Detective.Games.Engine do
  @moduledoc """
  Pure, server-authoritative game engine.

  Movement follows district membership rather than visual adjacency: one Move
  action reaches any other location sharing a district. A border location can
  belong to more than one district and therefore bridges later Move actions.
  """

  alias Detective.Cases.Validator
  alias Detective.Games.{Command, Event, Rules, State}

  @actions_per_turn 4
  @starting_scratch [4, 5, 6, 9]

  def new(game, players, case_definition) when is_map(case_definition) do
    detectives =
      players
      |> Enum.filter(&(&1.role == "detective"))
      |> Enum.sort_by(& &1.seat)

    chisels = Enum.filter(players, &(&1.role == "chisel"))

    with [chisel] <- chisels,
         true <- detectives != [] and length(detectives) <= 4,
         :ok <- Validator.validate(case_definition),
         {:ok, locations} <- normalize_locations(case_definition["locations"]),
         true <- Enum.any?(locations, fn {_id, location} -> location.type == "police_station" end) do
      detective_players =
        detectives
        |> Enum.with_index()
        |> Map.new(fn {player, index} ->
          scratch = Enum.at(@starting_scratch, index)

          {player.id,
           %{
             id: player.id,
             user_id: player.user_id,
             display_name: player.display_name,
             role: "detective",
             seat: player.seat,
             location_id: nil,
             actions_remaining: @actions_per_turn,
             scratch: scratch,
             leverage_supply: 7,
             leverage_on_suspects: %{},
             knowledge: [],
             kickback_day: nil
           }}
        end)

      chisel_player = %{
        id: chisel.id,
        user_id: chisel.user_id,
        display_name: chisel.display_name,
        role: "chisel",
        leverage_by_detective: Map.new(detectives, &{&1.id, 1})
      }

      detective_order = Enum.map(detectives, & &1.id)
      max_days = positive_integer(case_definition["max_days"], 6)

      {:ok,
       %State{
         game_id: game.id,
         case_version_id: game.case_version_id,
         days_remaining: max_days,
         chisel_player_id: chisel.id,
         current_detective_id: List.first(detective_order),
         detective_order: detective_order,
         players: Map.put(detective_players, chisel.id, chisel_player),
         locations: locations,
         suspects: normalize_suspects(case_definition["suspects"]),
         case_definition: case_definition
       }}
    else
      _invalid -> {:error, :invalid_initial_state}
    end
  end

  def apply(%State{} = state, actor_user_id, %Command{} = command) do
    with :ok <- validate_version(state, command.expected_version),
         {:ok, actor} <- fetch_actor(state, actor_user_id),
         :ok <- validate_detective_turn(state, actor) do
      execute(state, actor, command)
    end
  end

  defp execute(state, actor, %Command{type: :place, payload: payload}) do
    with :ok <- validate_unplaced(actor),
         {:ok, location} <- fetch_location(state, payload),
         :ok <- validate_police_station(location) do
      next_actor = %{actor | location_id: location.id}

      next_state =
        state
        |> put_player(next_actor)
        |> advance_version()
        |> append_history(%{
          type: "detective_placed",
          player_id: actor.id,
          location_id: location.id
        })

      event =
        %Event{
          type: :detective_placed,
          public_payload: %{player_id: actor.id, location_id: location.id}
        }

      {:ok, next_state, [event]}
    end
  end

  defp execute(state, actor, %Command{type: :move, payload: payload}) do
    with :ok <- validate_placed(actor),
         :ok <- validate_action_point(actor),
         {:ok, destination} <- fetch_location(state, payload),
         :ok <- validate_destination(state, actor, destination) do
      from_location_id = actor.location_id

      next_actor = %{
        actor
        | location_id: destination.id,
          actions_remaining: actor.actions_remaining - 1
      }

      next_state =
        state
        |> put_player(next_actor)
        |> advance_version()
        |> append_history(%{
          type: "player_moved",
          player_id: actor.id,
          from_location_id: from_location_id,
          location_id: destination.id
        })

      event =
        %Event{
          type: :player_moved,
          public_payload: %{
            player_id: actor.id,
            from_location_id: from_location_id,
            location_id: destination.id,
            actions_remaining: next_actor.actions_remaining
          }
        }

      {:ok, next_state, [event]}
    end
  end

  defp execute(state, actor, %Command{type: :analyze}) do
    with :ok <- validate_placed(actor),
         :ok <- validate_action_point(actor) do
      next_actor = %{
        actor
        | actions_remaining: actor.actions_remaining - 1,
          scratch: actor.scratch + 1
      }

      next_state =
        state
        |> put_player(next_actor)
        |> advance_version()
        |> append_history(%{
          type: "evidence_analyzed",
          player_id: actor.id
        })

      event =
        %Event{
          type: :evidence_analyzed,
          public_payload: %{
            player_id: actor.id,
            actions_remaining: next_actor.actions_remaining
          },
          private_payloads: %{
            actor.user_id => %{scratch: next_actor.scratch}
          }
        }

      {:ok, next_state, [event]}
    end
  end

  defp execute(state, actor, %Command{type: :kickback}) do
    with :ok <- validate_placed(actor),
         :ok <- validate_action_point(actor),
         {:ok, location} <- Map.fetch(state.locations, actor.location_id),
         :ok <- validate_mob_joint(location),
         :ok <- validate_kickback_day(state, actor) do
      payout = map_size(state.players)

      next_actor = %{
        actor
        | actions_remaining: actor.actions_remaining - 1,
          scratch: actor.scratch + payout,
          kickback_day: state.day
      }

      next_state =
        state
        |> put_player(next_actor)
        |> advance_version()
        |> append_history(%{
          type: "kickback_collected",
          player_id: actor.id,
          location_id: location.id
        })

      event =
        %Event{
          type: :kickback_collected,
          public_payload: %{
            player_id: actor.id,
            location_id: location.id,
            actions_remaining: next_actor.actions_remaining
          },
          private_payloads: %{
            actor.user_id => %{scratch: next_actor.scratch, payout: payout}
          }
        }

      {:ok, next_state, [event]}
    end
  end

  defp execute(state, actor, %Command{type: :end_turn}) do
    with :ok <- validate_placed(actor) do
      {next_state, turn_events} = advance_turn(state, actor)

      next_state =
        next_state
        |> advance_version()
        |> append_history(%{type: "turn_ended", player_id: actor.id})

      turn_ended = %Event{type: :turn_ended, public_payload: %{player_id: actor.id}}
      {:ok, next_state, [turn_ended | turn_events]}
    end
  end

  defp execute(_state, _actor, %Command{}), do: {:error, :command_not_allowed}

  defp advance_turn(state, actor) do
    current_index = Enum.find_index(state.detective_order, &(&1 == actor.id))
    next_id = Enum.at(state.detective_order, current_index + 1)

    if next_id do
      next_player = reset_actions(Map.fetch!(state.players, next_id))
      next_state = state |> put_player(next_player) |> Map.put(:current_detective_id, next_id)

      event = %Event{type: :turn_started, public_payload: %{player_id: next_id, day: state.day}}
      {next_state, [event]}
    else
      advance_day(state)
    end
  end

  defp advance_day(%State{days_remaining: 1} = state) do
    next_state = %{
      state
      | days_remaining: 0,
        phase: :accusation,
        current_detective_id: nil
    }

    event = %Event{type: :accusation_opened, public_payload: %{day: state.day}}
    {next_state, [event]}
  end

  defp advance_day(state) do
    next_id = List.first(state.detective_order)
    next_player = reset_actions(Map.fetch!(state.players, next_id))

    next_state = %{
      state
      | day: state.day + 1,
        days_remaining: state.days_remaining - 1,
        current_detective_id: next_id,
        players: Map.put(state.players, next_id, next_player)
    }

    events = [
      %Event{
        type: :day_advanced,
        public_payload: %{day: next_state.day, days_remaining: next_state.days_remaining}
      },
      %Event{type: :turn_started, public_payload: %{player_id: next_id, day: next_state.day}}
    ]

    {next_state, events}
  end

  defp reset_actions(player), do: %{player | actions_remaining: @actions_per_turn}

  defp fetch_actor(state, actor_user_id) do
    case State.player_by_user_id(state, actor_user_id) do
      nil -> {:error, :not_a_member}
      actor -> {:ok, actor}
    end
  end

  defp fetch_location(state, payload) do
    location_id = Map.get(payload, "location_id") || Map.get(payload, :location_id)

    case Map.fetch(state.locations, location_id) do
      {:ok, location} -> {:ok, location}
      :error -> {:error, :invalid_location}
    end
  end

  defp normalize_locations(locations) when is_list(locations) do
    locations
    |> Enum.reduce_while({:ok, %{}}, fn location, {:ok, acc} ->
      with id when is_binary(id) <- location["id"],
           name when is_binary(name) <- location["name"],
           type when type in ["standard", "police_station", "mob_joint"] <- location["type"],
           district_ids when is_list(district_ids) and district_ids != [] <-
             location["district_ids"],
           true <- Enum.all?(district_ids, &is_binary/1),
           x when is_number(x) and x >= 0 and x <= 1 <- location["x"],
           y when is_number(y) and y >= 0 and y <= 1 <- location["y"] do
        normalized = %{
          id: id,
          name: name,
          type: type,
          district_ids: district_ids,
          x: x,
          y: y
        }

        {:cont, {:ok, Map.put(acc, id, normalized)}}
      else
        _invalid -> {:halt, {:error, :invalid_locations}}
      end
    end)
  end

  defp normalize_locations(_locations), do: {:error, :invalid_locations}

  defp normalize_suspects(suspects) when is_list(suspects) do
    Map.new(suspects, fn suspect ->
      {suspect["id"],
       %{
         id: suspect["id"],
         name: suspect["name"],
         occupation: suspect["occupation"],
         location_id: suspect["location_id"]
       }}
    end)
  end

  defp normalize_suspects(_suspects), do: %{}

  defp validate_version(%State{version: version}, version), do: :ok
  defp validate_version(%State{}, _expected_version), do: {:error, :stale_version}

  defp validate_detective_turn(%State{phase: :detective_turn} = state, %{
         id: player_id,
         role: "detective"
       })
       when player_id == state.current_detective_id,
       do: :ok

  defp validate_detective_turn(%State{phase: phase}, _actor) when phase != :detective_turn,
    do: {:error, :wrong_phase}

  defp validate_detective_turn(_state, %{role: "chisel"}), do: {:error, :wrong_role}
  defp validate_detective_turn(_state, _actor), do: {:error, :not_your_turn}

  defp validate_unplaced(%{location_id: nil}), do: :ok
  defp validate_unplaced(_actor), do: {:error, :already_placed}

  defp validate_placed(%{location_id: nil}), do: {:error, :placement_required}
  defp validate_placed(_actor), do: :ok

  defp validate_action_point(%{actions_remaining: actions}) when actions > 0, do: :ok
  defp validate_action_point(_actor), do: {:error, :no_actions_remaining}

  defp validate_police_station(%{type: "police_station"}), do: :ok
  defp validate_police_station(_location), do: {:error, :police_station_required}

  defp validate_mob_joint(%{type: "mob_joint"}), do: :ok
  defp validate_mob_joint(_location), do: {:error, :mob_joint_required}

  defp validate_kickback_day(state, actor) do
    if actor.kickback_day == state.day do
      {:error, :kickback_already_used}
    else
      :ok
    end
  end

  defp validate_destination(state, actor, destination) do
    current_location = Map.fetch!(state.locations, actor.location_id)

    cond do
      destination.id == current_location.id -> {:error, :already_at_location}
      Rules.same_district?(current_location, destination) -> :ok
      true -> {:error, :destination_outside_district}
    end
  end

  defp put_player(state, player),
    do: %{state | players: Map.put(state.players, player.id, player)}

  defp advance_version(state), do: %{state | version: state.version + 1}

  defp append_history(state, history_entry) do
    %{state | public_history: Enum.take([history_entry | state.public_history], 100)}
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default
end
