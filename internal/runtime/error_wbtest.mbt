///|
test "runtime classifies shell launch failures" {
  let missing = shell_launch_error(
    "build",
    "missing",
    @host.InvalidInput("program not found"),
  )
  assert_true(missing is @planner.ShellNotFound(..))
  assert_eq(
    @planner.ExecutionError::message(missing),
    "error: recipe `build` could not be run because just could not find the shell `missing`: program not found",
  )
  let invalid_directory = shell_launch_error(
    "build",
    "sh",
    @host.InvalidInput("The directory name is invalid. (os error 267)"),
  )
  assert_true(invalid_directory is @planner.ShellLaunchIo(..))
  assert_eq(
    @planner.ExecutionError::message(invalid_directory),
    "error: recipe `build` could not be run because of an IO error while launching the shell `sh`: The directory name is invalid. (os error 267)",
  )
}
