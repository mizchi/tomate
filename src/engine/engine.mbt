// MovementExecutor: 3-phase model (Execute → Report → Judge)

///|
pub fn execute_movement(
  movement : @types.PieceMovement,
  task : String,
  provider : &@provider.Provider,
  state : @types.PieceState,
  callbacks : @types.EngineCallbacks,
) -> @types.AgentResponse {
  let variables : Map[String, String] = Map::new()
  // Add movement iteration to variables
  let move_iter = state.increment_movement_iteration(movement.name)
  variables["movement_iteration"] = move_iter.to_string()
  variables["iteration"] = state.iteration.to_string()
  // Phase 1: Execute - build instruction and call provider
  let prompt = @instruction.build_movement_instruction(
    movement, task, variables,
  )
  // Inject previous response if configured
  let user_msg = if movement.pass_previous_response {
    match state.get_last_output_content() {
      Some(prev) =>
        "<previous_response>\n" +
        prev +
        "\n</previous_response>\n\n" +
        prompt.user_message
      None => prompt.user_message
    }
  } else {
    prompt.user_message
  }
  (callbacks.on_phase_start)(movement.name, @types.PhaseName::Execute, user_msg)
  let response = provider.call(prompt.system_prompt, user_msg)
  (callbacks.on_phase_complete)(
    movement.name,
    @types.PhaseName::Execute,
    response.content,
    response.status.to_string(),
  )
  // Phase 2: Report - write output contracts
  (callbacks.on_phase_start)(
    movement.name,
    @types.PhaseName::Report,
    response.content,
  )
  for contract in movement.output_contracts {
    (callbacks.on_movement_report)(
      movement.name,
      contract.name,
      contract.format,
    )
  }
  (callbacks.on_phase_complete)(
    movement.name,
    @types.PhaseName::Report,
    response.content,
    "done",
  )
  // Phase 3: Judge - evaluate rules
  (callbacks.on_phase_start)(
    movement.name,
    @types.PhaseName::Judge,
    response.content,
  )
  let rule_match = @eval.evaluate_rules(movement.rules, response.content)
  let final_response = match rule_match {
    Some(m) => {
      let resp : @types.AgentResponse = {
        ..response,
        matched_rule_index: Some(m.rule_index),
        matched_rule_method: Some(m.match_method),
      }
      resp
    }
    None =>
      // If no tag match and there are AI conditions, use AI judge fallback
      if has_ai_conditions(movement.rules) {
        let judge_instruction = @instruction.build_judge_instruction(
          movement.rules,
          response.content,
        )
        let judge_response = provider.call("", judge_instruction)
        let judge_match = @eval.evaluate_rules(
          movement.rules,
          judge_response.content,
        )
        match judge_match {
          Some(m) => {
            let resp : @types.AgentResponse = {
              ..response,
              matched_rule_index: Some(m.rule_index),
              matched_rule_method: Some(@types.RuleMatchMethod::AiJudgeFallback),
            }
            resp
          }
          None => response
        }
      } else {
        response
      }
  }
  (callbacks.on_phase_complete)(
    movement.name,
    @types.PhaseName::Judge,
    final_response.content,
    match final_response.matched_rule_index {
      Some(i) => "rule_\{i}"
      None => "no_match"
    },
  )
  final_response
}

///|
fn has_ai_conditions(rules : Array[@types.PieceRule]) -> Bool {
  for rule in rules {
    if rule.is_ai_condition {
      return true
    }
  }
  false
}

// PieceEngine: main state machine loop

