// Integration test package - re-exports for blackbox tests

///|
pub fn run_workflow_test(
  config : @types.PieceConfig,
  task : String,
  provider : &@provider.Provider,
  callbacks : @types.EngineCallbacks,
) -> @types.PieceState {
  @engine.run_piece(config, task, provider, callbacks)
}

///|
pub fn parse_config(
  json_str : String,
) -> @types.PieceConfig raise @config.ConfigError {
  @config.parse_piece_config(json_str)
}
