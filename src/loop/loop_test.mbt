///|
test "LoopDetector: no loop with different movements" {
  let d = @loop.LoopDetector::default()
  assert_eq(d.record("a"), @loop.LoopCheckResult::Ok)
  assert_eq(d.record("b"), @loop.LoopCheckResult::Ok)
  assert_eq(d.record("a"), @loop.LoopCheckResult::Ok)
  assert_eq(d.record("b"), @loop.LoopCheckResult::Ok)
}

///|
test "LoopDetector: detects consecutive same movement" {
  let d = @loop.LoopDetector::new({
    max_consecutive_same_step: 3,
    action: @types.LoopAction::Abort,
  })
  assert_eq(d.record("a"), @loop.LoopCheckResult::Ok)
  assert_eq(d.record("a"), @loop.LoopCheckResult::Ok)
  assert_eq(d.record("a"), @loop.LoopCheckResult::Detected(3))
}

///|
test "LoopDetector: reset clears state" {
  let d = @loop.LoopDetector::new({
    max_consecutive_same_step: 3,
    action: @types.LoopAction::Warn,
  })
  ignore(d.record("a"))
  ignore(d.record("a"))
  d.reset()
  assert_eq(d.record("a"), @loop.LoopCheckResult::Ok)
  assert_eq(d.record("a"), @loop.LoopCheckResult::Ok)
  assert_eq(d.record("a"), @loop.LoopCheckResult::Detected(3))
}

///|
test "LoopDetector: different movement resets count" {
  let d = @loop.LoopDetector::new({
    max_consecutive_same_step: 3,
    action: @types.LoopAction::Warn,
  })
  ignore(d.record("a"))
  ignore(d.record("a"))
  ignore(d.record("b")) // resets
  assert_eq(d.record("b"), @loop.LoopCheckResult::Ok)
  assert_eq(d.record("b"), @loop.LoopCheckResult::Detected(3))
}

///|
test "CycleDetector: no cycle with non-matching pattern" {
  let d = @loop.CycleDetector::new(["review", "fix"], 2)
  assert_eq(d.record("plan"), @loop.CycleCheckResult::Ok)
  assert_eq(d.record("implement"), @loop.CycleCheckResult::Ok)
  assert_eq(d.record("plan"), @loop.CycleCheckResult::Ok)
}

///|
test "CycleDetector: detects 2-step cycle" {
  let d = @loop.CycleDetector::new(["review", "fix"], 2)
  assert_eq(d.record("review"), @loop.CycleCheckResult::Ok)
  assert_eq(d.record("fix"), @loop.CycleCheckResult::Ok) // cycle 1
  assert_eq(d.record("review"), @loop.CycleCheckResult::Ok)
  assert_eq(d.record("fix"), @loop.CycleCheckResult::CycleDetected(2)) // cycle 2
}

///|
test "CycleDetector: detects 3-step cycle" {
  let d = @loop.CycleDetector::new(["a", "b", "c"], 2)
  assert_eq(d.record("a"), @loop.CycleCheckResult::Ok)
  assert_eq(d.record("b"), @loop.CycleCheckResult::Ok)
  assert_eq(d.record("c"), @loop.CycleCheckResult::Ok) // cycle 1
  assert_eq(d.record("a"), @loop.CycleCheckResult::Ok)
  assert_eq(d.record("b"), @loop.CycleCheckResult::Ok)
  assert_eq(d.record("c"), @loop.CycleCheckResult::CycleDetected(2)) // cycle 2
}

///|
test "CycleDetector: threshold 3 requires 3 full cycles" {
  let d = @loop.CycleDetector::new(["a", "b"], 3)
  ignore(d.record("a"))
  ignore(d.record("b")) // cycle 1
  ignore(d.record("a"))
  ignore(d.record("b")) // cycle 2
  ignore(d.record("a"))
  assert_eq(d.record("b"), @loop.CycleCheckResult::CycleDetected(3)) // cycle 3
}

///|
test "CycleDetector: reset clears state" {
  let d = @loop.CycleDetector::new(["a", "b"], 2)
  ignore(d.record("a"))
  ignore(d.record("b"))
  d.reset()
  assert_eq(d.get_cycle_count(), 0)
  assert_eq(d.record("a"), @loop.CycleCheckResult::Ok)
  assert_eq(d.record("b"), @loop.CycleCheckResult::Ok) // only cycle 1 after reset
}

///|
test "CycleDetector: empty pattern never detects" {
  let d = @loop.CycleDetector::new([], 1)
  assert_eq(d.record("a"), @loop.CycleCheckResult::Ok)
  assert_eq(d.record("b"), @loop.CycleCheckResult::Ok)
}
