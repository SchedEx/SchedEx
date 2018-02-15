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
