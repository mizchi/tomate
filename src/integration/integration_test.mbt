// Integration tests using config DSL + engine + MockProvider

///|
fn collect_events() -> (@types.EngineCallbacks, Array[String]) {
  let events : Array[String] = []
  let cb : @types.EngineCallbacks = {
    on_movement_start: fn(name, iter, _) {
      events.push("start:\{name}:\{iter}")
    },
    on_movement_complete: fn(name, _resp, _) { events.push("complete:\{name}") },
    on_movement_report: fn(_, _, _) {  },
    on_phase_start: fn(_, _, _) {  },
    on_phase_complete: fn(_, _, _, _) {  },
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

///|
test "integration: plan→implement→COMPLETE via config DSL" {
  let config = @config.piece("plan-implement", [
    @config.movement("plan", instruction="Plan: {task}", rules=[
      @config.rule("done", next=Some("implement")),
    ]),
    @config.movement(
      "implement",
      instruction="Implement: {task}",
      rules=[@config.rule("done", next=Some("COMPLETE"))],
      pass_previous=true,
    ),
  ])
  let mock = @provider.MockProvider::new()
  mock.set_default("<rule_0> completed")
  let (cb, events) = collect_events()
  let state = @engine.run_piece(config, "add fib", mock, cb)
  assert_eq(state.status, @types.PieceStatus::Completed)
  assert_eq(state.iteration, 2)
  assert_true(events.contains("piece_complete"))
}

///|
test "integration: plan→implement→review→COMPLETE" {
  let config = @config.piece("plan-implement-review", [
    @config.movement("plan", instruction="Plan: {task}", rules=[
      @config.rule("done", next=Some("implement")),
    ]),
    @config.movement(
      "implement",
      instruction="Implement: {task}",
      rules=[@config.rule("done", next=Some("review"))],
      pass_previous=true,
    ),
    @config.movement(
      "review",
      instruction="Review: {task}",
      rules=[
        @config.rule("approved", next=Some("COMPLETE")),
        @config.rule("rejected", next=Some("implement")),
      ],
      pass_previous=true,
    ),
  ])
  let mock = @provider.MockProvider::new()
  mock.set_default("<rule_0> done")
  let (cb, events) = collect_events()
  let state = @engine.run_piece(config, "build feature", mock, cb)
  assert_eq(state.status, @types.PieceStatus::Completed)
  assert_eq(state.iteration, 3)
  assert_true(events.contains("start:plan:1"))
  assert_true(events.contains("start:implement:2"))
  assert_true(events.contains("start:review:3"))
  assert_true(events.contains("piece_complete"))
}

///|
test "integration: review→implement→review→COMPLETE (approval after fix)" {
  let config = @config.piece(
    "review-loop",
    [
      @config.movement("implement", instruction="Implement: {task}", rules=[
        @config.rule("done", next=Some("review")),
      ]),
      @config.movement(
        "review",
        instruction="Review: {task}",
        rules=[
          @config.rule("approved", next=Some("COMPLETE")),
          @config.rule("rejected", next=Some("implement")),
        ],
        pass_previous=true,
      ),
    ],
    max_movements=10,
  )
  let mock = @provider.MockProvider::new()
  mock.set_default("<rule_0>")
  let (cb, _events) = collect_events()
  let state = @engine.run_piece(config, "fix bug", mock, cb)
  assert_eq(state.status, @types.PieceStatus::Completed)
  assert_eq(state.iteration, 2)
}

///|
test "integration: loop detection with abort" {
  let config = @config.piece(
    "infinite-loop",
    [
      @config.movement("step", instruction="Do: {task}", rules=[
        @config.rule("again", next=Some("step")),
      ]),
    ],
    max_movements=20,
    loop_detection=Some({
      max_consecutive_same_step: 3,
      action: @types.LoopAction::Abort,
    }),
  )
  let mock = @provider.MockProvider::new()
  mock.set_default("<rule_0>")
  let (cb, events) = collect_events()
  let state = @engine.run_piece(config, "loop", mock, cb)
  assert_eq(state.status, @types.PieceStatus::PieceAborted)
  assert_true(events.contains("loop:step:3"))
}

///|
test "integration: iteration limit" {
  let config = @config.piece(
    "limited",
    [
      @config.movement("step", instruction="Do: {task}", rules=[
        @config.rule("next", next=Some("step")),
      ]),
    ],
    max_movements=3,
  )
  let mock = @provider.MockProvider::new()
  mock.set_default("<rule_0>")
  let (cb, events) = collect_events()
  let state = @engine.run_piece(config, "task", mock, cb)
  assert_eq(state.status, @types.PieceStatus::PieceAborted)
  assert_true(events.contains("iteration_limit:3:3"))
}

///|
test "integration: JSON config parse and run" {
  let json =
    #|{
    #|  "name": "json-test",
    #|  "movements": [
    #|    {
    #|      "name": "greet",
    #|      "instructionTemplate": "Say hello for: {task}"
    #|    }
    #|  ]
    #|}
  let config = @config.parse_piece_config(json)
  let mock = @provider.MockProvider::new()
  mock.set_default("Hello world!")
  let (cb, events) = collect_events()
  let state = @engine.run_piece(config, "greeting", mock, cb)
  assert_eq(state.status, @types.PieceStatus::Completed)
  assert_true(events.contains("piece_complete"))
}

///|
test "integration: cycle detection fires callback" {
  let config : @types.PieceConfig = {
    ..@config.piece(
      "cycle-test",
      [
        @config.movement("review", instruction="Review", rules=[
          @config.rule("fix needed", next=Some("fix")),
        ]),
        @config.movement("fix", instruction="Fix", rules=[
          @config.rule("done", next=Some("review")),
        ]),
      ],
      max_movements=20,
    ),
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
  ignore(@engine.run_piece(config, "fix", mock, cb))
  assert_true(events.contains("cycle:2"))
}

///|
test "integration: movement outputs are recorded" {
  let config = @config.piece("record-test", [
    @config.movement("alpha", instruction="Do A", rules=[
      @config.rule("next", next=Some("beta")),
    ]),
    @config.movement("beta", instruction="Do B"),
  ])
  let mock = @provider.MockProvider::new()
  mock.set_default("<rule_0> response text")
  let (cb, _events) = collect_events()
  let state = @engine.run_piece(config, "test", mock, cb)
  assert_eq(state.movement_outputs.length(), 2)
  assert_true(state.movement_outputs.get("alpha") is Some(_))
  assert_true(state.movement_outputs.get("beta") is Some(_))
}
