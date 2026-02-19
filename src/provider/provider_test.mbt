///|
test "MockProvider: default response" {
  let mock = @provider.MockProvider::new()
  let resp = mock.call("system", "user message")
  assert_eq(resp.status, @types.Status::Complete)
  assert_eq(resp.persona, "mock")
  assert_true(resp.content.contains("Mock response"))
}

///|
test "MockProvider: custom response matching" {
  let mock = @provider.MockProvider::new()
  ignore(mock.with_response("plan", "Here is the plan"))
  let resp = mock.call("system", "Please plan the task")
  assert_eq(resp.content, "Here is the plan")
}

///|
test "MockProvider: falls back to default when no match" {
  let mock = @provider.MockProvider::new()
  ignore(mock.with_response("deploy", "Deployed"))
  let resp = mock.call("system", "Review the code")
  assert_true(resp.content.contains("Mock response"))
}

///|
test "MockProvider: set_default changes default" {
  let mock = @provider.MockProvider::new()
  mock.set_default("Custom default")
  let resp = mock.call("system", "anything")
  assert_eq(resp.content, "Custom default")
}

///|
test "create_provider: mock type" {
  let p = @provider.create_provider(@types.ProviderType::Mock, "/tmp", None)
  let resp = p.call("sys", "msg")
  assert_eq(resp.status, @types.Status::Complete)
}
