///|
fn make_rule(condition : String, next : String?) -> @types.PieceRule {
  {
    condition,
    next,
    is_ai_condition: false,
    ai_condition_text: None,
    is_aggregate_condition: false,
    aggregate_type: None,
    aggregate_condition_text: None,
  }
}

///|
fn make_movement(
  name : String,
  instruction : String,
  rules? : Array[@types.PieceRule] = [],
  pass_previous? : Bool = false,
) -> @types.PieceMovement {
  {
    name,
    description: None,
    persona: None,
    persona_display_name: name,
    allowed_tools: None,
    provider: None,
    model: None,
    required_permission_mode: None,
    edit: false,
    instruction_template: instruction,
    rules,
    output_contracts: [],
    pass_previous_response: pass_previous,
    parallel: None,
    arpeggio: None,
    team_leader: None,
    policy_contents: None,
    knowledge_contents: None,
  }
}

///|
fn make_config(
  movements : Array[@types.PieceMovement],
  initial : String,
  max? : Int = 20,
) -> @types.PieceConfig {
  {
    name: "test-piece",
    description: None,
    movements,
    initial_movement: initial,
    max_movements: max,
    loop_detection: None,
    loop_monitors: None,
  }
}

///|
fn collect_events() -> (@types.EngineCallbacks, Array[String]) {
  let events : Array[String] = []
  let cb : @types.EngineCallbacks = {
    on_movement_start: fn(name, iter, _) {
      events.push("start:\{name}:\{iter}")
    },
    on_movement_complete: fn(name, _resp, _) { events.push("complete:\{name}") },
    on_movement_report: fn(name, _path, _fname) {
      events.push("report:\{name}")
    },
    on_phase_start: fn(name, phase, _) {
      events.push("phase_start:\{name}:\{phase}")
    },
    on_phase_complete: fn(name, phase, _, _) {
      events.push("phase_complete:\{name}:\{phase}")
    },
    on_piece_complete: fn(_) { events.push("piece_complete") },
    on_piece_abort: fn(_, reason) { events.push("piece_abort:\{reason}") },
    on_iteration_limit: fn(iter, max) {
      events.push("iteration_limit:\{iter}:\{max}")
    },
    on_loop_detected: fn(name, count) { events.push("loop:\{name}:\{count}") },
    on_cycle_detected: fn(_cycle, count) { events.push("cycle:\{count}") },
  }
  (cb, events)
}

// execute_movement tests

///|
test "execute_movement: basic execution" {
  let movement = make_movement("plan", "Plan the task: {task}")
  let state = make_config([movement], "plan").create_initial_state()
  let mock = @provider.MockProvider::new()
  mock.set_default("Here is the plan")
  let (cb, _events) = collect_events()
  let resp = @engine.execute_movement(movement, "build fib", mock, state, cb)
  assert_eq(resp.status, @types.Status::Complete)
  assert_eq(resp.content, "Here is the plan")
}

///|
test "execute_movement: tag detection in response" {
  let rules = [
    make_rule("approved", Some("deploy")),
    make_rule("rejected", Some("fix")),
  ]
  let movement = make_movement("review", "Review", rules~)
  let state = make_config([movement], "review").create_initial_state()
  let mock = @provider.MockProvider::new()
  mock.set_default("Code looks good <rule_0>")
  let (cb, _events) = collect_events()
  let resp = @engine.execute_movement(movement, "review code", mock, state, cb)
  assert_eq(resp.matched_rule_index, Some(0))
}

///|
test "execute_movement: no matching rule" {
  let rules = [make_rule("done", Some("COMPLETE"))]
  let movement = make_movement("step", "Do stuff", rules~)
  let state = make_config([movement], "step").create_initial_state()
  let mock = @provider.MockProvider::new()
  mock.set_default("Working on it...")
  let (cb, _events) = collect_events()
  let resp = @engine.execute_movement(movement, "do task", mock, state, cb)
  assert_true(resp.matched_rule_index is None)
}

// PieceEngine (run_piece) tests

///|
test "run_piece: single movement completes" {
  let movement = make_movement("plan", "Plan: {task}")
  let config = make_config([movement], "plan")
  let mock = @provider.MockProvider::new()
  let (cb, events) = collect_events()
  let state = @engine.run_piece(config, "hello", mock, cb)
  assert_eq(state.status, @types.PieceStatus::Completed)
  assert_eq(state.iteration, 1)
  assert_true(events.contains("piece_complete"))
}

///|
test "run_piece: A→B→COMPLETE transition" {
  let movements = [
    make_movement("plan", "Plan", rules=[make_rule("done", Some("implement"))]),
    make_movement("implement", "Implement", rules=[
      make_rule("done", Some("COMPLETE")),
    ]),
  ]
  let config = make_config(movements, "plan")
  let mock = @provider.MockProvider::new()
  mock.set_default("<rule_0> done")
  let (cb, events) = collect_events()
  let state = @engine.run_piece(config, "build fib", mock, cb)
  assert_eq(state.status, @types.PieceStatus::Completed)
  assert_eq(state.iteration, 2)
  assert_true(events.contains("start:plan:1"))
  assert_true(events.contains("start:implement:2"))
  assert_true(events.contains("piece_complete"))
}

