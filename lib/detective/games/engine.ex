defmodule Detective.Games.Engine do
  @moduledoc """
  Pure, server-authoritative game engine.

  Movement follows district membership rather than visual adjacency: one Move
  action reaches any other location sharing a district. A border location can
  belong to more than one district and therefore bridges later Move actions.
  """

  alias Detective.Cases.{ResponseMatrix, Validator}
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
      initial_knowledge = ResponseMatrix.initial_topic_ids(case_definition)

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
             knowledge: initial_knowledge,
             statements: [],
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
         {:ok, actor} <- fetch_actor(state, actor_user_id) do
      dispatch(state, actor, command)
    end
  end

  defp dispatch(state, actor, %Command{type: :select_response} = command) do
    with :ok <- validate_chisel_response_turn(state, actor) do
      execute(state, actor, command)
    end
  end

  defp dispatch(state, actor, %Command{type: type} = command)
       when type in [:accept_response, :challenge_response] do
    with :ok <- validate_detective_decision(state, actor) do
      execute(state, actor, command)
    end
  end

  defp dispatch(state, actor, command) do
    with :ok <- validate_detective_turn(state, actor) do
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

  defp execute(state, actor, %Command{
         type: :interrogate,
         command_id: command_id,
         payload: payload
       }) do
    suspect_id = payload_value(payload, "suspect_id")
    topic_id = payload_value(payload, "topic_id")
    spend_leverage = payload_value(payload, "spend_leverage") || false

    with :ok <- validate_placed(actor),
         :ok <- validate_action_point(actor),
         {:ok, suspect} <- fetch_suspect(state, suspect_id),
         :ok <- validate_suspect_location(actor, suspect),
         {:ok, topic} <- ResponseMatrix.topic(state.case_definition, topic_id),
         :ok <- validate_topic_knowledge(actor, topic),
         {:ok, options} <-
           ResponseMatrix.response_options(state.case_definition, suspect.id, topic.id),
         :ok <- validate_spend_leverage(spend_leverage),
         {:ok, next_actor} <- spend_detective_leverage(actor, suspect.id, spend_leverage) do
      next_actor = %{next_actor | actions_remaining: next_actor.actions_remaining - 1}

      pending_action = %{
        "id" => command_id,
        "type" => "interrogation",
        "detective_player_id" => actor.id,
        "detective_user_id" => actor.user_id,
        "suspect_id" => suspect.id,
        "topic_id" => topic.id,
        "topic_code" => topic.code,
        "forced_truthful" => spend_leverage,
        "selected_response_id" => nil,
        "selected_response_text" => nil,
        "selected_response_type" => nil
      }

      chisel = Map.fetch!(state.players, state.chisel_player_id)

      next_state =
        state
        |> put_player(next_actor)
        |> Map.put(:phase, :waiting_for_chisel)
        |> Map.put(:pending_action, pending_action)
        |> advance_version()
        |> append_history(%{
          type: "interrogation_started",
          player_id: actor.id,
          suspect_id: suspect.id,
          topic_code: topic.code
        })

      public_payload = %{
        interrogation_id: command_id,
        detective_player_id: actor.id,
        suspect_id: suspect.id,
        topic_code: topic.code,
        actions_remaining: next_actor.actions_remaining
      }

      private_payload = %{
        type: "chisel_response_options",
        interrogation_id: command_id,
        response_options: options
      }

      event = %Event{
        type: :interrogation_started,
        public_payload: public_payload,
        private_payloads: %{chisel.user_id => private_payload}
      }

      {:ok, next_state, [event]}
    end
  end

  defp execute(state, _actor, %Command{type: :select_response, payload: payload}) do
    pending = state.pending_action
    response_id = payload_value(payload, "response_id")

    with :ok <- validate_pending_interrogation(pending),
         {:ok, option} <-
           ResponseMatrix.response_option(
             state.case_definition,
             pending["suspect_id"],
             pending["topic_id"],
             response_id
           ),
         :ok <- validate_forced_response(pending, option) do
      next_pending = %{
        pending
        | "selected_response_id" => option.id,
          "selected_response_text" => option.text,
          "selected_response_type" => option.type
      }

      detective = Map.fetch!(state.players, pending["detective_player_id"])

      next_state =
        state
        |> Map.put(:phase, :waiting_for_detective_decision)
        |> Map.put(:pending_action, next_pending)
        |> advance_version()
        |> append_history(%{
          type: "response_delivered",
          player_id: detective.id,
          suspect_id: pending["suspect_id"],
          topic_code: pending["topic_code"]
        })

      event = %Event{
        type: :response_published,
        public_payload: %{
          interrogation_id: pending["id"],
          detective_player_id: detective.id,
          suspect_id: pending["suspect_id"],
          topic_code: pending["topic_code"]
        },
        private_payloads: %{
          detective.user_id => %{
            type: "suspect_response",
            interrogation_id: pending["id"],
            response_text: option.text
          }
        }
      }

      {:ok, next_state, [event]}
    end
  end

  defp execute(state, actor, %Command{type: :accept_response}) do
    pending = state.pending_action

    next_actor =
      append_statement(actor, pending, pending["selected_response_text"], "accepted")

    next_state =
      state
      |> put_player(next_actor)
      |> Map.put(:phase, :detective_turn)
      |> Map.put(:pending_action, nil)
      |> advance_version()
      |> append_history(%{
        type: "response_accepted",
        player_id: actor.id,
        suspect_id: pending["suspect_id"],
        topic_code: pending["topic_code"]
      })

    event = %Event{
      type: :response_accepted,
      public_payload: %{
        interrogation_id: pending["id"],
        detective_player_id: actor.id,
        suspect_id: pending["suspect_id"],
        topic_code: pending["topic_code"]
      }
    }

    {:ok, next_state, [event]}
  end

  defp execute(state, actor, %Command{type: :challenge_response}) do
    pending = state.pending_action

    with :ok <- validate_challenge_marker(actor),
         {:ok, most_useful} <-
           ResponseMatrix.most_useful(
             state.case_definition,
             pending["suspect_id"],
             pending["topic_id"]
           ) do
      succeeded = pending["selected_response_type"] == "misdirection"
      {next_actor, next_chisel} = resolve_challenge_leverage(state, actor, pending, succeeded)

      next_actor =
        append_statement(
          next_actor,
          pending,
          most_useful.text,
          if(succeeded, do: "challenge_succeeded", else: "challenge_failed")
        )

      next_state =
        state
        |> put_player(next_actor)
        |> put_player(next_chisel)
        |> Map.put(:phase, :detective_turn)
        |> Map.put(:pending_action, nil)
        |> advance_version()
        |> append_history(%{
          type: if(succeeded, do: "challenge_succeeded", else: "challenge_failed"),
          player_id: actor.id,
          suspect_id: pending["suspect_id"],
          topic_code: pending["topic_code"]
        })

      event_type = if(succeeded, do: :challenge_succeeded, else: :challenge_failed)

      event = %Event{
        type: event_type,
        public_payload: %{
          interrogation_id: pending["id"],
          detective_player_id: actor.id,
          suspect_id: pending["suspect_id"],
          topic_code: pending["topic_code"],
          succeeded: succeeded
        },
        private_payloads: %{
          actor.user_id => %{
            type: "challenge_resolved",
            interrogation_id: pending["id"],
            succeeded: succeeded,
            final_response_text: most_useful.text,
            leverage_supply: next_actor.leverage_supply,
            suspect_leverage: Map.get(next_actor.leverage_on_suspects, pending["suspect_id"], 0)
          }
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

  defp fetch_suspect(state, suspect_id) when is_binary(suspect_id) do
    case Map.fetch(state.suspects, suspect_id) do
      {:ok, suspect} -> {:ok, suspect}
      :error -> {:error, :invalid_suspect}
    end
  end

  defp fetch_suspect(_state, _suspect_id), do: {:error, :invalid_suspect}

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

  defp validate_chisel_response_turn(%State{phase: :waiting_for_chisel}, %{
         role: "chisel"
       }),
       do: :ok

  defp validate_chisel_response_turn(%State{phase: phase}, _actor)
       when phase != :waiting_for_chisel,
       do: {:error, :wrong_phase}

  defp validate_chisel_response_turn(_state, _actor), do: {:error, :wrong_role}

  defp validate_detective_decision(
         %State{phase: :waiting_for_detective_decision, pending_action: pending},
         %{id: player_id, role: "detective"}
       ) do
    cond do
      not is_map(pending) -> {:error, :invalid_pending_action}
      pending["detective_player_id"] != player_id -> {:error, :not_interrogating_detective}
      is_nil(pending["selected_response_id"]) -> {:error, :response_not_selected}
      true -> :ok
    end
  end

  defp validate_detective_decision(%State{phase: phase}, _actor)
       when phase != :waiting_for_detective_decision,
       do: {:error, :wrong_phase}

  defp validate_detective_decision(_state, _actor), do: {:error, :wrong_role}

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

  defp validate_suspect_location(actor, suspect) do
    if actor.location_id == suspect.location_id do
      :ok
    else
      {:error, :suspect_not_at_location}
    end
  end

  defp validate_topic_knowledge(actor, topic) do
    if topic.id in actor.knowledge do
      :ok
    else
      {:error, :topic_not_known}
    end
  end

  defp validate_spend_leverage(value) when is_boolean(value), do: :ok
  defp validate_spend_leverage(_value), do: {:error, :invalid_command}

  defp spend_detective_leverage(actor, _suspect_id, false), do: {:ok, actor}

  defp spend_detective_leverage(actor, suspect_id, true) do
    leverage = Map.get(actor.leverage_on_suspects, suspect_id, 0)

    if leverage > 0 do
      {:ok,
       %{
         actor
         | leverage_supply: actor.leverage_supply + 1,
           leverage_on_suspects: Map.put(actor.leverage_on_suspects, suspect_id, leverage - 1)
       }}
    else
      {:error, :suspect_leverage_required}
    end
  end

  defp validate_pending_interrogation(%{"type" => "interrogation"}), do: :ok
  defp validate_pending_interrogation(_pending), do: {:error, :invalid_pending_action}

  defp validate_forced_response(%{"forced_truthful" => true}, %{type: "most_useful"}), do: :ok

  defp validate_forced_response(%{"forced_truthful" => true}, _option),
    do: {:error, :response_forced_truthful}

  defp validate_forced_response(_pending, _option), do: :ok

  defp validate_challenge_marker(%{leverage_supply: supply}) when supply > 0, do: :ok
  defp validate_challenge_marker(_actor), do: {:error, :no_leverage_remaining}

  defp resolve_challenge_leverage(state, actor, pending, true) do
    suspect_id = pending["suspect_id"]
    suspect_leverage = Map.get(actor.leverage_on_suspects, suspect_id, 0)

    next_actor = %{
      actor
      | leverage_supply: actor.leverage_supply - 1,
        leverage_on_suspects:
          Map.put(actor.leverage_on_suspects, suspect_id, suspect_leverage + 1)
    }

    {next_actor, Map.fetch!(state.players, state.chisel_player_id)}
  end

  defp resolve_challenge_leverage(state, actor, _pending, false) do
    chisel = Map.fetch!(state.players, state.chisel_player_id)
    chisel_leverage = Map.get(chisel.leverage_by_detective, actor.id, 0)

    next_actor = %{actor | leverage_supply: actor.leverage_supply - 1}

    next_chisel = %{
      chisel
      | leverage_by_detective:
          Map.put(chisel.leverage_by_detective, actor.id, chisel_leverage + 1)
    }

    {next_actor, next_chisel}
  end

  defp append_statement(actor, pending, response_text, resolution) do
    statement = %{
      "interrogation_id" => pending["id"],
      "suspect_id" => pending["suspect_id"],
      "topic_id" => pending["topic_id"],
      "topic_code" => pending["topic_code"],
      "response_text" => response_text,
      "resolution" => resolution
    }

    %{actor | statements: Enum.take([statement | actor.statements], 50)}
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

  defp payload_value(payload, key), do: Map.get(payload, key)

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default
end
