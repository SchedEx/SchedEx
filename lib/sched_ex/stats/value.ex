defmodule SchedEx.Stats.Value do
  @moduledoc false

  defstruct min: nil, max: nil, avg: nil, count: 0, histogram: List.duplicate(0, 20)

  @num_periods 50
  @weight_factor 2 / (@num_periods + 1)
  @bucket_size 100

  def update(
        %__MODULE__{min: min, max: max, avg: avg, count: count, histogram: histogram},
        sample
      ) do
    index =
      trunc(sample / @bucket_size)
      |> max(0)
      |> min(length(histogram) - 1)

    %__MODULE__{
      min: min(min, sample),
      max: (max && max(max, sample)) || sample,
      avg: (avg && (sample - avg) * @weight_factor + avg) || sample,
      count: count + 1,
      histogram: List.update_at(histogram, index, &(&1 + 1))
    }
  end
end
