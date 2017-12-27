defmodule SchedEx.Runner do
  use GenServer

  def run_in(func, delay, opts) when is_function(func) and is_integer(delay) do
    if delay > 0 do
      GenServer.start_link(__MODULE__, {func, delay, opts})
    else
      func.()
      {:ok, nil}
    end
  end

  def cancel(pid) when is_pid(pid) do
    :shutdown = send(pid, :shutdown)
    :ok
  end

  def cancel(_token) do
    {:error, "Not a cancellable token"}
  end

  # Server API
  def init({func, delay, opts}) do
    Process.flag(:trap_exit, true)
    Process.send_after(self(), :run, delay)
    {:ok, %{func: func, delay: delay, opts: opts}}
  end

  def handle_info(:run, state) do
    state.func.()
    {:stop, :normal, state}
  end

  def handle_info(:shutdown, state) do
    {:stop, :normal, state}
  end
end
