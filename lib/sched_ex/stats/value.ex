defmodule SchedEx.Stats.Value do
  defstruct min: nil, max: 0, avg: 0, count: 0

  def update(%__MODULE__{min: min, max: max, avg: avg, count: count}, sample) do
    %__MODULE__{
      min: min(min, sample),
      max: max(max, sample),
      avg: ((count * avg) + sample) / (count + 1),
      count: count + 1
    }
  end
end
