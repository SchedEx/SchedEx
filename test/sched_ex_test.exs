defmodule SchedExTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Crontab.CronExpression.Parser

  doctest SchedEx

  @sleep_duration 20

  defmodule TestCallee do
    use Agent

    def start_link(_) do
      Agent.start_link(fn -> [] end)
    end

    def append(pid, x) do
      Agent.update(pid, &Kernel.++(&1, [x]))
    end

    def clear(pid) do
      Agent.get_and_update(pid, fn val -> {val, []} end)
    end
  end

  defmodule TestTimeScale do
    use GenServer

    def start_link(args) do
      GenServer.start_link(__MODULE__, args, name: __MODULE__)
    end

    def now(timezone) do
      GenServer.call(__MODULE__, {:now, timezone})
    end

    def speedup do
      GenServer.call(__MODULE__, {:speedup})
    end

    def init({base_time, speedup}) do
      {:ok, %{base_time: base_time, time_0: Timex.now(), speedup: speedup}}
    end

    def handle_call(
          {:now, timezone},
          _from,
          %{base_time: base_time, time_0: time_0, speedup: speedup} = state
        ) do
      diff = DateTime.diff(Timex.now(), time_0, :millisecond) * speedup

      now =
        base_time
        |> Timex.shift(milliseconds: diff)
        |> case do
          %Timex.AmbiguousDateTime{after: later_time} ->
            later_time

          time ->
            time
        end
        |> Timex.Timezone.convert(timezone)

      {:reply, now, state}
    end

    def handle_call({:speedup}, _from, %{speedup: speedup} = state) do
      {:reply, speedup, state}
    end
  end

  setup do
    {:ok, agent} = start_supervised(TestCallee)
    {:ok, agent: agent}
  end

  describe "run_at" do
    test "runs the m,f,a at the expected time", context do
      SchedEx.run_at(
        TestCallee,
        :append,
        [context.agent, 1],
        Timex.shift(DateTime.utc_now(), milliseconds: @sleep_duration)
      )

      Process.sleep(2 * @sleep_duration)
      assert TestCallee.clear(context.agent) == [1]
    end

    test "runs the fn at the expected time", context do
      SchedEx.run_at(
        fn -> TestCallee.append(context.agent, 1) end,
        Timex.shift(DateTime.utc_now(), milliseconds: @sleep_duration)
      )

      Process.sleep(2 * @sleep_duration)
      assert TestCallee.clear(context.agent) == [1]
    end

    test "runs immediately (but not in process) if the expected time is in the past", context do
      SchedEx.run_at(
        TestCallee,
        :append,
        [context.agent, 1],
        Timex.shift(DateTime.utc_now(), hours: -100)
      )

      Process.sleep(@sleep_duration)
      assert TestCallee.clear(context.agent) == [1]
    end

    test "is cancellable", context do
      {:ok, token} =
        SchedEx.run_at(
          TestCallee,
          :append,
          [context.agent, 1],
          Timex.shift(DateTime.utc_now(), milliseconds: @sleep_duration)
        )

      :ok = SchedEx.cancel(token)
      Process.sleep(2 * @sleep_duration)
      assert TestCallee.clear(context.agent) == []
    end
  end

  describe "run_in" do
    test "runs the m,f,a after the expected delay", context do
      SchedEx.run_in(TestCallee, :append, [context.agent, 1], @sleep_duration)
      Process.sleep(2 * @sleep_duration)
      assert TestCallee.clear(context.agent) == [1]
    end

    test "runs the fn after the expected delay", context do
      SchedEx.run_in(fn -> TestCallee.append(context.agent, 1) end, @sleep_duration)
      Process.sleep(2 * @sleep_duration)
      assert TestCallee.clear(context.agent) == [1]
    end

    test "optionally passes the runtime into the m,f,a", context do
      now = DateTime.utc_now()
      expected_time = Timex.shift(now, milliseconds: @sleep_duration)

      SchedEx.run_in(
        TestCallee,
        :append,
        [context.agent, :sched_ex_scheduled_time],
        @sleep_duration,
        start_time: now
      )

      Process.sleep(2 * @sleep_duration)
      assert TestCallee.clear(context.agent) == [expected_time]
    end

    test "optionally passes the runtime into the fn", context do
      now = DateTime.utc_now()
      expected_time = Timex.shift(now, milliseconds: @sleep_duration)

      SchedEx.run_in(
        fn time -> TestCallee.append(context.agent, time) end,
        @sleep_duration,
        start_time: now
      )

      Process.sleep(2 * @sleep_duration)
      assert TestCallee.clear(context.agent) == [expected_time]
    end

    test "can repeat", context do
      SchedEx.run_in(fn -> TestCallee.append(context.agent, 1) end, @sleep_duration, repeat: true)
      Process.sleep(round(2.5 * @sleep_duration))
      calls = TestCallee.clear(context.agent)
      assert length(calls) >= 2
      assert length(calls) <= 4
    end

    test "respects timescale", context do
      {:ok, _} = start_supervised({TestTimeScale, {Timex.now("UTC"), 1000}}, restart: :temporary)

      SchedEx.run_in(
        fn -> TestCallee.append(context.agent, 1) end,
        1000 * @sleep_duration,
        repeat: true,
        time_scale: TestTimeScale
      )

      Process.sleep(round(2.5 * @sleep_duration))
      assert TestCallee.clear(context.agent) == [1, 1]
    end

    test "runs immediately (but not in process) if the expected delay is non-positive", context do
      SchedEx.run_in(TestCallee, :append, [context.agent, 1], -100_000)
      Process.sleep(@sleep_duration)
      assert TestCallee.clear(context.agent) == [1]
    end

    test "is cancellable", context do
      {:ok, token} = SchedEx.run_in(TestCallee, :append, [context.agent, 1], @sleep_duration)
      :ok = SchedEx.cancel(token)
      Process.sleep(2 * @sleep_duration)
      assert TestCallee.clear(context.agent) == []
    end
  end

  describe "run_every" do
    test "runs the m,f,a per the given crontab", context do
      {:ok, _} = start_supervised({TestTimeScale, {Timex.now("UTC"), 60}}, restart: :temporary)

      SchedEx.run_every(
        TestCallee,
        :append,
        [context.agent, 1],
        "* * * * *",
        time_scale: TestTimeScale
      )

      Process.sleep(2000)
      calls = TestCallee.clear(context.agent)
      assert length(calls) >= 2
      assert length(calls) <= 4
    end

    test "runs the fn per the given crontab", context do
      {:ok, _} = start_supervised({TestTimeScale, {Timex.now("UTC"), 60}}, restart: :temporary)

      SchedEx.run_every(
        fn -> TestCallee.append(context.agent, 1) end,
        "* * * * *",
        time_scale: TestTimeScale
      )

      Process.sleep(2000)
      assert TestCallee.clear(context.agent) == [1, 1]
    end

    test "respects the repeat flag", context do
      {:ok, _} = start_supervised({TestTimeScale, {Timex.now("UTC"), 60}}, restart: :temporary)

      {:ok, pid} =
        SchedEx.run_every(
          fn -> TestCallee.append(context.agent, 1) end,
          "* * * * *",
          repeat: false,
          time_scale: TestTimeScale
        )

      Process.sleep(2000)
      assert TestCallee.clear(context.agent) == [1]
      refute Process.alive?(pid)
    end

    test "terminates after running if the crontab never fires again", context do
      now = Timex.now("UTC")
      then = Timex.shift(now, seconds: 30)

      crontab =
        Parser.parse!(
          "#{then.second} #{then.minute} #{then.hour} #{then.day} #{then.month} * #{then.year}",
          true
        )

      {:ok, _} = start_supervised({TestTimeScale, {now, 60}}, restart: :temporary)

      {:ok, pid} =
        SchedEx.run_every(
          fn -> TestCallee.append(context.agent, 1) end,
          crontab,
          time_scale: TestTimeScale
        )

      Process.sleep(2000)
      assert TestCallee.clear(context.agent) == [1]
      refute Process.alive?(pid)
    end

    test "doesn't start up if the crontab never fires in the future" do
      now = Timex.now("UTC")
      then = Timex.shift(now, seconds: -30)

      crontab =
        Parser.parse!(
          "#{then.second} #{then.minute} #{then.hour} #{then.day} #{then.month} * #{then.year}",
          true
        )

      assert SchedEx.run_every(fn -> :ok end, crontab) == :ignore
    end

    test "supports parsing extended strings", context do
      {:ok, _} = start_supervised({TestTimeScale, {Timex.now("UTC"), 1}}, restart: :temporary)

      SchedEx.run_every(
        fn -> TestCallee.append(context.agent, 1) end,
        "* * * * * * *",
        time_scale: TestTimeScale
      )

      Process.sleep(2000)
      assert TestCallee.clear(context.agent) == [1, 1]
    end

    test "supports crontab expressions (and extended ones at that)", context do
      {:ok, _} = start_supervised({TestTimeScale, {Timex.now("UTC"), 1}}, restart: :temporary)
      crontab = Parser.parse!("* * * * * *", true)

      SchedEx.run_every(
        fn -> TestCallee.append(context.agent, 1) end,
        crontab,
        time_scale: TestTimeScale
      )

      Process.sleep(2000)
      assert TestCallee.clear(context.agent) == [1, 1]
    end

    test "optionally passes the runtime into the m,f,a", context do
      {:ok, _} = start_supervised({TestTimeScale, {Timex.now("UTC"), 60}}, restart: :temporary)
      {:ok, crontab} = Parser.parse("* * * * *")

      {:ok, expected_naive_time} =
        Crontab.Scheduler.get_next_run_date(crontab, NaiveDateTime.utc_now())

      expected_time = Timex.to_datetime(expected_naive_time, "UTC")

      SchedEx.run_every(
        TestCallee,
        :append,
        [context.agent, :sched_ex_scheduled_time],
        "* * * * *",
        time_scale: TestTimeScale
      )

      Process.sleep(1000)
      assert TestCallee.clear(context.agent) == [expected_time]
    end

    test "optionally passes the runtime into the fn", context do
      {:ok, _} = start_supervised({TestTimeScale, {Timex.now("UTC"), 60}}, restart: :temporary)
      {:ok, crontab} = Parser.parse("* * * * *")

      {:ok, expected_naive_time} =
        Crontab.Scheduler.get_next_run_date(crontab, NaiveDateTime.utc_now())

      expected_time = Timex.to_datetime(expected_naive_time, "UTC")

      SchedEx.run_every(
        fn time -> TestCallee.append(context.agent, time) end,
        "* * * * *",
        time_scale: TestTimeScale
      )

      Process.sleep(1000)
      assert TestCallee.clear(context.agent) == [expected_time]
    end

    test "supports interpreting crontab in a given timezone", context do
      now = Timex.now("America/Chicago")
      {:ok, _} = start_supervised({TestTimeScale, {now, 86_400}}, restart: :temporary)
      {:ok, crontab} = Parser.parse("0 1 * * *")

      {:ok, naive_expected_time} =
        Crontab.Scheduler.get_next_run_date(crontab, DateTime.to_naive(now))

      expected_time = Timex.to_datetime(naive_expected_time, "America/Chicago")

      SchedEx.run_every(
        fn time -> TestCallee.append(context.agent, time) end,
        "0 1 * * *",
        timezone: "America/Chicago",
        time_scale: TestTimeScale
      )

      Process.sleep(1000)
      assert TestCallee.clear(context.agent) == [expected_time]
    end

    test "skips non-existent times when configured to do so and crontab refers to a non-existent time",
         context do
      # Next time will resolve to 2:30 AM CDT, which doesn't exist
      now = Timex.to_datetime({{2019, 3, 10}, {0, 30, 0}}, "America/Chicago")
      {:ok, _} = start_supervised({TestTimeScale, {now, 86_400}}, restart: :temporary)

      # Skip invocations until the next valid one
      expected_time_for_skip = Timex.to_datetime({{2019, 3, 11}, {2, 30, 0}}, "America/Chicago")

      SchedEx.run_every(
        fn time -> TestCallee.append(context.agent, time) end,
        "30 2 * * *",
        timezone: "America/Chicago",
        nonexistent_time_strategy: :skip,
        time_scale: TestTimeScale
      )

      # Needs an extra second to sleep since it's going a day forward
      Process.sleep(2000)
      assert TestCallee.clear(context.agent) == [expected_time_for_skip]
    end

    test "adjusts non-existent times when configured to do so and crontab refers to a non-existent time",
         context do
      # Next time will resolve to 2:30 AM CDT, which doesn't exist
      now = Timex.to_datetime({{2019, 3, 10}, {0, 30, 0}}, "America/Chicago")
      {:ok, _} = start_supervised({TestTimeScale, {now, 86_400}}, restart: :temporary)

      # Adjust the invocation forward so it's the same number of seconds from midnight
      expected_time_for_adjust = Timex.to_datetime({{2019, 3, 10}, {3, 30, 0}}, "America/Chicago")

      SchedEx.run_every(
        fn time -> TestCallee.append(context.agent, time) end,
        "30 2 * * *",
        timezone: "America/Chicago",
        nonexistent_time_strategy: :adjust,
        time_scale: TestTimeScale
      )

      Process.sleep(1000)
      assert TestCallee.clear(context.agent) == [expected_time_for_adjust]
    end

    test "takes the later time time when configured to do so and crontab refers to an ambiguous time",
         context do
      # Next time will resolve to 1:00 AM CST, which is ambiguous
      now = Timex.to_datetime({{2017, 11, 5}, {0, 30, 0}}, "America/Chicago")
      {:ok, _} = start_supervised({TestTimeScale, {now, 86_400}}, restart: :temporary)

      # Pick the later of the two ambiguous times
      expected_time = Timex.to_datetime({{2017, 11, 5}, {1, 0, 0}}, "America/Chicago").after

      SchedEx.run_every(
        fn time -> TestCallee.append(context.agent, time) end,
        "0 1 * * *",
        timezone: "America/Chicago",
        time_scale: TestTimeScale
      )

      Process.sleep(1000)
      assert TestCallee.clear(context.agent) == [expected_time]
    end

    test "is cancellable", context do
      {:ok, _} = start_supervised({TestTimeScale, {Timex.now("UTC"), 60}}, restart: :temporary)

      {:ok, token} =
        SchedEx.run_every(
          TestCallee,
          :append,
          [context.agent, 1],
          "* * * * *",
          time_scale: TestTimeScale
        )

      :ok = SchedEx.cancel(token)
      Process.sleep(1000)
      assert TestCallee.clear(context.agent) == []
    end

    test "handles invalid crontabs", context do
      {:error, error} = SchedEx.run_every(TestCallee, :append, [context.agent, 1], "O M G W T")
      assert error == "Can't parse O as minute."
    end

    test "accepts a name option", context do
      {:ok, _} = start_supervised({TestTimeScale, {Timex.now("UTC"), 60}}, restart: :temporary)

      {:ok, pid} =
        SchedEx.run_every(
          fn -> TestCallee.append(context.agent, 1) end,
          "* * * * *",
          name: :name_test,
          time_scale: TestTimeScale
        )

      Process.sleep(2000)
      assert TestCallee.clear(context.agent) == [1, 1]
      assert pid == Process.whereis(:name_test)
    end
  end

  describe "timer process supervision" do
    defmodule TerminationHelper do
      use GenServer

      def start_link(_) do
        GenServer.start_link(__MODULE__, [])
      end

      def schedule_job(pid, m, f, a, delay) do
        GenServer.call(pid, {:schedule_job, m, f, a, delay})
      end

      def self_destruct(pid, delay) do
        GenServer.call(pid, {:self_destruct, delay})
      end

      def init(_) do
        {:ok, %{}}
      end

      def handle_call({:schedule_job, m, f, a, delay}, _from, state) do
        {:ok, timer} = SchedEx.run_in(m, f, a, delay)
        {:reply, timer, state}
      end

      def handle_call({:self_destruct, delay}, from, state) do
        {:ok, timer} = SchedEx.run_in(fn -> 2 + 2 end, delay)
        send(timer, {:EXIT, from, :normal})
        {:reply, timer, state}
      end
    end

    setup do
      {:ok, helper} = start_supervised(TerminationHelper, restart: :temporary)
      {:ok, helper: helper}
    end

    test "timers should die along with their creator process", context do
      timer =
        TerminationHelper.schedule_job(
          context.helper,
          TestCallee,
          :append,
          [context.agent, 1],
          5 * @sleep_duration
        )

      GenServer.stop(context.helper)
      Process.sleep(@sleep_duration)

      refute Process.alive?(context.helper)
      refute Process.alive?(timer)

      Process.sleep(10 * @sleep_duration)
      assert TestCallee.clear(context.agent) == []
    end

    test "timers that exit normally should not take their creator process along with them",
         context do
      defmodule Quitter do
        def leave do
          Process.exit(self(), :normal)
        end
      end

      timer = TerminationHelper.schedule_job(context.helper, Quitter, :leave, [], @sleep_duration)
      Process.sleep(2 * @sleep_duration)

      assert Process.alive?(context.helper)
      refute Process.alive?(timer)
    end

    test "timers that die should take their creator process along with them by default",
         context do
      defmodule Crasher do
        def boom do
          raise "boom"
        end
      end

      warnings =
        capture_log(fn ->
          timer =
            TerminationHelper.schedule_job(context.helper, Crasher, :boom, [], @sleep_duration)

          Process.sleep(5 * @sleep_duration)

          refute Process.alive?(context.helper)
          refute Process.alive?(timer)
        end)

      assert warnings =~ "(RuntimeError) boom"
    end

    @tag exit: true
    test "timers should ignore messages from processes that exit normally.", context do
      timer = TerminationHelper.self_destruct(context.helper, @sleep_duration)
      Process.sleep(div(@sleep_duration, 2))
      assert Process.alive?(timer)
    end
  end

  describe "stats" do
    test "returns stats on the running job", context do
      {:ok, token} =
        SchedEx.run_in(TestCallee, :append, [context.agent, 1], @sleep_duration, repeat: true)

      Process.sleep(@sleep_duration)

      %SchedEx.Stats{
        scheduling_delay: %SchedEx.Stats.Value{
          min: sched_min,
          max: sched_max,
          avg: sched_avg,
          count: sched_count
        },
        execution_time: %SchedEx.Stats.Value{
          min: exec_min,
          max: exec_max,
          avg: exec_avg,
          count: exec_count
        }
      } = SchedEx.stats(token)

      assert sched_count == 1
      # Assume that scheduling delay is 1..3000 usec
      assert sched_avg > 1.0
      assert sched_avg < 3000.0
      assert sched_min == sched_avg
      assert sched_max == sched_avg

      assert exec_count == 1
      # Assume that execution time is 1..200 usec
      assert exec_avg > 1.0
      assert exec_avg < 200.0
      assert exec_min == exec_avg
      assert exec_max == exec_avg
    end
  end
end