///|
pub fn run_piece(
  config : @types.PieceConfig,
  task : String,
  provider : &@provider.Provider,
  callbacks : @types.EngineCallbacks,
) -> @types.PieceState {
  let state = config.create_initial_state()
  // Initialize loop detection
  let loop_detector = match config.loop_detection {
    Some(cfg) => Some(@loop.LoopDetector::new(cfg))
    None => None
  }
  // Initialize cycle detectors
  let cycle_detectors : Array[@loop.CycleDetector] = []
  match config.loop_monitors {
    Some(monitors) =>
      for m in monitors {
        cycle_detectors.push(@loop.CycleDetector::new(m.cycle, m.threshold))
      }
    None => ()
  }
  // Main loop
  while state.is_running() {
    // Check iteration limit
    if state.iteration >= config.max_movements {
      (callbacks.on_iteration_limit)(state.iteration, config.max_movements)
      state.abort()
      break
    }
    // Find current movement
    let movement = match config.find_movement(state.current_movement) {
      Some(m) => m
      None => {
        (callbacks.on_piece_abort)(
          state,
          "Movement not found: \{state.current_movement}",
        )
        state.abort()
        break
      }
    }
    // Check loop detection
    match loop_detector {
      Some(d) =>
        match d.record(movement.name) {
          @loop.LoopCheckResult::Detected(count) => {
            (callbacks.on_loop_detected)(movement.name, count)
            match d.action {
              @types.LoopAction::Abort => {
                (callbacks.on_piece_abort)(
                  state,
                  "Loop detected: \{movement.name} repeated \{count} times",
                )
                state.abort()
                break
              }
              _ => ()
            }
          }
          _ => ()
        }
      None => ()
    }
    // Check cycle detection
    for i, cd in cycle_detectors {
      match cd.record(movement.name) {
        @loop.CycleCheckResult::CycleDetected(count) => {
          let cycle = match config.loop_monitors {
            Some(monitors) =>
              if i < monitors.length() {
                monitors[i].cycle
              } else {
                []
              }
            None => []
          }
          (callbacks.on_cycle_detected)(cycle, count)
        }
        _ => ()
      }
    }
    state.increment_iteration()
    // Notify movement start
    (callbacks.on_movement_start)(
      movement.name,
      state.iteration,
      movement.instruction_template,
    )
    // Execute based on movement type
    let response = if movement.parallel is Some(_) {
      run_parallel(movement, task, provider, state, callbacks)
    } else if movement.arpeggio is Some(_) {
      run_arpeggio(movement, task, provider, state, callbacks)
    } else if movement.team_leader is Some(_) {
      run_team_leader(movement, task, provider, state, callbacks)
    } else {
      execute_movement(movement, task, provider, state, callbacks)
    }
    // Record output
    state.record_output(movement.name, response)
    (callbacks.on_movement_complete)(
      movement.name,
      response,
      movement.instruction_template,
    )
    // Determine next movement
    match response.matched_rule_index {
      Some(idx) =>
        if idx < movement.rules.length() {
          let rule = movement.rules[idx]
          match rule.next {
            Some("COMPLETE") => {
              (callbacks.on_piece_complete)(state)
              state.complete()
            }
            Some("ABORT") => {
              (callbacks.on_piece_abort)(state, "Aborted by rule")
              state.abort()
            }
            Some(next) => state.transition_to(next)
            None => {
              // No next specified, complete
              (callbacks.on_piece_complete)(state)
              state.complete()
            }
          }
        } else {
          // Rule index out of bounds, complete
          (callbacks.on_piece_complete)(state)
          state.complete()
        }
      None =>
        // No rule matched - if no rules defined, complete; otherwise continue
        if movement.rules.length() == 0 {
          (callbacks.on_piece_complete)(state)
          state.complete()
        }
      // else stay on same movement (will be caught by loop detection)
    }
  }
  state
}

// ParallelRunner: sequential execution of sub-movements (native constraint)

///|
fn run_parallel(
  movement : @types.PieceMovement,
  task : String,
  provider : &@provider.Provider,
  state : @types.PieceState,
  callbacks : @types.EngineCallbacks,
) -> @types.AgentResponse {
  let sub_movements = movement.parallel.unwrap_or([])
  let results : Array[@types.AgentResponse] = []
  let contents : Array[String] = []
  for sub in sub_movements {
    let resp = execute_movement(sub, task, provider, state, callbacks)
    results.push(resp)
    contents.push(resp.content)
  }
  // Evaluate aggregate rules
  let sub_results : Array[Array[Bool]] = []
  for _rule in movement.rules {
    let rule_results : Array[Bool] = []
    for resp in results {
      rule_results.push(resp.status == @types.Status::Complete)
    }
    sub_results.push(rule_results)
  }
  let rule_match = @eval.evaluate_rules_full(
    movement.rules,
    join_contents(contents),
    Some(sub_results),
  )
  let combined_content = join_contents(contents)
  {
    persona: movement.persona_display_name,
    status: @types.Status::Complete,
    content: combined_content,
    error: None,
    matched_rule_index: match rule_match {
      Some(m) => Some(m.rule_index)
      None => None
    },
    matched_rule_method: match rule_match {
      Some(m) => Some(m.match_method)
      None => None
    },
  }
}

// ArpeggioRunner: data-driven batch processing

///|
fn run_arpeggio(
  movement : @types.PieceMovement,
  task : String,
  provider : &@provider.Provider,
  state : @types.PieceState,
  callbacks : @types.EngineCallbacks,
) -> @types.AgentResponse {
  let _config = movement.arpeggio
  // For now, just execute the movement template once as a placeholder
  // Full arpeggio implementation would read CSV/JSON data source,
  // expand template per row, and merge results
  let resp = execute_movement(movement, task, provider, state, callbacks)
  resp
}

// TeamLeaderRunner: leader decomposes task, parts execute in parallel

///|
fn run_team_leader(
  movement : @types.PieceMovement,
  task : String,
  provider : &@provider.Provider,
  state : @types.PieceState,
  callbacks : @types.EngineCallbacks,
) -> @types.AgentResponse {
  let _config = movement.team_leader
  // For now, execute as single movement
  // Full implementation: leader agent decomposes → part agents execute → merge
  let resp = execute_movement(movement, task, provider, state, callbacks)
  resp
}

// Helper

///|
fn join_contents(contents : Array[String]) -> String {
  let buf = StringBuilder::new()
  for i, c in contents {
    if i > 0 {
      buf.write_string("\n\n---\n\n")
    }
    buf.write_string(c)
  }
  buf.to_string()
}
