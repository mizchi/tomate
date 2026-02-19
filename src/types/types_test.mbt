///|
test "Status equality" {
  assert_eq(Status::Complete, Status::Complete)
  assert_true(Status::Pending != Status::Complete)
}

///|
test "EngineCallbacks::noop creates valid callbacks" {
  let cb = EngineCallbacks::noop()
  (cb.on_movement_start)("test", 0, "instr")
  (cb.on_piece_complete)({
    piece_name: "test",
    current_movement: "m1",
    iteration: 0,
    movement_outputs: Map::new(),
    last_output: None,
    user_inputs: [],
    persona_sessions: Map::new(),
    movement_iterations: Map::new(),
    status: PieceStatus::Running,
  })
}

///|
test "PieceRule defaults" {
  let rule : PieceRule = {
    condition: "status is done",
    next: Some("next_step"),
    is_ai_condition: false,
    ai_condition_text: None,
    is_aggregate_condition: false,
    aggregate_type: None,
    aggregate_condition_text: None,
  }
  assert_eq(rule.condition, "status is done")
  assert_eq(rule.next, Some("next_step"))
  assert_false(rule.is_ai_condition)
}

///|
test "AgentResponse creation" {
  let resp : AgentResponse = {
    persona: "coder",
    status: Status::Complete,
    content: "done",
    error: None,
    matched_rule_index: Some(0),
    matched_rule_method: Some(RuleMatchMethod::TagDetect),
  }
  assert_eq(resp.status, Status::Complete)
  assert_eq(resp.matched_rule_index, Some(0))
}

// State method tests (migrated from state package)

///|
fn make_test_config() -> PieceConfig {
  {
    name: "test-piece",
    description: None,
    movements: [
      {
        name: "plan",
        description: None,
        persona: None,
        persona_display_name: "Planner",
        allowed_tools: None,
        provider: None,
        model: None,
        required_permission_mode: None,
        edit: false,
        instruction_template: "Plan the task",
        rules: [],
        output_contracts: [],
        pass_previous_response: false,
        parallel: None,
        arpeggio: None,
        team_leader: None,
        policy_contents: None,
        knowledge_contents: None,
      },
      {
        name: "implement",
        description: None,
        persona: None,
        persona_display_name: "Coder",
        allowed_tools: None,
        provider: None,
        model: None,
        required_permission_mode: None,
        edit: true,
        instruction_template: "Implement the plan",
        rules: [],
        output_contracts: [],
        pass_previous_response: true,
        parallel: None,
        arpeggio: None,
        team_leader: None,
        policy_contents: None,
        knowledge_contents: None,
      },
    ],
    initial_movement: "plan",
    max_movements: 10,
    loop_detection: None,
    loop_monitors: None,
  }
}

///|
test "create_initial_state" {
  let config = make_test_config()
  let state = config.create_initial_state()
  assert_eq(state.piece_name, "test-piece")
  assert_eq(state.current_movement, "plan")
  assert_eq(state.iteration, 0)
  assert_eq(state.status, PieceStatus::Running)
  assert_true(state.last_output is None)
}

///|
test "increment_iteration" {
  let state = make_test_config().create_initial_state()
  state.increment_iteration()
  assert_eq(state.iteration, 1)
  state.increment_iteration()
  assert_eq(state.iteration, 2)
}

///|
test "increment_movement_iteration" {
  let state = make_test_config().create_initial_state()
  let count = state.increment_movement_iteration("plan")
  assert_eq(count, 1)
  let count2 = state.increment_movement_iteration("plan")
  assert_eq(count2, 2)
  let count3 = state.increment_movement_iteration("implement")
  assert_eq(count3, 1)
}

///|
test "record_output and get_last_output_content" {
  let state = make_test_config().create_initial_state()
  let resp : AgentResponse = {
    persona: "planner",
    status: Status::Complete,
    content: "Here is the plan",
    error: None,
    matched_rule_index: None,
    matched_rule_method: None,
  }
  state.record_output("plan", resp)
  assert_eq(state.get_last_output_content(), Some("Here is the plan"))
}

///|
test "transition_to" {
  let state = make_test_config().create_initial_state()
  state.transition_to("implement")
  assert_eq(state.current_movement, "implement")
}

///|
test "complete and abort" {
  let state = make_test_config().create_initial_state()
  assert_true(state.is_running())
  state.complete()
  assert_false(state.is_running())
  assert_eq(state.status, PieceStatus::Completed)

  let state2 = make_test_config().create_initial_state()
  state2.abort()
  assert_eq(state2.status, PieceStatus::PieceAborted)
}

///|
test "find_movement" {
  let config = make_test_config()
  let m = config.find_movement("plan")
  assert_true(m is Some(_))
  let missing = config.find_movement("nonexistent")
  assert_true(missing is None)
}
