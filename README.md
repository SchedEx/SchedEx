<img src="https://user-images.githubusercontent.com/79646/36270991-42e8d440-124b-11e8-9bd6-17cfc02b77fa.png" alt="SchedEx" width="300"/>

[![Build Status](https://travis-ci.org/SchedEx/SchedEx.svg?branch=master)](https://travis-ci.org/SchedEx/SchedEx)
[![Inline docs](http://inch-ci.org/github/SchedEx/SchedEx.svg?branch=master&style=flat)](http://inch-ci.org/github/SchedEx/SchedEx)

SchedEx is a simple yet deceptively powerful scheduling library for Elixir. Though it is almost trivially simple by design, it
enables a number of very powerful use cases to be accomplished with very little effort.

SchedEx is written by [Mat Trudel](http://github.com/mtrudel), and development is generously supported by the fine folks
at [FunnelCloud](http://funnelcloud.io).

For usage details, please refer to the [documentation](https://hexdocs.pm/sched_ex).

# Basic Usage

In a supervised context `SchedEx.run_every` is the entry point most commonly used. Typically, jobs which you wish to
run on a regular basis will be started in your `application.ex` file like so:

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

In addition to `SchedEx.run_every`, SchedEx provides two other methods which serve to schedule jobs; `SchedEx.run_at`,
and `SchedEx.run_in`. As the names suggest, `SchedEx.run_at` takes a `DateTime` struct which indicates the time at which
the job should be executed, and `SchedEx.run_in` takes a duration in integer milliseconds from the time the function is
called at which to execute the job. Similarly to `SchedEx.run_every`, these functions both come in `module, function,
argument` and `fn` form.

The above functions have the same return values as standard `start_link` functions (`{:ok, pid}` on success, `{:error,
error}` on error). The returned pid can be passed to `SchedEx.cancel` to cancel any further invocations of the job.

## Crontab details

Jobs scheduled via `SchedEx.run_every` are implicitly recurring; they continue to to execute according to the crontab
until `SchedEx.cancel/1` is called or the original calling process terminates. If job execution takes longer than the
scheduling interval, the job is requeued at the next mathcing interval (for example, if a job set to run every minute
(crontab `* * * * *`) takes 61 seconds to run at minute `x` it will not run at minute `x+1` and will next run at minute
`x+2`).

SchedEx uses the [crontab](https://github.com/jshmrtn/crontab) library to parse crontab strings. If it is unable to
parse the given crontab string, an error is returned from the `SchedEx.run_every` call and no jobs are scheduled.

# Unsupervised Usage

## Event Sourcing

SchedEx is particularly suited to use in an event sourced architecture since — contrary to OTP idioms — it deliberately
does not supervise scheduled tasks.  Scheduled tasks are created and implicitly managed directly within the task which
creates them, and are simple GenServer instances behind the scenes. If the calling task later crashes, it takes down any
scheduled tasks along with it. Similarly, if a scheduled task crashes, it takes the creating task down with it (the
creating task can choose to handle termination explicitly if needed). Though this design may seem lacking, as it turns
out this is almost always what you want when event sourcing, as the scheduling of such jobs is simply a part of the
state your application builds out from persistent storage. Because you're always able to recreate your current running
state from persistent storage the problem of managing the merging or descheduling of of existing timers on startup after
a crash goes away, and in fact the least error-prone thing to do in this scenario is to simply throw all your timers on
the floor and build them up again as needed.

## Unsupervised Usage

Given the above rationalization, there are many cases where you may want to schedule an event in a non-durable manner,
so that the timer is automatically cancelled if the creating process stops. This can easily be accomplished by calling
`SchedEx.run_*` methods directly (the `SchedEx.run_in` variant is particularly well suited to this use case, when you
want to set an expiry timer based on some asyncronous event). Such usage looks like so:

``` elixir
# Scheduling for a particular date
{:ok, date, _} = DateTime.from_iso8601("2018-01-01T00:00:00Z")
SchedEx.run_at(IO, :write, ["Happy New Year!"], date)

# Scheduling with a given delay
SchedEx.run_in(IO, :write, ["Hello, delayed world!"], 10000)

# Scheduling with a crontab string
SchedEx.run_every(IO, :write, ["Hello, even-minute world!"], "*/2 * * * *")

# You can also pass a fn
SchedEx.run_in(fn() -> IO.write("Hello, delayed world!") end, 10000)
```

It is crucial to understand that SchedEx deliberately does *not* supervise or manage scheduled jobs in any way; the
process instances which back scheduling are simple GenServers which are linked directly to the calling process and are set to trap on exit. What
this means in practice is that if the calling process crashes, all pending jobs scheduled by that process will be
implicitly canceled, and if a job crashes it will bring down the calling process with it (unless the calling process
specifically catches this case as in the case of a Supervisor).

# Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `sched_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:sched_ex, "~> 0.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/sched_ex](https://hexdocs.pm/sched_ex).

# LICENSE

MIT
