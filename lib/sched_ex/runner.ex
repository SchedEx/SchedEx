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
    next = DateTime.add(from, delay, :millisecond)
    now = DateTime.utc_now()
    delay = max(DateTime.diff(next, now, :millisecond), 0)
    timer_ref = Process.send_after(self(), :run, delay)
    {next, DateTime.add(now, delay, :millisecond), timer_ref}
  end

  defp schedule_next(_from, crontab, opts) do
    time_scale = Keyword.get(opts, :time_scale, SchedEx.IdentityTimeScale)
    timezone = Keyword.get(opts, :timezone, "Etc/UTC")
    now = time_scale.now(timezone)

    case next_occurrence(now, crontab, timezone, opts) do
      %DateTime{} = next ->
        delay = round(max(DateTime.diff(next, now, :millisecond) / time_scale.speedup(), 0))
        timer_ref = Process.send_after(self(), :run, delay)
        {next, DateTime.add(DateTime.utc_now(), delay, :millisecond), timer_ref}

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
    case DateTime.from_naive(naive_next, timezone) do
      {:gap, _just_before, just_after} ->
        opts
        |> Keyword.get(:nonexistent_time_strategy, :skip)
        |> case do
          :skip ->
            next_occurrence(just_after, crontab, timezone, opts)

          :adjust ->
            adjust_non_existent_time(naive_next, timezone)
        end

      {:ambiguous, _first, second} ->
        second

      {:ok, time} ->
        time
    end
  end

  defp adjust_non_existent_time(
         %NaiveDateTime{} = naive_date,
         timezone
       ) do
    naive_start_of_day = NaiveDateTime.new!(NaiveDateTime.to_date(naive_date), ~T[00:00:00])
    difference_from_midnight = NaiveDateTime.diff(naive_date, naive_start_of_day)

    start_of_day =
      case DateTime.from_naive(naive_start_of_day, timezone) do
        {:ok, dt} -> dt
        {:gap, _before, just_after} -> just_after
        {:ambiguous, _first, second} -> second
      end

    DateTime.add(start_of_day, difference_from_midnight, :second)
  end
end
