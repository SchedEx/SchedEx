defmodule SchedEx.Runner do
  @moduledoc false

  use GenServer

  @doc """
  Main point of entry into this module. Starts and returns a process which will
  run the given function per the specified delay definition (can be an integer 
  unit as derived from a TimeScale, or a CronExpression)
  """
  def run(func, delay_definition, opts) when is_function(func) do
    GenServer.start_link(__MODULE__, {func, delay_definition, opts})
  end

  @doc """
  Returns stats for the given process. 
  """
  def stats(pid) when is_pid(pid) do
    GenServer.call(pid, :stats)
  end

  def stats(_token) do
    {:error, "Not a statable token"}
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

  def init({func, delay_definition, opts}) do
    Process.flag(:trap_exit, true)
    start_time = Keyword.get(opts, :start_time, DateTime.utc_now())

    case schedule_next(start_time, delay_definition, opts) do
      {%DateTime{} = next_time, quantized_next_time} ->
        stats = %SchedEx.Stats{}

        {:ok,
         %{
           func: func,
           delay_definition: delay_definition,
           scheduled_at: next_time,
           quantized_scheduled_at: quantized_next_time,
           stats: stats,
           opts: opts
         }}

      {:error, _} ->
        :ignore
    end
  end

  def handle_call(:stats, _from, %{stats: stats} = state) do
    {:reply, stats, state}
  end

  def handle_info(
        :run,
        %{
          func: func,
          delay_definition: delay_definition,
          scheduled_at: this_time,
          quantized_scheduled_at: quantized_this_time,
          stats: stats,
          opts: opts
        } = state
      ) do
    start_time = DateTime.utc_now()

    if is_function(func, 1) do
      func.(this_time)
    else
      func.()
    end

    end_time = DateTime.utc_now()
    stats = SchedEx.Stats.update(stats, this_time, quantized_this_time, start_time, end_time)

    if Keyword.get(opts, :repeat, false) do
      case schedule_next(this_time, delay_definition, opts) do
        {%DateTime{} = next_time, quantized_next_time} ->
          {:noreply,
           %{
             state
             | scheduled_at: next_time,
               quantized_scheduled_at: quantized_next_time,
               stats: stats
           }}

        _ ->
          {:stop, :normal, %{state | stats: stats}}
      end
    else
      {:stop, :normal, %{state | stats: stats}}
    end
  end

  def handle_info(:shutdown, state) do
    {:stop, :normal, state}
  end

  defp schedule_next(%DateTime{} = from, delay, opts) when is_integer(delay) do
    time_scale = Keyword.get(opts, :time_scale, SchedEx.IdentityTimeScale)
    delay = round(delay / time_scale.speedup())
    next = Timex.shift(from, milliseconds: delay)
    now = DateTime.utc_now()
    delay = max(DateTime.diff(next, now, :millisecond), 0)
    Process.send_after(self(), :run, delay)
    {next, Timex.shift(now, milliseconds: delay)}
  end

  defp schedule_next(_from, %Crontab.CronExpression{} = crontab, opts) do
    time_scale = Keyword.get(opts, :time_scale, SchedEx.IdentityTimeScale)
    timezone = Keyword.get(opts, :timezone, "UTC")
    now = time_scale.now(timezone)

    case Crontab.Scheduler.get_next_run_date(crontab, DateTime.to_naive(now)) do
      {:ok, naive_next} ->
        next =
          case Timex.to_datetime(naive_next, timezone) do
            %Timex.AmbiguousDateTime{after: later_time} -> later_time
            time -> time
          end

        delay = round(max(DateTime.diff(next, now, :millisecond) / time_scale.speedup(), 0))
        Process.send_after(self(), :run, delay)
        {next, Timex.shift(DateTime.utc_now(), milliseconds: delay)}

      {:error, _} = error ->
        error
    end
  end
end
