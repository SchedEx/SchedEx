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
    case Crontab.CronExpression.Parser.parse(crontab) do
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
    delay = delay_until(crontab)
    Process.send_after(self(), :run, delay)
    {:ok, %{func: func, crontab: crontab, opts: opts}}
  end

  def handle_info(:run, %{crontab: crontab} = state) do
    state.func.()
    delay = delay_until(crontab)
    Process.send_after(self(), :run, delay)
    {:noreply, state}
  end

  def handle_info(:run, state) do
    state.func.()
    {:stop, :normal, state}
  end

  def handle_info(:shutdown, state) do
    {:stop, :normal, state}
  end

  defp delay_until(%Crontab.CronExpression{} = crontab) do
    naive_now = DateTime.utc_now()
                |> DateTime.to_naive()
    {:ok, naive_next} = Crontab.Scheduler.get_next_run_date(crontab)
    NaiveDateTime.diff(naive_next, naive_now) * 1000
  end
end
