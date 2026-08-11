defmodule Detective.Games.Engine do
  @moduledoc """
  Pure, server-authoritative game engine.

  Movement follows district membership rather than visual adjacency: one Move
  action reaches any other location sharing a district. A border location can
  belong to more than one district and therefore bridges later Move actions.
  """

  alias Detective.Cases.{
    AccusationSheet,
    BoardCatalog,
    LegacyBoardAdapter,
    ResponseMatrix,
    SearchDeck,
    SpecialActors,
    SpecialRules,
    Validator
  }

  alias Detective.Games.{Command, Event, InvestigationStats, Rules, State}

  @actions_per_turn 4
  @starting_scratch [4, 5, 6, 9]
  @classic_days %{2 => 9, 3 => 8, 4 => 7}

  def new(game, players, case_definition) when is_map(case_definition) do
    detectives =
      players
      |> Enum.filter(&(&1.role == "detective"))
      |> Enum.sort_by(& &1.seat)

    chisels = Enum.filter(players, &(&1.role == "chisel"))

    with [chisel] <- chisels,
         true <- length(detectives) in 2..4,
         {:ok, case_definition} <- LegacyBoardAdapter.adapt(case_definition),
         :ok <- Validator.validate(case_definition),
         {:ok, board_locations} <- BoardCatalog.locations(case_definition["board_id"]),
         {:ok, locations} <- normalize_locations(board_locations),
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
             search_notes: [],
             evidence: [],
             free_question_suspect_id: nil,
             solve_token_available: true,
             solve_attempt: nil,
             final_guess: nil,
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
      default_days = Map.fetch!(@classic_days, length(detectives))

      max_days =
        case_definition["max_days"]
        |> positive_integer(default_days)
        |> then(&SpecialRules.starting_days(case_definition, length(detectives), &1))

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
         special_actors: SpecialActors.initialize(case_definition),
         case_definition: case_definition,
         public_case_card_ids: initial_knowledge
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

  def apply_system(%State{status: :active} = state, {:pause_for_disconnect, ids})
      when is_list(ids) and ids != [] do
    next_state =
      %{
        state
        | status: :paused,
          phase: :paused,
          paused_from_phase: state.phase,
          pause_reason: :player_disconnected,
          paused_player_ids: Enum.uniq(ids)
      }
      |> advance_version()

    event = %Event{
      type: :game_paused,
      public_payload: %{
        reason: "player_disconnected",
        disconnected_player_ids: next_state.paused_player_ids
      }
    }

    {:ok, next_state, [event]}
  end

  def apply_system(%State{status: status} = state, {:pause_for_disconnect, _ids})
      when status in [:paused, :finished],
      do: {:ok, state, []}

  defp dispatch(%State{status: :active}, _actor, %Command{type: :resume_game}),
    do: {:error, :game_not_paused}

  defp dispatch(%State{status: status} = state, actor, %Command{type: :concede_game} = command)
       when status in [:active, :paused] do
    with :ok <- validate_resume_actor(actor) do
      execute(state, actor, command)
    end
  end

  defp dispatch(%State{status: :paused} = state, actor, %Command{type: :resume_game} = command) do
    with :ok <- validate_resume_actor(actor) do
      execute(state, actor, command)
    end
  end

  defp dispatch(%State{status: :paused}, _actor, %Command{}), do: {:error, :game_paused}

  defp dispatch(state, actor, %Command{type: type} = command)
       when type in [:allow_question, :block_question, :resolve_snitches, :select_response] do
    with :ok <- validate_chisel_interrogation_turn(state, actor) do
      execute(state, actor, command)
    end
  end

  defp dispatch(state, actor, %Command{type: type} = command)
       when type in [:accept_question_block, :bribe_goon] do
    with :ok <- validate_blocked_question_decision(state, actor) do
      execute(state, actor, command)
    end
  end

  defp dispatch(state, actor, %Command{type: type} = command)
       when type in [:choose_snitch, :decline_snitch] do
    with :ok <- validate_snitch_turn(state, actor) do
      execute(state, actor, command)
    end
  end

  defp dispatch(state, actor, %Command{type: type} = command)
       when type in [:accept_response, :challenge_response] do
    with :ok <- validate_detective_decision(state, actor) do
      execute(state, actor, command)
    end
  end

  defp dispatch(state, actor, %Command{type: :submit_final_guess} = command) do
    with :ok <- validate_final_guess_turn(state, actor) do
      execute(state, actor, command)
    end
  end

  defp dispatch(state, actor, command) do
    with :ok <- validate_detective_turn(state, actor),
         :ok <- validate_free_question_command(actor, command) do
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

  defp execute(state, actor, %Command{type: :bribe_detective, payload: payload}) do
    target_id = payload_value(payload, "detective_player_id")
    case_card_id = payload_value(payload, "case_card_id")

    with :ok <- validate_placed(actor),
         {:ok, target} <- fetch_detective(state, target_id),
         :ok <- validate_other_detective(actor, target),
         :ok <- validate_bribe_target_location(actor, target),
         :ok <- validate_scratch(actor, 2),
         :ok <- validate_target_case_card(target, case_card_id),
         :ok <- validate_case_card_unknown(actor, case_card_id),
         {:ok, case_card} <- fetch_private_case_card(state, case_card_id) do
      next_actor = %{
        actor
        | scratch: actor.scratch - 2,
          knowledge: Enum.uniq([case_card_id | actor.knowledge])
      }

      next_target = %{target | scratch: target.scratch + 2}

      {next_state, newly_public_ids} =
        state
        |> put_player(next_actor)
        |> put_player(next_target)
        |> promote_shared_knowledge()

      next_actor = Map.fetch!(next_state.players, actor.id)
      next_target = Map.fetch!(next_state.players, target.id)

      next_state =
        next_state
        |> advance_version()
        |> append_history(%{
          type: "detective_bribed",
          player_id: actor.id,
          target_player_id: target.id,
          case_card_code: case_card.code
        })

      event = %Event{
        type: :detective_bribed,
        public_payload: %{
          player_id: actor.id,
          target_player_id: target.id,
          case_card_code: case_card.code,
          revealed_publicly: case_card_id in newly_public_ids
        },
        private_payloads: %{
          actor.user_id => %{
            type: "bribe_result",
            source: "detective",
            scratch: next_actor.scratch,
            case_card: case_card
          },
          target.user_id => %{
            type: "scratch_updated",
            scratch: next_target.scratch,
            received: 2
          }
        }
      }

      {:ok, next_state, [event]}
    end
  end

  defp execute(state, actor, %Command{type: :bribe_officer, payload: payload}) do
    case_card_id = payload_value(payload, "case_card_id")

    with :ok <- validate_placed(actor),
         :ok <- validate_scratch(actor, 3),
         {:ok, location} <- Map.fetch(state.locations, actor.location_id),
         :ok <- validate_police_station(location),
         :ok <- validate_case_card_unknown(actor, case_card_id),
         :ok <- validate_case_card_known_by_other_detective(state, actor, case_card_id),
         {:ok, case_card} <- fetch_private_case_card(state, case_card_id) do
      next_actor = %{
        actor
        | scratch: actor.scratch - 3,
          knowledge: Enum.uniq([case_card_id | actor.knowledge])
      }

      {next_state, newly_public_ids} =
        state
        |> put_player(next_actor)
        |> promote_shared_knowledge()

      next_actor = Map.fetch!(next_state.players, actor.id)

      next_state =
        next_state
        |> advance_version()
        |> append_history(%{
          type: "officer_bribed",
          player_id: actor.id,
          location_id: location.id,
          case_card_code: case_card.code
        })

      event = %Event{
        type: :officer_bribed,
        public_payload: %{
          player_id: actor.id,
          location_id: location.id,
          case_card_code: case_card.code,
          revealed_publicly: case_card_id in newly_public_ids
        },
        private_payloads: %{
          actor.user_id => %{
            type: "bribe_result",
            source: "officer",
            scratch: next_actor.scratch,
            case_card: case_card
          }
        }
      }

      {:ok, next_state, [event]}
    else
      :error -> {:error, :invalid_location}
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute(state, actor, %Command{type: :search_location}) do
    with :ok <- validate_placed(actor),
         :ok <- validate_action_point(actor),
         :ok <- validate_special_actor_block(state, actor, :search_location),
         {:ok, result} <- SearchDeck.location_result(state.case_definition, actor.location_id),
         :ok <- validate_search_target_available(state, result),
         :ok <- validate_evidence_available(state, result) do
      resolve_search(state, actor, result, :location_searched)
    end
  end

  defp execute(state, actor, %Command{type: :search_suspect, payload: payload}) do
    suspect_id = payload_value(payload, "suspect_id")

    with :ok <- validate_placed(actor),
         :ok <- validate_action_point(actor),
         {:ok, suspect} <- fetch_suspect(state, suspect_id),
         :ok <- validate_suspect_location(actor, suspect),
         :ok <- validate_special_actor_block(state, actor, :search_suspect),
         {:ok, result} <- SearchDeck.suspect_result(state.case_definition, suspect.id),
         :ok <- validate_search_target_available(state, result),
         :ok <- validate_evidence_available(state, result) do
      resolve_search(state, actor, result, :suspect_searched)
    end
  end

  defp execute(state, actor, %Command{type: :interact_special_actor, payload: payload}) do
    actor_id = payload_value(payload, "actor_id")
    option_id = payload_value(payload, "option_id")

    with :ok <- validate_placed(actor),
         {:ok, special_actor, option} <-
           SpecialActors.fetch_option(state.special_actors, actor_id, option_id),
         :ok <- validate_special_actor_location(actor, special_actor),
         :ok <- validate_special_actor_option(actor, special_actor, option),
         private_case_card_ids <- SpecialActors.private_case_card_ids(option),
         public_case_card_ids <- SpecialActors.public_case_card_ids(option),
         revealed_suspect_ids <- SpecialActors.revealed_suspect_ids(option),
         {:ok, case_cards} <-
           SearchDeck.case_cards(state.case_definition, private_case_card_ids) do
      next_actor = %{
        actor
        | actions_remaining: actor.actions_remaining - option.action_cost,
          scratch: actor.scratch - option.scratch_cost,
          knowledge: Enum.uniq(actor.knowledge ++ private_case_card_ids)
      }

      next_state = %{
        state
        | special_actors: SpecialActors.mark_used(state.special_actors, special_actor.id, option)
      }

      {next_state, effect_public_ids} =
        next_state
        |> put_player(next_actor)
        |> reveal_public_case_cards(public_case_card_ids)

      {next_state, newly_revealed_suspect_ids} =
        reveal_public_suspects(next_state, revealed_suspect_ids)

      {next_state, shared_public_ids} =
        next_state
        |> promote_shared_knowledge()

      newly_public_ids = Enum.uniq(effect_public_ids ++ shared_public_ids)

      next_actor = Map.fetch!(next_state.players, actor.id)
      next_special_actor = Map.fetch!(next_state.special_actors, special_actor.id)

      next_state =
        next_state
        |> advance_version()
        |> append_history(%{
          type: "special_actor_interacted",
          player_id: actor.id,
          special_actor_id: special_actor.id,
          option_id: option.id
        })

      event = %Event{
        type: :special_actor_interacted,
        public_payload: %{
          player_id: actor.id,
          special_actor_id: special_actor.id,
          option_id: option.id,
          option_label: option.label,
          actions_remaining: next_actor.actions_remaining,
          actor_active: next_special_actor.active,
          actor_from_location_id: special_actor.location_id,
          actor_location_id: next_special_actor.location_id,
          revealed_case_card_codes: case_card_codes(next_state, newly_public_ids),
          revealed_suspect_ids: newly_revealed_suspect_ids
        },
        private_payloads: %{
          actor.user_id => %{
            type: "special_actor_result",
            special_actor_id: special_actor.id,
            option_id: option.id,
            scratch: next_actor.scratch,
            case_cards:
              Enum.map(
                case_cards,
                &Map.take(&1, [:id, :code, :title, :type, :description])
              )
          }
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
    free_question? = actor.free_question_suspect_id == suspect_id

    with :ok <- validate_placed(actor),
         {:ok, suspect} <- fetch_suspect(state, suspect_id),
         :ok <- validate_suspect_location(actor, suspect),
         :ok <- validate_special_actor_block(state, actor, :interrogate),
         :ok <- validate_free_question_target(actor, suspect),
         :ok <- validate_interrogation_action(actor, free_question?),
         {:ok, topic} <- ResponseMatrix.topic(state.case_definition, topic_id),
         :ok <- validate_topic_knowledge(actor, topic),
         {:ok, options} <-
           ResponseMatrix.response_options(state.case_definition, suspect.id, topic.id),
         :ok <- validate_spend_leverage(spend_leverage),
         {:ok, next_actor} <- spend_detective_leverage(actor, suspect.id, spend_leverage) do
      next_actor = %{
        next_actor
        | actions_remaining:
            if(free_question?,
              do: next_actor.actions_remaining,
              else: next_actor.actions_remaining - 1
            ),
          free_question_suspect_id: nil
      }

      pending_action = %{
        "id" => command_id,
        "type" => "interrogation",
        "stage" => "block_decision",
        "detective_player_id" => actor.id,
        "detective_user_id" => actor.user_id,
        "suspect_id" => suspect.id,
        "topic_id" => topic.id,
        "topic_code" => topic.code,
        "free_question" => free_question?,
        "forced_truthful" => spend_leverage,
        "eligible_snitch_player_ids" => [],
        "snitch_decisions" => %{},
        "snitch_player_ids" => [],
        "blocked_snitch_player_ids" => [],
        "selected_response_id" => nil,
        "selected_response_text" => nil,
        "selected_response_type" => nil,
        "selected_response_case_card_ids" => []
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
        actions_remaining: next_actor.actions_remaining,
        free_question: free_question?
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

  defp execute(state, _actor, %Command{type: :allow_question}) do
    with :ok <- validate_pending_stage(state.pending_action, "block_decision") do
      {next_state, pending, waiting_phase} = open_snitch_window(state)

      next_state =
        next_state
        |> Map.put(:phase, waiting_phase)
        |> Map.put(:pending_action, pending)
        |> advance_version()
        |> append_history(%{
          type: "question_allowed",
          player_id: pending["detective_player_id"],
          suspect_id: pending["suspect_id"]
        })

      event = %Event{
        type: :question_allowed,
        public_payload: %{
          interrogation_id: pending["id"],
          detective_player_id: pending["detective_player_id"],
          snitch_window_open: waiting_phase == :waiting_for_snitches
        }
      }

      {:ok, next_state, [event]}
    end
  end

  defp execute(state, chisel, %Command{type: :block_question}) do
    pending = state.pending_action

    with :ok <- validate_pending_stage(pending, "block_decision"),
         detective <- Map.fetch!(state.players, pending["detective_player_id"]),
         {:ok, next_chisel, next_detective} <- spend_chisel_leverage(chisel, detective) do
      next_pending = Map.put(pending, "stage", "blocked_question")

      next_state =
        state
        |> put_player(next_chisel)
        |> put_player(next_detective)
        |> Map.put(:phase, :waiting_for_detective_decision)
        |> Map.put(:pending_action, next_pending)
        |> advance_version()
        |> append_history(%{
          type: "question_blocked",
          player_id: detective.id,
          suspect_id: pending["suspect_id"]
        })

      event = %Event{
        type: :question_blocked,
        public_payload: %{
          interrogation_id: pending["id"],
          detective_player_id: detective.id,
          suspect_id: pending["suspect_id"]
        }
      }

      {:ok, next_state, [event]}
    end
  end

  defp execute(state, actor, %Command{type: :accept_question_block}) do
    pending = state.pending_action

    with :ok <- validate_pending_stage(pending, "blocked_question") do
      next_state =
        state
        |> Map.put(:phase, :detective_turn)
        |> Map.put(:pending_action, nil)
        |> advance_version()
        |> append_history(%{
          type: "question_abandoned",
          player_id: actor.id,
          suspect_id: pending["suspect_id"]
        })

      event = %Event{
        type: :question_abandoned,
        public_payload: %{
          interrogation_id: pending["id"],
          detective_player_id: actor.id,
          suspect_id: pending["suspect_id"]
        }
      }

      {:ok, next_state, [event]}
    end
  end

  defp execute(state, actor, %Command{type: :bribe_goon}) do
    pending = state.pending_action

    with :ok <- validate_pending_stage(pending, "blocked_question"),
         :ok <- validate_scratch(actor, 2) do
      next_actor = %{actor | scratch: actor.scratch - 2}
      state = put_player(state, next_actor)
      {next_state, next_pending, waiting_phase} = open_snitch_window(state)

      next_state =
        next_state
        |> Map.put(:phase, waiting_phase)
        |> Map.put(:pending_action, next_pending)
        |> advance_version()
        |> append_history(%{
          type: "goon_bribed",
          player_id: actor.id,
          suspect_id: pending["suspect_id"]
        })

      event = %Event{
        type: :goon_bribed,
        public_payload: %{
          interrogation_id: pending["id"],
          detective_player_id: actor.id,
          snitch_window_open: waiting_phase == :waiting_for_snitches
        },
        private_payloads: %{
          actor.user_id => %{type: "scratch_updated", scratch: next_actor.scratch, spent: 2}
        }
      }

      {:ok, next_state, [event]}
    end
  end

  defp execute(state, actor, %Command{type: type})
       when type in [:choose_snitch, :decline_snitch] do
    pending = state.pending_action
    choice = type == :choose_snitch
    decisions = Map.put(pending["snitch_decisions"] || %{}, actor.id, choice)
    eligible_ids = pending["eligible_snitch_player_ids"] || []
    remaining_ids = eligible_ids -- Map.keys(decisions)
    chosen_ids = snitch_player_ids(eligible_ids, decisions)

    {next_phase, next_stage} =
      cond do
        remaining_ids != [] -> {:waiting_for_snitches, "snitch_decisions"}
        chosen_ids == [] -> {:waiting_for_chisel, "response"}
        true -> {:waiting_for_chisel, "snitch_block"}
      end

    next_pending =
      pending
      |> Map.put("stage", next_stage)
      |> Map.put("snitch_decisions", decisions)

    next_state =
      state
      |> Map.put(:phase, next_phase)
      |> Map.put(:pending_action, next_pending)
      |> advance_version()
      |> append_history(%{
        type: "snitch_decision_recorded",
        player_id: actor.id,
        interrogation_id: pending["id"]
      })

    decision_event = %Event{
      type: :snitch_decision_recorded,
      public_payload: %{
        interrogation_id: pending["id"],
        decisions_recorded: map_size(decisions),
        decisions_required: length(eligible_ids),
        choices_revealed: remaining_ids == []
      },
      private_payloads: %{
        actor.user_id => %{type: "snitch_choice_recorded", snitch: choice}
      }
    }

    events =
      if remaining_ids == [] do
        close_event = %Event{
          type: :snitch_window_closed,
          public_payload: %{
            interrogation_id: pending["id"],
            snitch_request_count: length(chosen_ids)
          }
        }

        [decision_event, close_event]
      else
        [decision_event]
      end

    {:ok, next_state, events}
  end

  defp execute(state, chisel, %Command{type: :resolve_snitches, payload: payload}) do
    pending = state.pending_action
    blocked_ids = payload_value(payload, "blocked_player_ids")
    eligible_ids = pending["eligible_snitch_player_ids"] || []
    chosen_ids = snitch_player_ids(eligible_ids, pending["snitch_decisions"] || %{})

    with :ok <- validate_pending_stage(pending, "snitch_block"),
         :ok <- validate_blocked_snitch_ids(blocked_ids, chosen_ids),
         :ok <- validate_chisel_leverage_for(chisel, blocked_ids) do
      {next_state, next_chisel} = spend_snitch_block_leverage(state, chisel, blocked_ids)
      allowed_ids = chosen_ids -- blocked_ids

      next_pending =
        pending
        |> Map.put("stage", "response")
        |> Map.put("snitch_player_ids", allowed_ids)
        |> Map.put("blocked_snitch_player_ids", blocked_ids)

      next_state =
        next_state
        |> put_player(next_chisel)
        |> Map.put(:phase, :waiting_for_chisel)
        |> Map.put(:pending_action, next_pending)
        |> advance_version()
        |> append_history(%{
          type: "snitches_resolved",
          interrogation_id: pending["id"],
          allowed_count: length(allowed_ids),
          blocked_count: length(blocked_ids)
        })

      private_payloads =
        Map.new(chosen_ids, fn player_id ->
          detective = Map.fetch!(next_state.players, player_id)

          {detective.user_id,
           %{
             type: "snitch_resolved",
             blocked: player_id in blocked_ids,
             scratch_cost: if(player_id in blocked_ids, do: 0, else: 3)
           }}
        end)

      event = %Event{
        type: :snitches_resolved,
        public_payload: %{
          interrogation_id: pending["id"],
          requested_count: length(chosen_ids),
          blocked_count: length(blocked_ids),
          allowed_count: length(allowed_ids)
        },
        private_payloads: private_payloads
      }

      {:ok, next_state, [event]}
    end
  end

  defp execute(state, actor, %Command{type: :skip_free_question}) do
    with suspect_id when is_binary(suspect_id) <- actor.free_question_suspect_id do
      next_actor = %{actor | free_question_suspect_id: nil}

      next_state =
        state
        |> put_player(next_actor)
        |> advance_version()
        |> append_history(%{
          type: "free_question_declined",
          player_id: actor.id,
          suspect_id: suspect_id
        })

      event = %Event{
        type: :free_question_declined,
        public_payload: %{player_id: actor.id, suspect_id: suspect_id}
      }

      {:ok, next_state, [event]}
    else
      _none -> {:error, :free_question_not_available}
    end
  end

  defp execute(state, _actor, %Command{type: :select_response, payload: payload}) do
    pending = state.pending_action
    response_id = payload_value(payload, "response_id")

    with :ok <- validate_pending_interrogation(pending),
         :ok <- validate_pending_stage(pending, "response"),
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
        | "stage" => "response_decision",
          "selected_response_id" => option.id,
          "selected_response_text" => option.text,
          "selected_response_type" => option.type,
          "selected_response_case_card_ids" => option.case_card_ids
      }

      detective = Map.fetch!(state.players, pending["detective_player_id"])

      {state, response_case_cards, newly_public_card_ids} =
        grant_response_case_cards(state, detective.id, option.case_card_ids)

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
          topic_code: pending["topic_code"],
          revealed_case_card_codes: case_card_codes(state, newly_public_card_ids)
        },
        private_payloads: %{
          detective.user_id => %{
            type: "suspect_response",
            interrogation_id: pending["id"],
            response_text: option.text,
            case_cards: response_case_cards
          }
        }
      }

      {:ok, next_state, [event]}
    end
  end

  defp execute(state, actor, %Command{type: :accept_response}) do
    pending = state.pending_action
    response_text = pending["selected_response_text"]

    {state, snitch_private_payloads, newly_public_card_ids} =
      deliver_snitch_results(
        state,
        pending,
        response_text,
        "snitched",
        pending["selected_response_case_card_ids"] || []
      )

    next_actor =
      state.players
      |> Map.fetch!(actor.id)
      |> append_statement(pending, response_text, "accepted")

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
        topic_code: pending["topic_code"],
        snitch_count: length(pending["snitch_player_ids"] || []),
        revealed_case_card_codes: case_card_codes(state, newly_public_card_ids)
      },
      private_payloads: snitch_private_payloads
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

      state =
        state
        |> put_player(next_actor)
        |> put_player(next_chisel)

      {state, challenge_case_cards, challenge_public_card_ids} =
        if succeeded do
          grant_response_case_cards(state, actor.id, most_useful.case_card_ids)
        else
          {state, [], []}
        end

      {state, snitch_private_payloads, snitch_public_card_ids} =
        deliver_snitch_results(
          state,
          pending,
          most_useful.text,
          if(succeeded, do: "snitch_challenge_succeeded", else: "snitch_challenge_failed"),
          most_useful.case_card_ids
        )

      next_actor = Map.fetch!(state.players, actor.id)
      next_chisel = Map.fetch!(state.players, state.chisel_player_id)

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
          succeeded: succeeded,
          snitch_count: length(pending["snitch_player_ids"] || []),
          revealed_case_card_codes:
            case_card_codes(
              state,
              Enum.uniq(challenge_public_card_ids ++ snitch_public_card_ids)
            )
        },
        private_payloads:
          Map.put(snitch_private_payloads, actor.user_id, %{
            type: "challenge_resolved",
            interrogation_id: pending["id"],
            succeeded: succeeded,
            final_response_text: most_useful.text,
            case_cards: challenge_case_cards,
            leverage_supply: next_actor.leverage_supply,
            suspect_leverage: Map.get(next_actor.leverage_on_suspects, pending["suspect_id"], 0)
          })
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

  defp execute(
         %State{paused_from_phase: restored_phase} = state,
         actor,
         %Command{type: :resume_game}
       ) do
    next_state =
      %{
        state
        | status: :active,
          phase: restored_phase,
          paused_from_phase: nil,
          pause_reason: nil,
          paused_player_ids: []
      }
      |> advance_version()

    event = %Event{
      type: :game_resumed,
      public_payload: %{
        chisel_player_id: actor.id,
        restored_phase: Atom.to_string(restored_phase)
      }
    }

    {:ok, next_state, [event]}
  end

  defp execute(state, _actor, %Command{type: :concede_game}) do
    {finished, finished_event} = finish_game(state, "detective", nil, "chisel_forfeit")

    next_state =
      %{
        finished
        | paused_from_phase: nil,
          pause_reason: nil,
          paused_player_ids: []
      }
      |> advance_version()
      |> append_history(%{type: "game_finished", winner_player_id: nil})

    {:ok, next_state, [finished_event]}
  end

  defp execute(state, actor, %Command{type: :accuse, payload: payload}) do
    with :ok <- validate_accusation_start(state, actor),
         {:ok, guess} <- AccusationSheet.build_guess(state.case_definition, payload),
         :ok <- validate_accusation_discovery(state, actor, guess),
         {:ok, correct_count} <- AccusationSheet.correct_count(state.case_definition, guess) do
      next_actor = %{
        actor
        | solve_token_available: false,
          solve_attempt: Map.put(guess, "correct_count", correct_count)
      }

      state = put_player(state, next_actor)

      submitted = %Event{
        type: :accusation_submitted,
        public_payload: %{player_id: actor.id},
        private_payloads: %{
          actor.user_id => %{
            type: "accusation_result",
            correct_count: correct_count,
            solved: correct_count == 3
          }
        }
      }

      if correct_count == 3 do
        {finished, finished_event} = finish_game(state, "detective", actor.id, "case_solved")

        next_state =
          finished
          |> advance_version()
          |> append_history(%{type: "game_finished", winner_player_id: actor.id})

        {:ok, next_state, [submitted, finished_event]}
      else
        next_state =
          state
          |> advance_version()
          |> append_history(%{type: "accusation_rejected", player_id: actor.id})

        rejected = %Event{
          type: :accusation_rejected,
          public_payload: %{player_id: actor.id},
          private_payloads: submitted.private_payloads
        }

        {:ok, next_state, [rejected]}
      end
    end
  end

  defp execute(state, actor, %Command{type: :submit_final_guess, payload: payload}) do
    with {:ok, guess} <- AccusationSheet.build_guess(state.case_definition, payload),
         :ok <- validate_accusation_discovery(state, actor, guess) do
      next_actor = %{actor | final_guess: guess}
      state = put_player(state, next_actor)
      submitted_count = Enum.count(detective_players(state), &is_map(&1.final_guess))
      required_count = length(state.detective_order)

      submitted = %Event{
        type: :final_guess_submitted,
        public_payload: %{
          player_id: actor.id,
          submitted_count: submitted_count,
          required_count: required_count
        },
        private_payloads: %{
          actor.user_id => %{type: "final_guess_recorded", guess: guess}
        }
      }

      if submitted_count == required_count do
        {finished, finished_event} = resolve_final_guesses(state)

        next_state =
          finished
          |> advance_version()
          |> append_history(%{
            type: "game_finished",
            winner_player_id: finished.winner["player_id"]
          })

        {:ok, next_state, [submitted, finished_event]}
      else
        next_state =
          state
          |> advance_version()
          |> append_history(%{type: "final_guess_submitted", player_id: actor.id})

        {:ok, next_state, [submitted]}
      end
    end
  end

  defp execute(_state, _actor, %Command{}), do: {:error, :command_not_allowed}

  defp resolve_search(state, actor, result, event_type) do
    {:ok, revealed_cards} =
      SearchDeck.case_cards(state.case_definition, result.reveal_case_card_ids)

    newly_revealed_suspects =
      result.reveal_suspect_ids
      |> Enum.filter(fn suspect_id ->
        case Map.get(state.suspects, suspect_id) do
          %{revealed: false} -> true
          _other -> false
        end
      end)

    free_question_suspect_id = List.first(newly_revealed_suspects)

    next_actor = %{
      actor
      | actions_remaining: actor.actions_remaining - 1,
        knowledge: Enum.uniq(actor.knowledge ++ result.reveal_case_card_ids),
        evidence: Enum.uniq(actor.evidence ++ result.take_case_card_ids),
        free_question_suspect_id: free_question_suspect_id,
        search_notes:
          Enum.take(
            [
              %{
                "target_type" => result.target_type,
                "target_id" => result.target_id,
                "text" => result.text,
                "case_card_ids" => result.reveal_case_card_ids,
                "taken_case_card_ids" => result.take_case_card_ids,
                "day" => state.day
              }
              | actor.search_notes
            ],
            50
          )
    }

    archived_searches =
      if result.archive do
        Enum.uniq([SearchDeck.target_key(result) | state.archived_searches])
      else
        state.archived_searches
      end

    suspects =
      Enum.reduce(newly_revealed_suspects, state.suspects, fn suspect_id, suspects ->
        Map.update!(suspects, suspect_id, &%{&1 | revealed: true})
      end)

    taken_evidence =
      Enum.reduce(result.take_case_card_ids, state.taken_evidence, fn card_id, taken ->
        release_day = if state.days_remaining > 3, do: state.day + 3

        Map.put(taken, card_id, %{
          "player_id" => actor.id,
          "taken_day" => state.day,
          "release_day" => release_day
        })
      end)

    next_state = %{
      state
      | archived_searches: archived_searches,
        suspects: suspects,
        taken_evidence: taken_evidence
    }

    {next_state, newly_public_card_ids} =
      next_state
      |> put_player(next_actor)
      |> promote_shared_knowledge()

    next_actor = Map.fetch!(next_state.players, actor.id)

    next_state =
      next_state
      |> advance_version()
      |> append_history(%{
        type: Atom.to_string(event_type),
        player_id: actor.id,
        target_type: result.target_type,
        target_id: result.target_id
      })

    event = %Event{
      type: event_type,
      public_payload: %{
        player_id: actor.id,
        target_type: result.target_type,
        target_id: result.target_id,
        archived: result.archive,
        actions_remaining: next_actor.actions_remaining,
        revealed_case_card_codes: case_card_codes(state, newly_public_card_ids),
        evidence_taken_count: length(result.take_case_card_ids),
        revealed_suspect_ids: newly_revealed_suspects,
        free_question_available: is_binary(free_question_suspect_id)
      },
      private_payloads: %{
        actor.user_id => %{
          type: "search_result",
          target_type: result.target_type,
          target_id: result.target_id,
          text: result.text,
          case_cards: revealed_cards,
          taken_case_card_ids: result.take_case_card_ids,
          free_question_suspect_id: free_question_suspect_id
        }
      }
    }

    {:ok, next_state, [event]}
  end

  defp promote_shared_knowledge(state) do
    detectives =
      state.players
      |> Map.values()
      |> Enum.filter(&(&1.role == "detective"))

    shared_ids =
      state.case_definition
      |> ResponseMatrix.topics()
      |> Enum.map(& &1.id)
      |> Enum.filter(fn card_id ->
        Enum.all?(detectives, &(card_id in &1.knowledge))
      end)

    newly_public_ids = shared_ids -- state.public_case_card_ids
    public_ids = Enum.uniq(state.public_case_card_ids ++ shared_ids)

    players =
      Map.new(state.players, fn
        {player_id, %{role: "detective"} = player} ->
          evidence = player.evidence -- newly_public_ids

          {player_id,
           %{player | knowledge: Enum.uniq(player.knowledge ++ shared_ids), evidence: evidence}}

        entry ->
          entry
      end)

    taken_evidence = Map.drop(state.taken_evidence, newly_public_ids)

    {%{
       state
       | public_case_card_ids: public_ids,
         players: players,
         taken_evidence: taken_evidence
     }, newly_public_ids}
  end

  defp case_card_codes(state, card_ids) do
    topics = ResponseMatrix.topics(state.case_definition)

    card_ids
    |> Enum.map(fn card_id -> Enum.find(topics, &(&1.id == card_id)) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(& &1.code)
  end

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

    {next_state, evidence_events} = release_due_evidence(next_state)
    {next_state, special_rule_events} = apply_day_special_rules(next_state)

    events = [
      %Event{
        type: :day_advanced,
        public_payload: %{day: next_state.day, days_remaining: next_state.days_remaining}
      }
      | evidence_events ++ special_rule_events
    ]

    events =
      events ++
        [%Event{type: :turn_started, public_payload: %{player_id: next_id, day: next_state.day}}]

    {next_state, events}
  end

  defp apply_day_special_rules(state) do
    state.case_definition
    |> SpecialRules.day_rules(state.day)
    |> Enum.reject(&(&1["id"] in state.triggered_special_rule_ids))
    |> Enum.reduce({state, []}, fn rule, {next_state, events} ->
      effect = rule["effect"]
      case_card_ids = effect["reveal_case_card_ids"] || []
      suspect_ids = effect["reveal_suspect_ids"] || []
      actor_updates = effect["special_actor_updates"] || []

      {special_actors, public_actor_updates} =
        SpecialActors.apply_lifecycle_updates(next_state.special_actors, actor_updates)

      next_state = %{next_state | special_actors: special_actors}

      {next_state, revealed_case_card_ids} = reveal_public_case_cards(next_state, case_card_ids)
      {next_state, revealed_suspect_ids} = reveal_public_suspects(next_state, suspect_ids)

      next_state = %{
        next_state
        | triggered_special_rule_ids:
            Enum.uniq([rule["id"] | next_state.triggered_special_rule_ids])
      }

      next_state =
        append_history(next_state, %{
          type: "special_rule_triggered",
          special_rule_id: rule["id"],
          title: rule["title"],
          day: next_state.day
        })

      event = %Event{
        type: :special_rule_triggered,
        public_payload: %{
          special_rule_id: rule["id"],
          title: rule["title"],
          text: rule["text"],
          day: next_state.day,
          revealed_case_card_codes: case_card_codes(next_state, revealed_case_card_ids),
          revealed_suspect_ids: revealed_suspect_ids,
          special_actor_updates: public_actor_updates
        }
      }

      {next_state, events ++ [event]}
    end)
  end

  defp reveal_public_case_cards(state, case_card_ids) do
    newly_revealed_ids = case_card_ids -- state.public_case_card_ids

    players =
      Map.new(state.players, fn
        {player_id, %{role: "detective"} = player} ->
          {player_id,
           %{
             player
             | knowledge: Enum.uniq(player.knowledge ++ case_card_ids),
               evidence: player.evidence -- case_card_ids
           }}

        entry ->
          entry
      end)

    next_state = %{
      state
      | players: players,
        public_case_card_ids: Enum.uniq(state.public_case_card_ids ++ case_card_ids),
        taken_evidence: Map.drop(state.taken_evidence, case_card_ids)
    }

    {next_state, newly_revealed_ids}
  end

  defp reveal_public_suspects(state, suspect_ids) do
    newly_revealed_ids =
      Enum.filter(suspect_ids, fn suspect_id ->
        match?(%{revealed: false}, Map.get(state.suspects, suspect_id))
      end)

    suspects =
      Enum.reduce(suspect_ids, state.suspects, fn suspect_id, suspects ->
        Map.update!(suspects, suspect_id, &%{&1 | revealed: true})
      end)

    {%{state | suspects: suspects}, newly_revealed_ids}
  end

  defp release_due_evidence(state) do
    due_evidence =
      Enum.filter(state.taken_evidence, fn {_card_id, evidence} ->
        evidence["release_day"] == state.day
      end)

    Enum.reduce(due_evidence, {state, []}, fn {card_id, evidence}, {next_state, events} ->
      players =
        Map.new(next_state.players, fn
          {player_id, %{role: "detective"} = player} ->
            {player_id,
             %{
               player
               | knowledge: Enum.uniq([card_id | player.knowledge]),
                 evidence: List.delete(player.evidence, card_id)
             }}

          entry ->
            entry
        end)

      updated_state = %{
        next_state
        | players: players,
          public_case_card_ids: Enum.uniq([card_id | next_state.public_case_card_ids]),
          taken_evidence: Map.delete(next_state.taken_evidence, card_id)
      }

      event = %Event{
        type: :evidence_submitted,
        public_payload: %{
          case_card_code: List.first(case_card_codes(next_state, [card_id])),
          former_holder_player_id: evidence["player_id"]
        }
      }

      {updated_state, events ++ [event]}
    end)
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

  defp fetch_detective(state, player_id) when is_binary(player_id) do
    case Map.get(state.players, player_id) do
      %{role: "detective"} = detective -> {:ok, detective}
      _player -> {:error, :invalid_bribe_target}
    end
  end

  defp fetch_detective(_state, _player_id), do: {:error, :invalid_bribe_target}

  defp fetch_private_case_card(state, case_card_id) when is_binary(case_card_id) do
    case SearchDeck.case_cards(state.case_definition, [case_card_id]) do
      {:ok, [case_card]} ->
        {:ok, Map.take(case_card, [:id, :code, :title, :type, :description])}

      _error ->
        {:error, :invalid_case_card}
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
         location_id: suspect["location_id"],
         revealed: suspect["initially_known"] != false
       }}
    end)
  end

  defp normalize_suspects(_suspects), do: %{}

  defp validate_version(%State{version: version}, version), do: :ok
  defp validate_version(%State{}, _expected_version), do: {:error, :stale_version}

  defp validate_resume_actor(%{role: "chisel"}), do: :ok
  defp validate_resume_actor(_actor), do: {:error, :wrong_role}

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

  defp validate_final_guess_turn(
         %State{phase: :accusation} = state,
         %{
           role: "detective"
         } = actor
       ) do
    cond do
      not AccusationSheet.configured?(state.case_definition) ->
        {:error, :accusation_not_available}

      is_map(actor.final_guess) ->
        {:error, :final_guess_already_submitted}

      true ->
        :ok
    end
  end

  defp validate_final_guess_turn(_state, %{role: role}) when role != "detective",
    do: {:error, :wrong_role}

  defp validate_final_guess_turn(_state, _actor), do: {:error, :wrong_phase}

  defp validate_free_question_command(%{free_question_suspect_id: nil}, _command), do: :ok

  defp validate_free_question_command(_actor, %Command{type: type})
       when type in [:interrogate, :skip_free_question],
       do: :ok

  defp validate_free_question_command(_actor, _command), do: {:error, :free_question_pending}

  defp validate_chisel_interrogation_turn(%State{phase: :waiting_for_chisel}, %{
         role: "chisel"
       }),
       do: :ok

  defp validate_chisel_interrogation_turn(_state, %{role: role}) when role != "chisel",
    do: {:error, :wrong_role}

  defp validate_chisel_interrogation_turn(%State{phase: phase}, _actor)
       when phase != :waiting_for_chisel,
       do: {:error, :wrong_phase}

  defp validate_chisel_interrogation_turn(_state, _actor), do: {:error, :wrong_role}

  defp validate_blocked_question_decision(
         %State{phase: :waiting_for_detective_decision, pending_action: pending},
         %{id: player_id, role: "detective"}
       ) do
    cond do
      not is_map(pending) -> {:error, :invalid_pending_action}
      pending_stage(pending) != "blocked_question" -> {:error, :question_not_blocked}
      pending["detective_player_id"] != player_id -> {:error, :not_interrogating_detective}
      true -> :ok
    end
  end

  defp validate_blocked_question_decision(_state, %{role: role}) when role != "detective",
    do: {:error, :wrong_role}

  defp validate_blocked_question_decision(_state, _actor), do: {:error, :wrong_phase}

  defp validate_snitch_turn(
         %State{phase: :waiting_for_snitches, pending_action: pending},
         %{id: player_id, role: "detective"}
       ) do
    eligible_ids = pending["eligible_snitch_player_ids"] || []
    decisions = pending["snitch_decisions"] || %{}

    cond do
      pending_stage(pending) != "snitch_decisions" -> {:error, :wrong_phase}
      player_id not in eligible_ids -> {:error, :not_snitch_eligible}
      Map.has_key?(decisions, player_id) -> {:error, :snitch_choice_recorded}
      true -> :ok
    end
  end

  defp validate_snitch_turn(_state, %{role: role}) when role != "detective",
    do: {:error, :wrong_role}

  defp validate_snitch_turn(_state, _actor), do: {:error, :wrong_phase}

  defp validate_detective_decision(
         %State{phase: :waiting_for_detective_decision, pending_action: pending},
         %{id: player_id, role: "detective"}
       ) do
    cond do
      not is_map(pending) -> {:error, :invalid_pending_action}
      pending["detective_player_id"] != player_id -> {:error, :not_interrogating_detective}
      pending_stage(pending) != "response_decision" -> {:error, :response_not_selected}
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

  defp validate_special_actor_location(actor, special_actor) do
    if actor.location_id == special_actor.location_id,
      do: :ok,
      else: {:error, :special_actor_not_at_location}
  end

  defp validate_special_actor_option(actor, special_actor, option) do
    if SpecialActors.option_available?(option, special_actor, actor) do
      :ok
    else
      cond do
        option.once and option.id in special_actor.used_option_ids ->
          {:error, :special_interaction_used}

        Map.get(option, :choice_group) &&
            Map.get(option, :choice_group) in Map.get(special_actor, :resolved_choice_groups, []) ->
          {:error, :special_choice_resolved}

        actor.actions_remaining < option.action_cost ->
          {:error, :no_actions_remaining}

        actor.scratch < option.scratch_cost ->
          {:error, :insufficient_scratch}

        true ->
          {:error, :invalid_special_interaction}
      end
    end
  end

  defp validate_special_actor_block(state, actor, action) do
    if SpecialActors.blocks_action?(
         state.special_actors,
         actor.location_id,
         Atom.to_string(action)
       ) do
      {:error, :special_actor_blocks_action}
    else
      :ok
    end
  end

  defp validate_accusation_start(state, actor) do
    cond do
      not AccusationSheet.configured?(state.case_definition) ->
        {:error, :accusation_not_available}

      not Map.get(actor, :solve_token_available, true) ->
        {:error, :solve_token_spent}

      actor.actions_remaining != @actions_per_turn ->
        {:error, :accusation_must_start_turn}

      true ->
        :ok
    end
  end

  defp validate_accusation_discovery(state, actor, guess) do
    suspect = Map.get(state.suspects, guess["suspect_id"])

    cond do
      not is_map(suspect) or not Map.get(suspect, :revealed, true) ->
        {:error, :accusation_suspect_unknown}

      true ->
        with {:ok, weapon} <-
               AccusationSheet.weapon(state.case_definition, guess["weapon_id"]),
             true <- weapon["case_card_id"] in actor.knowledge do
          :ok
        else
          false -> {:error, :accusation_weapon_unknown}
          {:error, reason} -> {:error, reason}
        end
    end
  end

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

  defp validate_suspect_location(_actor, %{revealed: false}), do: {:error, :invalid_suspect}

  defp validate_suspect_location(actor, suspect) do
    if actor.location_id == suspect.location_id,
      do: :ok,
      else: {:error, :suspect_not_at_location}
  end

  defp validate_free_question_target(%{free_question_suspect_id: nil}, _suspect), do: :ok

  defp validate_free_question_target(%{free_question_suspect_id: suspect_id}, %{id: suspect_id}),
    do: :ok

  defp validate_free_question_target(_actor, _suspect), do: {:error, :free_question_pending}

  defp validate_interrogation_action(_actor, true), do: :ok
  defp validate_interrogation_action(actor, false), do: validate_action_point(actor)

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

  defp validate_pending_stage(pending, expected_stage) do
    if pending_stage(pending) == expected_stage,
      do: :ok,
      else: {:error, :command_not_allowed}
  end

  defp pending_stage(%{"stage" => stage}) when is_binary(stage), do: stage

  defp pending_stage(%{"selected_response_id" => response_id}) when is_binary(response_id),
    do: "response_decision"

  defp pending_stage(%{"type" => "interrogation"}), do: "response"
  defp pending_stage(_pending), do: nil

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

  defp open_snitch_window(state) do
    pending = state.pending_action

    eligible_ids =
      state.players
      |> Map.values()
      |> Enum.filter(fn player ->
        player.role == "detective" and player.id != pending["detective_player_id"] and
          player.scratch >= 3
      end)
      |> Enum.sort_by(& &1.seat)
      |> Enum.map(& &1.id)

    if pending["forced_truthful"] or eligible_ids == [] do
      pending =
        pending
        |> Map.put("stage", "response")
        |> Map.put("eligible_snitch_player_ids", [])

      {state, pending, :waiting_for_chisel}
    else
      pending =
        pending
        |> Map.put("stage", "snitch_decisions")
        |> Map.put("eligible_snitch_player_ids", eligible_ids)
        |> Map.put("snitch_decisions", %{})

      {state, pending, :waiting_for_snitches}
    end
  end

  defp snitch_player_ids(eligible_ids, decisions) do
    Enum.filter(eligible_ids, &(Map.get(decisions, &1) == true))
  end

  defp spend_chisel_leverage(chisel, detective) do
    leverage = Map.get(chisel.leverage_by_detective, detective.id, 0)

    if leverage > 0 do
      next_chisel = %{
        chisel
        | leverage_by_detective: Map.put(chisel.leverage_by_detective, detective.id, leverage - 1)
      }

      next_detective = %{detective | leverage_supply: detective.leverage_supply + 1}
      {:ok, next_chisel, next_detective}
    else
      {:error, :question_block_unavailable}
    end
  end

  defp validate_scratch(%{scratch: scratch}, cost) when scratch >= cost, do: :ok
  defp validate_scratch(_actor, _cost), do: {:error, :insufficient_scratch}

  defp validate_other_detective(%{id: player_id}, %{id: player_id}),
    do: {:error, :invalid_bribe_target}

  defp validate_other_detective(_actor, _target), do: :ok

  defp validate_bribe_target_location(%{location_id: location_id}, %{location_id: location_id})
       when not is_nil(location_id),
       do: :ok

  defp validate_bribe_target_location(_actor, _target),
    do: {:error, :bribe_target_not_at_location}

  defp validate_target_case_card(target, case_card_id) when is_binary(case_card_id) do
    if case_card_id in target.knowledge,
      do: :ok,
      else: {:error, :case_card_not_known_by_target}
  end

  defp validate_target_case_card(_target, _case_card_id),
    do: {:error, :case_card_not_known_by_target}

  defp validate_case_card_unknown(actor, case_card_id) when is_binary(case_card_id) do
    if case_card_id in actor.knowledge,
      do: {:error, :case_card_already_known},
      else: :ok
  end

  defp validate_case_card_unknown(_actor, _case_card_id), do: {:error, :invalid_case_card}

  defp validate_case_card_known_by_other_detective(state, actor, case_card_id)
       when is_binary(case_card_id) do
    known? =
      state.players
      |> Map.values()
      |> Enum.any?(fn player ->
        player.role == "detective" and player.id != actor.id and case_card_id in player.knowledge
      end)

    if known?, do: :ok, else: {:error, :case_card_not_known_by_detective}
  end

  defp validate_blocked_snitch_ids(blocked_ids, chosen_ids)
       when is_list(blocked_ids) do
    valid_ids? =
      Enum.all?(blocked_ids, &(is_binary(&1) and &1 in chosen_ids)) and
        Enum.uniq(blocked_ids) == blocked_ids

    if valid_ids?, do: :ok, else: {:error, :invalid_snitch_resolution}
  end

  defp validate_blocked_snitch_ids(_blocked_ids, _chosen_ids),
    do: {:error, :invalid_snitch_resolution}

  defp validate_chisel_leverage_for(chisel, player_ids) do
    if Enum.all?(player_ids, &(Map.get(chisel.leverage_by_detective, &1, 0) > 0)),
      do: :ok,
      else: {:error, :insufficient_chisel_leverage}
  end

  defp spend_snitch_block_leverage(state, chisel, blocked_ids) do
    Enum.reduce(blocked_ids, {state, chisel}, fn player_id, {next_state, next_chisel} ->
      detective = Map.fetch!(next_state.players, player_id)
      leverage = Map.fetch!(next_chisel.leverage_by_detective, player_id)

      next_detective = %{detective | leverage_supply: detective.leverage_supply + 1}

      next_chisel = %{
        next_chisel
        | leverage_by_detective:
            Map.put(next_chisel.leverage_by_detective, player_id, leverage - 1)
      }

      {put_player(next_state, next_detective), next_chisel}
    end)
  end

  defp deliver_snitch_results(state, pending, response_text, resolution, case_card_ids) do
    case_cards = private_response_case_cards(state, case_card_ids)

    {state, private_payloads} =
      pending
      |> Map.get("snitch_player_ids", [])
      |> Enum.reduce({state, %{}}, fn player_id, {next_state, private_payloads} ->
        detective = Map.fetch!(next_state.players, player_id)

        next_detective =
          detective
          |> Map.put(:scratch, detective.scratch - 3)
          |> Map.update!(:knowledge, &Enum.uniq(&1 ++ case_card_ids))
          |> append_statement(pending, response_text, resolution)

        private_payload = %{
          type: "snitch_result",
          interrogation_id: pending["id"],
          response_text: response_text,
          case_cards: case_cards,
          scratch: next_detective.scratch,
          scratch_spent: 3
        }

        {put_player(next_state, next_detective),
         Map.put(private_payloads, detective.user_id, private_payload)}
      end)

    {state, newly_public_card_ids} = promote_shared_knowledge(state)
    {state, private_payloads, newly_public_card_ids}
  end

  defp grant_response_case_cards(state, player_id, case_card_ids) do
    player = Map.fetch!(state.players, player_id)
    next_player = %{player | knowledge: Enum.uniq(player.knowledge ++ case_card_ids)}

    {next_state, newly_public_card_ids} =
      state
      |> put_player(next_player)
      |> promote_shared_knowledge()

    {next_state, private_response_case_cards(state, case_card_ids), newly_public_card_ids}
  end

  defp private_response_case_cards(state, case_card_ids) do
    {:ok, case_cards} = SearchDeck.case_cards(state.case_definition, case_card_ids)

    Enum.map(case_cards, &Map.take(&1, [:id, :code, :title, :type, :description]))
  end

  defp detective_players(state) do
    state.detective_order
    |> Enum.map(&Map.fetch!(state.players, &1))
  end

  defp resolve_final_guesses(state) do
    results =
      Map.new(state.detective_order, fn player_id ->
        detective = Map.fetch!(state.players, player_id)

        {:ok, correct_count} =
          AccusationSheet.correct_count(state.case_definition, detective.final_guess)

        {player_id, correct_count}
      end)

    players =
      Map.new(state.players, fn
        {player_id, %{role: "detective"} = detective} ->
          final_guess =
            Map.put(detective.final_guess, "correct_count", Map.fetch!(results, player_id))

          {player_id, %{detective | final_guess: final_guess}}

        entry ->
          entry
      end)

    state = %{state | players: players}

    winning_detective_id =
      state.detective_order
      |> Enum.reverse()
      |> Enum.find(&(Map.fetch!(results, &1) == 3))

    if winning_detective_id do
      finish_game(state, "detective", winning_detective_id, "final_guess")
    else
      finish_game(state, "chisel", state.chisel_player_id, "time_expired")
    end
  end

  defp finish_game(state, role, player_id, reason) do
    winner = %{
      "role" => role,
      "player_id" => player_id,
      "reason" => reason
    }

    next_state = %{
      state
      | status: :finished,
        phase: :finished,
        current_detective_id: nil,
        pending_action: nil,
        winner: winner
    }

    private_payloads =
      state
      |> detective_players()
      |> Map.new(fn detective ->
        {detective.user_id,
         %{
           type: "game_result",
           winner: winner,
           correct_count: private_correct_count(detective)
         }}
      end)

    event = %Event{
      type: :game_finished,
      public_payload: game_result_payload(state.case_definition, winner),
      private_payloads: private_payloads
    }

    {next_state, event}
  end

  defp private_correct_count(%{final_guess: final_guess}) when is_map(final_guess),
    do: final_guess["correct_count"]

  defp private_correct_count(%{solve_attempt: solve_attempt}) when is_map(solve_attempt),
    do: solve_attempt["correct_count"]

  defp private_correct_count(_detective), do: nil

  defp game_result_payload(case_definition, winner) do
    {:ok, solution} = AccusationSheet.revealed_solution(case_definition)

    %{
      winner: winner,
      solution: solution,
      epilogue: case_definition["epilogue"]
    }
  end

  defp validate_search_target_available(state, result) do
    if SearchDeck.target_key(result) in state.archived_searches,
      do: {:error, :search_archived},
      else: :ok
  end

  defp validate_evidence_available(state, result) do
    with {:ok, cards} <- SearchDeck.case_cards(state.case_definition, result.take_case_card_ids) do
      cond do
        not Enum.all?(cards, & &1.takeable) ->
          {:error, :evidence_not_takeable}

        Enum.any?(result.take_case_card_ids, &Map.has_key?(state.taken_evidence, &1)) ->
          {:error, :evidence_unavailable}

        Enum.any?(result.take_case_card_ids, &(&1 in state.public_case_card_ids)) ->
          {:error, :evidence_unavailable}

        true ->
          :ok
      end
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
    %{
      state
      | investigation_stats: InvestigationStats.record(state.investigation_stats, history_entry),
        public_history: Enum.take([history_entry | state.public_history], 100)
    }
  end

  defp payload_value(payload, key), do: Map.get(payload, key)

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default
end
