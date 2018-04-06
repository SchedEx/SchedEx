defmodule SchedEx.Stats do
  alias SchedEx.Stats.Value

  defstruct scheduling_delay: %Value{}, execution_time: %Value{}

  def update(
        %__MODULE__{
          scheduling_delay: %Value{} = scheduling_delay,
          execution_time: %Value{} = execution_time
        },
        %DateTime{} = scheduled_start,
        %DateTime{} = actual_start,
        %DateTime{} = actual_end
      ) do
    %__MODULE__{
      scheduling_delay:
        scheduling_delay
        |> Value.update(DateTime.diff(actual_start, scheduled_start, :microsecond)),
      execution_time:
        execution_time 
        |> Value.update(DateTime.diff(actual_end, actual_start, :microsecond))
    }
  end
end
