defmodule SchedEx.Stats.Value do
  defstruct min: nil, max: nil, avg: nil, count: 0

  @num_periods 10
  @weight_factor 2 / (@num_periods + 1)

  def update(%__MODULE__{min: min, max: max, avg: avg, count: count}, sample) do
    %__MODULE__{
      min: min(min, sample),
      max: max && max(max, sample) || sample,
      avg: avg && (((sample - avg) * @weight_factor) + avg) || sample,
      count: count + 1
    }
  end
end