///|
test "run_piece: A→B→C→COMPLETE three step" {
  let movements = [
    make_movement("a", "Step A", rules=[make_rule("next", Some("b"))]),
    make_movement("b", "Step B", rules=[make_rule("next", Some("c"))]),
    make_movement("c", "Step C", rules=[make_rule("next", Some("COMPLETE"))]),
  ]
  let config = make_config(movements, "a")
  let mock = @provider.MockProvider::new()
  mock.set_default("<rule_0>")
  let (cb, _events) = collect_events()
  let state = @engine.run_piece(config, "task", mock, cb)
  assert_eq(state.status, @types.PieceStatus::Completed)
  assert_eq(state.iteration, 3)
}

///|
test "run_piece: ABORT rule" {
  let movements = [
    make_movement("check", "Check", rules=[make_rule("fail", Some("ABORT"))]),
  ]
  let config = make_config(movements, "check")
  let mock = @provider.MockProvider::new()
  mock.set_default("<rule_0> failed")
  let (cb, events) = collect_events()
  let state = @engine.run_piece(config, "check", mock, cb)
  assert_eq(state.status, @types.PieceStatus::PieceAborted)
  assert_true(events.contains("piece_abort:Aborted by rule"))
}

///|
test "run_piece: iteration limit" {
  let movements = [
    make_movement("loop", "Loop forever", rules=[
      make_rule("again", Some("loop")),
    ]),
  ]
  let config = make_config(movements, "loop", max=3)
  let mock = @provider.MockProvider::new()
  mock.set_default("<rule_0>")
  let (cb, events) = collect_events()
  let state = @engine.run_piece(config, "loop", mock, cb)
  assert_eq(state.status, @types.PieceStatus::PieceAborted)
  assert_true(events.contains("iteration_limit:3:3"))
}

///|
test "run_piece: loop detection aborts" {
  let movements = [
    make_movement("step", "Step", rules=[make_rule("again", Some("step"))]),
  ]
  let config : @types.PieceConfig = {
    ..make_config(movements, "step", max=20),
    loop_detection: Some({
      max_consecutive_same_step: 3,
      action: @types.LoopAction::Abort,
    }),
  }
  let mock = @provider.MockProvider::new()
  mock.set_default("<rule_0>")
  let (cb, events) = collect_events()
  let state = @engine.run_piece(config, "task", mock, cb)
  assert_eq(state.status, @types.PieceStatus::PieceAborted)
  assert_true(events.contains("loop:step:3"))
}

///|
test "run_piece: cycle detection fires" {
  let movements = [
    make_movement("review", "Review", rules=[
      make_rule("fix needed", Some("fix")),
    ]),
    make_movement("fix", "Fix", rules=[make_rule("done fixing", Some("review"))]),
  ]
  let config : @types.PieceConfig = {
    ..make_config(movements, "review", max=20),
    loop_monitors: Some([
      {
        cycle: ["review", "fix"],
        threshold: 2,
        judge: { persona: None, instruction_template: None, rules: [] },
      },
    ]),
  }
  let mock = @provider.MockProvider::new()
  mock.set_default("<rule_0>")
  let (cb, events) = collect_events()
  ignore(@engine.run_piece(config, "fix bug", mock, cb))
  assert_true(events.contains("cycle:2"))
}

///|
test "run_piece: movement not found aborts" {
  let movements = [
    make_movement("a", "Step A", rules=[make_rule("next", Some("nonexistent"))]),
  ]
  let config = make_config(movements, "a")
  let mock = @provider.MockProvider::new()
  mock.set_default("<rule_0>")
  let (cb, events) = collect_events()
  let state = @engine.run_piece(config, "task", mock, cb)
  assert_eq(state.status, @types.PieceStatus::PieceAborted)
  assert_true(events.iter().any(fn(e) { e.contains("Movement not found") }))
}

///|
test "run_piece: pass_previous_response" {
  let movements = [
    make_movement("plan", "Plan", rules=[make_rule("done", Some("implement"))]),
    make_movement(
      "implement",
      "Implement based on plan",
      rules=[make_rule("done", Some("COMPLETE"))],
      pass_previous=true,
    ),
  ]
  let config = make_config(movements, "plan")
  let mock = @provider.MockProvider::new()
  mock.set_default("<rule_0> response text")
  let (cb, _events) = collect_events()
  let state = @engine.run_piece(config, "build", mock, cb)
  assert_eq(state.status, @types.PieceStatus::Completed)
}

///|
test "run_piece: callbacks receive correct movement names" {
  let movements = [
    make_movement("alpha", "Do A", rules=[make_rule("next", Some("beta"))]),
    make_movement("beta", "Do B"),
  ]
  let config = make_config(movements, "alpha")
  let mock = @provider.MockProvider::new()
  mock.set_default("<rule_0>")
  let (cb, events) = collect_events()
  ignore(@engine.run_piece(config, "task", mock, cb))
  assert_true(events.contains("start:alpha:1"))
  assert_true(events.contains("complete:alpha"))
  assert_true(events.contains("start:beta:2"))
  assert_true(events.contains("complete:beta"))
}
