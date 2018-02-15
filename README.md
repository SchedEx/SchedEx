<img src="https://user-images.githubusercontent.com/79646/36270991-42e8d440-124b-11e8-9bd6-17cfc02b77fa.png" alt="SchedEx" width="300"/>

[![Build Status](https://travis-ci.org/SchedEx/SchedEx.svg?branch=master)](https://travis-ci.org/SchedEx/SchedEx)
[![Inline docs](http://inch-ci.org/github/SchedEx/SchedEx.svg?branch=master&style=flat)](http://inch-ci.org/github/SchedEx/SchedEx)

SchedEx is a simple yet deceptively powerful scheduling library for Elixir. It is trivially simple by design, and is especially
suited for use within an event sourced architecture.

SchedEx is particularly suited to use in an event sourced architecture since — contrary to OTP idioms — it deliberately
does not supervise scheduled tasks.  Scheduled tasks are created and implicitly managed directly within the task which
creates them. If the calling task later crashes, it takes down any scheduled tasks along with it. Similarly, if
a scheduled task crashes, it takes the creating task down with it (the creating task can choose to handle termination
explicitly if needed). Though this design may seem lacking, as it turns out this is almost always what
you want when event sourcing, as the scheduling of such jobs is simply a part of the state your application builds out
from persistent storage. Because you're always able to recreate your current running state from persistent storage the
problem of managing the merging or descheduling of of existing timers on startup after a crash goes away, and in fact
the least error-prone thing to do in this scenario is to simply throw all your timers on the floor and build them up
again as needed.

SchedEx is written by [Mat Trudel](http://github.com/mtrudel), and development is generously supported by the fine folks
at [FunnelCloud](http://funnelcloud.io).

For usage details, please refer to the [documentation](https://hexdocs.pm/sched_ex).

# Basic Usage

In common usage, SchedEx provides three methods which serve to schedule jobs; `SchedEx.run_at`, `SchedEx.run_in`, and `SchedEx.run_every`. As the names
suggest, `SchedEx.run_at` takes a `DateTime` struct which indicates the time at which the job should be executed, and `SchedEx.run_in`
takes a duration in integer milliseconds from the time the function is called at which to execute the job.
`SchedEx.run_every` takes a valid crontab string and runs the job accordingly. All functions come in `module, function, argument` tuple and `fn` forms:

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

The values returned by the above functions serve as tokens which can be passed to `SchedEx.cancel` to cancel any further
invocations of the job.

It is crucial to understand that SchedEx deliberately does *not* supervise or manage scheduled jobs in any way; the
process instances which back scheduling are linked directly to the calling process and are set to trap on exit. What
this means in practice is that if the calling process crashes, all pending jobs scheduled by that process will be
implicitly canceled.

## Crontab details

Jobs scheduled via `SchedEx.run_every` are implicitly recurring; they continue to to execute according to the crontab
until `SchedEx.cancel/1` is called or the original calling process terminates. If job execution takes longer than the
scheduling interval, the job is requeued at the next mathcing interval (for example, if a job set to run every minute
(crontab `* * * * *`) takes 61 seconds to run at minute `x` it will not run at minute `x+1` and will next run at minute
`x+2`).

SchedEx uses the [crontab](https://github.com/jshmrtn/crontab) library to parse crontab strings. If it is unable to
parse the given crontab string, an error is returned from the `SchedEx.run_every` call and no jobs are scheduled.

# Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `sched_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:sched_ex, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/sched_ex](https://hexdocs.pm/sched_ex).

# LICENSE

MIT
