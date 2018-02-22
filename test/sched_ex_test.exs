defmodule SchedExTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

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

  setup do
    {:ok, agent} = start_supervised(TestCallee)
    {:ok, agent: agent}
  end

  describe "run_at" do
    test "runs the m,f,a at the expected time", context do
      SchedEx.run_at(TestCallee, :append, [context.agent, 1], Timex.shift(DateTime.utc_now(), milliseconds: @sleep_duration))
      Process.sleep(2 * @sleep_duration)
      assert TestCallee.clear(context.agent) == [1]
    end

    test "runs the fn at the expected time", context do
      SchedEx.run_at(fn() -> TestCallee.append(context.agent, 1) end, Timex.shift(DateTime.utc_now(), milliseconds: @sleep_duration))
      Process.sleep(2 * @sleep_duration)
      assert TestCallee.clear(context.agent) == [1]
    end

    test "runs immediately in process if the expected time is in the past", context do
      {:ok, token} = SchedEx.run_at(TestCallee, :append, [context.agent, 1], Timex.shift(DateTime.utc_now(), milliseconds: -@sleep_duration))
      assert TestCallee.clear(context.agent) == [1]
      assert token == nil
    end

    test "is cancellable", context do
      {:ok, token} = SchedEx.run_at(TestCallee, :append, [context.agent, 1], Timex.shift(DateTime.utc_now(), milliseconds: @sleep_duration))
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
      SchedEx.run_in(fn() -> TestCallee.append(context.agent, 1) end, @sleep_duration)
      Process.sleep(2 * @sleep_duration)
      assert TestCallee.clear(context.agent) == [1]
    end

    test "runs immediately in process if the expected delay is non-positive", context do
      {:ok, token} = SchedEx.run_in(TestCallee, :append, [context.agent, 1], -@sleep_duration)
      assert TestCallee.clear(context.agent) == [1]
      assert token == nil
    end

    test "is cancellable", context do
      {:ok, token} = SchedEx.run_in(TestCallee, :append, [context.agent, 1], @sleep_duration)
      :ok = SchedEx.cancel(token)
      Process.sleep(2 * @sleep_duration)
      assert TestCallee.clear(context.agent) == []
    end
  end

  describe "run_every" do
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

      def handle_call({:now, timezone}, _from, %{base_time: base_time, time_0: time_0, speedup: speedup} = state) do
        diff = DateTime.diff(Timex.now(), time_0, :millisecond) * speedup
        now = base_time
              |> Timex.shift(milliseconds: diff)
              |> Timex.Timezone.convert(timezone)
        {:reply, now, state}
      end

      def handle_call({:speedup}, _from, %{speedup: speedup} = state) do
        {:reply, speedup, state}
      end
    end

    test "runs the m,f,a per the given crontab", context do
      {:ok, _} = start_supervised({TestTimeScale, {Timex.now("UTC"), 60}}, restart: :temporary)
      SchedEx.run_every(TestCallee, :append, [context.agent, 1], "* * * * *", time_scale: TestTimeScale)
      Process.sleep(2000)
      assert TestCallee.clear(context.agent) == [1, 1]
    end

    test "runs the fn per the given crontab", context do
      {:ok, _} = start_supervised({TestTimeScale, {Timex.now("UTC"), 60}}, restart: :temporary)
      SchedEx.run_every(fn() -> TestCallee.append(context.agent, 1) end, "* * * * *", time_scale: TestTimeScale)
      Process.sleep(2000)
      assert TestCallee.clear(context.agent) == [1, 1]
    end

    test "optionally passes the runtime into the fn", context do
      {:ok, _} = start_supervised({TestTimeScale, {Timex.now("UTC"), 60}}, restart: :temporary)
      {:ok, crontab} = Crontab.CronExpression.Parser.parse("* * * * *")
      {:ok, expected_naive_time} = Crontab.Scheduler.get_next_run_date(crontab, NaiveDateTime.utc_now())
      expected_time = Timex.to_datetime(expected_naive_time, "UTC")
      SchedEx.run_every(fn(time) -> TestCallee.append(context.agent, time) end, "* * * * *", time_scale: TestTimeScale)
      Process.sleep(1000)
      assert TestCallee.clear(context.agent) == [expected_time]
    end

    test "supports interpreting crontab in a given timezone", context do
      now = Timex.now("America/Chicago")
      {:ok, _} = start_supervised({TestTimeScale, {now, 86400}}, restart: :temporary)
      {:ok, crontab} = Crontab.CronExpression.Parser.parse("0 1 * * *")
      {:ok, naive_expected_time} = Crontab.Scheduler.get_next_run_date(crontab, DateTime.to_naive(now))
      expected_time = Timex.to_datetime(naive_expected_time, "America/Chicago")
      SchedEx.run_every(fn(time) -> TestCallee.append(context.agent, time) end, "0 1 * * *", timezone: "America/Chicago", time_scale: TestTimeScale)
      Process.sleep(1000)
      assert TestCallee.clear(context.agent) == [expected_time]
    end

    test "handles scheduling when crontab refers to an ambiguous time (for example on DST transition)", context do
      # Next time will resolve to 1:00 AM CST, which is ambiguous
      now = Timex.to_datetime({{2017, 11, 5}, {0, 30, 0}}, "America/Chicago")
      {:ok, _} = start_supervised({TestTimeScale, {now, 86400}}, restart: :temporary)
      {:ok, crontab} = Crontab.CronExpression.Parser.parse("0 1 * * *")
      {:ok, naive_expected_time} = Crontab.Scheduler.get_next_run_date(crontab, DateTime.to_naive(now))
      expected_time = Timex.to_datetime(naive_expected_time, "America/Chicago").after
      SchedEx.run_every(fn(time) -> TestCallee.append(context.agent, time) end, "0 1 * * *", timezone: "America/Chicago", time_scale: TestTimeScale)
      Process.sleep(1000)
      assert TestCallee.clear(context.agent) == [expected_time]
    end

    test "is cancellable", context do
      {:ok, _} = start_supervised({TestTimeScale, {Timex.now("UTC"), 60}}, restart: :temporary)
      {:ok, token} = SchedEx.run_every(TestCallee, :append, [context.agent, 1], "* * * * *", time_scale: TestTimeScale)
      :ok = SchedEx.cancel(token)
      Process.sleep(1000)
      assert TestCallee.clear(context.agent) == []
    end

    test "handles invalid crontabs", context do
      {:error, error} = SchedEx.run_every(TestCallee, :append, [context.agent, 1], "O M G W T")
      assert error == "Can't parse O as interval minute."
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

      def init(_) do
        {:ok, %{}}
      end

      def handle_call({:schedule_job, m, f, a, delay}, _from, state) do
        {:ok, timer} = SchedEx.run_in(m, f, a, delay)
        {:reply, timer, state}
      end
    end

    setup do
      {:ok, helper} = start_supervised(TerminationHelper, restart: :temporary)
      {:ok, helper: helper}
    end

    test "timers should die along with their creator process", context do
      timer = TerminationHelper.schedule_job(context.helper, TestCallee, :append, [context.agent, 1], 5 * @sleep_duration)

      GenServer.stop(context.helper)
      Process.sleep(@sleep_duration)

      refute Process.alive?(context.helper)
      refute Process.alive?(timer)

      Process.sleep(10 * @sleep_duration)
      assert TestCallee.clear(context.agent) == []
    end

    test "timers that exit normally should not take their creator process along with them", context do
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

    test "timers that die should take their creator process along with them by default", context do
      defmodule Crasher do
        def boom do
          raise "boom"
        end
      end

      timer = TerminationHelper.schedule_job(context.helper, Crasher, :boom, [], @sleep_duration)

      warnings = capture_log(fn ->
        Process.sleep(2 * @sleep_duration)
      end)

      assert warnings =~ "(RuntimeError) boom"

      refute Process.alive?(context.helper)
      refute Process.alive?(timer)
    end
  end
end
