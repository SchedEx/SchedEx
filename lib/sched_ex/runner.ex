defmodule SchedEx.Runner do
  @moduledoc false

  use GenServer

  @doc """
  Main point of entry into this module. Starts and returns a process which will
  run the given function after the specified delay
  """
  def run_in(func, delay, opts) when is_function(func) and is_integer(delay) do
    if delay > 0 do
      GenServer.start_link(__MODULE__, {func, delay, opts})
    else
      func.()
      {:ok, nil}
    end
  end

  @doc """
  Main point of entry into this module. Starts and returns a process which will
  repeatedly run the given function according to the specified crontab
  """
  def run_every(func, crontab, opts) when is_function(func) do
    case as_crontab(crontab) do
      {:ok, expression} ->
        GenServer.start_link(__MODULE__, {func, expression, opts})
      {:error, _} = error ->
        error
    end
  end

  @doc """
  Cancels future invocation of the given process. If it has already been invoked, does nothing.
  """
  def cancel(pid) when is_pid(pid) do
    :shutdown = send(pid, :shutdown)
    :ok
  end

  def cancel(_token) do
    {:error, "Not a cancellable token"}
  end

  # Server API

  def init({func, delay, opts}) when is_integer(delay) do
    Process.flag(:trap_exit, true)
    Process.send_after(self(), :run, delay)
    {:ok, %{func: func, delay: delay, opts: opts}}
  end

  def init({func, %Crontab.CronExpression{} = crontab, opts}) do
    Process.flag(:trap_exit, true)
    next_time = schedule_next(crontab, opts)
    {:ok, %{func: func, crontab: crontab, scheduled_at: next_time, opts: opts}}
  end

  def handle_info(:run, %{func: func, crontab: crontab, scheduled_at: this_time, opts: opts} = state) do
    if is_function(state.func, 1) do
      func.(this_time)
    else
      func.()
    end
    next_time = schedule_next(crontab, opts)
    {:noreply, %{state | scheduled_at: next_time}}
  end

  def handle_info(:run, state) do
    state.func.()
    {:stop, :normal, state}
  end

  def handle_info(:shutdown, state) do
    {:stop, :normal, state}
  end

  defp as_crontab(%Crontab.CronExpression{} = crontab), do: {:ok, crontab}
  defp as_crontab(crontab), do: Crontab.CronExpression.Parser.parse(crontab)

  defp schedule_next(%Crontab.CronExpression{} = crontab, opts) do
    time_scale = Keyword.get(opts, :time_scale, SchedEx.IdentityTimeScale)
    timezone = Keyword.get(opts, :timezone, "UTC")
    now = time_scale.now(timezone)
    {:ok, naive_next} = Crontab.Scheduler.get_next_run_date(crontab, DateTime.to_naive(now))
    next = case Timex.to_datetime(naive_next, timezone) do
      %Timex.AmbiguousDateTime{after: later_time} -> later_time
      time -> time
    end
    delay = round(max(DateTime.diff(next, now, :millisecond) / time_scale.speedup(), 0))
    Process.send_after(self(), :run, delay)
    next
  end
end
