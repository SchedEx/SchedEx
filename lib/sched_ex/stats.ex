defmodule SchedEx.Stats do
  @moduledoc false

  alias SchedEx.Stats.Value

  defstruct scheduling_delay: %Value{}, quantization_error: %Value{}, execution_time: %Value{}

  def update(
        %__MODULE__{
          scheduling_delay: %Value{} = scheduling_delay,
          quantization_error: %Value{} = quantization_error,
          execution_time: %Value{} = execution_time
        },
        %DateTime{} = scheduled_start,
        %DateTime{} = quantized_scheduled_start,
        %DateTime{} = actual_start,
        %DateTime{} = actual_end
      ) do
    %__MODULE__{
      scheduling_delay:
        scheduling_delay
        |> Value.update(DateTime.diff(actual_start, quantized_scheduled_start, :microsecond)),
      quantization_error:
        quantization_error
        |> Value.update(
          abs(DateTime.diff(quantized_scheduled_start, scheduled_start, :microsecond))
        ),
      execution_time:
        execution_time
        |> Value.update(DateTime.diff(actual_end, actual_start, :microsecond))
    }
  end
end
