defmodule SchedEx do
  @moduledoc """
  SchedEx schedules jobs (either an m,f,a or a function) to run in the future. These jobs are run in isolated processes, and are unsurpervised.
  """

  @doc """
  Runs the given module, function and argument at the given time
  """
  def run_at(m, f, a, %DateTime{} = time) when is_atom(m) and is_atom(f) and is_list(a) do
    run_at(fn -> apply(m,f,a) end, time)
  end

  @doc """
  Runs the given function at the given time
  """
  def run_at(func, %DateTime{} = time) when is_function(func) do
    delay = DateTime.diff(time, DateTime.utc_now(), :millisecond)
    run_in(func, delay)
  end

  @doc """
  Runs the given module, function and argument in the given number of milliseconds
  """
  def run_in(m, f, a, delay, opts \\ []) when is_atom(m) and is_atom(f) and is_list(a) do
    run_in(fn -> apply(m,f,a) end, delay, opts)
  end

  @doc """
  Runs the given function in given number of milliseconds
  """
  def run_in(func, delay, opts \\ []) when is_function(func) and is_integer(delay) do
    SchedEx.Runner.run_in(func, delay, opts)
  end

  @doc """
  Runs the given module, function and argument on every occurence of the given crontab

  Supports the following options:

  timezone: A string timezone identifier ("America/Chicago") specifying the timezone within which 
  the crontab should be interpreted. If not specified, defaults to "UTC"

  time_scale: A module implementing two methods: now/1, which returns the current time in the specified timezone, and 
  speedup/0, which returns an integer factor to speed up delays by. Used mostly for speeding up test runs. If not specified, defaults to 
  an identity module which returns 'now', and a factor of 1
  """
  def run_every(m, f, a, crontab, opts \\ []) when is_atom(m) and is_atom(f) and is_list(a) do
    run_every(fn -> apply(m,f,a) end, crontab, opts)
  end

  @doc """
  Runs the given function on every occurence of the given crontab. If func is of arity 1, the 
  scheduled execution time will be passed for each invocation

  Supports the following options:

  timezone: A string timezone identifier ("America/Chicago") specifying the timezone within which 
  the crontab should be interpreted. If not specified, defaults to "UTC"

  time_scale: A module implementing two methods: now/1, which returns the current time in the specified timezone, and 
  speedup/0, which returns an integer factor to speed up delays by. Used mostly for speeding up test runs. If not specified, defaults to 
  an identity module which returns 'now', and a factor of 1
  """
  def run_every(func, crontab, opts \\ []) when is_function(func) do
    SchedEx.Runner.run_every(func, crontab, opts)
  end

  @doc """
  Cancels the given scheduled job
  """
  def cancel(token) do
    SchedEx.Runner.cancel(token)
  end
end
