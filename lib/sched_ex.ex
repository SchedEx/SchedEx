defmodule SchedEx do
  @moduledoc """
  SchedEx schedules jobs (either an m,f,a or a function) to run in the future. These jobs are run in isolated processes, and are unsurpervised.
  """

  @doc """
  Runs the given module, function and argument at the given time
  """
  def run_at(m, f, a, %DateTime{} = time) when is_atom(m) and is_atom(f) and is_list(a) do
    run_at(fn -> apply(m, f, a) end, time)
  end

  @doc """
  Runs the given function at the given time
  """
  def run_at(func, %DateTime{} = time) when is_function(func) do
    delay = DateTime.diff(time, DateTime.utc_now(), :millisecond)
    run_in(func, delay)
  end

  @doc """
  Runs the given module, function and argument in given number of units (this 
  corresponds to milliseconds unless a custom `time_scale` is specified). Any 
  values in the arguments array which are equal to the magic symbol `:sched_ex_scheduled_time`
  are replaced with the scheduled execution time for each invocation

  Supports the following options:

  * `repeat`: Whether or not this job should be recurring
  * `start_time`: A `DateTime` to use as the basis to offset from
  * `time_scale`: A module implementing one method: `speedup/0`, which returns a
  float factor to speed up delays by. Used mostly for speeding up test runs. 
  If not specified, defaults to an identity module which returns a value of 1, 
  such that this method runs the job in 'delay' ms
  """
  def run_in(m, f, a, delay, opts \\ []) when is_atom(m) and is_atom(f) and is_list(a) do
    run_in(mfa_to_fn(m, f, a), delay, opts)
  end

  @doc """
  Runs the given function in given number of units (this corresponds to milliseconds 
  unless a custom `time_scale` is specified). If func is of arity 1, the scheduled 
  execution time will be passed for each invocation

  Supports the following options:

  * `repeat`: Whether or not this job should be recurring. Defaults to false
  * `start_time`: A `DateTime` to use as the basis to offset from
  * `time_scale`: A module implementing one method: `speedup/0`, which returns a
  float factor to speed up delays by. Used mostly for speeding up test runs. 
  If not specified, defaults to an identity module which returns a value of 1, 
  such that this method runs the job in 'delay' ms
  """
  def run_in(func, delay, opts \\ []) when is_function(func) and is_integer(delay) do
    SchedEx.Runner.run(func, delay, opts)
  end

  @doc """
  Runs the given module, function and argument on every occurence of the given crontab. Any
  values in the arguments array which are equal to the magic symbol `:sched_ex_scheduled_time`
  are replaced with the scheduled execution time for each invocation

  Supports the following options:

  * `timezone`: A string timezone identifier (`America/Chicago`) specifying the timezone within which 
  the crontab should be interpreted. If not specified, defaults to `UTC`
  * `time_scale`: A module implementing two methods: `now/1`, which returns the current time in the specified timezone, and 
  `speedup/0`, which returns a float factor to speed up delays by. Used mostly for speeding up test runs. If not specified, defaults to 
  an identity module which returns 'now', and a factor of 1
  """
  def run_every(m, f, a, crontab, opts \\ []) when is_atom(m) and is_atom(f) and is_list(a) do
    run_every(mfa_to_fn(m, f, a), crontab, opts)
  end

  @doc """
  Runs the given function on every occurence of the given crontab. If func is of arity 1, the 
  scheduled execution time will be passed for each invocation

  Supports the following options:

  * `timezone`: A string timezone identifier (`America/Chicago`) specifying the timezone within which 
  the crontab should be interpreted. If not specified, defaults to `UTC`
  * `time_scale`: A module implementing two methods: `now/1`, which returns the current time in the specified timezone, and 
  `speedup/0`, which returns an integer factor to speed up delays by. Used mostly for speeding up test runs. If not specified, defaults to 
  an identity module which returns 'now', and a factor of 1
  * `repeat`: Whether or not this job should be recurring. If false, only the next matching time of the crontab is executed. Defaults to true
  """
  def run_every(func, crontab, opts \\ []) when is_function(func) do
    case as_crontab(crontab) do
      {:ok, expression} ->
        SchedEx.Runner.run(func, expression, Keyword.put_new(opts, :repeat, true))

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Cancels the given scheduled job
  """
  def cancel(token) do
    SchedEx.Runner.cancel(token)
  end

  @doc """
  Returns stats on the given job. Stats are returned for:
  * `scheduling_delay`: The delay between when the job was scheduled to execute, and the time
  it actually was executed. Based on the quantized scheduled start, and so does not include quantization error. Value specified in microseconds.
  * `quantization_error`: Erlang is only capable of scheduling future calls with millisecond precision, so there is some 
  inevitable precision lost between when the job would be scheduled in a perfect world, and how well Erlang is able to 
  schedule the job (ie: to the closest millisecond). This error value captures that difference. Value specified in microseconds.
  * `execution_time`: The amount of time the job spent executing. Value specified in microseconds.

  """
  def stats(token) do
    SchedEx.Runner.stats(token)
  end

  defp mfa_to_fn(m, f, args) do
    fn time ->
      substituted_args =
        Enum.map(args, fn arg ->
          case arg do
            :sched_ex_scheduled_time -> time
            _ -> arg
          end
        end)

      apply(m, f, substituted_args)
    end
  end

  defp as_crontab(%Crontab.CronExpression{} = crontab), do: {:ok, crontab}

  defp as_crontab(crontab) do
    extended = length(String.split(crontab)) > 5
    Crontab.CronExpression.Parser.parse(crontab, extended)
  end
end
