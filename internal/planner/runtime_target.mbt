///|
/// Plan one dependency group with the same target/runtime resolution rules for
/// ordinary and subsequent dependencies. Keeping this traversal in one async
/// state machine avoids emitting two copies of the dependency scheduling logic.
async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] plan_dependency_group_async(
  process : P,
  host : H,
  dependencies : ArrayView[@syntax.Dependency],
  project : @semantic.ProjectCompilation?,
  project_runtimes : ArrayView[ProjectModuleRuntime],
  module_path : @modulepath.ModulePath,
  compilation : @semantic.Compilation,
  global : @evaluator.Environment,
  recipe_context : @evaluator.EvaluationContext,
  parent_shell : @environment.ShellConfiguration,
  recipe_shell : @environment.ShellConfiguration,
  cwd : @path.PathValue,
  process_environment : ArrayView[(String, String)],
  options : ExecutionOptions,
  configuration : ScriptConfiguration,
  scope : @evaluator.Environment,
  ran : Map[String, Int],
  stack : Array[String],
  entry_dependencies : ArrayView[Int],
  tasks : Array[ExecutionTask],
  stderr : Array[Byte],
  confirmations : Array[ConfirmationRequest],
  parallel : Bool,
) -> (Array[Int], Array[Int]) raise ExecutionError {
  let terminals : Array[Int] = []
  let mut serial_fence = entry_dependencies.to_owned()
  for dependency in dependencies {
    let target = dependency_planning_target(
      project,
      project_runtimes,
      module_path,
      compilation,
      dependency.name(),
    )
    let target_global = target.runtime
      .map(ProjectModuleRuntime::global)
      .unwrap_or(global)
    let target_context = target.runtime
      .map(ProjectModuleRuntime::context)
      .unwrap_or(recipe_context)
    let target_shell = target.runtime
      .map(ProjectModuleRuntime::shell)
      .unwrap_or(parent_shell)
    let target_cwd = target.runtime
      .map(ProjectModuleRuntime::cwd)
      .unwrap_or(cwd)
    let target_evaluation_directory = target_context.cwd().unwrap_or(target_cwd)
    let target_invocation_directory = target_context
      .invocation_directory_native()
      .unwrap_or(target_cwd)
    let target_environment = target.runtime
      .map(ProjectModuleRuntime::process_environment)
      .unwrap_or(process_environment)
    let target_configuration = target.runtime
      .map(ProjectModuleRuntime::configuration)
      .unwrap_or(configuration)
    let target_options = options.with_guards(
      target.compilation.settings().bool("guards"),
    )
    // Empty dependency arguments are common in large static DAGs. Avoid
    // constructing an effect shell and evaluating an empty expression list.
    let values = if dependency.arguments().is_empty() {
      []
    } else {
      async_dependency_arguments(
        process, host, dependency, scope, recipe_context, recipe_shell,
      )
    }
    if !dependency.starred() {
      let terminal = plan_graph_recipe_async(
        process,
        host,
        target.compilation,
        target.name,
        values,
        target_global,
        target_context,
        target_shell,
        target_cwd,
        target_evaluation_directory,
        target_invocation_directory,
        target_environment,
        target_options,
        target_configuration,
        ran,
        stack,
        if parallel {
          entry_dependencies.to_owned()
        } else {
          serial_fence.copy()
        },
        tasks,
        stderr,
        confirmations,
        true,
        project?,
        module_path=target.module_path,
        project_runtimes~,
      )
      if !terminals.contains(terminal) {
        terminals.push(terminal)
      }
      if !parallel {
        serial_fence = [terminal]
      }
    } else {
      for mapped_values in expanded_dependency_argument_sets(dependency, values) {
        let terminal = plan_graph_recipe_async(
          process,
          host,
          target.compilation,
          target.name,
          mapped_values,
          target_global,
          target_context,
          target_shell,
          target_cwd,
          target_evaluation_directory,
          target_invocation_directory,
          target_environment,
          target_options,
          target_configuration,
          ran,
          stack,
          if parallel {
            entry_dependencies.to_owned()
          } else {
            serial_fence.copy()
          },
          tasks,
          stderr,
          confirmations,
          true,
          project?,
          module_path=target.module_path,
          project_runtimes~,
        )
        if !terminals.contains(terminal) {
          terminals.push(terminal)
        }
        if !parallel {
          serial_fence = [terminal]
        }
      }
    }
  }
  (terminals, serial_fence)
}
