defmodule SchedEx.IdentityTimeScale do
  @moduledoc """
  The default module used to set the `time_scale`. Can be thought of as "normal time" where "now" is now and speedup is 1 (no speedup).
  """
  @behaviour SchedEx.TimeScale

  @impl true
  def now(timezone) do
    Timex.now(timezone)
  end

  @impl true
  def speedup do
    1
  end
end
