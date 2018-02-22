defmodule SchedEx.IdentityTimeScale do
  @moduledoc false

  def now(timezone) do
    Timex.now(timezone)
  end

  def speedup do
    1
  end
end
