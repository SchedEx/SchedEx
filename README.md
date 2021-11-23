<img src="https://user-images.githubusercontent.com/79646/36270991-42e8d440-124b-11e8-9bd6-17cfc02b77fa.png" alt="SchedEx" width="300"/>

[![Build Status](https://github.com/SchedEx/SchedEx/workflows/Elixir%20CI/badge.svg)](https://github.com/SchedEx/SchedEx/actions)
[![Module Version](https://img.shields.io/hexpm/v/sched_ex.svg)](https://hex.pm/packages/sched_ex)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/sched_ex/)
[![Total Download](https://img.shields.io/hexpm/dt/sched_ex.svg)](https://hex.pm/packages/sched_ex)
[![License](https://img.shields.io/hexpm/l/sched_ex.svg)](https://github.com/SchedEx/SchedEx/blob/master/LICENSE.md)
[![Last Updated](https://img.shields.io/github/last-commit/SchedEx/SchedEx.svg)](https://github.com/SchedEx/SchedEx/commits/master)


SchedEx is a simple yet deceptively powerful scheduling library for Elixir. Though it is almost trivially simple by
design, it enables a number of very powerful use cases to be accomplished with very little effort.

SchedEx is written by [Mat Trudel](http://github.com/mtrudel), and development is generously supported by the fine folks
at [FunnelCloud](http://funnelcloud.io).

For usage details, please refer to the [documentation](https://hexdocs.pm/sched_ex).

## Basic Usage

In most contexts `SchedEx.run_every` is the function most commonly used. There are two typical use cases:

### Static Configuration

This approach is useful when you want SchedEx to manage jobs whose configuration is static. At FunnelCloud, we use this
approach to run things like our hourly reports, cleanup tasks and such.  Typically, you will start jobs inside your
`application.ex` file:

```elixir
defmodule Example.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Call Runner.do_frequent/0 every five minutes
      %{ id: "frequent", start: {SchedEx, :run_every, [Example.Runner, :do_frequent, [], "*/5 * * * *"]} },

      # Call Runner.do_daily/0 at 1:01 UTC every day
      %{ id: "daily", start: {SchedEx, :run_every, [Example.Runner, :do_daily, [], "1 1 * * *"]} },

      # You can also pass a function instead of an m,f,a:
      %{ id: "hourly", start: {SchedEx, :run_every, [fn -> IO.puts "It is the top of the hour" end, "0 * * * *"]} }
    ]

    opts = [strategy: :one_for_one, name: Example.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

This will cause the corresponding methods to be run according to the specified crontab entries. If the jobs crash they
also take down the SchedEx process which ran them (SchedEx does not provide supervision by design). Your application's
Supervisor will then restart the relevant SchedEx process, which will continue to run according to its crontab entry.

### Dynamically Scheduled Tasks

SchedEx is especially suited to running tasks which run on a schedule and may be dynamically configured by the user.
For example, at FunnelCloud we have a `ScheduledTask` Ecto schema with a string field called `crontab`. At startup our
`scheduled_task` application reads entries from this table, determines the `module, function, argument` which
should be invoked when the task comes due, and adds a SchedEx job to a supervisor:

```elixir
def start_scheduled_tasks(sup, scheduled_tasks) do
  scheduled_tasks
  |> Enum.map(&child_spec_for_scheduled_task/1)
  |> Enum.map(&(DynamicSupervisor.start_child(sup, &1)))
end

defp child_spec_for_scheduled_task(%ScheduledTask{id: id, crontab: crontab} = task) do
  %{id: "scheduled-task-#{id}", start: {SchedEx, :run_every, mfa_for_task(task) ++ [crontab]}}
end

defp mfa_for_task(task) do
  # Logic that returns the [m, f, a] that should be invoked when task comes due
  [IO, :puts, ["Hello, scheduled task: #{inspect task}"]]
end
```

This will start one SchedEx process per `ScheduledTask`, all supervised within a `DynamicSupervisor`. If either SchedEx or
the invoked function crashes `DynamicSupervisor` will restart it, making this approach robust to failures anywhere in the
application. Note that the above is somewhat simplified - in production we have some additional logic to handle
starting / stopping / reloading tasks on user change.

You can optionally pass a name to the task that would allow you to lookup the task later with Registry or gproc and remove it like so:

```elixir
child_spec = %{
  id: "scheduled-task-#{id}",
  start:
    {SchedEx, :run_every,
     mfa_for_task(task) ++
       [crontab, [name: {:via, Registry, {RegistryName, "scheduled-task-#{id}"}}]]}
}

def get_scheduled_item(id) do
  #ie. "scheduled-task-1"
  list = Registry.lookup(RegistryName, id)

  if length(list) > 0 do
    {pid, _} = hd(list)
    {:ok, pid}
  else
    {:error, "does not exist"}
  end
end

def cancel_scheduled_item(id) do
  with {:ok, pid} <- get_scheduled_item(id) do
    DynamicSupervisor.terminate_child(DSName, pid)
  end
end
```

Then in your children in application.ex
```elixir
{Registry, keys: :unique, name: RegistryName},
{DynamicSupervisor, strategy: :one_for_one, name: DSName},
```

## Other Functions

In addition to `SchedEx.run_every`, SchedEx provides two other methods which serve to schedule jobs; `SchedEx.run_at`,
and `SchedEx.run_in`. As the names suggest, `SchedEx.run_at` takes a `DateTime` struct which indicates the time at which
the job should be executed, and `SchedEx.run_in` takes a duration in integer milliseconds from the time the function is
called at which to execute the job. Similarly to `SchedEx.run_every`, these functions both come in `module, function,
argument` and `fn` form.

The above functions have the same return values as standard `start_link` functions (`{:ok, pid}` on success, `{:error,
error}` on error). The returned pid can be passed to `SchedEx.cancel` to cancel any further invocations of the job.

## Crontab details

SchedEx uses the [crontab](https://github.com/jshmrtn/crontab) library to parse crontab strings. If it is unable to
parse the given crontab string, an error is returned from the `SchedEx.run_every` call and no jobs are scheduled.

Building on the support provided by the crontab library, SchedEx supports *extended* crontabs. Such crontabs have
7 segments instead of the usual 5; one is added to the beginning of the crontab and expresses a seconds value, and one
added to the end expresses a year value. As such, it's possible to specify a unique instant down to the second, for
example:

```elixir
50 59 23 31 12 * 1999     # You'd better be getting ready to party
```

Jobs scheduled via `SchedEx.run_every` are implicitly recurring; they continue to to execute according to the crontab
until `SchedEx.cancel/1` is called or the original calling process terminates. If job execution takes longer than the
scheduling interval, the job is requeued at the next matching interval (for example, if a job set to run every minute
(crontab `* * * * *`) takes 61 seconds to run at minute `x` it will not run at minute `x+1` and will next run at minute
`x+2`).

## Testing

SchedEx has a feature called *TimeScales* which help provide a performant and high parity environment for testing
scheduled code. When invoking `SchedEx.run_every` or `SchedEx.run_in`, you can pass an optional `time_scale` parameter
which allows you to change the speed at which time runs within SchedEx. This allows you to run an entire day (or longer)
worth of scheduling time in a much shorter amount of real time. For example:

```elixir
defmodule ExampleTest do
  use ExUnit.Case

  defmodule AgentHelper do
    def set(agent, value) do
      Agent.update(agent, fn _ -> value end)
    end

    def get(agent) do
      Agent.get(agent, & &1)
    end
  end

  defmodule TestTimeScale do
    def now(_) do
      DateTime.utc_now()
    end

    def speedup do
      86400
    end
  end

  test "updates the agent at 10am every morning" do
    {:ok, agent} = start_supervised({Agent, fn -> nil end})

    SchedEx.run_every(AgentHelper, :set, [agent, :sched_ex_scheduled_time], "* 10 * * *", time_scale: TestTimeScale)

    # Let SchedEx run through a day's worth of scheduling time
    Process.sleep(1000)

    expected_time = Timex.now() |> Timex.beginning_of_day() |> Timex.shift(hours: 34)
    assert DateTime.diff(AgentHelper.get(agent), expected_time) == 0
  end
end
```

will run through an entire day's worth of scheduling time in one second, and allows us to test against the expectations
of the called function quickly, while maintaining near-perfect parity with development. The only thing that changes in
the test environment is the passing of a `time_scale`; all other code is exactly as it is in production.

Note that in the above test, the atom `:sched_ex_scheduled_time` is passed as a value in the argument array. This atom
is treated specially by SchedEx, and is replaced by the scheduled invocation time for which the function is being
called.

## Installation

SchedEx can be installed by adding `:sched_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:sched_ex, "~> 1.0"}
  ]
end
```

## Copyright and License

Copyright (c) 2018 Mat Trudel on behalf of FunnelCloud Inc.

This work is free. You can redistribute it and/or modify it under the
terms of the MIT License. See the [LICENSE.md](./LICENSE.md) file for more details.
