defmodule SchedEx.Runner do
  @moduledoc false

  use GenServer

  @doc """
  Main point of entry into this module. Starts and returns a process which will
  run the given function per the specified delay definition (can be an integer
  unit as derived from a TimeScale, or a CronExpression)
  """
  def run(func, delay_definition, opts) when is_function(func) do
    GenServer.start_link(__MODULE__, {func, delay_definition, opts}, Keyword.take(opts, [:name]))
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
      {%DateTime{} = next_time, quantized_next_time, timer_ref} ->
        stats = %SchedEx.Stats{}

        {:ok,
         %{
           func: func,
           delay_definition: delay_definition,
           scheduled_at: next_time,
           quantized_scheduled_at: quantized_next_time,
           timer_ref: timer_ref,
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
        {%DateTime{} = next_time, quantized_next_time, timer_ref} ->
          {:noreply,
           %{
             state
             | scheduled_at: next_time,
               quantized_scheduled_at: quantized_next_time,
               timer_ref: timer_ref,
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

  def handle_info({:EXIT, _pid, :normal}, state) do
    {:noreply, state}
  end

  defp schedule_next(%DateTime{} = from, delay, opts) when is_integer(delay) do
    time_scale = Keyword.get(opts, :time_scale, SchedEx.IdentityTimeScale)
    delay = round(delay / time_scale.speedup())
    next = Timex.shift(from, milliseconds: delay)
    now = DateTime.utc_now()
    delay = max(DateTime.diff(next, now, :millisecond), 0)
    timer_ref = Process.send_after(self(), :run, delay)
    {next, Timex.shift(now, milliseconds: delay), timer_ref}
  end

  defp schedule_next(_from, crontab, opts) do
    time_scale = Keyword.get(opts, :time_scale, SchedEx.IdentityTimeScale)
    timezone = Keyword.get(opts, :timezone, "UTC")
    now = time_scale.now(timezone)

    case next_occurrence(now, crontab, timezone, opts) do
      %DateTime{} = next ->
        delay = round(max(DateTime.diff(next, now, :millisecond) / time_scale.speedup(), 0))
        timer_ref = Process.send_after(self(), :run, delay)
        {next, Timex.shift(DateTime.utc_now(), milliseconds: delay), timer_ref}

      {:error, _} = error ->
        error
    end
  end

  defp next_occurrence(
         %DateTime{} = from,
         %Crontab.CronExpression{} = crontab,
         timezone,
         opts
       ) do
    naive_from = from |> DateTime.to_naive()

    case Crontab.Scheduler.get_next_run_date(crontab, naive_from) do
      {:ok, naive_next} ->
        convert_naive_to_timezone(naive_next, crontab, timezone, opts)

      {:error, _} = error ->
        error
    end
  end

  defp convert_naive_to_timezone(naive_next, crontab, timezone, opts) do
    case Timex.to_datetime(naive_next, timezone) do
      {:error, {:could_not_resolve_timezone, _, wall_offset, _}} ->
        opts
        |> Keyword.get(:nonexistent_time_strategy, :skip)
        |> case do
          :skip ->
            skip_non_existent_time(naive_next, wall_offset, crontab, timezone, opts)

          :adjust ->
            adjust_non_existent_time(naive_next, timezone)
        end

      %Timex.AmbiguousDateTime{after: later_time} ->
        later_time

      time ->
        time
    end
  end

  defp skip_non_existent_time(
         %NaiveDateTime{} = naive_date,
         wall_offset,
         crontab,
         timezone,
         opts
       ) do
    # Assume that there will be a single valid period one hour past the non existent time
    [%{from: %{wall: start_of_next_period}}] =
      Tzdata.periods_for_time(timezone, wall_offset + 3600, :wall)

    first_date_in_next_period =
      naive_date
      |> Timex.shift(seconds: start_of_next_period - wall_offset)
      |> Timex.to_datetime(timezone)

    next_occurrence(first_date_in_next_period, crontab, timezone, opts)
  end

  defp adjust_non_existent_time(
         %NaiveDateTime{} = naive_date,
         timezone
       ) do
    # Assume that midnight of the non-existent day is in a valid period
    naive_start_of_day = Timex.beginning_of_day(naive_date)
    difference_from_midnight = NaiveDateTime.diff(naive_date, naive_start_of_day)

    start_of_day = naive_start_of_day |> Timex.to_datetime(timezone)
    start_of_day |> Timex.shift(seconds: difference_from_midnight)
  end
end
