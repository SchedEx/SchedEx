defmodule SchedEx.TimeScale do
  @moduledoc """
  Constrols time in SchedEx, often used to speed up test runs, or implement
  custom timing loops.

  Default implementation is `SchedEx.IdentityTimeScale`.
  """

  @doc """
  Must return the current time in the specified timezone.
  """
  @callback now(Timex.Types.valid_timezone()) :: DateTime.t()

  @doc """
  Must returns a float factor to speed up delays by.
  """
  @callback speedup() :: number
end
